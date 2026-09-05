package beadshx.nativeextern.issueops;

import beadshx.nativeextern.time.Time;

/** Exact exported stored dependency edge returned by `issueops.EdgeReader`. */
@:go.import("github.com/steveyegge/beads/issueops")
@:go.package("issueops")
@:go.name("Dependency")
@:go.struct
extern class Dependency {
	@:go.name("ID") public var id:String;
	@:go.name("IssueID") public var issueId:String;
	@:go.name("DependsOnID") public var dependsOnId:String;
	@:go.name("Type") public var dependencyType:DependencyType;
	@:go.name("CreatedAt") public var createdAt:Time;
	@:go.name("CreatedBy") public var createdBy:String;
	@:go.name("Metadata") public var metadata:String;
	@:go.name("ThreadID") public var threadId:String;
}
