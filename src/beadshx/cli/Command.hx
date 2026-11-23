package beadshx.cli;

/** Commands admitted by the first read-only BeadsHX profile. */
enum Command {
	RootHelp;
	Version;
	Where;
	Info;
	Ping;
	Status;
	Count;
	Ready;
	Search;
	Query;
	Stale;
	Orphans;
	Children;
	DepList;
	DepCycles;
	DepTree;
	GraphCheck;
	Graph;
	Blocked;
	Comments;
	History;
	Events;
	EventsTail;
	EventsExport;
	Types;
	Statuses;
	Config;
	ConfigGet;
	ConfigList;
	ConfigShow;
	ConfigValidate;
	ConfigDrift;
	Label;
	LabelList;
	LabelListAll;
	List;
	Show;

	/** The hidden BeadsHX snapshot extension (BHX-M08-09); upstream has no such command. */
	Snapshot;
}
