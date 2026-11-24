package beadshx.store;

/**
	The rendering that `list --format` selects.

	Why: upstream's outputFormattedList (cmd/bd/list_output.go:98-115) compares the
	value exactly. `dot` prints the Graphviz document of outputDotFormat, the preset
	name `digraph` stands for the template `{{.IssueID}} {{.DependsOnID}}`, and any
	other value is a Go text/template.
	What: Haxe renders the two built-in formats from the list page. A Go template
	still goes to the native store, because upstream gives it Go values (a
	`map[string]interface{}` of strings and `*types.Issue`) that haxe.go cannot build.
**/
enum IssueListFormat {
	/** No `--format`: one of the list views renders the page. */
	NoListFormat;

	/** `dot`: upstream's outputDotFormat Graphviz document. */
	GraphvizDot;

	/** `digraph`: one `<issue> <dependency>` line for each edge inside the page. */
	DependencyDigraph;

	/** Any other value: a Go text/template, which the native store renders. */
	GoTemplate(source:String);
}

/** Selects the rendering for the `--format` value of `list`, as upstream compares it. */
function selectIssueListFormat(format:String):IssueListFormat {
	return switch format {
		case "": NoListFormat;
		case "dot": GraphvizDot;
		case "digraph": DependencyDigraph;
		case _: GoTemplate(format);
	};
}
