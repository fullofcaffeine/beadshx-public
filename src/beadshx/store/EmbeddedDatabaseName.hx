package beadshx.store;

import haxe.io.Path;

/** Resolves the Dolt database recorded by one embedded Beads workspace. */
function resolveEmbeddedDatabaseName(beadsDir:String, selected:String):String {
	if (selected != "")
		return selected;
	final metadataPath = Path.join([beadsDir, "metadata.json"]);
	if (sys.FileSystem.exists(metadataPath)) {
		final recorded = JsonValue.rawTopLevelString(sys.io.File.getContent(metadataPath), "dolt_database");
		if (recorded != null && recorded != "")
			return recorded;
	}
	return "beads";
}
