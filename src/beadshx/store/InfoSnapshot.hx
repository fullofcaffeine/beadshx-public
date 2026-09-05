package beadshx.store;

/** One filtered setting returned by the read-only native boundary. */
typedef ConfigEntry = {
	final key:String;
	final value:String;
}

/** Database information with no native storage types. */
typedef InfoSnapshot = {
	final databasePath:String;
	final mode:String;
	final issueCount:Int;
	final config:Array<ConfigEntry>;
	final schemaVersion:String;
	final issuePrefix:String;
	final sampleIssueIds:Array<String>;
}
