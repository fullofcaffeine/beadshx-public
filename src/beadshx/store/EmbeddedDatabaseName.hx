package beadshx.store;

import beadshx.config.LayeredConfig.environmentValue;
import beadshx.store.EmbeddedDatabaseLookup.configuredEmbeddedDatabase;

/**
	The Dolt database that the embedded store of one workspace opens: `selected`
	when a --db value names one, or else the name that upstream configfile
	GetDoltDatabase takes from BEADS_DOLT_SERVER_DATABASE and the workspace's
	metadata.json.
**/
function resolveEmbeddedDatabaseName(beadsDir:String, selected:String):String {
	return selected != "" ? selected : configuredEmbeddedDatabase(beadsDir, environmentValue("BEADS_DOLT_SERVER_DATABASE"));
}
