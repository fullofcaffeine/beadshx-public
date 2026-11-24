package beadshx.nativeextern.servercfg;

import beadshx.nativeextern.filesys.Filesys;

/**
	Dolt's own sql-server config.yaml reader, which upstream's server port
	resolution calls for the config.yaml in the Dolt data directory.

	Why: Dolt owns that file's format. It expands `${VAR}` placeholders, then
	decodes the YAML with gopkg.in/yaml.v2's strict mode against its full
	server schema, so an unknown key, a duplicate key or a wrong type fails.
	A Haxe copy of those rules would drift with each Dolt release. What: the
	one reader function. How: a precise extern; the Go error stays native.
**/
@:go.import("github.com/dolthub/dolt/go/libraries/doltcore/servercfg")
@:go.package("servercfg")
@:goNative
extern class ServercfgPkg {
	@:go.tupleReturn
	@:go.name("YamlConfigFromFile") public static function yamlConfigFromFile(fs:Filesys, path:String):YamlConfigResult;
}
