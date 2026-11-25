package beadshx.workspace;

import beadshx.config.ConfigProbes;
import beadshx.config.ConfigValidate.PathStat;
import beadshx.nativeextern.bytes.BytesPkg;
import beadshx.nativeextern.exec.Cmd;
import beadshx.nativeextern.exec.ExecPkg;
import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.nativeextern.strings.StringsPkg;
import beadshx.store.CustomConfig.goTrimSpace;
import sys.FileSystem;
import sys.io.File;

/** Upstream beads.GetRedirectInfo's answer, as its pre-run reads it before it follows a redirect. */
enum RedirectSourceLookup {
	/** `localDir` holds a redirect that upstream follows, so its dolt_database names the database that upstream opens. */
	RedirectedFrom(localDir:String);

	/** No local `.beads` directory, or one without a redirect that upstream follows. */
	NotRedirected;
}

/** What a `.beads/redirect` file names, as upstream FollowRedirect reads it. */
enum RedirectTarget {
	/** No readable redirect file, or one that names nothing. */
	NoTarget;

	/** The target as upstream canonicalizes it (see RedirectSource.canonicalBeadsDir). */
	Target(path:String);
}

/** Upstream gitContext: the repository of the current directory. */
typedef GitRepository = {
	final root:String;
	final commonDirectory:String;
	final worktree:Bool;
}

/**
	Upstream beads.GetRedirectInfo().LocalDir, the redirecting workspace whose
	dolt_database upstream's pre-run keeps (preserveRedirectSourceDatabase).

	Why: upstream does not take the redirecting workspace that discovery and
	`bd where` find. It looks first at the `.beads` directory of the Git
	repository root, also when -C or BEADS_DIR selects another workspace. Then
	it looks at BEADS_DIR, which -C sets, and only without one at the worktree
	fallbacks and the first `.beads` directory above the current directory.
	What: that directory when it holds a redirect that upstream follows.
	How: a port of GetRedirectInfo, checkRedirectInDir, findLocalBeadsDir and
	FollowRedirect, without their warnings, which RedirectLookups prints. Paths
	are canonical as upstream's are: on macOS each name has the case that the
	file system stores (see canonicalizePath).
**/
@:goNative
final class RedirectSource {
	/**
		`beadsDirVariable` is BEADS_DIR as upstream's pre-run sees it: the
		workspace that -C selects, which upstream writes to BEADS_DIR, or else
		the variable itself.
	**/
	public static function lookup(beadsDirVariable:String):RedirectSourceLookup {
		final repository = gitRepository();
		if (repository != null) {
			// findLocalBdsDirInRepo: the repository's own .beads first, whatever BEADS_DIR says.
			final repositoryBeads = FilepathPkg.join(repository.root, ".beads");
			if (isDirectory(repositoryBeads))
				switch checkRedirect(repositoryBeads) {
					case NotRedirected:
					case found:
						return found;
				}
		}
		return localRedirect(beadsDirVariable, repository);
	}

	/**
		Upstream preserveRedirectSourceDatabase: the redirecting workspace's
		dolt_database goes to BEADS_DOLT_SERVER_DATABASE, which every later
		store open of the process reads, the native facade's too.
	**/
	public static function preserveSourceDatabase(database:String):Void {
		Sys.putEnv("BEADS_DOLT_SERVER_DATABASE", database);
	}

	/**
		Upstream where's findOriginalBeadsDir (cmd/bd/where.go:146-190), with
		BEADS_DIR bound to `boundBeadsDir`, and where's comparison with
		`beadsDir`, the workspace that `where` reports (:69-72): the `.beads`
		directory that redirected to it, or "".

		Why: the setups of `where` bind BEADS_DIR to the directory that its
		last lookup starts from. When that directory has a redirect of its
		own, which the lookup follows, upstream names that directory as the
		origin of the workspace that it reports.
		What: BEADS_DIR's directory when it has a redirect file, else the first
		`.beads` directory above the current directory when that one has one;
		"" when that directory is `beadsDir` itself. How: it only reads.
	**/
	public static function whereOrigin(boundBeadsDir:String, beadsDir:String):String {
		final bound = canonicalizePath(boundBeadsDir);
		if (ConfigProbes.statSucceeds(FilepathPkg.join(bound, "redirect")))
			return bound == beadsDir ? "" : bound;
		final directory = FilepathPkg.clean(Sys.getCwd());
		final resolved = FilepathPkg.evalSymlinks(directory);
		var current = resolved.value2 == null ? resolved.value1 : directory;
		while (current != "/" && current != ".") {
			final candidate = FilepathPkg.join(current, ".beads");
			if (isDirectory(candidate))
				return candidate != beadsDir && ConfigProbes.statSucceeds(FilepathPkg.join(candidate, "redirect")) ? candidate : "";
			final parent = FilepathPkg.dir(current);
			if (parent == current)
				break;
			current = parent;
		}
		return "";
	}

