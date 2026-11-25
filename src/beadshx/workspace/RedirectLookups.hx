package beadshx.workspace;

import beadshx.config.ConfigProbes;
import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.nativeextern.os.OsPkg;
import beadshx.nativeextern.strconv.StrconvPkg;
import beadshx.nativeextern.user.UserPkg;
import beadshx.store.EmbeddedDatabaseLookup.redirectSourceDatabase;
import beadshx.workspace.RedirectSource.GitRepository;
import sys.FileSystem;

/**
	Upstream bd v1.2.1's workspace lookups that follow a `.beads/redirect`,
	with the warnings that each of them prints.

	Why: upstream calls FollowRedirect each time one of its steps looks up the
	workspace, and FollowRedirect prints its warnings on every call: a target
	that does not exist, a redirect chain, and the BD_DEBUG_ROUTING line. So a
	broken redirect warns several times per command, at times that upstream's
	steps decide. The native discovery prints the same warnings at its own
	times, so GoWorkspace silences it, and the commands call these lookups
	where upstream's steps run them.

	What: one object per process, which keeps upstream's process state that
	these lookups read: BEADS_DIR as upstream's pre-run sets it,
	BEADS_DOLT_SERVER_DATABASE as preserveRedirectSourceDatabase sets it, the
	once-only GetRepoContext and the once-per-directory warning for a target
	without project files. Each method is one upstream function and prints
	what upstream prints there. Before the command takes the output (see
	`release`), the lookups of the parser's `.env` step are held.

	How: the lookups only read the file system. They run `git rev-parse`
	once, and only when a `.beads` directory above the current directory has
	a redirect file: without one, no lookup that needs the repository root
	can print anything. Git worktree and jj workspace fallbacks are not
	modelled beyond RedirectSource's, and resolveCommandBeadsDir follows no
	redirect here.
**/
@:goNative
final class RedirectLookups {
	/** Upstream's unsafePrefixes (internal/beads/context.go:299): system directories that a workspace never trusts. */
	static final UNSAFE_PREFIXES = [
		"/etc",
		"/usr",
		"/var",
		"/root",
		"/System",
		"/Library",
		"/bin",
		"/sbin",
		"/opt",
		"/private"
	];

	var write:Null<String->Void> = null;
	var held = new StringBuf();

	/** BEADS_DIR as -C or prepareSelectedCommandContext set it; null while the process environment's value holds. */
	var boundBeadsDir:Null<String> = null;

	/** Whether a selected-directory setup ran, which loads that directory's `.env` (see `serverDatabaseSet`). */
	var selectedContextPrepared = false;

	final callerServerDatabase:Bool;
	var serverDatabasePreserved = false;
	var repoContextBuilt = false;
	final invalidTargetWarned = new Map<String, Bool>();
	final repositoryBeadsResolved = new Map<String, Bool>();
	var nearbyRedirect:Null<Bool> = null;
	var repositoryRead = false;
	var repository:Null<GitRepository> = null;

	public function new() {
		callerServerDatabase = environmentValue("BEADS_DOLT_SERVER_DATABASE") != "";
	}

	/** Prints the held warnings through `writer`, and every later one at once. */
	public function release(writer:String->Void):Void {
		write = writer;
		final text = held.toString();
		held = new StringBuf();
		if (text != "")
			writer(text);
	}

	/** Drops the held warnings: the command stops before upstream's pre-run, which would print them. */
	public function discard():Void {
		held = new StringBuf();
	}

	/**
		Upstream applyChangeDirSelection (cmd/bd/main.go:819): FindBeadsDirFrom
		for the -C directory (:808), and BEADS_DIR set to what it finds.
	**/
	public function changeDirectory(directory:String):Void {
		final absolute = FilepathPkg.abs(directory);
		if (absolute.value2 != null || !RedirectSource.isDirectory(absolute.value1))
			return;
		final found = findBeadsDirFrom(absolute.value1);
		if (found != "")
			boundBeadsDir = found;
	}

	/**
		Upstream prepareSelectedCommandContext (cmd/bd/main.go:596-614) up to its
		config reload: BEADS_DIR set to `beadsDir`, then
		preserveRedirectSourceDatabase for it (:603).
	**/
	public function prepareSelectedContext(beadsDir:String):Void {
		if (beadsDir == "")
			return;
		boundBeadsDir = beadsDir;
		selectedContextPrepared = true;
		preserveSourceDatabase(beadsDir);
	}

