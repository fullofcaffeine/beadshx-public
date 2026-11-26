package beadshx.store;

import beadshx.nativeextern.strconv.StrconvPkg;
import haxe.Int64;

/**
	Go `int` addition for the row bounds of the list and ready reads.

	Why: a Haxe `Int` here can hold a value of Go's 64-bit `int`, because the
	command parses `--limit`, `--max-rows` and BEADS_MAX_ROWS natively, but Haxe
	`Int` arithmetic wraps at 32 bits. Upstream adds in Go's `int`, so
	`BEADS_MAX_ROWS=4294967297` asks for `LIMIT 4294967298`, not `LIMIT 2`.
	How: the sum is taken in `haxe.Int64` from each value's exact decimal text,
	so it wraps as Go's `int` does, and comes back through Go's `strconv.Atoi`.
**/
@:goNative
final class GoInt {
	public static function add(left:Int, right:Int):Int {
		final sum = Int64.parseString(StrconvPkg.itoa(left)) + Int64.parseString(StrconvPkg.itoa(right));
		return StrconvPkg.atoi(Int64.toStr(sum)).value1;
	}
}
