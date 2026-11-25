import beadshx.cli.ListFormatView.renderListDigraph;
import beadshx.cli.ListFormatView.renderListDot;
import beadshx.store.IssueListDependency;
import beadshx.store.IssueListFormat;
import beadshx.store.IssueListFormat.selectIssueListFormat;
import beadshx.store.IssueListItem;
import beadshx.store.JsonInteger;
import beadshx.store.StoredMetadata;

/**
	Pins upstream's two built-in `list --format` renderings (cmd/bd/list_output.go:25-155) by
	hand: which values select them, the `digraph` preset lines and the Graphviz `dot`
	document. The expected bytes are the ones the retired native renderer produced, so the
	port keeps them. Parity covers the real runs, the Go-template route and the hint.
**/
final class Main {
	static var failures = 0;

	static function main():Void {
		selectionContracts();
		digraphContracts();
		dotContracts();
		if (failures > 0) {
			Sys.println('list format Haxe contracts: ${failures} failure(s)');
			Sys.exit(1);
		}
		Sys.println("list format Haxe contracts: PASS");
	}

	static function selectionContracts():Void {
		equal(describe(selectIssueListFormat("")), "none");
		equal(describe(selectIssueListFormat("dot")), "dot");
		equal(describe(selectIssueListFormat("digraph")), "digraph");
		// Upstream compares the names exactly; any other value is a Go template.
		equal(describe(selectIssueListFormat("DOT")), "template:DOT");
		equal(describe(selectIssueListFormat("digraph ")), "template:digraph ");
		equal(describe(selectIssueListFormat("{{.IssueID}}")), "template:{{.IssueID}}");
	}

	static function digraphContracts():Void {
		equal(renderListDigraph([]), "");
		equal(renderListDigraph(fixture()), "list-a list-b\n");
		// Each issue keeps its page position; its edges sort by target, type and edge ID, and an
		// edge to an issue outside the page is left out.
		final items = [
			issue("list-c", "Gamma", "open", 3, "task", [
				edge("e3", "list-c", "list-b", "related"),
				edge("e2", "list-c", "external:other:cap", "blocks"),
				edge("e1", "list-c", "list-a", "parent-child"),
				edge("e0", "list-c", "list-b", "blocks")
			]),
			issue("list-a", "Alpha", "open", 1, "bug", []),
			issue("list-b", "Beta", "closed", 2, "task", [edge("e4", "list-b", "list-a", "blocks")])
		];
		equal(renderListDigraph(items), "list-c list-a\nlist-c list-b\nlist-c list-b\nlist-b list-a\n");
	}

	static function dotContracts():Void {
		equal(renderListDot([], quote), "digraph dependencies {\n  rankdir=TB;\n  node [shape=box, style=rounded];\n\n\n}\n");
		equal(renderListDot(fixture(), quote),
			"digraph dependencies {\n"
			+ "  rankdir=TB;\n"
			+ "  node [shape=box, style=rounded];\n\n"
			+ "  \"list-a\" [label=\"list-a\\n[bug P1]\\nAlpha\\n(open)\", style=\"rounded,filled\", fillcolor=\"white\", fontcolor=\"black\"];\n"
			+ "  \"list-b\" [label=\"list-b\\n[task P2]\\nBeta\\n(closed)\", style=\"rounded,filled\", fillcolor=\"lightgray\", fontcolor=\"dimgray\"];\n\n"
			+ "  \"list-a\" -> \"list-b\" [label=\"blocks\", color=red, style=bold];\n"
			+ "}\n");
		// Status colors fill the nodes; the dependency type colors and styles each edge.
		final items = [
			issue("dot-a", "Say \"hi\"", "in_progress", 0, "feature",
				[
					edge("", "dot-a", "dot-b", "parent-child"),
					edge("", "dot-a", "dot-c", "discovered-from"),
					edge("", "dot-a", "dot-d", "related"),
					edge("", "dot-a", "dot-e", "relates-to")
				]),
			issue("dot-b", "B", "blocked", 4, "task", []),
			issue("dot-c", "C", "deferred", 2, "task", []),
			issue("dot-d", "D", "pinned", 2, "task", []),
			issue("dot-e", "E", "hooked", 2, "task", [])
		];
		equal(renderListDot(items, quote),
			"digraph dependencies {\n"
			+ "  rankdir=TB;\n"
			+ "  node [shape=box, style=rounded];\n\n"
			+
			"  \"dot-a\" [label=\"dot-a\\n[feature P0]\\nSay \\\"hi\\\"\\n(in_progress)\", style=\"rounded,filled\", fillcolor=\"lightyellow\", fontcolor=\"black\"];\n"
			+ "  \"dot-b\" [label=\"dot-b\\n[task P4]\\nB\\n(blocked)\", style=\"rounded,filled\", fillcolor=\"lightcoral\", fontcolor=\"black\"];\n"
			+ "  \"dot-c\" [label=\"dot-c\\n[task P2]\\nC\\n(deferred)\", style=\"rounded,filled\", fillcolor=\"white\", fontcolor=\"black\"];\n"
			+ "  \"dot-d\" [label=\"dot-d\\n[task P2]\\nD\\n(pinned)\", style=\"rounded,filled\", fillcolor=\"white\", fontcolor=\"black\"];\n"
			+ "  \"dot-e\" [label=\"dot-e\\n[task P2]\\nE\\n(hooked)\", style=\"rounded,filled\", fillcolor=\"white\", fontcolor=\"black\"];\n\n"
			+ "  \"dot-a\" -> \"dot-b\" [label=\"parent-child\", color=blue, style=solid];\n"
			+ "  \"dot-a\" -> \"dot-c\" [label=\"discovered-from\", color=green, style=dashed];\n"
			+ "  \"dot-a\" -> \"dot-d\" [label=\"related\", color=gray, style=dashed];\n"
			+ "  \"dot-a\" -> \"dot-e\" [label=\"relates-to\", color=black, style=solid];\n"
			+ "}\n");
	}

