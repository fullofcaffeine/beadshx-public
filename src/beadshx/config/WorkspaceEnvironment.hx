package beadshx.config;

import beadshx.cli.JsonSettingPort.WorkspaceSelection;
import beadshx.config.ConfigShow.WorkspaceMetadataFields;
import beadshx.config.ConfigShow.readMetadataFields;
import beadshx.config.DatabaseVariableSelection.DatabaseVariableUse;
import beadshx.config.LayeredConfig.environmentValue;
import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.nativeextern.os.OsPkg;
import beadshx.store.CustomConfig.goTrimSpace;
import beadshx.workspace.WorkspaceDiscovery;
import beadshx.workspace.WorkspacePort;

/**
	Upstream's `.beads/.env` loading in the root pre-run, and the BEADS_DB and
	BD_DB selection that decides which workspace's file it loads.

	Why: upstream reads every BD_ and BEADS_ setting from the process
	environment, and its pre-run first copies the selected workspace's
	`.beads/.env` there, so a variable in that file acts as if it were
	exported, unless the real environment already has it. What: two steps
	that change the process environment the way upstream does, before any
	setting is read. How: first, when neither -C nor a set BEADS_DIR, BEADS_DB
	or BD_DB chooses the workspace, the .env file of the workspace found from
	the current directory may set those three selectors (upstream
	loadSelectionEnvironment). Then BEADS_DB or BD_DB may choose the workspace
	(see selectDatabaseVariable). Last, every variable of the selected
	workspace's .env file that the environment does not have is set (upstream
	loadBeadsEnvFile under prepareSelectedCommandContext). Upstream sets
	BEADS_DIR to the selected directory before that last step, so the file
	cannot set BEADS_DIR there and `$BEADS_DIR` expands to that directory.
	Nothing is printed: a missing, unreadable or rejected file adds nothing.
**/
@:goNative
final class WorkspaceEnvironment {
	/** Whether the first step set BEADS_DIR, which was then unset or empty for upstream's process-start config. */
	static var callerBeadsDirReplaced = false;

	/**
		Loads the `.env` variables for one command's -C and --db selection, and
		returns what BEADS_DB or BD_DB selects for that command.
	**/
	public static function load(workspace:WorkspacePort, selection:WorkspaceSelection, use:DatabaseVariableUse):DatabaseVariableSelection {
		var selected:Null<WorkspaceDiscovery> = null;
		// -C sets BEADS_DIR before upstream's first step, which then does nothing.
		if (goTrimSpace(selection.directory) == ""
			&& environmentValue("BEADS_DIR") == ""
			&& environmentValue("BEADS_DB") == ""
			&& environmentValue("BD_DB") == "") {
			final found = workspace.discover("", "");
			var changed = false;
			switch found {
				case Found(location):
					final variables = DotEnv.read(FilepathPkg.join(location.path, ".env"), name -> Sys.getEnv(name));
					if (variables != null)
						for (name in ["BEADS_DIR", "BEADS_DB", "BD_DB"]) {
							final assigned = variables.get(name);
							if (environmentValue(name) != "" || assigned == null || goTrimSpace(assigned) == "")
								continue;
							Sys.putEnv(name, assigned);
							changed = true;
							if (name == "BEADS_DIR")
								callerBeadsDirReplaced = true;
						}
				case NotFound | InvalidSelection(_):
			}
			// Without a new selector or --db, the selection is the workspace just found.
			if (!changed && selection.databasePath == "")
				selected = found;
		}
		final variable = selectDatabaseVariable(workspace, selection, use);
		switch variable {
			case VariablePath(_, path, _):
				selected = workspace.discover(selection.directory, path);
			case NoVariable | UnsupportedPath(_):
				if (selected == null)
					selected = workspace.discover(selection.directory, selection.databasePath);
		}
		switch selected {
			case Found(location):
				loadFile(location.path);
			case NotFound | InvalidSelection(_):
		}
		return variable;
	}

	/**
		BEADS_DIR as upstream's process-start config saw it: "" when the first
		step set it, since that step runs only when BEADS_DIR is unset or empty.
	**/
	public static function callerBeadsDir():Null<String> {
		return callerBeadsDirReplaced ? "" : Sys.getEnv("BEADS_DIR");
	}

