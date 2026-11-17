import beadshx.nativeextern.database.sql.Tx;
import beadshx.nativeextern.context.ContextPkg;
import beadshx.store.EmbeddedScalarIssueDetailsReader;

/** Test boundary invokes actual assembly using a native-owned disposable transaction. */
@:access(beadshx.store.EmbeddedScalarIssueDetailsReader)
@:goNative
class Main {
	public static function observeLabels(transaction:Tx):String {
		return switch EmbeddedScalarIssueDetailsReader.readFromTransaction(ContextPkg.background(), transaction, "id-sentinel",
			{includeComments: false, includeDependents: false, briefDependencies: false}) {
			case EmbeddedScalarDetailsFound(details): haxe.Json.stringify({error: "", labels: details.labels});
			case EmbeddedScalarDetailsFailure(message): haxe.Json.stringify({error: message, labels: []});
			case EmbeddedScalarDetailsMissing: haxe.Json.stringify({error: "missing", labels: []});
			case EmbeddedScalarDetailsRequireRelations: haxe.Json.stringify({error: "relations", labels: []});
		};
	}

	static function main():Void {
		if (Sys.args().indexOf("--label-observer") >= 0)
			Sys.println(observeLabels(null));
	}
}
