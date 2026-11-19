package beadshx.store;

import beadshx.nativeextern.context.Context;
import beadshx.nativeextern.database.sql.Tx;
import beadshx.store.CustomConfig.backfilledTypeNames;
import beadshx.store.CustomConfig.parseTypesConfigValue;

/**
	Reads the custom types that `bd types` lists, in the caller's SQL snapshot.

	Upstream opens an embedded store with its schema migrations, which fill an
	empty custom_types table from the types.custom config value, and then reads
	the table. These reads give what upstream reads after that fill, without
	writing. Like upstream `bd types`, a failed read gives no custom types.
	Upstream also adds types.custom from config.yaml and BD_TYPES_CUSTOM, which
	this build does not read yet (BHX-M08-02).
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
