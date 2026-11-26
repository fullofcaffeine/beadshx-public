package beadshx.nativeextern.glamour;

/** Typed carrier for the renderer and error results of `glamour.NewTermRenderer`. */
@:goNative
final class NewTermRendererResult {
	public var value1(default, null):Null<TermRenderer>;
	public var value2(default, null):Null<go.Error>;

	public function new(value1:Null<TermRenderer>, value2:Null<go.Error>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
