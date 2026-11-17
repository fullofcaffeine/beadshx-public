package beadshx.store;

import haxe.Int64;

/** Inputs to the pinned human compaction-savings calculation. */
typedef CompactionSavingsInput = {
	final level:JsonInteger;
	final original:JsonInteger;
	final description:String;
	final design:String;
	final notes:String;
	final acceptance:String;
}

/**
	Pinned Beads calculations whose native Go `int` width affects output.

	JSON integers elsewhere can have any number of digits. Before arithmetic,
	this module rejects values outside the signed 64-bit range of the currently
	named amd64/arm64 Go targets. Subtraction then deliberately wraps like Go `int`.
**/
function parseSigned64(value:JsonInteger):StoreResult<Int64> {
	final wire = value.wireValue();
	final negative = wire.charAt(0) == "-";
	final digits = negative ? wire.substr(1) : wire;
	final limit = negative ? "9223372036854775808" : "9223372036854775807";
	if (digits.length > limit.length || (digits.length == limit.length && digits > limit))
		return Failure('native issue integer is outside signed 64-bit range: ${wire}');
	return Success(Int64.parseString(wire));
}

/** Go's merged issue/wisp sort compares the sign of a wrapping subtraction. */
function comparePriorityMerged(left:JsonInteger, right:JsonInteger):StoreResult<Int> {
	final nativeLeft = switch parseSigned64(left) {
		case Success(value): value;
		case Failure(message): return Failure(message);
	};
	final nativeRight = switch parseSigned64(right) {
		case Success(value): value;
		case Failure(message): return Failure(message);
	};
	final difference = nativeLeft - nativeRight;
	final order = Int64.compare(difference, Int64.ofInt(0));
	return Success(order < 0 ? -1 : order > 0 ? 1 : 0);
}

/**
	Report exact native byte sizes and Go's rounded compaction percentage.

	The source stores integer sizes; only the percentage converts to Float.
	`fmt.Sprintf` is the exact `%.0f` boundary, including ties-to-even. This
	precise extern passes the one Float value used by this format into Go's
	exported variadic call.
**/
function compactionSavingsLine(input:CompactionSavingsInput):StoreResult<String> {
	final nativeLevel = switch parseSigned64(input.level) {
		case Success(value): value;
		case Failure(message): return Failure(message);
	};
	final nativeOriginal = switch parseSigned64(input.original) {
		case Success(value): value;
		case Failure(message): return Failure(message);
	};
	final zero = Int64.ofInt(0);
	if (Int64.compare(nativeLevel, zero) == 0 || Int64.compare(nativeOriginal, zero) <= 0)
		return Success("");
	final current = nativeByteLength(input.description)
		+ nativeByteLength(input.design)
		+ nativeByteLength(input.notes)
		+ nativeByteLength(input.acceptance);
	final saved = nativeOriginal - current;
	if (Int64.compare(saved, zero) <= 0)
		return Success("");
	final percentage = Std.parseFloat(Int64.toStr(saved)) / Std.parseFloat(Int64.toStr(nativeOriginal)) * 100;
	final rounded = NativeIssuePercentFormat.sprintf("%.0f", percentage);
	return Success('📊 ${Int64.toStr(nativeOriginal)} → ${Int64.toStr(current)} bytes (${rounded}% reduction)');
}

/** Go's `len(string)` is a signed-64-bit byte count on the named targets. */
private function nativeByteLength(value:String):Int64 {
	final reader = NativeIssueStrings.newReader(value);
	// Reader.Size returns int64(len(value)); format through the exact native
	// scalar boundary without copying all bytes or narrowing through Haxe Int.
	return Int64.parseString(NativeIssueStrconv.formatInt(reader.size(), 10));
}

@:go.import("fmt") private extern class NativeIssuePercentFormat {
	@:go.name("Sprintf") public static function sprintf(format:String, value:Float):String;
}

@:go.import("strings") @:go.package("strings") @:goNative private extern class NativeIssueStrings {
	@:go.name("NewReader") public static function newReader(value:String):NativeIssueStringReader;
}

@:go.import("strings") @:go.package("strings") @:go.name("Reader") @:go.struct @:goNative private extern class NativeIssueStringReader {
	@:go.name("Size") public function size():go.NativeInt64;
}

@:go.import("strconv") @:go.package("strconv") @:goNative private extern class NativeIssueStrconv {
	@:go.name("FormatInt") public static function formatInt(value:go.NativeInt64, base:Int):String;
}
