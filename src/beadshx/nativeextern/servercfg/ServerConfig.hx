package beadshx.nativeextern.servercfg;

/** The one Dolt servercfg.ServerConfig answer that upstream's server port resolution reads. */
@:go.import("github.com/dolthub/dolt/go/libraries/doltcore/servercfg")
@:go.package("servercfg")
@:go.name("ServerConfig")
extern interface ServerConfig {
	/** The listener port: `listener.port` as decoded, or servercfg.DefaultPort (3306) when the file sets none. */
	@:go.name("Port") public function port():Int;
}
