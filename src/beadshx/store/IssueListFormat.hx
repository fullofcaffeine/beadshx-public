package beadshx.store;

import beadshx.store.ListTemplateCheck.templateMatchesUpstream;

/**
	The rendering that `list --format` selects.

	Why: upstream's outputFormattedList (cmd/bd/list_output.go:98-115) compares the
	value exactly. `dot` prints the Graphviz document of outputDotFormat, the preset
	name `digraph` stands for the template `{{.IssueID}} {{.DependsOnID}}`, and any
	other value is a Go text/template.
	What: Haxe renders the two built-in formats from the list page, and also a Go
	template whose every use of the data agrees with upstream's Go values. Any other
	Go template still goes to the native store, because upstream gives it Go values
	(`*types.Issue`, named strings, `time.Time`) that haxe.go cannot build (see
	templateMatchesUpstream).
**/
enum IssueListFormat {
	/** No `--format`: one of the list views renders the page. */
	NoListFormat;

	/** `dot`: upstream's outputDotFormat Graphviz document. */
	GraphvizDot;

	/** `digraph`: one `<issue> <dependency>` line for each edge inside the page. */
	DependencyDigraph;

	/** A Go text/template that Haxe renders from the page with native Go data. */
	PageTemplate(source:String);

	/** A Go text/template that needs upstream's Go types; the native store renders it. */
	NativeTemplate(source:String);
}

/** Selects the rendering for the `--format` value of `list`, as upstream compares it. */
function selectIssueListFormat(format:String):IssueListFormat {
	return switch format {
		case "": NoListFormat;
		case "dot": GraphvizDot;
		case "digraph": DependencyDigraph;
		case _ if (templateMatchesUpstream(format)): PageTemplate(format);
		case _: NativeTemplate(format);
	};
}
