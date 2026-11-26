package beadshx.nativeextern.glamour;

/**
	The glamour v2 package functions that upstream's internal/uimd renders
	issue text with: the renderer and the options that it sets.
**/
@:go.import("charm.land/glamour/v2")
@:go.package("glamour")
@:goNative
extern class GlamourPkg {
	/** `glamour.NewTermRenderer(options...)`: a renderer with each option applied in order, or the first option's error. */
	@:go.tupleReturn
	@:go.name("NewTermRenderer") public static function newTermRenderer(options:haxe.Rest<TermRendererOption>):NewTermRendererResult;

	/** `glamour.WithWordWrap(width)`: wraps text at `width` columns. */
	@:go.name("WithWordWrap") public static function withWordWrap(width:Int):TermRendererOption;

	/** `glamour.WithPreservedNewLines()`: keeps the line breaks of the source text. */
	@:go.name("WithPreservedNewLines") public static function withPreservedNewLines():TermRendererOption;

	/** `glamour.WithTableWrap(wrap)`: whether table cells wrap. */
	@:go.name("WithTableWrap") public static function withTableWrap(wrap:Bool):TermRendererOption;

	/** `glamour.WithEnvironmentConfig()`: the style that GLAMOUR_STYLE names, or the dark style when it is empty. */
	@:go.name("WithEnvironmentConfig") public static function withEnvironmentConfig():TermRendererOption;

	/** `glamour.WithChromaFormatter(formatter)`: the chroma formatter for code blocks, such as "terminal256". */
	@:go.name("WithChromaFormatter") public static function withChromaFormatter(formatter:String):TermRendererOption;

	/** `glamour.WithStandardStyle(style)`: one of glamour's built-in styles, such as "notty" (`styles.NoTTYStyle`). */
	@:go.name("WithStandardStyle") public static function withStandardStyle(style:String):TermRendererOption;
}
