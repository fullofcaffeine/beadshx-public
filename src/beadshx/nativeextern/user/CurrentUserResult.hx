package beadshx.nativeextern.user;

/** Typed carrier for the `(*user.User, error)` result of `user.Current`. */
@:goNative
final class CurrentUserResult {
	public var value1(default, null):Null<User>;
	public var value2(default, null):Null<go.NativeError>;

	public function new(value1:Null<User>, value2:Null<go.NativeError>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
