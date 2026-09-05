package beadshx.nativeextern.issueops;

/** Open Beads dependency vocabulary represented by its exact Go named string. */
@:go.import("github.com/steveyegge/beads/issueops")
@:go.package("issueops")
@:go.name("DependencyType")
extern abstract DependencyType(String) from String to String {}
