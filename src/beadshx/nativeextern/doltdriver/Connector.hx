package beadshx.nativeextern.doltdriver;

/** Exact embedded Dolt connector lifetime surface used by Haxe storage. */
@:go.import("github.com/dolthub/driver/v2")
@:go.package("embedded")
@:go.name("Connector")
@:go.struct
@:goNative
extern class Connector {
	public function new();

	@:go.name("Close")
	public function close():go.Error;
}
