package beadshx.nativeextern.mysql;

import beadshx.nativeextern.database.sql.driver.Connector;

/** Typed carrier for the driver connector and its native construction error. */
@:goNative
final class NewConnectorResult {
	public var value1(default, null):Connector;
	public var value2(default, null):Null<go.NativeError>;

	public function new(value1:Connector, value2:Null<go.NativeError>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
