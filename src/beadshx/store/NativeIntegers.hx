package beadshx.store;

import beadshx.nativeextern.strconv.StrconvPkg;

/**
	Move exact native integers into validated decimal domain values. The native
	formatter guarantees integer syntax; validation protects that boundary contract.
	Class metadata declares the narrowly owned native authority.
**/
@:goNative
final class NativeIntegers {
	public static function fromInt(value:Int):JsonInteger {
		return validated(StrconvPkg.itoa(value));
	}

	public static function fromInt64(value:go.NativeInt64):JsonInteger {
		return validated(StrconvPkg.formatInt(value, 10));
	}

	static function validated(value:String):JsonInteger {
		return switch JsonInteger.parse(value) {
			case Success(integer): integer;
			case Failure(message): throw new haxe.Exception(message);
		};
	}
}
