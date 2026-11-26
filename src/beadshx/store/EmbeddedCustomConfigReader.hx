package beadshx.store;

import beadshx.config.ConfigKeys.ConfigSetting;
import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.store.CustomConfig.DatabaseCustomStatuses;
import beadshx.store.CustomConfig.DatabaseCustomTypes;
import beadshx.store.EmbeddedSession.EmbeddedRead;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;

/**
	Own one read transaction for `bd types`, `bd statuses`, `bd config get` or
	`bd config list`, or for the routing settings and the issue count of
	contributor auto-routing; the config table semantics are authored Haxe.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedCustomConfigReader {
	static final WORDING = EmbeddedReadWording.forNoun("config", false);

	public static function readTypes(beadsDir:String, databaseName:String):StoreResult<DatabaseCustomTypes> {
		return fallBackAfterRelease(EmbeddedSession.withRead(beadsDir, databaseName, SqlCustomConfigReader.readCustomTypes), UnreadableTypes);
	}

	public static function readStatuses(beadsDir:String, databaseName:String):StoreResult<DatabaseCustomStatuses> {
		return fallBackAfterRelease(EmbeddedSession.withRead(beadsDir, databaseName, SqlCustomConfigReader.readCustomStatuses), NoStoredStatuses);
	}

	public static function readSetting(beadsDir:String, databaseName:String, key:String):StoreResult<String> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlCustomConfigReader.readSetting(context, transaction, key));
	}

	public static function readSettings(beadsDir:String, databaseName:String):StoreResult<Array<ConfigSetting>> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlCustomConfigReader.readSettings(context, transaction));
	}

	public static function readIssueTotal(beadsDir:String, databaseName:String):StoreResult<Int> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlCustomConfigReader.readIssueTotal(context, transaction));
	}

	static function read<T>(beadsDir:String, databaseName:String, reader:(Context, Tx) -> StoreResult<T>):StoreResult<T> {
		return WORDING.joinedResult(EmbeddedSession.withRead(beadsDir, databaseName, reader));
	}

	/**
		Upstream GetCustomTypes and GetCustomStatusesDetailed fall back to the
		layered list on every error of their store call, a failed rollback or
		close included, and `bd types` and `bd statuses` ignore the error that
		is left. So after the body, a failed release step gives `fallback`, the
		value of a failed table read, and no error. A step before the body
		keeps this reader's words.
	**/
	static function fallBackAfterRelease<T>(read:EmbeddedRead<T>, fallback:T):StoreResult<T> {
		return switch read {
			case EmbeddedReadNotStarted(stage, error, _): Failure(WORDING.stageMessage(stage, error));
			case EmbeddedReadFinished(value, cleanup): Success(cleanup.length == 0 ? value : fallback);
		};
	}
}