	/** Upstream loadBeadsEnvFile with BEADS_DIR set to `beadsDir`: gotenv.Load after an os.Stat check. */
	static function loadFile(beadsDir:String):Void {
		final path = FilepathPkg.join(beadsDir, ".env");
		if (OsPkg.stat(path).value2 != null)
			return;
		final variables = DotEnv.read(path, name -> name == "BEADS_DIR" ? beadsDir : Sys.getEnv(name));
		if (variables == null)
			return;
		for (name in variables.keys())
			if (name != "BEADS_DIR" && Sys.getEnv(name) == null)
				Sys.putEnv(name, variables.get(name));
	}

	/**
		Whether BEADS_DB or BD_DB chooses the workspace of a command with the -C
		and --db values of `typed`.

		Why: without --db, upstream's commands that open the store read BEADS_DB
		when no -C or BEADS_DIR is set and no workspace is found from the current
		directory, and `where` reads BEADS_DB, else BD_DB, before all of those.
		What: the variable and its path when one of them selects as described in
		DatabaseVariableUse. How: selectPath decides whether this build's --db
		discovery selects that path exactly as upstream does.
	**/
	static function selectDatabaseVariable(workspace:WorkspacePort, typed:WorkspaceSelection, use:DatabaseVariableUse):DatabaseVariableSelection {
		if (typed.databasePath != "")
			return NoVariable;
		return switch use {
			case WithoutWorkspace: selectWithoutWorkspace(workspace, typed);
			case BeforeWorkspace: selectBeforeWorkspace(workspace, typed);
		};
	}

	/** BEADS_DB for a command that opens the store, once nothing else selects a workspace. */
	static function selectWithoutWorkspace(workspace:WorkspacePort, typed:WorkspaceSelection):DatabaseVariableSelection {
		final path = environmentValue("BEADS_DB");
		if (path == "" || goTrimSpace(typed.directory) != "" || environmentValue("BEADS_DIR") != "")
			return NoVariable;
		return switch workspace.discover("", "") {
			case NotFound: selectPath(workspace, "", "BEADS_DB", path);
			case Found(_) | InvalidSelection(_): NoVariable;
		};
	}

	/** BEADS_DB, else BD_DB, for `where`, before -C, BEADS_DIR and the current directory. */
	static function selectBeforeWorkspace(workspace:WorkspacePort, typed:WorkspaceSelection):DatabaseVariableSelection {
		// Upstream checks -C before the command runs; its error comes first.
		if (goTrimSpace(typed.directory) != "")
			switch workspace.discover(typed.directory, "") {
				case InvalidSelection(_):
					return NoVariable;
				case Found(_) | NotFound:
			}
		for (name in ["BEADS_DB", "BD_DB"]) {
			final path = environmentValue(name);
			if (path != "")
				return selectPath(workspace, typed.directory, name, path);
		}
		return NoVariable;
	}

	/**
		The paths of variable `name` that select an existing embedded workspace
		in upstream the way this build's --db discovery does.

		Why: upstream turns BEADS_DB into a database path with FindDatabasePath,
		then maps it to a workspace with resolveCommandBeadsDir, and opens or
		creates the database there. What: VariablePath for three forms whose
		workspace holds metadata.json and an `embeddeddolt` database, without a
		redirect: that workspace directory itself, its `embeddeddolt`
		directory, and a missing file in a directory named `.beads`, such as a
		legacy `beads.db` (upstream reads the workspace's database for it).
		Every other path is UnsupportedPath. For a missing path elsewhere, a
		directory that is not a workspace, or a workspace without a database,
		upstream creates an embedded database. How: these checks run before
		discovery, which may rewrite a legacy config.json as metadata.json, and
		discovery must then return the directory that upstream selects. The
		workspace directory must not be inside a directory named `.beads`, and
		the database path must be directly inside one, because upstream takes
		such a parent before it compares any candidate.
	**/
	static function selectPath(workspace:WorkspacePort, directory:String, name:String, path:String):DatabaseVariableSelection {
		final parent = FilepathPkg.dir(path);
		final inBeadsDirectory = FilepathPkg.base(parent) == ".beads";
		var missingFile:Null<String> = null;
		final selectedPath = switch ConfigProbes.statPath(path) {
			case StatDirectory if (ConfigProbes.statSucceeds(FilepathPkg.join(path, "metadata.json"))):
				inBeadsDirectory ? null : path;
			// Upstream looks for a database inside this directory first, and finds none.
			case StatDirectory
				if (inBeadsDirectory
					&& FilepathPkg.base(path) == "embeddeddolt"
					&& !ConfigProbes.statSucceeds(FilepathPkg.join(path, "config.json"))
					&& !ConfigProbes.statSucceeds(FilepathPkg.join(path, "embeddeddolt"))
					&& !ConfigProbes.statSucceeds(FilepathPkg.join(path, "dolt"))):
				parent;
			case StatMissing if (inBeadsDirectory):
				missingFile = absolutePath(path);
				parent;
			case StatDirectory | StatMissing | StatNotDirectory | StatFailed(_):
				null;
		};
		if (selectedPath == null
			|| !ConfigProbes.statSucceeds(FilepathPkg.join(selectedPath, "metadata.json"))
			|| ConfigProbes.statSucceeds(FilepathPkg.join(selectedPath, "redirect")))
			return UnsupportedPath(name);
		return switch workspace.discover(directory, path) {
			case Found(location)
				if (location.path == selectedPath
					&& location.databaseName == ""
					&& !location.proxiedServer
					&& FilepathPkg.base(location.databasePath) == "embeddeddolt"):
				VariablePath(name, path, missingFile);
			case Found(_) | NotFound | InvalidSelection(_):
				UnsupportedPath(name);
		};
	}

