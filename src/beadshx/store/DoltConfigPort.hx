package beadshx.store;

import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.nativeextern.filesys.FilesysPkg;
import beadshx.nativeextern.os.OsPkg;
import beadshx.nativeextern.servercfg.ServercfgPkg;

/**
	Reads the server port from the `config.yaml` file in a Dolt data directory,
	as upstream doltserver `configYamlPort` does.

	Why: upstream's server port walk counts this file as a source only when it
	gives a port of more than 0. The configuration probes and the deprecated
	`dolt_server_port` warning both ask for it. The read uses Dolt's own
	`servercfg` package, and the repository's storage boundary lets only the
	storage adapters import Dolt packages. So the read lives here, in the store
	package, and the configuration code calls it.

	What: `read(doltDirectory)` returns the listener port of
	`<doltDirectory>/config.yaml`, which is 3306 when the file sets none. It
	returns 0 when `os.Stat` of the file fails, or when Dolt cannot read the
	file, expand a `${VAR}` placeholder in it, or decode it strictly.

	How: it calls `servercfg.YamlConfigFromFile` through Dolt's local file
	system, as upstream does, and only reads.
**/
@:goNative
final class DoltConfigPort {
	public static function read(doltDirectory:String):Int {
		final path = FilepathPkg.join(doltDirectory, "config.yaml");
		if (OsPkg.stat(path).value2 != null)
			return 0;
		final result = ServercfgPkg.yamlConfigFromFile(FilesysPkg.localFs, path);
		final serverConfig = result.value1;
		return result.value2 != null || serverConfig == null ? 0 : serverConfig.port();
	}
}
