import beadshx.nativeextern.context.ContextPkg;
import beadshx.nativeextern.database.sql.SqlPkg;
import beadshx.nativeextern.database.sql.NullString;
import beadshx.nativeextern.database.sql.TxOptions;
import beadshx.nativeextern.doltdriver.Config;
import beadshx.nativeextern.doltdriver.DoltDriverPkg;

/** Exercises Haxe-owned transaction lifecycle control over independent Go APIs. */
@:goNative
class Main {
	static function main():Void {
		final arguments = Sys.args();
		if (arguments.length != 1) {
			throw "usage: storage-transaction-tracer <disposable-directory>";
		}

		final config = new Config();
		config.directory = arguments[0];
		config.commitName = "BeadsHX transaction tracer";
		config.commitEmail = "beadshx-transaction-tracer@invalid";
		config.multiStatements = true;

		final openedConnector = DoltDriverPkg.newConnector(config);
		requireSuccess("create connector", openedConnector.value2);
		final connector = openedConnector.value1;
		final database = SqlPkg.openDoltDB(connector);
		final context = ContextPkg.background();

		final pingError = database.pingContext(context);
		if (pingError != null) {
			connector.close();
			throw 'ping database: ${pingError.toString()}';
		}

		final openedTransaction = database.beginTx(context, new TxOptions());
		if (openedTransaction.value2 != null) {
			database.close();
			connector.close();
			throw 'begin transaction: ${openedTransaction.value2.toString()}';
		}
		final transaction = openedTransaction.value1;
		final queried = transaction.queryContext(context, "SELECT CAST(? AS CHAR), NULL", "haxe-row");
		if (queried.value2 != null) {
			transaction.rollback();
			database.close();
			connector.close();
			throw 'query transaction: ${queried.value2.toString()}';
		}
		final rows = queried.value1;
		if (!rows.next())
			throw "query transaction: expected one row";
		final text = new NullString();
		final absent = new NullString();
		requireSuccess("scan transaction row", rows.scan(text, absent));
		if (!text.valid || text.string != "haxe-row" || absent.valid)
			throw "query transaction: nullable row values differ";
		if (rows.next())
			throw "query transaction: expected exactly one row";
		requireSuccess("finish transaction rows", rows.err());
		requireSuccess("close transaction rows", rows.close());

		requireSuccess("roll back transaction", transaction.rollback());
		requireSuccess("close database", database.close());
		requireSuccess("close connector", connector.close());
		Sys.println("storage transaction tracer: PASS");
	}

	static function requireSuccess(operation:String, error:Null<go.Error>):Void {
		if (error != null) {
			throw '$operation: ${error.toString()}';
		}
	}
}
