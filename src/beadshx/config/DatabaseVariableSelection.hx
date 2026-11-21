package beadshx.config;

/** When upstream's pre-run lets BEADS_DB and BD_DB choose the workspace of one command. */
enum DatabaseVariableUse {
	/**
		A command that opens the store, and every other command except `where`.
		Upstream's FindDatabasePath reads BEADS_DB only when no --db, -C or
		BEADS_DIR is set and no workspace is found from the current directory.
		It never reads BD_DB.
	**/
	WithoutWorkspace;

	/**
		`where`: upstream's selectedNoDBBeadsDir takes BEADS_DB, else BD_DB,
		before -C, BEADS_DIR and the current directory. Only --db comes first.
	**/
	BeforeWorkspace;
}

/** What BEADS_DB or BD_DB selects for one command. */
enum DatabaseVariableSelection {
	/** Neither variable chooses the workspace; --db, -C, BEADS_DIR or the current directory do. */
	NoVariable;

	/**
		The variable `name` chooses the workspace, as a --db flag with its value
		`path` would. `missingFile` is the absolute path when `path` names a
		missing file in the workspace directory, such as a legacy `beads.db`:
		upstream then keeps that path as its database path, which `bd info`
		prints. It is null when upstream uses the database directory.
	**/
	VariablePath(name:String, path:String, missingFile:Null<String>);

	/**
		The variable `name` names a path that this build does not select as
		upstream does. For most such paths upstream creates a database.
	**/
	UnsupportedPath(name:String);
}
