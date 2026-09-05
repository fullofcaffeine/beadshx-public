package beadshx.nativeextern.doltdriver;

/**
	What: the typed configuration fields needed to open an embedded Dolt connector.
	Why: Dolt is an independent storage library and remains behind a precise extern.
	How: omitted native fields retain their Go zero values.
**/
@:go.import("github.com/dolthub/driver/v2")
@:go.package("embedded")
@:go.name("Config")
@:go.struct
@:goNative
extern class Config {
	public function new();

	@:go.name("Directory")
	public var directory:String;

	@:go.name("CommitName")
	public var commitName:String;

	@:go.name("CommitEmail")
	public var commitEmail:String;

	@:go.name("Database")
	public var database:String;

	@:go.name("MultiStatements")
	public var multiStatements:Bool;
}
