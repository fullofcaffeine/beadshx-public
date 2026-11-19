package beadshx.nativeextern.database.sql.driver;

/**
	What: the standard `driver.Connector` interface that `sql.OpenDB` accepts.
	Why: the server driver returns this interface, not a concrete type.
	How: opaque; Go's `database/sql` alone calls its methods.
**/
@:go.import("database/sql/driver")
@:go.package("driver")
@:go.name("Connector")
extern interface Connector {}
