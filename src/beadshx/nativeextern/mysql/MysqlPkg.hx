package beadshx.nativeextern.mysql;

/** Constructors for a Dolt SQL server connection through the independent MySQL driver. */
@:go.import("github.com/go-sql-driver/mysql")
@:go.package("mysql")
@:goNative
extern class MysqlPkg {
	/** Returns the driver's defaults, which a zero `Config` does not have. */
	@:go.name("NewConfig")
	public static function newConfig():Config;

	/** Validates a private copy of `config`; it does not dial. */
	@:go.tupleReturn
	@:go.name("NewConnector")
	public static function newConnector(config:Config):NewConnectorResult;
}
