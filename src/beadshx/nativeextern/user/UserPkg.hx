package beadshx.nativeextern.user;

/** The standard-library account lookup that upstream's path boundary check trusts over HOME. */
@:go.import("os/user")
@:go.package("user")
@:goNative
extern class UserPkg {
	/** `user.Current`: the account of the process's user, from the account database. */
	@:go.tupleReturn
	@:go.name("Current") public static function current():CurrentUserResult;
}
