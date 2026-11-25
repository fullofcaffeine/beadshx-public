package beadshx.cli;

import beadshx.cli.ListFormatView.visibleEdges;
import beadshx.nativeextern.bytes.Buffer;
import beadshx.nativeextern.strconv.StrconvPkg;
import beadshx.nativeextern.template.TemplatePkg;
import beadshx.nativeextern.time.TimePkg;
import beadshx.store.IssueListDependency;
import beadshx.store.IssueListItem;
import beadshx.store.JsonInteger;
import beadshx.store.ListTemplateCheck.DependencyTemplateField;
import beadshx.store.ListTemplateCheck.IssueTemplateField;
import beadshx.store.ListTemplateCheck.dependencyTemplateFields;
import beadshx.store.ListTemplateCheck.issueTemplateFields;
import go.NativeAny;
import go.NativeAnyMap;
import go.NativeStringSlice;

/** The text that a `list --format` template printed, and the error that stopped it, if any. */
typedef ListTemplateText = {
	final text:String;
	final error:Null<String>;
}

/** The Go `String()` text of the three times that one edge's template data holds. */
private typedef EdgeTimes = {
	final issueCreatedAt:String;
	final issueUpdatedAt:String;
	final dependencyCreatedAt:String;
}

/**
	A Go template of `list --format`, rendered from the page as upstream's
	outputFormattedList does (cmd/bd/list_output.go:116-155).

	Why: upstream parses the template, then executes it once for each visible edge
	and prints each result with a newline as soon as it renders. A template that
	fails on a later edge leaves the lines before it, and `list` prints the --limit
	hint after the lines (cmd/bd/list.go:333-339).
	What: the printed text, and `invalid format template: <error>` or
	`template execution error: <error>` when Go's text/template stops.
	How: Go's text/template runs on a native `map[string]any` with upstream's five
	keys. IssueListFormat sends only templates whose uses of that data agree with
	upstream's Go values here (see templateMatchesUpstream).
**/
@:goNative
function renderListTemplate(items:Array<IssueListItem>, source:String):ListTemplateText {
	final parsed = TemplatePkg.create("format").parse(source);
	if (parsed.value2 != null)
		return {text: "", error: 'invalid format template: ${parsed.value2.text()}'};
	final template = parsed.value1;
	final text = new StringBuf();
	for (edge in visibleEdges(items)) {
		final times = edgeTimes(edge.issue, edge.dependency);
		if (times == null)
			return {text: text.toString(), error: "native store returned an invalid issue time"};
		final rendered = new Buffer();
		final error = template.execute(rendered, ListTemplateData.root(edge.issue, edge.dependency, times));
		if (error != null)
			return {text: text.toString(), error: 'template execution error: ${error.text()}'};
		text.add(rendered.stringValue());
		text.add("\n");
	}
	return {text: text.toString(), error: null};
}

/**
	The native Go data of one edge. Its functions take and return go.NativeAny values, so they
	stay inside this class: a module-level function's signature would reach every caller of the
	module's functions.
**/
@:goNative
private final class ListTemplateData {
	/** Upstream's data root: IssueID, DependsOnID, Type, Issue and Dependency. */
	public static function root(issue:IssueListItem, dependency:IssueListDependency, times:EdgeTimes):NativeAnyMap {
		final issueData = new NativeAnyMap();
		for (field in issueTemplateFields())
			issueData.set(field, issueValue(issue, field, times));
		final dependencyData = new NativeAnyMap();
		for (field in dependencyTemplateFields())
			dependencyData.set(field, dependencyValue(dependency, field, times));
		final data = new NativeAnyMap();
		data.set("IssueID", NativeAny.ofString(issue.id));
		data.set("DependsOnID", NativeAny.ofString(dependency.dependsOnId));
		data.set("Type", NativeAny.ofString(dependency.dependencyType));
		data.set("Issue", NativeAny.ofMap(issueData));
		data.set("Dependency", NativeAny.ofMap(dependencyData));
		return data;
	}