	static function describe(format:IssueListFormat):String {
		return switch format {
			case NoListFormat: "none";
			case GraphvizDot: "dot";
			case DependencyDigraph: "digraph";
			case GoTemplate(source): 'template:${source}';
		};
	}

	/** Go's strconv.Quote for the ASCII text of these fixtures; the binary passes the real one. */
	static function quote(value:String):String {
		final quoted = new StringBuf();
		quoted.add('"');
		for (index in 0...value.length) {
			final character = value.charAt(index);
			quoted.add(switch character {
				case '"': '\\"';
				case "\\": "\\\\";
				case "\n": "\\n";
				case "\t": "\\t";
				case _: character;
			});
		}
		quoted.add('"');
		return quoted.toString();
	}

	static function fixture():Array<IssueListItem> {
		return [
			issue("list-a", "Alpha", "open", 1, "bug", [edge("", "list-a", "list-b", "blocks")]),
			issue("list-b", "Beta", "closed", 2, "task", [])
		];
	}

	static function edge(id:String, issueId:String, dependsOnId:String, dependencyType:String):IssueListDependency {
		return {
			id: id,
			issueId: issueId,
			dependsOnId: dependsOnId,
			dependencyType: dependencyType,
			createdAt: "2026-08-25T00:00:00Z",
			createdBy: "tester",
			metadata: "",
			threadId: ""
		};
	}

	static function issue(id:String, title:String, status:String, priority:Int, issueType:String, dependencies:Array<IssueListDependency>):IssueListItem {
		final zero = switch JsonInteger.parse("0") {
			case Failure(message): throw message;
			case Success(value): value;
		};
		return {
			id: id,
			title: title,
			description: "",
			design: "",
			acceptanceCriteria: "",
			notes: "",
			specId: "",
			status: status,
			priority: priority,
			issueType: issueType,
			assignee: "",
			owner: "fixture",
			estimatedMinutes: beadshx.store.OptionalIssueInteger.IntegerAbsent,
			createdAt: "2026-08-25T00:00:00Z",
			createdBy: "tester",
			updatedAt: "2026-08-25T00:00:00Z",
			startedAt: "",
			closedAt: "",
			closeReason: "",
			closedBySession: "",
			dueAt: "",
			deferUntil: "",
			externalRef: null,
			sourceSystem: "",
			metadata: StoredMetadata.fromSql(""),
			wispType: "",
			moleculeType: "",
			longFields: {
				isBlocked: false,
				leaseExpiresAt: "",
				heartbeatAt: "",
				leaseGrantedNode: "",
				compactionLevel: 0,
				compactedAt: "",
				compactedAtCommit: null,
				originalSize: 0,
				sender: "",
				ephemeral: false,
				noHistory: false,
				storageClass: "",
				pinned: false,
				template: false,
				bondedFrom: [],
				awaitType: "",
				awaitId: "",
				timeout: "",
				timeoutNanos: zero,
				waiters: [],
				sourceFormula: "",
				sourceLocation: "",
				workType: "",
				eventKind: "",
				actor: "",
				target: "",
				payload: ""
			},
			labels: [],
			dependencies: dependencies,
			dependencyCount: dependencies.length,
			dependentCount: 0,
			commentCount: 0,
			parent: "",
			blockedBy: [],
			blocks: [],
			blockingParent: ""
		};
	}

	static function equal<T>(actual:T, expected:T):Void {
		if (actual != expected) {
			failures++;
			Sys.println('expected ${expected}, got ${actual}');
		}
	}
}
