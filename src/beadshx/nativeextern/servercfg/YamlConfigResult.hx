package beadshx.nativeextern.servercfg;

/** Typed carrier for `servercfg.YamlConfigFromFile`'s config and read, expand or decode error results. */
@:goNative
final class YamlConfigResult {
	public var value1(default, null):Null<ServerConfig>;
	public var value2(default, null):Null<go.NativeError>;

	public function new(value1:Null<ServerConfig>, value2:Null<go.NativeError>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
