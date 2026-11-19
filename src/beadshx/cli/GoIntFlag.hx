package beadshx.cli;

import haxe.Int64;
import beadshx.nativeextern.strconv.StrconvPkg;

/** pflag's int and int64 flags: `strconv.ParseInt(value, 0, 64)`, so 0x, 0o, 0b, a sign and `_` follow Go syntax. */
@:goNative
final class GoIntFlag {
	/** Assigns the value, or returns pflag's message for a value that ParseInt rejects. */
	public static function parse(flag:String, raw:String, assign:Int64->Void):Null<String> {
		final parsed = StrconvPkg.parseInt(raw, 0, 64);
		if (parsed.value2 != null)
			return 'invalid argument ${StrconvPkg.quote(raw)} for "${flag}" flag: ${parsed.value2.toString()}';
		assign(Int64.parseString(StrconvPkg.formatInt(parsed.value1, 10)));
		return null;
	}
}