	/** Go's filepath.Abs, which upstream's CanonicalizePath returns for a path that does not exist. */
	static function absolutePath(path:String):String {
		return FilepathPkg.isAbs(path) ? FilepathPkg.clean(path) : FilepathPkg.join(Sys.getCwd(), path);
	}

	/**
		Upstream resolveCommandBeadsDir: the `.beads` directory that a database
		`path` selects, where `foundBeadsDir` is the directory that upstream's
		FindBeadsDir finds ("" for none).

		Why: `where`, `version` and help pages, and commands that open a store
		for a `db` setting, set up this directory, which can differ from the
		workspace that this build's discovery returns for the same path. What:
		the directory of a workspace whose metadata.json claims the path (see
		claimingBeadsDir), or else databasePathBeadsDir. How: it only reads.
		Upstream's configfile.Load would rewrite a legacy config.json that it
		checks; such a directory counts as claiming the path here, without the
		rewrite.
	**/
	public static function commandBeadsDir(path:String, foundBeadsDir:String):String {
		if (path == "")
			return "";
		final claimed = claimingBeadsDir(path, foundBeadsDir);
		return claimed != "" ? claimed : databasePathBeadsDir(path);
	}

	/**
		The `.beads` directory as upstream's setup names it for a command that
		opens a store, when discovery names it `beadsDir`. For a BEADS_DB path
		(`selection`), upstream's FindDatabasePath first makes the path
		absolute and resolves its symbolic links. For a missing file it keeps
		the absolute path, and the file's parent `.beads` directory claims it.
		Any other selection keeps `beadsDir`.
	**/
	public static function storeSetupDirectory(selection:DatabaseVariableSelection, beadsDir:String):String {
		return switch selection {
			case VariablePath(_, _, missingFile): missingFile != null ? FilepathPkg.dir(missingFile) : canonicalPath(beadsDir);
			case NoVariable | UnsupportedPath(_): beadsDir;
		};
	}

	/**
		Upstream FindBeadsDir while BEADS_DIR names `beadsDir`, as upstream's
		setup for that directory leaves it, or "" when it finds no directory.
		The body of `where` sets up this directory again after its pre-run set
		up `beadsDir` for a `db` setting. It costs one more native discovery.
		BEADS_DIR gets its value back before this returns.
	**/
	public static function findWithBeadsDir(workspace:WorkspacePort, beadsDir:String):String {
		final previous = Sys.getEnv("BEADS_DIR");
		Sys.putEnv("BEADS_DIR", beadsDir);
		final found = workspace.discover("", "");
		Sys.putEnv("BEADS_DIR", previous);
		return switch found {
			case Found(location): location.path;
			case NotFound | InvalidSelection(_): "";
		};
	}

