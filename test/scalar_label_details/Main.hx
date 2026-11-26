import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.store.SqlIssueDetailsReader;

/** Test boundary invokes actual assembly using a native-owned disposable transaction. */
@:goNative
class Main {
	public static function observeLabels(transaction:Tx):String {
		return switch SqlIssueDetailsReader.readSqlIssueDetails(ContextPkg.background(), transaction, "id-sentinel",
			{includeComments: false, includeDependents: false, briefDependencies: false}) {
			case Success(DetailsFound(details)): haxe.Json.stringify({error: "", labels: details.labels});
			case Failure(message): haxe.Json.stringify({error: message, labels: []});
			case Success(DetailsMissing): haxe.Json.stringify({error: "missing", labels: []});
		};
	}

	static function main():Void {
		if (Sys.args().indexOf("--label-observer") >= 0)
			Sys.println(observeLabels(null));
	}
}
