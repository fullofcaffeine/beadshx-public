package beadshx.config;

import beadshx.cli.JsonSettingPort.WorkspaceSelection;
import beadshx.config.ConfigShow.WorkspaceMetadataFields;
import beadshx.config.ConfigShow.readMetadataFields;
import beadshx.config.DatabaseVariableSelection.DatabaseVariableUse;
import beadshx.config.LayeredConfig.environmentValue;
import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.nativeextern.os.OsPkg;
import beadshx.nativeextern.strings.StringsPkg;
import beadshx.store.CustomConfig.goTrimSpace;
import beadshx.store.EmbeddedDatabaseLookup.isEmbeddedDatabaseIdentifier;
import beadshx.store.EmbeddedDatabaseLookup.redirectSourceDatabase;
import beadshx.workspace.RedirectLookups;
import beadshx.workspace.RedirectSource;
import beadshx.workspace.RedirectSource.RedirectSourceLookup;
import beadshx.workspace.WorkspaceDiscovery;
import beadshx.workspace.WorkspaceLocation;
import beadshx.workspace.WorkspacePort;
import sys.FileSystem;

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
	(see selectDatabaseVariable). Last, every variable of the .env file of the
	directory that upstream sets up first (see setupDirectory) that the
	environment does not have is set (upstream loadBeadsEnvFile under
	prepareSelectedCommandContext). With -C that directory is the redirect
	target of the -C workspace when upstream follows its redirect. A command
	that opens a store and binds the second target of a redirect chain (see
	storeChainTarget) then also loads that target's file, as upstream's
	second setup does before it rereads the settings. Upstream sets BEADS_DIR
	to each directory before it loads the file, so the file cannot set
	BEADS_DIR there and `$BEADS_DIR` expands to that directory. Nothing is
	printed: a missing,
	unreadable or rejected file adds nothing.
**/
@:goNative
final class WorkspaceEnvironment {
	/** Whether the first step set BEADS_DIR, which was then unset or empty for upstream's process-start config. */
	static var callerBeadsDirReplaced = false;

