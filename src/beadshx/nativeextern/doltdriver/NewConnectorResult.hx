package beadshx.nativeextern.doltdriver;

/** Typed carrier for the embedded connector and construction error results. */
@:goBuildConstraint("cgo")
@:goNative
class NewConnectorResult {
	public var value1(default, null):Connector;
	public var value2(default, null):Null<go.Error>;

	public function new(value1:Connector, value2:Null<go.Error>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