	/**
		Upstream resolveBeadsDirForDBPath. A parent directory named `.beads`
		with a metadata.json file claims `path` first, as written and then
		canonical. Otherwise the candidates are the path itself when it is a
		directory, its parent directory, each `.beads` directory beside it or
		an ancestor (and each ancestor named `.beads`), and the found directory,
		each once. The first candidate whose config loads claims the path when
		the candidate is the path, its parent directory, or the Dolt directory
		that the config names. Returns "" when none does.
	**/
	static function claimingBeadsDir(path:String, foundBeadsDir:String):String {
		final canonical = canonicalPath(path);
		for (selected in [path, canonical]) {
			final parent = FilepathPkg.dir(selected);
			if (FilepathPkg.base(parent) == ".beads" && ConfigProbes.statSucceeds(FilepathPkg.join(parent, "metadata.json")))
				return parent;
		}
		final seen = new Map<String, Bool>();
		final candidates = new Array<String>();
		function addCandidate(candidate:String):Void {
			final key = comparablePath(candidate);
			if (key == "" || seen.exists(key))
				return;
			seen.set(key, true);
			candidates.push(candidate);
		}
		function addAncestorCandidates(start:String):Void {
			var directory = start;
			while (directory != "" && directory != FilepathPkg.dir(directory)) {
				addCandidate(FilepathPkg.join(directory, ".beads"));
				if (FilepathPkg.base(directory) == ".beads")
					addCandidate(directory);
				directory = FilepathPkg.dir(directory);
			}
		}
		for (selected in [path, canonical])
			switch ConfigProbes.statPath(selected) {
				case StatDirectory:
					addCandidate(selected);
				case StatMissing | StatNotDirectory | StatFailed(_):
			}
		addCandidate(FilepathPkg.dir(path));
		addCandidate(FilepathPkg.dir(canonical));
		addAncestorCandidates(FilepathPkg.dir(path));
		addAncestorCandidates(FilepathPkg.dir(canonical));
		if (foundBeadsDir != "") {
			addCandidate(foundBeadsDir);
			addCandidate(canonicalPath(foundBeadsDir));
		}
		for (candidate in candidates) {
			final dataDirectory = switch readMetadataFields(candidate) {
				case MetadataFields(fields): ConfigProbes.doltDirectory(candidate, fields);
				case MetadataFieldsLegacyOnly: ConfigProbes.doltDirectory(candidate, null);
				case MetadataAbsent | MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported: null;
			};
			if (dataDirectory != null)
				for (selected in [path, canonical])
					if (samePath(candidate, selected)
						|| samePath(FilepathPkg.dir(selected), candidate)
						|| samePath(dataDirectory, selected))
						return candidate;
		}
		return "";
	}

	/**
		Upstream utils.CanonicalizePath without its final step: the absolute
		path with symbolic links resolved, or the absolute path when that fails.
		On macOS and Windows upstream also takes each name's case from the file
		system, which comparablePath makes irrelevant here.
	**/
	static function canonicalPath(path:String):String {
		final absolute = absolutePath(path);
		final resolved = FilepathPkg.evalSymlinks(absolute);
		return resolved.value2 == null ? resolved.value1 : absolute;
	}

	/** Upstream utils.NormalizePathForComparison: canonicalPath, in lower case on macOS and Windows; "" for "". */
	static function comparablePath(path:String):String {
		if (path == "")
			return "";
		final canonical = canonicalPath(path);
		final system = Sys.systemName();
		return system == "Mac" || system == "Windows" ? canonical.toLowerCase() : canonical;
	}

	/** Upstream utils.PathsEqual. */
	static function samePath(first:String, second:String):Bool {
		return comparablePath(first) == comparablePath(second);
	}

	/**
		Upstream resolveCommandBeadsDir for a --db `path` that no workspace with
		metadata.json or a legacy config.json claims: the first `.beads`
		directory beside the path's directory or one of its ancestors, else the
		path's directory. It keeps a relative path relative, and it stops before
		`.` or the root directory, as Go's filepath.Dir loop does.
	**/
	public static function databasePathBeadsDir(path:String):String {
		final parent = FilepathPkg.dir(path);
		var directory = parent;
		while (directory != "" && directory != FilepathPkg.dir(directory)) {
			final candidate = FilepathPkg.join(directory, ".beads");
			switch ConfigProbes.statPath(candidate) {
				case StatDirectory:
					return candidate;
				case StatMissing | StatNotDirectory | StatFailed(_):
			}
			directory = FilepathPkg.dir(directory);
		}
		return parent;
	}
}