	/**
		Upstream preserveRedirectSourceDatabase (cmd/bd/main.go:496-508): unless
		BEADS_DOLT_SERVER_DATABASE is set, ResolveRedirect follows the redirect
		of `beadsDir` (internal/beads/beads.go:86), and a followed redirect from
		a directory whose metadata.json names a dolt_database sets that variable
		(RedirectSource.preserveSourceDatabase). Every later store open reads
		it, in every store mode: the embedded readers, and the native server
		open, which checks the name before it dials.
	**/
	public function preserveSourceDatabase(beadsDir:String):Void {
		if (beadsDir == "" || serverDatabaseSet() || follow(beadsDir) == beadsDir)
			return;
		final source = redirectSourceDatabase(beadsDir);
		if (source == "")
			return;
		serverDatabasePreserved = true;
		RedirectSource.preserveSourceDatabase(source);
		if (environmentValue("BD_DEBUG_ROUTING") != "")
			emit('[routing] Preserved source dolt_database ${StrconvPkg.quote(source)} across redirect\n');
	}

	/**
		Removes the dolt_database that preserveSourceDatabase kept in
		BEADS_DOLT_SERVER_DATABASE, for a workspace without metadata.json.

		Why: there upstream's pre-run opens `beads` whatever the variable says
		(cmd/bd/main.go:1484-1494), but the native facade's open would read
		it. What: the variable is unset when this object set it. The lookups
		still count it as set (see serverDatabaseSet), as upstream's do.
	**/
	public function dropPreservedServerDatabase():Void {
		if (serverDatabasePreserved)
			Sys.putEnv("BEADS_DOLT_SERVER_DATABASE", null);
	}

	/**
		Upstream FindBeadsDir (internal/beads/beads.go:757-998): BEADS_DIR's
		directory after its redirect when that has project files (:763), else
		the walk from the current directory to the repository root (:974).
		Returns the directory it finds, or "".
	**/
	public function findBeadsDir():String {
		final variable = beadsDirVariable();
		if (variable != "") {
			final followed = follow(RedirectSource.canonicalBeadsDir(variable));
			if (RedirectSource.isDirectory(followed) && RedirectSource.hasBeadsProjectFiles(followed))
				return followed;
		}
		final root = redirectNearby() ? repositoryRoot() : "";
		var current = RedirectSource.canonicalizePath(Sys.getCwd());
		while (current != "/" && current != ".") {
			final candidate = FilepathPkg.join(current, ".beads");
			if (RedirectSource.isDirectory(candidate)) {
				final followed = follow(candidate);
				if (RedirectSource.hasBeadsProjectFiles(followed))
					return followed;
			}
			if (root != "" && current == root)
				break;
			final parent = FilepathPkg.dir(current);
			if (parent == current)
				break;
			current = parent;
		}
		return "";
	}

	/**
		The `.beads` directories that upstream guardUndiscoveredLegacyWorkspace
		(cmd/bd/legacy_upgrade_guard.go:177-200) checks, in its order, when the
		pre-run finds no workspace: BEADS_DIR's directory after its redirect,
		which prints FollowRedirect's warnings here, or else the `.beads` of
		each directory from the current one up to the repository root. Outside
		a repository that is only the current directory's: upstream
		canonicalizes the empty root to the current directory.
	**/
	public function undiscoveredBeadsDirs():Array<String> {
		final variable = beadsDirVariable();
		if (variable != "")
			return [follow(RedirectSource.canonicalizePath(variable))];
		final root = repositoryRoot();
		final boundary = comparisonKey(RedirectSource.canonicalizePath(root != "" ? root : Sys.getCwd()));
		final directories = new Array<String>();
		var current = RedirectSource.canonicalizePath(Sys.getCwd());
		while (true) {
			directories.push(FilepathPkg.join(current, ".beads"));
			if (comparisonKey(current) == boundary)
				break;
			final parent = FilepathPkg.dir(current);
			if (parent == current)
				break;
			current = parent;
		}
		return directories;
	}

	/** Upstream utils.PathsEqual for two canonical paths: in lower case on macOS and Windows. */
	static function comparisonKey(path:String):String {
		final system = Sys.systemName();
		return system == "Mac" || system == "Windows" ? path.toLowerCase() : path;
	}

