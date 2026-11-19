package beadshx.nativeextern.mysql;

import beadshx.nativeextern.time.Duration;

/**
	What: the typed `mysql.Config` fields used to reach a Dolt SQL server.
	Why: the driver is an independent library; BeadsHX sets its fields directly
	instead of formatting and parsing a DSN string.
	How: start from `MysqlPkg.newConfig()`. Omitted fields keep driver defaults.
	Each timeout is a `time.Duration` stored by value: a write copies the value
	from its non-null carrier, and a read returns an independent copy.
**/
@:go.import("github.com/go-sql-driver/mysql")
@:go.package("mysql")
@:go.name("Config")
@:go.struct
@:goNative
extern class Config {
	@:go.name("Net")
	public var net:String;

	@:go.name("Addr")
	public var addr:String;

	/** Dial timeout. */
	@:go.name("Timeout")
	@:go.valueField
	public var timeout:Duration;

	/** I/O read timeout. */
	@:go.name("ReadTimeout")
	@:go.valueField
	public var readTimeout:Duration;

	/** I/O write timeout. */
	@:go.name("WriteTimeout")
	@:go.valueField
	public var writeTimeout:Duration;

	/** Returns an independent copy, as `NewConnector` also makes. */
	@:go.name("Clone")
	public function clone():Config;

	@:go.name("FormatDSN")
	public function formatDSN():String;
}
