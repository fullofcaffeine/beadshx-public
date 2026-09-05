package beadshx.nativeextern.doltdriver;

/** Package constructor for the independent embedded Dolt SQL connector. */
@:go.import("github.com/dolthub/driver/v2")
@:go.package("embedded")
@:goNative
extern class DoltDriverPkg {
	@:go.tupleReturn
	@:go.valueArgs("0")
	@:go.name("NewConnector")
	public static function newConnector(config:Config):NewConnectorResult;
}
