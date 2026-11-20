package beadshx.nativeextern.viper;

import beadshx.nativeextern.strings.Replacer;

/**
	The exact spf13/viper registry surface that upstream config.Initialize builds
	and that `bd config get`, `bd config list`, `bd types` and `bd statuses`
	read. Viper owns YAML decoding, merging, case folding, environment lookup
	and string conversion; the files, precedence, environment names and
	defaults are authored Haxe.
**/
@:go.import("github.com/spf13/viper")
@:go.package("viper")
@:go.name("Viper")
@:goNative
extern class Viper {
	@:go.name("SetConfigType") public function setConfigType(configType:String):Void;
	@:go.name("SetConfigFile") public function setConfigFile(path:String):Void;
	@:go.name("ReadInConfig") public function readInConfig():go.Error;
	@:go.name("MergeInConfig") public function mergeInConfig():go.Error;
	@:go.name("SetEnvPrefix") public function setEnvPrefix(prefix:String):Void;
	@:go.name("SetEnvKeyReplacer") public function setEnvKeyReplacer(replacer:Replacer):Void;
	@:go.name("AutomaticEnv") public function automaticEnv():Void;

	/** `BindEnv(key, names...)`; Viper fails only without a key. */
	@:go.name("BindEnv") public function bindEnv(keyAndNames:haxe.Rest<String>):go.Error;

	@:go.name("SetDefault") public function setStringDefault(key:String, value:String):Void;
	@:go.name("SetDefault") public function setBoolDefault(key:String, value:Bool):Void;
	@:go.name("SetDefault") public function setIntDefault(key:String, value:Int):Void;
	@:go.name("SetDefault") public function setStringsDefault(key:String, value:go.NativeStringSlice):Void;

	@:go.name("GetString") public function getString(key:String):String;
	@:go.name("GetBool") public function getBool(key:String):Bool;

	/** The value through cast.ToStringSlice: a YAML sequence item by item, a scalar split at white space. */
	@:go.name("GetStringSlice") public function getStringSlice(key:String):go.NativeStringSlice;

	@:go.name("InConfig") public function inConfig(key:String):Bool;

	/** Whether a file, default or bound variable gives the key a non-null value. */
	@:go.name("IsSet") public function isSet(key:String):Bool;

	@:go.name("AllKeys") public function allKeys():go.NativeStringSlice;
}
