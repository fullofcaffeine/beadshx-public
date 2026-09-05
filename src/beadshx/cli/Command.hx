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
	List;
	Show;
}
