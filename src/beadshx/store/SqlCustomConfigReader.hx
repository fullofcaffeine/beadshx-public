package beadshx.store;

import beadshx.config.ConfigKeys.ConfigSetting;
import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.store.CustomConfig.CustomStatus;
import beadshx.store.CustomConfig.backfilledStatuses;
import beadshx.store.CustomConfig.backfilledTypeNames;
import beadshx.store.CustomConfig.parseCustomStatusConfig;
import beadshx.store.CustomConfig.parseTypesConfigValue;
import beadshx.store.DatabaseErrors.isTableNotExist;

/**
	Reads the custom types and statuses that `bd types` and `bd statuses` list, in
	the caller's SQL snapshot.

	Upstream opens an embedded store with its schema migrations, which fill an
	empty custom_types or custom_statuses table from the types.custom or
	status.custom config value, and then reads the table. These reads give what
	upstream reads after that fill, without writing. Like upstream, a failed read
	gives no custom entries. Upstream also reads both keys from config.yaml and
	BD_TYPES_CUSTOM or BD_STATUS_CUSTOM, which this build does not read yet
	(BHX-M08-02).
**/
@:goNative
final class SqlCustomConfigReader {
	/** Upstream ResolveCustomTypesInTx: the table by name, or else the config value. */
	public static function readCustomTypes(context:Context, transaction:Tx):Array<String> {
		final stored = new Array<String>();
		// Like upstream, a failed table query falls through to the config value.
		final queried = transaction.queryContext(context, "SELECT name FROM custom_types ORDER BY name");
		if (queried.value2 == null) {
			final rows = queried.value1;
			while (rows.next()) {
				final name = go.NativePointer.of("");
				// Upstream skips a row it cannot scan.
				if (rows.scan(name) == null)
					stored.push(name.get());
			}
			final rowError = rows.err();
			rows.close();
			if (rowError != null)
				return [];
		}
		if (stored.length > 0)
			return stored;
		final value = readConfigValue(context, transaction, "types.custom");
		return value == null ? [] : backfilledTypeNames(parseTypesConfigValue(value));
	}

	/** Upstream ResolveCustomStatusesDetailedInTx: the table by name, or else the config value. */
	public static function readCustomStatuses(context:Context, transaction:Tx):Array<CustomStatus> {
		final queried = transaction.queryNativeContext(context, "SELECT name, category FROM custom_statuses ORDER BY name");
		if (queried.error != null) {
			// Only a missing table falls through to the config value.
			if (!isTableNotExist(queried.error))
				return [];
		} else {
			final rows = queried.rows;
			final stored = new Array<CustomStatus>();
			while (rows.next()) {
				final name = go.NativePointer.of("");
				final category = go.NativePointer.of("");
				if (rows.scan(name, category) != null) {
					rows.close();
					return [];
				}
				stored.push({name: name.get(), category: category.get()});
			}
			final rowError = rows.err();
			rows.close();
			if (rowError != null)
				return [];
			if (stored.length > 0)
				return stored;
		}
		final value = readConfigValue(context, transaction, "status.custom");
		final parsed = value == null ? null : parseCustomStatusConfig(value);
		return parsed == null ? [] : backfilledStatuses(parsed);
	}

	/** Upstream GetConfigInTx for `bd config get`: an empty string for a missing key. */
	public static function readSetting(context:Context, transaction:Tx, key:String):StoreResult<String> {
		final queried = transaction.queryContext(context, "SELECT value FROM config WHERE `key` = ?", key);
		if (queried.value2 != null)
			return Failure('get config ${key}: ${queried.value2.toString()}');
		final rows = queried.value1;
		if (!rows.next()) {
			final rowError = rows.err();
			rows.close();
			return rowError == null ? Success("") : Failure('get config ${key}: ${rowError.toString()}');
		}
		final value = go.NativePointer.of("");
		final scanError = rows.scan(value);
		rows.close();
		return scanError == null ? Success(value.get()) : Failure('get config ${key}: ${scanError.toString()}');
	}

	/** Upstream GetAllConfigInTx for `bd config list`: every row, in the order the table gives them. */
	public static function readSettings(context:Context, transaction:Tx):StoreResult<Array<ConfigSetting>> {
		final queried = transaction.queryContext(context, "SELECT `key`, value FROM config");
		if (queried.value2 != null)
			return Failure('get all config: ${queried.value2.toString()}');
		final rows = queried.value1;
		final settings = new Array<ConfigSetting>();
		while (rows.next()) {
			final key = go.NativePointer.of("");
			final value = go.NativePointer.of("");
			final scanError = rows.scan(key, value);
			if (scanError != null) {
				rows.close();
				return Failure('get all config: scan: ${scanError.toString()}');
			}
			settings.push({key: key.get(), value: value.get()});
		}
		final rowError = rows.err();
		rows.close();
		return rowError == null ? Success(settings) : Failure(rowError.toString());
	}

	/** Upstream GetConfigInTx: an empty string for a missing key, or null for a failed read. */
	static function readConfigValue(context:Context, transaction:Tx, key:String):Null<String> {
		final queried = transaction.queryContext(context, "SELECT value FROM config WHERE `key` = ?", key);
		if (queried.value2 != null)
			return null;
		final rows = queried.value1;
		if (!rows.next()) {
			final rowError = rows.err();
			rows.close();
			return rowError == null ? "" : null;
		}
		final value = go.NativePointer.of("");
		final scanError = rows.scan(value);
		final closeError = rows.close();
		return scanError == null && closeError == null ? value.get() : null;
	}
}