	/** Upstream findLocalBeadsDir, then checkRedirectInDir on the directory it finds. */
	static function localRedirect(beadsDirVariable:String, repository:Null<GitRepository>):RedirectSourceLookup {
		if (beadsDirVariable != "")
			return checkRedirect(canonicalBeadsDir(beadsDirVariable));
		final local = localBeadsDir(repository);
		return local == "" ? NotRedirected : checkRedirect(local);
	}

	/**
		Upstream findLocalBeadsDir without BEADS_DIR: in a linked worktree its
		own `.beads` when that redirects or holds project files, else the
		`.beads` beside the main repository's Git directory; then the first
		`.beads` directory above the current directory, as os.Getwd names it.
		"" for none.
	**/
	public static function localBeadsDir(repository:Null<GitRepository>):String {
		if (repository != null && repository.worktree) {
			final worktreeBeads = FilepathPkg.join(repository.root, ".beads");
			if (ConfigProbes.statSucceeds(FilepathPkg.join(worktreeBeads, "redirect"))
				|| (isDirectory(worktreeBeads) && hasBeadsProjectFiles(worktreeBeads)))
				return worktreeBeads;
			// GetWorktreeFallbackBeadsDir: the .beads directory beside the main repository's Git directory.
			final common = canonicalizePath(repository.commonDirectory);
			final fallback = FilepathPkg.base(common) == ".git" ? FilepathPkg.join(FilepathPkg.dir(common), ".beads") : FilepathPkg.join(common, ".beads");
			if (isDirectory(fallback))
				return fallback;
		}
		var current = FilepathPkg.clean(Sys.getCwd());
		while (current != "/" && current != ".") {
			final candidate = FilepathPkg.join(current, ".beads");
			if (isDirectory(candidate))
				return candidate;
			final parent = FilepathPkg.dir(current);
			if (parent == current)
				break;
			current = parent;
		}
		return "";
	}

	/** Upstream checkRedirectInDir: a redirect file whose target FollowRedirect accepts. */
	static function checkRedirect(beadsDir:String):RedirectSourceLookup {
		if (!ConfigProbes.statSucceeds(FilepathPkg.join(beadsDir, "redirect")))
			return NotRedirected;
		return followRedirect(beadsDir) == beadsDir ? NotRedirected : RedirectedFrom(beadsDir);
	}

	/**
		Upstream FollowRedirect: the first line of the redirect file that is not
		empty or a comment, relative to the directory above `beadsDir`. It is
		`beadsDir` itself when that target is no directory or has no Beads
		project files.
	**/
	static function followRedirect(beadsDir:String):String {
		return switch redirectTarget(beadsDir) {
			case NoTarget: beadsDir;
			case Target(target): isDirectory(target) && hasBeadsProjectFiles(target) ? target : beadsDir;
		};
	}

	/**
		The directory that upstream FollowRedirect returns for `beadsDir` when
		that is another directory: the target of its redirect file, which has
		project files. Null when FollowRedirect returns `beadsDir` itself.
	**/
	public static function followedTarget(beadsDir:String):Null<String> {
		final target = followRedirect(beadsDir);
		return target == beadsDir ? null : target;
	}

	/**
		The target of `beadsDir`'s redirect file, as upstream FollowRedirect
		reads it: the first line that is not empty or a comment, relative to
		the directory above `beadsDir`, made canonical (see canonicalBeadsDir).
	**/
	public static function redirectTarget(beadsDir:String):RedirectTarget {
		final content:Null<String> = try File.getContent(FilepathPkg.join(beadsDir, "redirect")) catch (_:haxe.Exception) null;
		if (content == null)
			return NoTarget;
		var target = "";
		for (line in goTrimSpace(content).split("\n")) {
			final trimmed = goTrimSpace(line);
			if (trimmed != "" && !StringTools.startsWith(trimmed, "#")) {
				target = trimmed;
				break;
			}
		}
		if (target == "")
			return NoTarget;
		if (!FilepathPkg.isAbs(target))
			target = FilepathPkg.join(FilepathPkg.dir(beadsDir), target);
		return Target(canonicalBeadsDir(target));
	}

