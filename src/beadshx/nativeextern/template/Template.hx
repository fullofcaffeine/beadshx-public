package beadshx.nativeextern.template;

import beadshx.nativeextern.bytes.Buffer;

/**
	A standard-library `*template.Template` from `text/template`, the engine that upstream's
	`list --format` runs (cmd/bd/list_output.go:116-147).
**/
@:go.import("text/template")
@:go.package("template")
@:go.name("Template")
@:goNative
extern class Template {
	/** Parses `text` into this template; the error is upstream's parse error. */
	@:go.tupleReturn
	@:go.name("Parse") public function parse(text:String):ParseTemplateResult;

	/** Executes the template with `data` and writes the text into `writer`; null on success. */
	@:go.name("Execute") public function execute(writer:Buffer, data:go.NativeAny):Null<go.NativeError>;
}
