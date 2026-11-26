package beadshx.nativeextern.glamour;

/** Typed carrier for the rendered text and error results of `(*glamour.TermRenderer).Render`. */
@:goNative
final class RenderResult {
	public var value1(default, null):String;
	public var value2(default, null):Null<go.Error>;

	public function new(value1:String, value2:Null<go.Error>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
