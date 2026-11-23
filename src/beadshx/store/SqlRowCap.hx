package beadshx.store;

import haxe.Int64;

/**
	Builds the SQL row-cap clause for a capped search.

	Why: upstream `searchTableInTxT` asks for one row more than the cap, so the
	caller can tell that the cap was exceeded. A cap of 2147483647 must therefore
	ask for `LIMIT 2147483648`, which does not fit in a 32-bit Haxe `Int`.

	What: `limitClause(maxRows)` returns ` LIMIT <maxRows + 1>`, or an empty string
	when there is no cap (`maxRows <= 0`).

	How: the sum is computed with `haxe.Int64`, so it never wraps. This is a pure
	function with no store access, so a unit test can prove the arithmetic without
	running a query. A query with a cap this large makes Dolt reserve memory in
	proportion to the limit (about 1.8 GB), in upstream bd as in BeadsHX.
**/
class SqlRowCap {
	public static function limitClause(maxRows:Int):String {
		return maxRows > 0 ? ' LIMIT ${Int64.toStr(Int64.ofInt(maxRows) + 1)}' : "";
	}
}
