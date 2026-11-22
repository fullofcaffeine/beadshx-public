package beadshx.nativeextern.database.sql;

/** Connection counts from `sql.DB.Stats`, used to observe a lazy pool. */
@:go.import("database/sql")
@:go.package("sql")
@:go.name("DBStats")
@:go.struct
extern class DBStats {
	public function new();

	@:go.name("MaxOpenConnections")
	public var maxOpenConnections:Int;

	@:go.name("Idle")
	public var idle:Int;

	@:go.name("InUse")
	public var inUse:Int;

	@:go.name("OpenConnections")
	public var openConnections:Int;
}
