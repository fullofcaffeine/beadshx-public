package beadshx.nativeextern.fs;

/** Opaque native `io/fs.FileMode` value of one `os.FileInfo`, which upstream's permission check reads. */
@:go.import("io/fs")
@:go.package("fs")
@:go.name("FileMode")
@:go.valueType
extern class FileMode {
	/** `FileMode.Perm`: the mode with only its nine Unix permission bits. */
	@:go.valueReturn
	@:go.name("Perm") public function perm():FileMode;

	/**
		`FileMode.String`. For a mode that holds only permission bits, such as
		the result of `perm`, Go prints `-` and then `rwxrwxrwx`, with `-` in
		place of each bit that is not set.
	**/
	@:go.name("String") public function toString():String;

	/** `FileMode.IsRegular`: whether the mode has no type bits, as for a regular file but not a link, a directory or a device. */
	@:go.name("IsRegular") public function isRegular():Bool;
}