	/**
		Upstream FindBeadsDirFrom (internal/beads/beads.go:600-680) without its
		worktree and jj fallbacks: the walk from `start` (:636), which stops at
		the first `.beads` whose redirect target has project files.
	**/
	function findBeadsDirFrom(start:String):String {
		var current = RedirectSource.canonicalizePath(start);
		while (current != "/" && current != ".") {
			final candidate = FilepathPkg.join(current, ".beads");
			if (RedirectSource.isDirectory(candidate)) {
				final followed = follow(candidate);
				if (RedirectSource.hasBeadsProjectFiles(followed))
					return followed;
			}
			final parent = FilepathPkg.dir(current);
			if (parent == current)
				break;
			current = parent;
		}
		return "";
	}

	/**
		Upstream FindDatabasePath (internal/beads/beads.go:540-588): with
		BEADS_DIR set it follows that directory's redirect (:552); BEADS_DB
		names the database itself; otherwise findDatabaseInTree searches.
	**/
	public function findDatabasePath():Void {
		final variable = beadsDirVariable();
		if (variable != "")
			follow(RedirectSource.canonicalBeadsDir(variable));
		else if (environmentValue("BEADS_DB") == "")
			findDatabaseInTree();
	}

	/**
		Upstream findDatabaseInTree (internal/beads/beads.go:1122-1270) without
		its worktree and jj fallbacks: it follows the current directory's
		`.beads` redirect (:1157), then each `.beads` redirect from there to the
		repository root (:1252), until a directory holds a database. A
		directory with project files stands for one here: the commands reach
		this search only when discovery found no workspace.
	**/
	function findDatabaseInTree():Void {
		if (!redirectNearby())
			return;
		var current = RedirectSource.canonicalizePath(Sys.getCwd());
		final own = FilepathPkg.join(current, ".beads");
		if (RedirectSource.isDirectory(own) && RedirectSource.hasBeadsProjectFiles(follow(own)))
			return;
		final root = repositoryRoot();
		while (true) {
			final candidate = FilepathPkg.join(current, ".beads");
			if (RedirectSource.isDirectory(candidate) && RedirectSource.hasBeadsProjectFiles(follow(candidate)))
				return;
			final parent = FilepathPkg.dir(current);
			if (parent == current || (root != "" && current == root))
				return;
			current = parent;
		}
	}

	/**
		Upstream GetRedirectInfo (internal/beads/beads.go:345-363): the
		repository root's `.beads` when its redirect is followed (:354), else
		findLocalBeadsDir's directory, whose redirect it follows too (:361).
		Returns that directory (RedirectInfo.LocalDir), or "".
	**/
	public function getRedirectInfo():String {
		final repository = redirectNearby() ? gitRepository() : null;
		if (repository != null) {
			final repositoryBeads = FilepathPkg.join(repository.root, ".beads");
			if (RedirectSource.isDirectory(repositoryBeads)
				&& hasRedirectFile(repositoryBeads)
				&& follow(repositoryBeads) != repositoryBeads)
				return repositoryBeads;
		}
		final variable = beadsDirVariable();
		final local = variable != "" ? RedirectSource.canonicalBeadsDir(variable) : RedirectSource.localBeadsDir(repository);
		if (local != "" && hasRedirectFile(local))
			follow(local);
		return local;
	}

	/**
		Upstream warnMultipleDatabases (cmd/bd/worktree.go:51) through
		FindAllDatabases (internal/beads/beads.go:1283-1356): from the current
		directory, as os.Getwd names it, up to the repository root, it follows
		each `.beads` directory's redirect (:1302) until one holds a `dolt`
		directory or a `*.db` file. It never finds more than one, so it never
		prints its own warning.
	**/
	public function findAllDatabases():Void {
		if (!redirectNearby())
			return;
		final root = repositoryRoot();
		var current = FilepathPkg.clean(Sys.getCwd());
		while (true) {
			final candidate = FilepathPkg.join(current, ".beads");
			if (RedirectSource.isDirectory(candidate)) {
				final followed = follow(candidate);
				if (RedirectSource.isDirectory(FilepathPkg.join(followed, "dolt")) || hasDatabaseFile(followed))
					break;
			}
			final parent = FilepathPkg.dir(current);
			if (parent == current || (root != "" && current == root))
				break;
			current = parent;
		}
	}