	/**
		Upstream canonicalizeBeadsDirPath (internal/beads/beads.go:205-211),
		which canonicalizes a BEADS_DIR path and a redirect target: the
		canonical path, or the `.beads` directory of a branch worktree that
		upstream prefers to it (see stableBranchWorktreeBeadsDir).
	**/
	public static function canonicalBeadsDir(path:String):String {
		final canonical = canonicalizePath(path);
		final stable = stableBranchWorktreeBeadsDir(canonical);
		return stable != "" ? stable : canonical;
	}

	/**
		Upstream preferStableBranchWorktreeBeadsDir (internal/beads/beads.go:
		221-275): for the `.beads` directory of a detached commit worktree, the
		canonical `.beads` directory of a branch worktree of the same
		repository that has the same commit checked out; "" for none.

		Why: upstream prefers a stable branch checkout to a detached snapshot
		checkout, which the megarepo convention places under
		`refs/commits/<sha>`, so its lookups, its warnings and the dolt_database
		that it keeps name the branch worktree's directory.
		What: `beadsDir` must be named `.beads`, and the directory above it
		must have `/refs/commits/` in its path and a detached HEAD
		(`git rev-parse --abbrev-ref HEAD` prints `HEAD`). The candidates are
		the worktrees that `git worktree list --porcelain` lists that are not
		bare, not detached and on a branch, with the same HEAD commit, other
		than that directory (by upstream's PathsEqual). Of them upstream takes
		only the first, those outside `/refs/commits/` first and then by path,
		and only when its `.beads` is a directory.
		How: up to three git commands, only for such a path. Upstream stops
		each git command after 5 seconds; this build waits for git.
	**/
	static function stableBranchWorktreeBeadsDir(beadsDir:String):String {
		if (FilepathPkg.base(beadsDir) != ".beads")
			return "";
		final root = FilepathPkg.dir(beadsDir);
		if (!inDetachedCommitWorktree(root))
			return "";
		if (gitOutput(ExecPkg.command("git", "-C", root, "rev-parse", "--abbrev-ref", "HEAD")) != "HEAD")
			return "";
		final head = gitOutput(ExecPkg.command("git", "-C", root, "rev-parse", "HEAD"));
		if (head == null || head == "")
			return "";
		final listing = gitOutput(ExecPkg.command("git", "-C", root, "worktree", "list", "--porcelain"));
		if (listing == null)
			return "";
		final candidates = [
			for (worktree in listWorktrees(listing))
				if (!worktree.bare && !worktree.detached && worktree.branch != "" && worktree.head == head && !samePath(worktree.path, root)) worktree.path
		];
		if (candidates.length == 0)
			return "";
		candidates.sort((first, second) -> {
			final firstStable = !inDetachedCommitWorktree(first);
			if (firstStable != !inDetachedCommitWorktree(second))
				return firstStable ? -1 : 1;
			return first < second ? -1 : (first > second ? 1 : 0);
		});
		final stable = FilepathPkg.join(candidates[0], ".beads");
		return isDirectory(stable) ? canonicalizePath(stable) : "";
	}

	/** Upstream isDetachedCommitWorktreePath: the megarepo convention of detached worktrees under `refs/commits/<sha>`. */
	static function inDetachedCommitWorktree(path:String):Bool {
		return path.indexOf("/refs/commits/") >= 0;
	}

	/** Upstream gitOutput: the command's standard output without surrounding white space, or null when it fails. */
	static function gitOutput(command:Cmd):Null<String> {
		final result = command.output();
		return result.value2 != null ? null : goTrimSpace(BytesPkg.newBuffer(result.value1).stringValue());
	}

	/** Upstream listWorktrees: the entries of `git worktree list --porcelain`, as upstream reads them. */
	static function listWorktrees(listing:String):Array<GitWorktree> {
		final worktrees = new Array<GitWorktree>();
		for (line in listing.split("\n")) {
			final current = worktrees.length > 0 ? worktrees[worktrees.length - 1] : null;
			if (StringTools.startsWith(line, "worktree "))
				worktrees.push(new GitWorktree(line.substr("worktree ".length)));
			else if (current == null)
				continue;
			else if (StringTools.startsWith(line, "HEAD "))
				current.head = line.substr("HEAD ".length);
			else if (StringTools.startsWith(line, "branch refs/heads/"))
				current.branch = line.substr("branch refs/heads/".length);
			else if (line == "detached")
				current.detached = true;
			else if (line == "bare")
				current.bare = true;
		}
		return worktrees;
	}

