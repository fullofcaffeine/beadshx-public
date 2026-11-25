package beadshx.nativeextern.template;

/** Exact standard-library template construction: `template.New(name)`. */
@:go.import("text/template")
@:go.package("template")
@:goNative
extern class TemplatePkg {
	@:go.name("New") public static function create(name:String):Template;
}
