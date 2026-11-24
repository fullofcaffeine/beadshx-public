package beadshx.nativeextern.filesys;

/**
	Dolt's file-system interface, which Dolt readers such as
	servercfg.YamlConfigFromFile take. Haxe only passes a value through, so
	no method is bound.
**/
@:go.import("github.com/dolthub/dolt/go/libraries/utils/filesys")
@:go.package("filesys")
@:go.name("Filesys")
extern interface Filesys {}