	/**
		Upstream utils.CanonicalizePath: the absolute path with symbolic links
		resolved, or only the absolute path when that fails.

		Why: upstream compares and returns these paths, and on macOS it then
		takes each name's case from the file system, so a path typed in another
		case names the directory as stored, which upstream prints: a redirect
		target in FollowRedirect's routing line and warnings, a BEADS_DIR path,
		a database path. What: on macOS the resolved path with the names that
		its directories list (see storedCasePath) when they are all found, else
		the resolved path. Windows keeps the resolved path, as upstream does.
		How: it only reads.
	**/
	public static function canonicalizePath(path:String):String {
		final absolute = FilepathPkg.isAbs(path) ? FilepathPkg.clean(path) : FilepathPkg.join(Sys.getCwd(), path);
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

		The F_GETPATH call costs one system call, but each step of the walk
		lists a whole directory, and a command canonicalizes the same paths
		many times. So the walk keeps the stored form of each path whose names
		it found (storedPrefixes): a name keeps its stored case while a command
		runs.
	**/
	static function storedCasePath(path:String):String {
		var typed = "/";
		var stored = "/";
		for (name in FilepathPkg.clean(path).split("/")) {
			if (name == "")
				continue;
			typed = FilepathPkg.join(typed, name);
			final known = storedPrefixes.get(typed);
			if (known != null) {
				stored = known;
				continue;
			}
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
			storedPrefixes.set(typed, stored);
		}
		return stored;
	}

	/** storedCasePath's answer for each path, as typed, whose names it found. */
	static final storedPrefixes = new Map<String, String>();

	/**
		Upstream utils.NormalizePathForComparison: the absolute path with its
		symbolic links resolved when they resolve, in lower case on macOS and
		Windows; "" for "". Unlike canonicalizePath, it takes no case from the
		file system.
	**/
	public static function comparablePath(path:String):String {
		if (path == "")
			return "";
		final absolute = FilepathPkg.isAbs(path) ? FilepathPkg.clean(path) : FilepathPkg.join(Sys.getCwd(), path);
		final resolved = FilepathPkg.evalSymlinks(absolute);
		final normalized = resolved.value2 == null ? resolved.value1 : absolute;
		final system = Sys.systemName();
		return system == "Mac" || system == "Windows" ? normalized.toLowerCase() : normalized;
	}

	/** Upstream utils.PathsEqual. */
	public static function samePath(first:String, second:String):Bool {
		return comparablePath(first) == comparablePath(second);
	}

	/** Upstream hasBeadsProjectFiles. */
	public static function hasBeadsProjectFiles(beadsDir:String):Bool {
		if (ConfigProbes.statSucceeds(FilepathPkg.join(beadsDir, "metadata.json"))
			|| ConfigProbes.statSucceeds(FilepathPkg.join(beadsDir, "config.yaml"))
			|| isDirectory(FilepathPkg.join(beadsDir, "dolt"))
			|| isDirectory(FilepathPkg.join(beadsDir, "embeddeddolt")))
			return true;
		final entries = try FileSystem.readDirectory(beadsDir) catch (_:haxe.Exception) [];
		for (entry in entries)
			if (StringTools.endsWith(entry, ".db") && entry.indexOf(".backup") < 0 && entry != "vc.db")
				return true;
		return false;
	}

	/** os.Stat names a directory, following a symbolic link. */
	public static function isDirectory(path:String):Bool {
		return ConfigProbes.statPath(path).match(StatDirectory);
	}

	/** Upstream initGitContext's `git rev-parse` in the current directory, or null outside a repository. */
	public static function gitRepository():Null<GitRepository> {
		final result = ExecPkg.command("git", "rev-parse", "--git-dir", "--git-common-dir", "--show-toplevel").output();
		if (result.value2 != null)
			return null;
		final lines = goTrimSpace(BytesPkg.newBuffer(result.value1).stringValue()).split("\n");
		if (lines.length < 3)
			return null;
		final gitDirectory = canonicalizeAbsolute(goTrimSpace(lines[0]));
		final commonDirectory = canonicalizeAbsolute(goTrimSpace(lines[1]));
		final root = goTrimSpace(lines[2]);
		final resolvedRoot = FilepathPkg.evalSymlinks(root);
		return {
			root: resolvedRoot.value2 == null ? resolvedRoot.value1 : root,
			commonDirectory: commonDirectory,
			worktree: gitDirectory != commonDirectory
		};
	}

	/** Go's filepath.Abs, which upstream applies to the Git directories before it compares them. */
	static function canonicalizeAbsolute(path:String):String {
		return FilepathPkg.isAbs(path) ? FilepathPkg.clean(path) : FilepathPkg.join(Sys.getCwd(), path);
	}
}

/** One entry of `git worktree list --porcelain`, as upstream's worktreeInfo holds it. */
private final class GitWorktree {
	public final path:String;
	public var head = "";
	public var branch = "";
	public var detached = false;
	public var bare = false;

	public function new(path:String) {
		this.path = path;
	}
}
