package beadshx.nativeextern.user;

/** The `*user.User` field that upstream's path boundary check reads. */
@:go.import("os/user")
@:go.package("user")
@:go.name("User")
@:go.struct
extern class User {
	@:go.name("HomeDir") public var homeDir:String;
}
