package beadshx.nativeextern.glamour;

/** A glamour v2 `*TermRenderer`: a Markdown renderer for terminal output. */
@:go.import("charm.land/glamour/v2")
@:go.package("glamour")
@:go.name("TermRenderer")
@:go.struct
@:goNative
extern class TermRenderer {
	/** `(*TermRenderer).Render(in)`: the rendered text, or the renderer's error. */
	@:go.tupleReturn
	@:go.name("Render") public function render(markdown:String):RenderResult;
}
