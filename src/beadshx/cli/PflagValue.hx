package beadshx.cli;

import beadshx.nativeextern.strconv.StrconvPkg;
import haxe.Int64;

/** An int flag value, or pflag's message for a value that the flag rejects. */
enum IntFlagValue {
	IntAccepted(value:Int);
	IntRejected(message:String);
}

/** An int64 flag value, or pflag's message for a value that the flag rejects. */
enum Int64FlagValue {
	Int64Accepted(value:Int64);
	Int64Rejected(message:String);
}

/**
	Why: cobra parses the flags with pflag before any pre-run, so a value that a
	typed flag rejects fails first, with pflag's text, also with `--json`.

	What: pflag's FlagSet.Set message, `invalid argument %q for %q flag: %v`.
	The flag reads `-s, --name` when it has a shorthand and `--name` otherwise;
	the cause is the strconv error of the flag's type.

	How: int and int64 flags parse with the native `strconv.ParseInt(value, 0,
	64)`, as pflag does, so Go's prefixes, `_` separators, sign, range check and
	error text all apply. A bool flag's cause is strconv.ParseBool's error text.
**/
@:goNative
final class PflagValue {
	/** pflag's message for a value that the flag named `flagName` rejects with `cause`. */
	public static function invalidArgument(flagName:String, raw:String, cause:String):String {
		return 'invalid argument ${StrconvPkg.quote(raw)} for "${flagName}" flag: ${cause}';
	}

	/** pflag's message for a bool flag value that strconv.ParseBool rejects. */
	public static function invalidBoolean(flagName:String, raw:String):String {
		return invalidArgument(flagName, raw, 'strconv.ParseBool: parsing ${StrconvPkg.quote(raw)}: invalid syntax');
	}

	/** An int flag. pflag keeps the int64 as Go's int, which holds every int64 on a 64-bit build. */
	public static function parseInt(flagName:String, raw:String):IntFlagValue {
		final parsed = StrconvPkg.parseInt(raw, 0, 64);
		if (parsed.value2 != null)
			return IntRejected(invalidArgument(flagName, raw, parsed.value2.toString()));
		return IntAccepted(StrconvPkg.atoi(StrconvPkg.formatInt(parsed.value1, 10)).value1);
	}

	/** An int64 flag. */
	public static function parseInt64(flagName:String, raw:String):Int64FlagValue {
		final parsed = StrconvPkg.parseInt(raw, 0, 64);
		if (parsed.value2 != null)
			return Int64Rejected(invalidArgument(flagName, raw, parsed.value2.toString()));
		return Int64Accepted(Int64.parseString(StrconvPkg.formatInt(parsed.value1, 10)));
	}
}
