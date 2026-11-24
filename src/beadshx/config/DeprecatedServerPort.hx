package beadshx.config;

import beadshx.config.LayeredConfig.environmentValue;
import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.nativeextern.strconv.StrconvPkg;
import beadshx.store.CustomConfig.goTrimSpace;
import sys.io.File;

/**
	Upstream doltserver.DefaultConfig's deprecated metadata.json port source.

	Why: upstream's root pre-run resolves the Dolt server port for every
	command that opens a store, also in an embedded workspace, and warns on
	stderr when the port comes from metadata.json's `dolt_server_port`. What:
	the sources in upstream's order, outside shared-server mode. How: Go's
	Atoi and Dolt's config.yaml reader through precise externs, and the file
	checks upstream makes.
**/
@:goNative
final class DeprecatedServerPort {
	/** The three lines that upstream prints on stderr when it takes the port from metadata.json. */
	public static final WARNING = "Warning: dolt_server_port in metadata.json is deprecated (can cause cross-project data leakage).\n"
		+ "  The port file (.beads/dolt-server.port) is now the primary source.\n"
		+ "  Remove dolt_server_port from .beads/metadata.json to silence this warning.\n";

	/**
		Whether upstream takes the server port of the workspace `beadsDir` from
		the decoded `metadata` fields: BEADS_DOLT_SERVER_PORT is not a value
		that Go's Atoi reads (0 and negative values count), `.beads/dolt-server.port`
		holds no positive port, the Dolt directory's config.yaml gives no
		positive listener port, the dolt.port setting is not positive, and
		dolt_server_port is positive.

		A config.yaml that Dolt decodes gives 3306 when it sets no port. A file
		that Dolt cannot read or decode gives none, so the walk goes on.
	**/
	public static function fromMetadata(beadsDir:String, metadata:Map<String, String>, config:LayeredConfig):Bool {
		final variable = environmentValue("BEADS_DOLT_SERVER_PORT");
		if (variable != "" && StrconvPkg.atoi(variable).value2 == null)
			return false;
		final portFile = try File.getContent(FilepathPkg.join(beadsDir, "dolt-server.port")) catch (_:haxe.Exception) null;
		if (portFile != null && positive(goTrimSpace(portFile)))
			return false;
		if (ConfigProbes.doltConfigPort(ConfigProbes.doltDirectory(beadsDir, metadata)) > 0)
			return false;
		if (positive(config.getString("dolt.port")))
			return false;
		// The decoded int is "0", a negative number with its sign, or a positive one.
		final port = metadata.get("dolt_server_port");
		return port != null && port != "0" && !StringTools.startsWith(port, "-");
	}

	/** A port that Go's Atoi reads as more than 0. */
	static function positive(text:String):Bool {
		final parsed = StrconvPkg.atoi(text);
		return parsed.value2 == null && parsed.value1 > 0;
	}
}
