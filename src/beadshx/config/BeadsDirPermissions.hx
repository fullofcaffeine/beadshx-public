package beadshx.config;

/**
	Upstream config.CheckBeadsDirPermissions for the directory `path`.

	Why: upstream's selected-directory setup warns on stderr, without failing,
	when group or others have any permission bit on the `.beads` directory.
	What: that warning line, or null when only the owner has bits.
	`permissions` is the text that Go's FileMode.String prints for the
	directory's permission bits, such as `-rwxr-xr-x` (see
	ConfigProbes.beadsDirPermissions). How: the nine letters give the bits;
	upstream checks `perm&0077`, prints the bits with `%04o`, and prints `path`
	as it names the directory.
**/
function beadsDirPermissionWarning(path:String, permissions:String):Null<String> {
	var mode = 0;
	for (index in 1...10)
		mode = (mode << 1) | (permissions.charAt(index) == "-" ? 0 : 1);
	// The group and other bits: octal 077.
	if ((mode & 63) == 0)
		return null;
	final octal = '0${mode >> 6}${(mode >> 3) & 7}${mode & 7}';
	return 'Warning: ${path} has permissions ${octal} (recommended: 0700). Run: chmod 700 ${path}\n';
}