	/**
		Loads the `.env` variables for one command's -C and --db selection, and
		returns what BEADS_DB or BD_DB selects for that command. `lookups`
		runs upstream's workspace lookups of these steps: FindBeadsDirFrom for
		-C (cmd/bd/main.go:808) and FindBeadsDir for the first step (:404).
	**/
	public static function load(workspace:WorkspacePort, selection:WorkspaceSelection, use:DatabaseVariableUse,
			lookups:Null<RedirectLookups>):DatabaseVariableSelection {
		var found:Null<WorkspaceDiscovery> = null;
		if (lookups != null && goTrimSpace(selection.directory) != "")
			lookups.changeDirectory(selection.directory);
		// -C sets BEADS_DIR before upstream's first step, which then does nothing.
		if (goTrimSpace(selection.directory) == ""
			&& environmentValue("BEADS_DIR") == ""
			&& environmentValue("BEADS_DB") == ""
			&& environmentValue("BD_DB") == "") {
			if (lookups != null)
				lookups.findBeadsDir();
			final discovered = workspace.discover("", "");
			var changed = false;
			switch discovered {
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
			// Without a new selector, the workspace just found is the one that FindBeadsDir finds.
			if (!changed)
				found = discovered;
		}
		final variable = selectDatabaseVariable(workspace, selection, use);
		final discovery = found != null ? found : workspace.discover(selection.directory, "");
		final foundBeadsDir = discoveredPath(discovery);
		final beadsDir = setupDirectory(selection, use, foundBeadsDir);
		if (beadsDir == "")
			return variable;
		final location = switch discovery {
			case Found(location) if (beadsDir == foundBeadsDir): location;
			case Found(_) | NotFound | InvalidSelection(_): null;
		};
		// With -C, upstream's first setup already takes the redirect target, and so does its second.
		final changeTarget = location != null && goTrimSpace(selection.directory) != "" ? redirectedThrough(foundBeadsDir) : null;
		loadFile(changeTarget != null ? changeTarget : beadsDir);
		if (location != null && changeTarget == null && use == WithoutWorkspace) {
			final storeTarget = storeChainTarget(selection, location);
			if (storeTarget != null)
				loadSecondTargetFile(foundBeadsDir, storeTarget);
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

	/**
		Upstream loadBeadsEnvFile with BEADS_DIR set to `beadsDir`: gotenv.Load
		after an os.Stat check, which sets each variable that the environment
		does not have, except those named in `skipped`.
	**/
	public static function loadFile(beadsDir:String, ?skipped:Array<String>):Void {
		final path = FilepathPkg.join(beadsDir, ".env");
		if (OsPkg.stat(path).value2 != null)
			return;
		final variables = DotEnv.read(path, name -> name == "BEADS_DIR" ? beadsDir : Sys.getEnv(name));
		if (variables == null)
			return;
		for (name in variables.keys())
			if (name != "BEADS_DIR" && Sys.getEnv(name) == null && (skipped == null || !skipped.contains(name)))
				Sys.putEnv(name, variables.get(name));
	}

	/**
		The second setup's `.env` file for a command that opens a store and
		binds `target`, the redirect target of `foundBeadsDir` (see
		storeChainTarget).

		Why: upstream loads it after the first target's file (cmd/bd/main.go:
		1317), but keeps a redirecting directory's dolt_database in
		BEADS_DOLT_SERVER_DATABASE before that (:1210, and :603 for the first
		target), so the file's own value applies only when neither kept one.
		What: every other variable of the file that the environment lacks.
		How: the same reads as Application.validateEmbeddedDatabase's.
	**/
	static function loadSecondTargetFile(foundBeadsDir:String, target:String):Void {
		final redirecting = switch RedirectSource.lookup(environmentValue("BEADS_DIR")) {
			case RedirectedFrom(localDir): redirectSourceDatabase(localDir);
			case NotRedirected | RedirectUnknown: "";
		};
		final kept = environmentValue("BEADS_DOLT_SERVER_DATABASE") == ""
			&& (redirecting != "" || redirectSourceDatabase(foundBeadsDir) != "");
		loadFile(target, kept ? ["BEADS_DOLT_SERVER_DATABASE"] : []);
	}

	/**
		The workspace that a command which opens a store binds instead of
		`found`, the workspace that discovery found for `selection`, or null
		for `found` itself.

		Why: upstream's pre-run sets BEADS_DIR to the found workspace
		(cmd/bd/main.go:1219) before FindDatabasePath looks for the database
		through it (:1250), which follows that workspace's own redirect, a
		chain that FindBeadsDir ignored, and the second setup binds that
		target (:1316-1317). What: that redirect target, unless a --db path or
		a `db` setting selects the database, or the found workspace's metadata
		makes upstream bind it directly (see followsToDatabase). How: it only
		reads.
	**/
	public static function storeChainTarget(selection:WorkspaceSelection, found:WorkspaceLocation):Null<String> {
		final flag = selection.databasePath;
		if ((flag != "" && !namesDatabase(flag)) || databaseSettingSelects(selection) || !followsToDatabase(found))
			return null;
		return redirectedThrough(found.path);
	}

	/**
		The redirect target that upstream's lookups through BEADS_DIR find when
		BEADS_DIR names `beadsDir`: the target of its redirect when
		FollowRedirect follows it to another directory, or null.
	**/
	public static function redirectedThrough(beadsDir:String):Null<String> {
		return RedirectSource.followedTarget(RedirectSource.canonicalizePath(beadsDir));
	}

	/**
		The `.beads` directory whose config gives a command its settings after
		upstream's setups, which reread the JSON switch and other settings
		from it (refreshBoundCommandConfig, cmd/bd/main.go:1158, :1220, :1318),
		for `found`, the workspace that discovery found for `selection`. With
		-C, BEADS_DIR names that workspace before the first setup, which takes
		its redirect target. A command that opens a store also rereads them
		after it binds the second target of a chain (see storeChainTarget).
		Otherwise `found` itself; a database path selection follows no
		redirect.
	**/
	public static function settingsBeadsDir(selection:WorkspaceSelection, use:DatabaseVariableUse, found:WorkspaceLocation):String {
		final pathSelects = switch use {
			case BeforeWorkspace: noStorePathSelects(selection);
			case WithoutWorkspace: selection.databasePath != "" && !namesDatabase(selection.databasePath);
		};
		if (pathSelects)
			return found.path;
		final changeTarget = goTrimSpace(selection.directory) != "" ? redirectedThrough(found.path) : null;
		if (changeTarget != null)
			return changeTarget;
		final storeTarget = use == WithoutWorkspace ? storeChainTarget(selection, found) : null;
		return storeTarget != null ? storeTarget : found.path;
	}

	/**
		Whether upstream's pre-run looks for the database through the
		workspace that it found (cmd/bd/main.go:1223-1250), which follows that
		workspace's redirect, instead of binding the workspace itself: not for
		a proxied server, a metadata.json that does not load or names a
		backend other than Dolt, or a server host that implies server mode
		without metadata.json.
	**/
	static function followsToDatabase(location:WorkspaceLocation):Bool {
		if (location.proxiedServer)
			return false;
		final backend = switch readMetadataFields(location.path) {
			case MetadataFields(fields):
				final value = fields.get("backend");
				value == null ? "" : value;
			case MetadataAbsent:
				return !LayeredConfig.forWorkspace(location.path).hostImpliesServerMode();
			case MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported | MetadataFieldsLegacyOnly:
				return false;
		};
		return backend == "" || backend == "dolt";
	}

	/** The `.beads` directory of a discovery, or "" when it found none. */
	static function discoveredPath(discovery:WorkspaceDiscovery):String {
		return switch discovery {
			case Found(location): location.path;
			case NotFound | InvalidSelection(_): "";
		};
	}

	/**
		The `.beads` directory that upstream's pre-run sets up first for a
		command with this `use`, which loads that directory's `.env` file, or ""
		for none. `foundBeadsDir` is the directory that upstream's FindBeadsDir
		finds from -C, BEADS_DIR or the current directory ("" for none).

		Why: upstream binds the command to that directory before it reads any
		setting, and the directory can differ from the workspace that this
		build reads. What: for `where`, `version` and help pages, upstream's
		selectedNoDBBeadsDir (main.go:1156, see noStoreDirectory). For a
		command that opens the store, the directory that
		resolveCommandBeadsDir derives from a --db path, else from the `db`
		setting (main.go:1004, :1316); else the found directory (:1214-1219);
		and without one, the directory that BEADS_DB selects (:1250, :1316, see
		variableBeadsDir), unless -C or BEADS_DIR is set. How: it only reads.
		Upstream sets up a second time when it binds the database that it found
		in that directory (:1316), which names the same file.
	**/
	static function setupDirectory(selection:WorkspaceSelection, use:DatabaseVariableUse, foundBeadsDir:String):String {
		switch use {
			case BeforeWorkspace:
				return noStoreDirectory(selection, foundBeadsDir);
			case WithoutWorkspace:
		}
		final flag = selection.databasePath;
		if (flag != "" && !namesDatabase(flag))
			return commandBeadsDir(flag, foundBeadsDir);
		if (databaseSettingSelects(selection))
			return commandBeadsDir(LayeredConfig.atStartup().getString("db"), foundBeadsDir);
		if (foundBeadsDir != "")
			return foundBeadsDir;
		final variable = environmentValue("BEADS_DB");
		if (variable == "" || goTrimSpace(selection.directory) != "" || environmentValue("BEADS_DIR") != "")
			return "";
		return variableBeadsDir(variable);
	}

	/**
		Upstream selectedNoDBBeadsDir: the `.beads` directory that `where`,
		`version` and help pages set up, or "" for none.

		Why: a database path selects the directory that resolveCommandBeadsDir
		derives from it, which can differ from the workspace that this build
		reads. Commands that open a store set up the same directory for a `db`
		setting. What: that directory for the path that noStoreDatabasePath
		takes, or else the directory that -C, BEADS_DIR or the current
		directory finds. How: it only reads.
	**/
	public static function noStoreBeadsDir(workspace:WorkspacePort, selection:WorkspaceSelection):String {
		return noStoreDirectory(selection, discoveredPath(workspace.discover(selection.directory, "")));
	}

	/** noStoreBeadsDir with `foundBeadsDir`, the directory that -C, BEADS_DIR or the current directory finds ("" for none). */
	static function noStoreDirectory(selection:WorkspaceSelection, foundBeadsDir:String):String {
		final path = noStoreDatabasePath(selection);
		return path == "" ? foundBeadsDir : commandBeadsDir(path, foundBeadsDir);
	}

	/**
		The database path from which upstream's selectedNoDBBeadsDir takes the
		directory: --db, unless its value names a database (see namesDatabase),
		then BEADS_DB, then BD_DB, then the `db` setting (see
		databaseSettingSelects). "" when none of them gives a path.
	**/
	static function noStoreDatabasePath(selection:WorkspaceSelection):String {
		final flag = selection.databasePath;
		if (flag != "" && !namesDatabase(flag))
			return flag;
		for (name in ["BEADS_DB", "BD_DB"]) {
			final value = environmentValue(name);
			if (value != "")
				return value;
		}
		return databaseSettingSelects(selection) ? LayeredConfig.atStartup().getString("db") : "";
	}

	/**
		Whether a --db path, BEADS_DB or BD_DB gives upstream's
		selectedNoDBBeadsDir its directory (see noStoreDatabasePath), so that
		it does not look the workspace up.
	**/
	public static function noStorePathSelects(selection:WorkspaceSelection):Bool {
		final flag = selection.databasePath;
		return (flag != "" && !namesDatabase(flag)) || environmentValue("BEADS_DB") != "" || environmentValue("BD_DB") != "";
	}

	/**
		Whether upstream's pre-run takes a --db `value` as a database name
		instead of a path: an identifier as dbidentifier.ValidateIdentifier
		accepts it (at most 64 letters, digits and underscores, not starting
		with a digit) that names no file.
	**/
	static function namesDatabase(value:String):Bool {
		return value.length <= 64 && isEmbeddedDatabaseIdentifier(value) && ConfigProbes.statMissing(value);
	}

	/**
		Upstream's pre-run takes the `db` setting from the process-start config
		as the database path only when no --db flag, -C directory, BEADS_DB,
		BD_DB or BEADS_DIR selects the workspace. The config loads only when no
		selector is set.
	**/
	public static function databaseSettingSelects(selection:WorkspaceSelection):Bool {
		return selection.databasePath == ""
			&& goTrimSpace(selection.directory) == ""
			&& environmentValue("BEADS_DB") == ""
			&& environmentValue("BD_DB") == ""
			&& environmentValue("BEADS_DIR") == ""
			&& LayeredConfig.atStartup().getString("db") != "";
	}

	/**
		Whether BEADS_DB or BD_DB chooses the workspace of a command with the -C
		and --db values of `typed`.

		Why: without --db, upstream's commands that open the store read BEADS_DB
		when no -C or BEADS_DIR is set and no workspace is found from the current
		directory, and `where`, `version` and help pages read BEADS_DB, else
		BD_DB, before all of those. What: the variable and its path when one of
		them selects as described in DatabaseVariableUse. How: selectPath decides
		whether this build's --db discovery selects that path exactly as
		upstream does.
	**/
	static function selectDatabaseVariable(workspace:WorkspacePort, typed:WorkspaceSelection, use:DatabaseVariableUse):DatabaseVariableSelection {
		if (typed.databasePath != "")
			return NoVariable;
		return switch use {
			case WithoutWorkspace: selectWithoutWorkspace(workspace, typed);
			case BeforeWorkspace: selectBeforeWorkspace(workspace, typed);
		};
	}

	/**
		BEADS_DB for a command that opens the store, once nothing else selects a
		workspace. Upstream's database path is then the one that its
		FindDatabasePath takes from the variable (see variableDatabasePath).
	**/
	static function selectWithoutWorkspace(workspace:WorkspacePort, typed:WorkspaceSelection):DatabaseVariableSelection {
		final path = environmentValue("BEADS_DB");
		if (path == "" || goTrimSpace(typed.directory) != "" || environmentValue("BEADS_DIR") != "")
			return NoVariable;
		return switch workspace.discover("", "") {
			case NotFound:
				switch selectPath(workspace, "", "BEADS_DB", path) {
					case VariablePath(name, selected, _): VariablePath(name, selected, variableDatabasePath(selected));
					case NoVariable: NoVariable;
					case UnsupportedPath(name): UnsupportedPath(name);
				}
			case Found(_) | InvalidSelection(_): NoVariable;
		};
	}

	/** BEADS_DB, else BD_DB, for `where`, `version` and help pages, before -C, BEADS_DIR and the current directory. */
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
		such a parent before it compares any candidate. The VariablePath has no
		database path; selectWithoutWorkspace adds the one that upstream takes.
	**/
	static function selectPath(workspace:WorkspacePort, directory:String, name:String, path:String):DatabaseVariableSelection {
		final parent = FilepathPkg.dir(path);
		final inBeadsDirectory = FilepathPkg.base(parent) == ".beads";
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
				VariablePath(name, path, null);
			case Found(_) | NotFound | InvalidSelection(_):
				UnsupportedPath(name);
		};
	}

	/**
		The `.beads` directory that upstream's pre-run sets up for a command that
		opens the store when BEADS_DB names `path` and nothing else selects a
		workspace: resolveCommandBeadsDir of the database path that
		FindDatabasePath takes (see variableDatabasePath). No workspace is found
		then, so none is a candidate.
	**/
	public static function variableBeadsDir(path:String):String {
		return commandBeadsDir(variableDatabasePath(path), "");
	}

	/**
		Upstream FindDatabasePath for a BEADS_DB `path` when BEADS_DIR is unset:
		the canonical path (see canonicalPath), or, when that is a directory,
		the database that findDatabaseInBeadsDir finds there (see
		directoryDatabase). It is absolute, and `bd info` prints it.
	**/
	static function variableDatabasePath(path:String):String {
		final canonical = canonicalPath(path);
		if (isDirectory(canonical)) {
			final database = directoryDatabase(canonical);
			if (database != "")
				return database;
		}
		return canonical;
	}

	/**
		Upstream findDatabaseInBeadsDir: the database path that the metadata.json
		of `directory` selects, or "" for none.

		Why: FindDatabasePath takes it for a BEADS_DB directory. What: "" when
		metadata.json does not load or names a backend other than Dolt. In a
		Dolt server mode, the configured Dolt directory (configfile
		DatabasePath), which need not exist; else the `embeddeddolt` directory,
		then the configured Dolt directory, when they are directories. Without
		metadata.json, `embeddeddolt` and then `dolt`. How: upstream reads
		metadata.json with configfile.Load, which rewrites a legacy config.json
		as metadata.json; this reads it without the rewrite and, as
		claimingBeadsDir does, takes no fields from a legacy file. Server mode
		comes from the process-start config, which upstream's configfile reads
		at that point.
	**/
	static function directoryDatabase(directory:String):String {
		final embedded = FilepathPkg.join(directory, "embeddeddolt");
		var configured = true;
		var fields:Null<Map<String, String>> = null;
		switch readMetadataFields(directory) {
			case MetadataFields(decoded):
				fields = decoded;
			case MetadataFieldsLegacyOnly:
			case MetadataAbsent:
				configured = false;
			case MetadataFieldsUndecodable(_) | MetadataFieldsUnsupported:
				return "";
		}
		if (configured) {
			final backend = metadataField(fields, "backend");
			if (backend != "" && backend != "dolt")
				return "";
			final dolt = ConfigProbes.doltDirectory(directory, fields);
			if (LayeredConfig.atStartup().doltServerMode(metadataField(fields, "dolt_mode"), metadataField(fields, "dolt_server_host")))
				return dolt;
			if (isDirectory(embedded))
				return embedded;
			if (isDirectory(dolt))
				return dolt;
		}
		if (isDirectory(embedded))
			return embedded;
		final dolt = FilepathPkg.join(directory, "dolt");
		return isDirectory(dolt) ? dolt : "";
	}

	/** One decoded metadata.json field, or "" when it is absent or there are no fields. */
	static function metadataField(fields:Null<Map<String, String>>, tag:String):String {
		if (fields == null)
			return "";
		final value = fields.get(tag);
		return value == null ? "" : value;
	}

	static function isDirectory(path:String):Bool {
		return ConfigProbes.statPath(path).match(StatDirectory);
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
		for a `db` setting or a BEADS_DB path, set up this directory, which can
		differ from the workspace that this build's discovery returns for the
		same path. What: the directory of a workspace whose metadata.json claims
		the path (see claimingBeadsDir), or else databasePathBeadsDir. How: it
		only reads. Upstream's configfile.Load would rewrite a legacy
		config.json that it checks; such a directory counts as claiming the
		path here, without the rewrite.
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
		return discoveredPath(discoverWithBeadsDir(workspace, beadsDir));
	}

	/**
		The workspace that discovery finds while BEADS_DIR names `beadsDir`:
		the directory that upstream's FindBeadsDir finds then, with its config
		and the database that FindDatabasePath finds there. BEADS_DIR gets its
		value back before this returns.
	**/
	public static function discoverWithBeadsDir(workspace:WorkspacePort, beadsDir:String):WorkspaceDiscovery {
		final previous = Sys.getEnv("BEADS_DIR");
		Sys.putEnv("BEADS_DIR", beadsDir);
		final found = workspace.discover("", "");
		Sys.putEnv("BEADS_DIR", previous);
		return found;
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
		Upstream utils.CanonicalizePath: the absolute path with symbolic links
		resolved, or only the absolute path when that fails.

		Why: upstream compares and returns these paths, and on macOS it then
		takes each name's case from the file system, so a path typed in another
		case names the directory as stored, which upstream prints. What: on
		macOS the resolved path with the names that its directories list (see
		storedCasePath) when they are all found, else the resolved path.
		Windows keeps the resolved path, as upstream does. How: it only reads.
	**/
	static function canonicalPath(path:String):String {
		final absolute = absolutePath(path);
		final resolved = FilepathPkg.evalSymlinks(absolute);
		if (resolved.value2 != null)
			return absolute;
		if (Sys.systemName() == "Mac") {
			final stored = storedCasePath(resolved.value1);
			if (stored != "")
				return stored;
		}
		return resolved.value1;
	}

	/**
		Upstream resolveCanonicalCaseWalk: the absolute `path` with each name
		replaced by the first entry of its directory, in os.ReadDir's sorted
		order, that equals it under strings.EqualFold; "" when a directory
		cannot be read or has no such entry.

		Upstream first asks the kernel for the path (fcntl F_GETPATH) and walks
		only when that fails. Both give the stored names of a directory or file
		whose ancestors can be listed. They can differ for an ancestor that
		cannot be listed, a hard link, or a name stored in another Unicode
		normalization.
	**/
	static function storedCasePath(path:String):String {
		var stored = "/";
		for (name in FilepathPkg.clean(path).split("/")) {
			if (name == "")
				continue;
			final entries = try FileSystem.readDirectory(stored) catch (_:haxe.Exception) null;
			if (entries == null)
				return "";
			var match = "";
			for (entry in entries)
				if (StringsPkg.equalFold(entry, name)) {
					match = entry;
					break;
				}
			if (match == "")
				return "";
			stored = FilepathPkg.join(stored, match);
		}
		return stored;
	}

	/**
		Upstream utils.NormalizePathForComparison: the absolute path with its
		symbolic links resolved when they resolve, in lower case on macOS and
		Windows; "" for "". Unlike canonicalPath, it takes no case from the file
		system.
	**/
	static function comparablePath(path:String):String {
		if (path == "")
			return "";
		final absolute = absolutePath(path);
		final resolved = FilepathPkg.evalSymlinks(absolute);
		final normalized = resolved.value2 == null ? resolved.value1 : absolute;
		final system = Sys.systemName();
		return system == "Mac" || system == "Windows" ? normalized.toLowerCase() : normalized;
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
