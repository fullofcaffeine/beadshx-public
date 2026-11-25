package beadshx.config;

import beadshx.config.LayeredConfig.gitBeadsRole;
import beadshx.config.LayeredConfig.gitOutput;
import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.nativeextern.url.UrlPkg;
import beadshx.store.CustomConfig.goTrimSpace;
import sys.FileSystem;
import sys.io.File;

/**
	Upstream routing.DetectUserRole's check of the user's role.

	Why: upstream asks for the role each time `list` or `ready` reads issues,
	and each time an issue lookup misses and falls back to contributor
	auto-routing. When Git sets no role, upstream then prints WARNING on
	stderr, for example outside a Git repository.

	What: whether `git config --get beads.role` in the current directory gives
	`maintainer` or `contributor`. A jj secondary workspace has no Git
	repository of its own, so there upstream also asks its primary workspace.

	How: Git reads its system, global and repository config. This only reads;
	it never writes a setting.
**/
@:goNative
final class UserRole {
	/** The three lines that upstream prints on stderr when Git sets no role. */
	public static final WARNING = "warning: beads.role not configured (GH#2950).\n" + "  Fix: git config beads.role maintainer\n"
		+ "  Or:  git config beads.role contributor\n";

	/** Whether Git sets a role that upstream accepts, so that upstream prints no WARNING. */
	public static function configured():Bool {
		if (isUserRole(gitBeadsRole()))
			return true;
		final primary = jjPrimaryWorkspaceRoot(FilepathPkg.clean(Sys.getCwd()));
		return primary != null && isUserRole(gitBeadsRole(primary));
	}

	/**
		The role that upstream routing.DetectUserRole returns, without its WARNING
		(internal/routing/routing.go:37-64).

		Without a role from Git, upstream guesses it with the deprecated
		detectFromURL (:86-113) in the current directory, or in the primary
		workspace of a jj secondary workspace: without an `origin` remote the user
		is a maintainer; with an `upstream` remote for another repository a
		contributor; with an `origin` URL for SSH or with credentials (an `@`) a
		maintainer; and else a contributor.
	**/
	public static function detect():String {
		final role = gitBeadsRole();
		if (isUserRole(role))
			return role;
		final primary = jjPrimaryWorkspaceRoot(FilepathPkg.clean(Sys.getCwd()));
		if (primary != null && isUserRole(gitBeadsRole(primary)))
			return gitBeadsRole(primary);
		var origin = gitOutput(primary, ["remote", "get-url", "--push", "origin"]);
		if (origin == null)
			origin = gitOutput(primary, ["remote", "get-url", "origin"]);
		if (origin == null)
			return "maintainer";
		final originUrl = goTrimSpace(origin);
		final upstream = gitOutput(primary, ["remote", "get-url", "upstream"]);
		if (upstream != null && goTrimSpace(upstream) != "" && !sameRemoteRepository(originUrl, goTrimSpace(upstream)))
			return "contributor";
		return StringTools.startsWith(originUrl, "git@")
			|| StringTools.startsWith(originUrl, "ssh://")
			|| originUrl.indexOf("@") >= 0 ? "maintainer" : "contributor";
	}

	/** Upstream sameRemoteRepository: the same repository path when both remotes give one, else the same trimmed text. */
	static function sameRemoteRepository(left:String, right:String):Bool {
		final leftSlug = remoteRepositorySlug(left);
		final rightSlug = remoteRepositorySlug(right);
		if (leftSlug != null && rightSlug != null)
			return leftSlug == rightSlug;
		return goTrimSpace(left) == goTrimSpace(right);
	}

	/** Upstream remoteRepositorySlug: the path of an SCP-like remote after its colon, or of a URL that url.Parse accepts. */
	static function remoteRepositorySlug(remote:String):Null<String> {
		final trimmed = goTrimSpace(StringTools.endsWith(remote, "/") ? remote.substr(0, remote.length - 1) : remote);
		if (trimmed == "")
			return null;
		if (trimmed.indexOf("@") >= 0 && trimmed.indexOf(":") >= 0 && trimmed.indexOf("://") < 0)
			return normalizeRemotePath(trimmed.substr(trimmed.indexOf(":") + 1));
		final parsed = UrlPkg.parse(trimmed);
		final url = parsed.value1;
		return parsed.value2 != null || url == null ? null : normalizeRemotePath(url.path);
	}

	/** Upstream normalizeRemotePath: without slashes around it and without a final `.git`; null when that leaves nothing. */
	static function normalizeRemotePath(path:String):Null<String> {
		var start = 0;
		var end = path.length;
		while (start < end && path.charAt(start) == "/")
			start++;
		while (end > start && path.charAt(end - 1) == "/")
			end--;
		var normalized = goTrimSpace(path.substring(start, end));
		if (StringTools.endsWith(normalized, ".git"))
			normalized = normalized.substr(0, normalized.length - 4);
		return normalized == "" ? null : normalized;
	}

	/** Upstream roleFromGitConfig accepts only these two values. */
	static function isUserRole(value:String):Bool {
		return value == "maintainer" || value == "contributor";
	}

	/**
		Upstream git.GetJJPrimaryWorkspaceRootFrom, for a jj secondary workspace
		only: its `.jj/repo` is a file that names the primary's `.jj/repo`
		directory, relative to `.jj` or absolute. Null when `start` is not in a
		secondary workspace or the file names nothing. Upstream also resolves
		symbolic links in the path, which does not change where Git reads.
	**/
	static function jjPrimaryWorkspaceRoot(start:String):Null<String> {
		final root = jjWorkspaceRoot(start);
		if (root == null)
			return null;
		final repository = FilepathPkg.join(root, ".jj", "repo");
		if (!FileSystem.exists(repository) || FileSystem.isDirectory(repository))
			return null;
		final target = try goTrimSpace(File.getContent(repository)) catch (_:haxe.Exception) "";
		if (target == "")
			return null;
		final primaryRepository = FilepathPkg.isAbs(target) ? FilepathPkg.clean(target) : FilepathPkg.join(root, ".jj", target);
		return FilepathPkg.dir(FilepathPkg.dir(primaryRepository));
	}

	/** Upstream getJujutsuRootFrom: the nearest directory with a `.jj` directory, without passing a Git repository. */
	static function jjWorkspaceRoot(start:String):Null<String> {
		var directory = start;
		var previous = "";
		while (directory != previous) {
			final jj = FilepathPkg.join(directory, ".jj");
			if (FileSystem.exists(jj) && FileSystem.isDirectory(jj))
				return directory;
			if (FileSystem.exists(FilepathPkg.join(directory, ".git")))
				return null;
			previous = directory;
			directory = FilepathPkg.dir(directory);
		}
		return null;
	}
}
