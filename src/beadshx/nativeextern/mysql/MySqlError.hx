package beadshx.nativeextern.mysql;

/** Read the driver's error code directly; classification policy belongs to Haxe. */
@:go.import("github.com/go-sql-driver/mysql")
@:go.name("MySQLError")
@:go.struct
extern class MySqlError {
	@:go.name("Number")
	public var number:Int;
}