	/**
		Upstream GetRepoContext (internal/beads/context.go:95-138), which builds
		its answer once per process: FindBeadsDir (:106), and for a workspace
		inside upstream's safe boundary (see isPathInSafeBoundary) also
		GetRedirectInfo (:117).
	**/
	public function getRepoContext():Void {
		if (repoContextBuilt)
			return;
		repoContextBuilt = true;
		final beadsDir = findBeadsDir();
		if (beadsDir != "" && isPathInSafeBoundary(beadsDir))
			getRedirectInfo();
	}

	/**
		Upstream doctor ResolveBeadsDirForRepo (cmd/bd/doctor/backend.go:32),
		which caches its answer per repository: beads.ResolveBeadsDirForRepo
		follows the repository's `.beads` redirect (internal/beads/beads.go:1044).
	**/
	public function resolveBeadsDirForRepo(repositoryPath:String):Void {
		final key = RedirectSource.canonicalizePath(repositoryPath);
		if (repositoryBeadsResolved.exists(key))
			return;
		repositoryBeadsResolved.set(key, true);
		final local = FilepathPkg.join(key, ".beads");
		if (RedirectSource.isDirectory(local))
			follow(local);
	}

	/**
		Upstream FollowRedirect (internal/beads/beads.go:104-185): prints its
		warnings for `beadsDir` and returns the directory that it returns. The
		warning for a target without project files prints once per `beadsDir`
		(warnInvalidRedirectTargetOnce, :196-203).
	**/
	public function follow(beadsDir:String):String {
		final target = switch RedirectSource.redirectTarget(beadsDir) {
			case Target(path): path;
			case NoTarget: return beadsDir;
		};
		if (!RedirectSource.isDirectory(target)) {
			emit('Warning: redirect target does not exist or is not a directory: ${target}\n');
			return beadsDir;
		}
		if (!RedirectSource.hasBeadsProjectFiles(target)) {
			if (!invalidTargetWarned.exists(beadsDir)) {
				invalidTargetWarned.set(beadsDir, true);
				emit('Warning: ignoring redirect from ${beadsDir} to ${target} because the target has no database or metadata.json; fix or delete the redirect file\n');
			}
			return beadsDir;
		}
		if (ConfigProbes.statSucceeds(FilepathPkg.join(target, "redirect")))
			emit('Warning: redirect chains not allowed, ignoring redirect in ${target}\n');
		if (environmentValue("BD_DEBUG_ROUTING") != "")
			emit('[routing] Followed redirect from ${beadsDir} -> ${target}\n');
		return target;
	}

	function emit(text:String):Void {
		final writer = write;
		if (writer == null)
			held.add(text);
		else
			writer(text);
	}

	/**
		Whether no lookup can print anything now: no `.beads` directory above the
		current directory has a redirect file, and neither has BEADS_DIR's.
		Callers skip the work that would only decide which lookups run.
	**/
	public function followsNothing():Bool {
		final variable = beadsDirVariable();
		return !redirectNearby() && (variable == "" || !hasRedirectFile(RedirectSource.canonicalBeadsDir(variable)));
	}

	/** Whether upstream's BEADS_DIR is set: by -C, by a setup, or in the environment. */
	public function beadsDirSet():Bool {
		return beadsDirVariable() != "";
	}

	function beadsDirVariable():String {
		final bound = boundBeadsDir;
		return bound != null ? bound : environmentValue("BEADS_DIR");
	}

	/**
		Whether BEADS_DOLT_SERVER_DATABASE is set for preserveRedirectSourceDatabase:
		by an earlier preservation, or in the environment. Before the first
		selected-directory setup that is the caller's environment, since upstream
		loads the workspace's `.env`, which this build loaded already, only there.
	**/
	function serverDatabaseSet():Bool {
		return serverDatabasePreserved
			|| (selectedContextPrepared ? environmentValue("BEADS_DOLT_SERVER_DATABASE") != "" : callerServerDatabase);
	}

	/**
		Whether a `.beads` directory above the current directory, as either the
		resolved or the os.Getwd path names it, has a redirect file. Without one
		the repository's own `.beads` and the walks follow nothing.
	**/
	function redirectNearby():Bool {
		final known = nearbyRedirect;
		if (known != null)
			return known;
		var found = false;
		for (start in [RedirectSource.canonicalizePath(Sys.getCwd()), FilepathPkg.clean(Sys.getCwd())]) {
			var current = start;
			while (!found) {
				found = hasRedirectFile(FilepathPkg.join(current, ".beads"));
				final parent = FilepathPkg.dir(current);
				if (parent == current)
					break;
				current = parent;
			}
		}
		nearbyRedirect = found;
		return found;
	}

