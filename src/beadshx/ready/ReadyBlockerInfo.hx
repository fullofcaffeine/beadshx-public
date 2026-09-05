package beadshx.ready;

/** Typed blocker details exposed by `ready --explain`. */
typedef ReadyBlockerInfo = {
	final id:String;
	final title:String;
	final status:String;
	final priority:Int;
}
