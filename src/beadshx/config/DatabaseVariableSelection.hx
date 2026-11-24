package beadshx.config;

/** When upstream's pre-run lets BEADS_DB and BD_DB choose the workspace of one command. */
enum DatabaseVariableUse {
	/**
		A command that opens the store, and the label, events and config groups,
		whose help cobra shows without the pre-run. Upstream's FindDatabasePath
		reads BEADS_DB only when no --db, -C or BEADS_DIR is set and no workspace
		is found from the current directory. It never reads BD_DB.
	**/
	WithoutWorkspace;

	/**
		`where`, `version` and help pages: upstream's selectedNoDBBeadsDir takes
		BEADS_DB, else BD_DB, before -C, BEADS_DIR and the current directory.
		Only --db comes first.
	**/
	BeforeWorkspace;
}

/** What BEADS_DB or BD_DB selects for one command. */
enum DatabaseVariableSelection {
	/** Neither variable chooses the workspace; --db, -C, BEADS_DIR or the current directory do. */
	NoVariable;

	/**
		The variable `name` chooses the workspace, as a --db flag with its value
		`path` would. `databasePath` is the database path that upstream's
		FindDatabasePath takes from the variable for a command that opens the
		store, which `bd info` prints: the canonical path, or the database
		directory inside it. It is null for `where`, `version` and help pages,
		which take no database path from the variable.
	**/
	VariablePath(name:String, path:String, databasePath:Null<String>);

	/**
		The variable `name` names a path that this build does not select as
		upstream does. For most such paths upstream creates a database.
	**/
	UnsupportedPath(name:String);
}
