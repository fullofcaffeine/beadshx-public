import beadshx.store.EmbeddedSession;
import beadshx.store.ExportIssueLine;
import beadshx.store.SqlExportReader;
import beadshx.store.StoreResult;

/**
	Prints the line that the Haxe export read gives for each issue of an
	upstream-created disposable workspace, in the read's own order, so that
	scripts/beadshx/test-export-read.sh can compare them with upstream
	`bd export --all`. The read runs in one rolled-back transaction.
**/
@:goNative
class Main {
	static function main():Void {
		final args = Sys.args();
		if (args.length != 1)
			throw "usage: export-read-test <disposable workspace>";
		final workspace = args[0];
		if (!sys.FileSystem.exists(haxe.io.Path.join([workspace, ".beadshx-disposable-fixture"])))
			throw 'export read test requires a disposable fixture: $workspace';
		final read = EmbeddedSession.withRead(haxe.io.Path.join([workspace, ".beads"]), "",
			(context, transaction) -> SqlExportReader.readAllIssues(context, transaction));
		final issues = switch read {
			case EmbeddedReadNotStarted(_, error, _): fail('session: ${error.toString()}');
			case EmbeddedReadFinished(Failure(message), _): fail(message);
			case EmbeddedReadFinished(Success(value), cleanup):
				if (cleanup.length > 0)
					fail("session release failed");
				value;
		};
		final lines = new StringBuf();
		for (issue in issues)
			switch ExportIssueLine.render(issue) {
				case Failure(message):
					fail(message);
				case Success(line):
					lines.add(line + "\n");
			}
		Sys.print(lines.toString());
	}

	static function fail<T>(message:String):T {
		Sys.stderr().writeString('export read: FAIL: $message\n');
		Sys.exit(1);
		throw message;
	}
}
