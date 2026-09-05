package beadshx.relation;

import haxe.io.Bytes;

enum DependencyKindParse {
	DependencyKindValid(value:DependencyKind);
	DependencyKindInvalid;
}

/**
	An open Beads dependency kind with the database column's byte bound.

	The vocabulary is intentionally open so workspaces can define relation
	kinds without modifying BeadsHX. Construction is validated at input and
	storage boundaries.
**/
abstract DependencyKind(String) {
	public static inline final MAX_BYTES = 32;

	private inline function new(value:String) {
		this = value;
	}

	public static function parse(value:String):DependencyKindParse {
		if (value == "" || Bytes.ofString(value).length > MAX_BYTES)
			return DependencyKindInvalid;
		return DependencyKindValid(new DependencyKind(value));
	}

	public inline function toString():String {
		return this;
	}
}
