package beadshx.nativeextern.template;

/** Typed carrier for `(*template.Template).Parse` template and error results. */
@:goNative
final class ParseTemplateResult {
	public var value1(default, null):Template;
	public var value2(default, null):Null<go.NativeError>;

	public function new(value1:Template, value2:Null<go.NativeError>) {
		this.value1 = value1;
		this.value2 = value2;
	}
}
