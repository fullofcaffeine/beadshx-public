import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.mysql.MysqlPkg;
import beadshx.nativeextern.time.Duration;
import beadshx.nativeextern.time.TimePkg;

/**
	What: the Dolt server driver keeps typed dial, read and write timeouts.
	Why: a server connection needs bounded waits. The driver stores each
	`time.Duration` by value in `mysql.Config`, so the generated Go must copy
	values, not pointers.
	How: nothing requests a connection, and the endpoint is a missing Unix
	socket, so an unexpected dial cannot reach a real server.
**/
@:goNative
class Main {
	static inline final endpoint = "/nonexistent/beadshx-driver-timeouts.sock";

	static function duration(text:String):Duration {
		final parsed = TimePkg.parseDuration(text);
		if (parsed.value2 != null)
			throw 'parse duration $text: ${parsed.value2.toString()}';
		return parsed.value1;
	}

	static function expect(name:String, actual:String, expected:String):Void {
		if (actual != expected)
			throw '$name: expected $expected, received $actual';
	}

	static function expectNoConnections(name:String, openConnections:Int, inUse:Int, idle:Int):Void {
		if (openConnections != 0 || inUse != 0 || idle != 0)
			throw '$name: expected no connections, received open=$openConnections inUse=$inUse idle=$idle';
	}

	static function main():Void {
		final config = MysqlPkg.newConfig();
		expect("default dial timeout", config.timeout.toString(), "0s");
		expect("default read timeout", config.readTimeout.toString(), "0s");
		expect("default write timeout", config.writeTimeout.toString(), "0s");

		config.net = "unix";
		config.addr = endpoint;
		config.timeout = duration("1.5s");
		config.readTimeout = duration("30s");
		config.writeTimeout = duration("45s");
		expect("dial timeout", config.timeout.toString(), "1.5s");
		expect("read timeout", config.readTimeout.toString(), "30s");
		expect("write timeout", config.writeTimeout.toString(), "45s");
		// The driver's own DSN writer reads the native fields.
		expect("driver DSN", config.formatDSN(), 'unix($endpoint)/?readTimeout=30s&timeout=1.5s&writeTimeout=45s');

		// A field read is a copy: a later write must not change it.
		final earlierRead = config.timeout;
		final clone = config.clone();
		expect("cloned dial timeout", clone.timeout.toString(), "1.5s");
		expect("cloned read timeout", clone.readTimeout.toString(), "30s");
		expect("cloned write timeout", clone.writeTimeout.toString(), "45s");
		clone.timeout = duration("2s");
		config.readTimeout = duration("31s");
		expect("clone keeps its own dial timeout", clone.timeout.toString(), "2s");
		expect("original keeps its dial timeout", config.timeout.toString(), "1.5s");
		expect("clone keeps its read timeout", clone.readTimeout.toString(), "30s");
		expect("earlier read is a copy", earlierRead.toString(), "1.5s");
		config.readTimeout = duration("30s");

		final opened = MysqlPkg.newConnector(config);
		if (opened.value2 != null)
			throw 'new connector: ${opened.value2.text()}';
		final database = SqlPkg.openDB(opened.value1);
		final lazy = database.stats();
		expectNoConnections("opened database", lazy.openConnections, lazy.inUse, lazy.idle);
		final closeError = database.close();
		if (closeError != null)
			throw 'close database: ${closeError.toString()}';
		final closed = database.stats();
		expectNoConnections("closed database", closed.openConnections, closed.inUse, closed.idle);
		// A closed pool refuses before it asks the driver for a connection.
		final pingError = database.pingContext(ContextPkg.background());
		if (pingError == null)
			throw "ping after close: expected an error";
		expect("ping after close", pingError.toString(), "sql: database is closed");
		Sys.println("server driver timeouts: PASS");
	}
}