	/** Upstream git.GetRepoRoot through RedirectSource's `git rev-parse`, read once; "" outside a repository. */
	function repositoryRoot():String {
		final repository = gitRepository();
		return repository == null ? "" : repository.root;
	}

	function gitRepository():Null<GitRepository> {
		if (!repositoryRead) {
			repositoryRead = true;
			repository = RedirectSource.gitRepository();
		}
		return repository;
	}

	static function hasRedirectFile(beadsDir:String):Bool {
		return ConfigProbes.statSucceeds(FilepathPkg.join(beadsDir, "redirect"));
	}

	/** filepath.Glob(`*.db`) in FindAllDatabases: any file whose name ends in `.db`. */
	static function hasDatabaseFile(beadsDir:String):Bool {
		final entries = try FileSystem.readDirectory(beadsDir) catch (_:haxe.Exception) [];
		for (entry in entries)
			if (StringTools.endsWith(entry, ".db"))
				return true;
		return false;
	}

	/**
		Upstream isPathInSafeBoundary (internal/beads/context.go:306-386): the
		temporary directory, /var/home and /var/tmp are safe; system
		directories are not; under /Users, /home and /var/home only the
		account's own home directory is. Upstream also trusts the macOS Shared
		folder (context.go:362); this build does not, because the repository's
		machine-local path check refuses that literal path, so a workspace
		there prints the post-run redirect warnings two times fewer than
		upstream (see the README limits).
	**/
	public static function isPathInSafeBoundary(path:String):Bool {
		final absoluteResult = FilepathPkg.abs(path);
		if (absoluteResult.value2 != null)
			return false;
		final absolute = absoluteResult.value1;
		final temporary = trimSlash(OsPkg.tempDir());
		final physicalTemporary = trimSlash(resolveLongestExistingAncestor(temporary));
		if (within(absolute, temporary) || within(absolute, physicalTemporary))
			return resolvedPathWithinRoot(absolute, temporary);
		if (StringTools.startsWith(absolute, "/var/home/"))
			return true;
		if (within(absolute, "/var/tmp"))
			return resolvedPathWithinRoot(absolute, "/var/tmp");
		for (prefix in UNSAFE_PREFIXES)
			if (within(absolute, prefix))
				return false;
		if (StringTools.startsWith(absolute, "/Users/")
			|| StringTools.startsWith(absolute, "/home/")
			|| StringTools.startsWith(absolute, "/var/home/")) {
			final account = UserPkg.current();
			final user = account.value1;
			var home = account.value2 == null && user != null ? user.homeDir : "";
			if (home == "") {
				final fallback = OsPkg.userHomeDir();
				home = fallback.value2 == null ? fallback.value1 : "";
			}
			if (home != "" && !within(absolute, trimSlash(home)))
				return false;
		}
		return true;
	}

	/** `path` is `root` or below it, by string prefix as upstream compares. */
	static function within(path:String, root:String):Bool {
		return path == root || StringTools.startsWith(path, root + "/");
	}

	static function trimSlash(path:String):String {
		return StringTools.endsWith(path, "/") ? path.substr(0, path.length - 1) : path;
	}

	/** Upstream resolvedPathWithinRoot (internal/beads/context.go:430-434). */
	static function resolvedPathWithinRoot(absolute:String, root:String):Bool {
		final resolved = resolveLongestExistingAncestor(absolute);
		final resolvedRoot = resolveLongestExistingAncestor(root);
		final separator = Sys.systemName() == "Windows" ? "\\" : "/";
		return resolved == resolvedRoot || StringTools.startsWith(resolved, resolvedRoot + separator);
	}

	/** Upstream resolveLongestExistingAncestor (internal/beads/context.go:394-413). */
	static function resolveLongestExistingAncestor(path:String):String {
		var current = FilepathPkg.clean(path);
		var remainder = "";
		while (true) {
			final resolved = FilepathPkg.evalSymlinks(current);
			if (resolved.value2 == null)
				return remainder == "" ? resolved.value1 : FilepathPkg.join(resolved.value1, remainder);
			final parent = FilepathPkg.dir(current);
			if (parent == current)
				return FilepathPkg.clean(path);
			remainder = FilepathPkg.join(FilepathPkg.base(current), remainder);
			current = parent;
		}
	}

	static function environmentValue(name:String):String {
		final value = Sys.getEnv(name);
		return value == null ? "" : value;
	}
}
