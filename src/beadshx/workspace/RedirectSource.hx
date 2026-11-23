package beadshx.workspace;

import beadshx.config.ConfigProbes;
import beadshx.config.ConfigValidate.PathStat;
import beadshx.nativeextern.bytes.BytesPkg;
import beadshx.nativeextern.exec.ExecPkg;
import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.store.CustomConfig.goTrimSpace;
import sys.FileSystem;
import sys.io.File;

/** Upstream beads.GetRedirectInfo's answer, as its pre-run reads it before it follows a redirect. */
enum RedirectSourceLookup {
	/** `localDir` holds a redirect that upstream follows, so its dolt_database names the database that upstream opens. */
	RedirectedFrom(localDir:String);

	/** No local `.beads` directory, or one without a redirect that upstream follows. */
	NotRedirected;

	/**
		A redirect in, or to, a detached commit worktree (`/refs/commits/`), for
		which upstream may take a branch worktree instead. This build does not
		model that choice.
	**/
	RedirectUnknown;
}

/** Upstream gitContext: the repository of the current directory. */
private typedef GitRepository = {
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
	FollowRedirect, without their warnings, which discovery prints. Paths keep
	the case that the file system gives them: upstream's case lookup on macOS
	changes only how a path is written.
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

	/** Upstream findLocalBeadsDir, then checkRedirectInDir on the directory it finds. */
	static function localRedirect(beadsDirVariable:String, repository:Null<GitRepository>):RedirectSourceLookup {
		if (beadsDirVariable != "") {
			final canonical = canonicalBeadsDir(beadsDirVariable);
			if (canonical != null)
				return checkRedirect(canonical);
			// Upstream may take a branch worktree's .beads instead, which this build does not model; it refuses only when this one redirects.
			return ConfigProbes.statSucceeds(FilepathPkg.join(canonicalizePath(beadsDirVariable), "redirect")) ? RedirectUnknown : NotRedirected;
		}
		if (repository != null && repository.worktree) {
			final worktreeBeads = FilepathPkg.join(repository.root, ".beads");
			if (ConfigProbes.statSucceeds(FilepathPkg.join(worktreeBeads, "redirect"))
				|| (isDirectory(worktreeBeads) && hasBeadsProjectFiles(worktreeBeads)))
				return checkRedirect(worktreeBeads);
			// GetWorktreeFallbackBeadsDir: the .beads directory beside the main repository's Git directory.
			final common = canonicalizePath(repository.commonDirectory);
			final fallback = FilepathPkg.base(common) == ".git" ? FilepathPkg.join(FilepathPkg.dir(common), ".beads") : FilepathPkg.join(common, ".beads");
			if (isDirectory(fallback))
				return checkRedirect(fallback);
		}
		var current = FilepathPkg.clean(Sys.getCwd());
		while (current != "/" && current != ".") {
			final candidate = FilepathPkg.join(current, ".beads");
			if (isDirectory(candidate))
				return checkRedirect(candidate);
			final parent = FilepathPkg.dir(current);
			if (parent == current)
				break;
			current = parent;
		}
		return NotRedirected;
	}

	/** Upstream checkRedirectInDir: a redirect file whose target FollowRedirect accepts. */
	static function checkRedirect(beadsDir:String):RedirectSourceLookup {
		if (!ConfigProbes.statSucceeds(FilepathPkg.join(beadsDir, "redirect")))
			return NotRedirected;
		final target = followRedirect(beadsDir);
		return target == null ? RedirectUnknown : target == beadsDir ? NotRedirected : RedirectedFrom(beadsDir);
	}

	/**
		Upstream FollowRedirect: the first line of the redirect file that is not
		empty or a comment, relative to the directory above `beadsDir`. It is
		`beadsDir` itself when that target is no directory or has no Beads
		project files. Null when the target is in a detached commit worktree.
	**/
	static function followRedirect(beadsDir:String):Null<String> {
		final content:Null<String> = try File.getContent(FilepathPkg.join(beadsDir, "redirect")) catch (_:haxe.Exception) null;
		if (content == null)
			return beadsDir;
		var target = "";
		for (line in goTrimSpace(content).split("\n")) {
			final trimmed = goTrimSpace(line);
			if (trimmed != "" && !StringTools.startsWith(trimmed, "#")) {
				target = trimmed;
				break;
			}
		}
		if (target == "")
			return beadsDir;
		if (!FilepathPkg.isAbs(target))
			target = FilepathPkg.join(FilepathPkg.dir(beadsDir), target);
		final canonical = canonicalBeadsDir(target);
		if (canonical == null)
			return null;
		return isDirectory(canonical) && hasBeadsProjectFiles(canonical) ? canonical : beadsDir;
	}

	/** Upstream canonicalizeBeadsDirPath, or null where its detached-worktree preference could apply. */
	static function canonicalBeadsDir(path:String):Null<String> {
		final canonical = canonicalizePath(path);
		if (FilepathPkg.base(canonical) == ".beads" && FilepathPkg.dir(canonical).indexOf("/refs/commits/") >= 0)
			return null;
		return canonical;
	}

	/** Upstream utils.CanonicalizePath: the absolute path with its symbolic links resolved when they resolve. */
	static function canonicalizePath(path:String):String {
		final absolute = FilepathPkg.isAbs(path) ? FilepathPkg.clean(path) : FilepathPkg.join(Sys.getCwd(), path);
		final resolved = FilepathPkg.evalSymlinks(absolute);
		return resolved.value2 == null ? resolved.value1 : absolute;
	}

	/** Upstream hasBeadsProjectFiles. */
	static function hasBeadsProjectFiles(beadsDir:String):Bool {
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

	static function isDirectory(path:String):Bool {
		return ConfigProbes.statPath(path).match(StatDirectory);
	}

	/** Upstream initGitContext's `git rev-parse` in the current directory, or null outside a repository. */
	static function gitRepository():Null<GitRepository> {
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