	/** One field of upstream's *types.Issue as the Go value that a template reads. */
	static function issueValue(issue:IssueListItem, field:IssueTemplateField, times:EdgeTimes):NativeAny {
		final long = issue.longFields;
		return switch field {
			case ID: NativeAny.ofString(issue.id);
			case Title: NativeAny.ofString(issue.title);
			case Description: NativeAny.ofString(issue.description);
			case Design: NativeAny.ofString(issue.design);
			case AcceptanceCriteria: NativeAny.ofString(issue.acceptanceCriteria);
			case Notes: NativeAny.ofString(issue.notes);
			case SpecID: NativeAny.ofString(issue.specId);
			case Status: NativeAny.ofString(issue.status);
			case Priority: NativeAny.ofInt(goInt(issue.priority));
			case IssueType: NativeAny.ofString(issue.issueType);
			case IsBlocked: NativeAny.ofBool(long.isBlocked);
			case Assignee: NativeAny.ofString(issue.assignee);
			case Owner: NativeAny.ofString(issue.owner);
			case CreatedAt: NativeAny.ofString(times.issueCreatedAt);
			case CreatedBy: NativeAny.ofString(issue.createdBy);
			case UpdatedAt: NativeAny.ofString(times.issueUpdatedAt);
			case CloseReason: NativeAny.ofString(issue.closeReason);
			case ClosedBySession: NativeAny.ofString(issue.closedBySession);
			case LeaseGrantedNode: NativeAny.ofString(long.leaseGrantedNode);
			case SourceSystem: NativeAny.ofString(issue.sourceSystem);
			case CompactionLevel: NativeAny.ofInt(goInt(long.compactionLevel));
			case OriginalSize: NativeAny.ofInt(goInt(long.originalSize));
			case Labels: NativeAny.ofStrings(NativeStringSlice.fromArray(issue.labels));
			case Sender: NativeAny.ofString(long.sender);
			case Ephemeral: NativeAny.ofBool(long.ephemeral);
			case NoHistory: NativeAny.ofBool(long.noHistory);
			case WispType: NativeAny.ofString(issue.wispType);
			case StorageClass: NativeAny.ofString(long.storageClass);
			case Pinned: NativeAny.ofBool(long.pinned);
			case IsTemplate: NativeAny.ofBool(long.template);
			case AwaitType: NativeAny.ofString(long.awaitType);
			case AwaitID: NativeAny.ofString(long.awaitId);
			case Waiters: NativeAny.ofStrings(NativeStringSlice.fromArray(long.waiters));
			case SourceFormula: NativeAny.ofString(long.sourceFormula);
			case SourceLocation: NativeAny.ofString(long.sourceLocation);
			case MolType: NativeAny.ofString(issue.moleculeType);
			case WorkType: NativeAny.ofString(long.workType);
			case EventKind: NativeAny.ofString(long.eventKind);
			case Actor: NativeAny.ofString(long.actor);
			case Target: NativeAny.ofString(long.target);
			case Payload: NativeAny.ofString(long.payload);
			case IsCompound: NativeAny.ofBool(long.bondedFrom.length > 0);
		};
	}

	/** One field of upstream's *types.Dependency as the Go value that a template reads. */
	static function dependencyValue(dependency:IssueListDependency, field:DependencyTemplateField, times:EdgeTimes):NativeAny {
		return switch field {
			case ID: NativeAny.ofString(dependency.id);
			case IssueID: NativeAny.ofString(dependency.issueId);
			case DependsOnID: NativeAny.ofString(dependency.dependsOnId);
			case Type: NativeAny.ofString(dependency.dependencyType);
			case CreatedAt: NativeAny.ofString(times.dependencyCreatedAt);
			case CreatedBy: NativeAny.ofString(dependency.createdBy);
			case Metadata: NativeAny.ofString(dependency.metadata);
			case ThreadID: NativeAny.ofString(dependency.threadId);
		};
	}
}

/** Go's int for a stored integer, which the native read formatted from a Go int. */
@:goNative
private function goInt(value:JsonInteger):Int {
	return StrconvPkg.atoi(value.wireValue()).value1;
}

/** The three times of one edge as time.Time `String()` prints them, or null when one does not parse. */
@:goNative
private function edgeTimes(issue:IssueListItem, dependency:IssueListDependency):Null<EdgeTimes> {
	final issueCreatedAt = goTimeText(issue.createdAt);
	final issueUpdatedAt = goTimeText(issue.updatedAt);
	final dependencyCreatedAt = goTimeText(dependency.createdAt);
	if (issueCreatedAt == null || issueUpdatedAt == null || dependencyCreatedAt == null)
		return null;
	return {issueCreatedAt: issueCreatedAt, issueUpdatedAt: issueUpdatedAt, dependencyCreatedAt: dependencyCreatedAt};
}

/**
	A time.Time's `String()` text for the RFC 3339 text that the native read made from it with
	`Format(time.RFC3339Nano)`. Parsing restores the instant and, for `Z`, the UTC location
	that the database reads give, so the zone prints as `+0000 UTC`.
**/
@:goNative
private function goTimeText(instant:String):Null<String> {
	final parsed = TimePkg.parse("2006-01-02T15:04:05.999999999Z07:00", instant);
	return parsed.value2 != null ? null : parsed.value1.stringValue();
}
