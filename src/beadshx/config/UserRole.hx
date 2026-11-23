package beadshx.config;

import beadshx.config.LayeredConfig.gitBeadsRole;
import beadshx.nativeextern.filepath.FilepathPkg;
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
