package beadshx.store;

import beadshx.config.ConfigKeys.ConfigSetting;
import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.store.EmbeddedSession.EmbeddedReadWording;

/**
	Own one read transaction for `bd types`, `bd statuses`, `bd config get` or
	`bd config list`; the config table semantics are authored Haxe.
**/
@:goBuildConstraint("cgo")
@:goNative
final class EmbeddedCustomConfigReader {
	public static function readTypes(beadsDir:String, databaseName:String):StoreResult<CustomConfig.DatabaseCustomTypes> {
		return read(beadsDir, databaseName, (context, transaction) -> Success(SqlCustomConfigReader.readCustomTypes(context, transaction)));
	}

	public static function readStatuses(beadsDir:String, databaseName:String):StoreResult<CustomConfig.DatabaseCustomStatuses> {
		return read(beadsDir, databaseName, (context, transaction) -> Success(SqlCustomConfigReader.readCustomStatuses(context, transaction)));
	}

	public static function readSetting(beadsDir:String, databaseName:String, key:String):StoreResult<String> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlCustomConfigReader.readSetting(context, transaction, key));
	}

	public static function readSettings(beadsDir:String, databaseName:String):StoreResult<Array<ConfigSetting>> {
		return read(beadsDir, databaseName, (context, transaction) -> SqlCustomConfigReader.readSettings(context, transaction));
	}

	static function read<T>(beadsDir:String, databaseName:String, reader:(Context, Tx) -> StoreResult<T>):StoreResult<T> {
		return EmbeddedReadWording.forNoun("config", false).cleanupFailureFirst(EmbeddedSession.withRead(beadsDir, databaseName, reader));
	}
}
