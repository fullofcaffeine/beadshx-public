package beadshx.config;

import beadshx.cli.ConfigView.ConfigKeyFacts;
import beadshx.config.ConfigKeys.ConfigSource;
import beadshx.config.ConfigKeys.environmentNames;
import beadshx.nativeextern.bytes.BytesPkg;
import beadshx.nativeextern.exec.Cmd;
import beadshx.nativeextern.exec.ExecPkg;
import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.nativeextern.os.OsPkg;
import beadshx.nativeextern.os.PathResult;
import beadshx.nativeextern.strconv.StrconvPkg;
import beadshx.nativeextern.strings.StringsPkg;
import beadshx.nativeextern.viper.Viper;
import beadshx.nativeextern.viper.ViperPkg;
import beadshx.store.CustomConfig.goTrimSpace;
import sys.FileSystem;

/** The user config.yaml locations upstream considers, each empty when its root cannot be resolved. */
private typedef UserConfigCandidates = {
	final legacy:String;
	final native:String;
	final documented:String;
}

/**
	Upstream config.Initialize: one Viper registry over the user, project,
	BEADS_DIR and config.local.yaml files, BD_ environment variables and the
	defaults.

	Why: `bd config get` and `bd config list` print the layered values and say
	where they came from, and `bd types` and `bd statuses` read their custom
	lists from them. What: Haxe chooses the files and their order, binds the
	environment and sets the defaults exactly as upstream; Viper, an independent
	library, decodes, merges and converts the values. How: upstream initializes
	once at process start and again for the selected workspace with BEADS_DIR set
	to it, so callers load twice and print each `failure` as upstream's warning.
**/
@:goNative
final class LayeredConfig {
	final registry:Viper;

	/** Upstream Initialize's error; the registry keeps what loaded before it, as upstream's does. */
	public final failure:Null<String>;

	/** Upstream's process-start initialization: the current directory and the caller's BEADS_DIR, before any `.beads/.env`. */
	public static function atStartup():LayeredConfig {
		return new LayeredConfig(Sys.getCwd(), WorkspaceEnvironment.callerBeadsDir());
	}

	/** Upstream prepareSelectedCommandContext: BEADS_DIR set to the selected .beads directory. */
	public static function forWorkspace(beadsDir:String):LayeredConfig {
		return new LayeredConfig(Sys.getCwd(), beadsDir);
	}

	/**
		Loads the layers for a current directory and a BEADS_DIR value. An empty
		directory means upstream's os.Getwd failed, which skips the project search.
	**/
	function new(currentDirectory:String, beadsDir:Null<String>) {
		registry = ViperPkg.create();
		registry.setConfigType("yaml");
		final paths = new Array<String>();
		var primaryPath = "";
		final user = userConfigCandidates();
		for (path in [user.legacy, user.native, user.documented]) {
			if (path == "" || !FileSystem.exists(path))
				continue;
			var duplicate = false;
			for (existing in paths)
				if (FilepathPkg.clean(existing) == path)
					duplicate = true;
			if (!duplicate)
				paths.push(path);
		}
		final rawBeadsDir = beadsDir == null ? "" : beadsDir;
		final trimmedBeadsDir = goTrimSpace(rawBeadsDir);
		final beadsDirConfigPath = trimmedBeadsDir == "" ? "" : FilepathPkg.clean(FilepathPkg.join(trimmedBeadsDir, "config.yaml"));
		if (currentDirectory != "") {
			function tryProjectConfig(path:String):Bool {
				if (path == "" || !FileSystem.exists(path))
					return false;
				paths.push(path);
				primaryPath = path;
				return true;
			}
			var directory = currentDirectory;
			while (directory != FilepathPkg.dir(directory)) {
				final path = FilepathPkg.join(directory, ".beads", "config.yaml");
				// A BEADS_DIR naming another workspace keeps the caller's config out.
				if (FileSystem.exists(path)
					&& ((beadsDirConfigPath != "" && FilepathPkg.clean(path) != beadsDirConfigPath) || tryProjectConfig(path)))
					break;
				directory = FilepathPkg.dir(directory);
			}
			if (primaryPath == "" && beadsDirConfigPath == "")
				tryProjectConfig(worktreeFallbackConfigPath(currentDirectory));
		}
		if (rawBeadsDir != "") {
			final path = FilepathPkg.join(rawBeadsDir, "config.yaml");
			if (FileSystem.exists(path)) {
				if (primaryPath == "" || FilepathPkg.clean(path) != FilepathPkg.clean(primaryPath))
					paths.push(path);
				primaryPath = path;
			}
		}
		registry.setEnvPrefix("BD");
		registry.setEnvKeyReplacer(StringsPkg.newReplacer(".", "_", "-", "_"));
		registry.automaticEnv();
		setDefaults(registry);
		failure = readFiles(registry, paths, primaryPath);
	}

	/** Upstream doltserver.IsSharedServerMode, which makes an unset backup.enabled read as off. */
	public function sharedServerMode():Bool {
		final flag = Sys.getEnv("BEADS_DOLT_SHARED_SERVER");
		return flag == "1" || (flag != null && flag.toLowerCase() == "true") || registry.getBool("dolt.shared-server");
	}

	/**
		Upstream configfile.HostImpliesServerMode, with metadata.json's
		`dolt_mode` and `dolt_server_host` ("" without metadata.json): a
		proxied-server mode never implies server mode. Otherwise
		BEADS_DOLT_SERVER_HOST decides when it is set; then a set dolt_mode
		turns the inference off; then dolt_server_host decides when it is set;
		then a set dolt.mode setting turns it off; then the dolt.host setting
		decides. A host implies server mode when it is not this machine.
	**/
	public function hostImpliesServerMode(doltMode = "", metadataHost = ""):Bool {
		if (doltMode.toLowerCase() == "proxied-server")
			return false;
		final variable = environmentValue("BEADS_DOLT_SERVER_HOST");
		if (variable != "")
			return !isLocalHost(variable);
		if (doltMode != "")
			return false;
		if (metadataHost != "")
			return !isLocalHost(metadataHost);
		if (registry.getString("dolt.mode") != "")
			return false;
		final host = registry.getString("dolt.host");
		return host != "" && !isLocalHost(host);
	}

	/**
		Upstream configfile Config.IsDoltServerMode for a Dolt workspace, with
		metadata.json's `dolt_mode` and `dolt_server_host` ("" without
		metadata.json): BEADS_DOLT_SERVER_MODE=1, BEADS_DOLT_SHARED_SERVER (1 or
		true), a host that implies server mode, then dolt_mode, then the
		dolt.mode setting. Shared-server mode from a config file does not count.
	**/
	public function doltServerMode(doltMode:String, metadataHost:String):Bool {
		if (environmentValue("BEADS_DOLT_SERVER_MODE") == "1")
			return true;
		final shared = environmentValue("BEADS_DOLT_SHARED_SERVER");
		if (shared == "1" || shared.toLowerCase() == "true")
			return true;
		if (hostImpliesServerMode(doltMode, metadataHost))
			return true;
		if (doltMode != "")
			return doltMode.toLowerCase() == "server";
		return registry.getString("dolt.mode").toLowerCase() == "server";
	}

	public function getString(key:String):String {
		return registry.getString(key);
	}

	public function getBool(key:String):Bool {
		return registry.getBool(key);
	}

	/**
		Upstream getConfigList, which GetCustomTypesFromYAML and
		GetCustomStatusesFromYAML read: Viper's string list with each entry split
		again at commas, or else the string value split at commas. Entries are
		trimmed and empty ones dropped.
	**/
	public function list(key:String):Array<String> {
		final slice = registry.getStringSlice(key);
		final entries = [for (index in 0...slice.length) slice[index]];
		final listed = commaEntries(entries);
		return listed.length > 0 ? listed : commaEntries([registry.getString(key)]);
	}

	/** Viper's AllKeys: every default, file and bound-environment key, lower-cased. */
	public function allKeys():Array<String> {
		final keys = registry.allKeys();
		return [for (index in 0...keys.length) keys[index]];
	}

	/** Upstream GetValueSource: a set BD_ or BEADS_ variable, then a config file, then the default. */
	public function source(key:String):ConfigSource {
		if (environmentName(key) != "")
			return EnvironmentSource;
		return registry.inConfig(key) ? ConfigFileSource : DefaultSource;
	}

	/** Upstream EnvVarName: the first of the key's variables that is set, even to "". */
	public function environmentName(key:String):String {
		for (name in environmentNames(key))
			if (Sys.getEnv(name) != null)
				return name;
		return "";
	}

	public function facts(key:String):ConfigKeyFacts {
		final name = environmentName(key);
		return {
			environmentName: name,
			environmentValue: name == "" ? "" : Sys.getEnv(name),
			source: source(key),
			value: registry.getString(key)
		};
	}
}

/** Upstream's defaults, which `bd config get` prints for an unset YAML key and `bd config list` counts as keys. */
private function setDefaults(registry:Viper):Void {
	for (key in ["json", "events-export", "events-journal"])
		registry.setBoolDefault(key, false);
	registry.setIntDefault("events-journal-retain-days", 7);
	registry.setIntDefault("events-journal-retain-rows", 100000);
	registry.setBoolDefault("events-journal-auto-prune", true);
	for (key in ["audit.enabled", "no-db", "no-hooks"])
		registry.setBoolDefault(key, false);
	for (key in ["db", "actor", "issue-prefix"])
		registry.setStringDefault(key, "");
	registry.bindEnv("identity", "BEADS_IDENTITY");
	registry.setStringDefault("identity", "");
	registry.bindEnv("node_id", "BEADS_NODE_ID", "BD_NODE_ID");
	registry.setStringDefault("node_id", "");
	registry.setStringDefault("dolt.auto-commit", "on");
	registry.setStringDefault("routing.mode", "");
	registry.setStringDefault("routing.default", ".");
	registry.setStringDefault("routing.maintainer", ".");
	registry.setStringDefault("routing.contributor", "~/.beads-planning");
	registry.setBoolDefault("sync.require_confirmation_on_mass_delete", false);
	registry.setBoolDefault("metrics.disabled", false);
	registry.setStringDefault("metrics.endpoint", "https://gastownhall-eventsapi.com/mp/collect");
	registry.setStringDefault("federation.remote", "");
	registry.setStringDefault("federation.sovereignty", "");
	registry.setStringsDefault("federation.allowed-remote-patterns", go.NativeStringSlice.fromArray([]));
	registry.setStringsDefault("federation.exclude_types", go.NativeStringSlice.fromArray(["wisp"]));
	registry.setBoolDefault("no-push", false);
	registry.setStringDefault("agent.profile", "conservative");
	registry.setBoolDefault("create.require-description", false);
	for (key in [
		"validation.on-create",
		"validation.on-close",
		"validation.on-sync",
		"validation.metadata.mode"
	])
		registry.setStringDefault(key, "none");
	registry.setIntDefault("hierarchy.max-depth", 3);
	registry.setStringDefault("git.author", "");
	registry.setBoolDefault("git.no-gpg-sign", false);
	// Upstream's default here and for external_projects is an empty map[string]string. Viper keeps
	// any non-map default as one opaque leaf and GetString gives "" for both, so an empty list
	// leaf reads the same for every lookup these commands make.
	registry.setStringsDefault("directory.labels", go.NativeStringSlice.fromArray([]));
	registry.setBoolDefault("backup.enabled", false);
	registry.setStringDefault("backup.interval", "15m");
	registry.setBoolDefault("backup.git-push", false);
	registry.setStringDefault("backup.git-repo", "");
	registry.setBoolDefault("export.auto", false);
	registry.setStringDefault("export.interval", "60s");
	registry.setStringDefault("export.path", "issues.jsonl");
	registry.setBoolDefault("export.git-add", false);
	registry.setBoolDefault("import.auto", true);
	registry.setStringDefault("import.path", "issues.jsonl");
	registry.setStringDefault("ai.model", "claude-haiku-4-5-20251001");
	registry.setStringDefault("ai.base_url", "");
	registry.setIntDefault("list.limit", 50);
	registry.setIntDefault("output.title-length", 255);
	registry.setStringsDefault("external_projects", go.NativeStringSlice.fromArray([]));
}

/** Each entry split at commas, as Go's strings.Split does, keeping the trimmed non-empty parts in order. */
private function commaEntries(entries:Array<String>):Array<String> {
	final parts = new Array<String>();
	for (entry in entries)
		for (part in entry.split(",")) {
			final trimmed = goTrimSpace(part);
			if (trimmed != "")
				parts.push(trimmed);
		}
	return parts;
}

/** Reads the lowest file and merges the others over it, then config.local.yaml beside the primary file. */
private function readFiles(registry:Viper, paths:Array<String>, primaryPath:String):Null<String> {
	if (paths.length == 0)
		return null;
	registry.setConfigFile(paths[0]);
	final readError = registry.readInConfig();
	if (readError != null)
		return 'error reading config file: ${readError.toString()}';
	for (index in 1...paths.length) {
		registry.setConfigFile(paths[index]);
		final mergeError = registry.mergeInConfig();
		if (mergeError != null)
			return 'error merging config file ${paths[index]}: ${mergeError.toString()}';
	}
	// Viper ignores an empty path, so with only user files the last one stays current.
	registry.setConfigFile(primaryPath);
	final localPath = FilepathPkg.join(FilepathPkg.dir(primaryPath), "config.local.yaml");
	if (FileSystem.exists(localPath)) {
		registry.setConfigFile(localPath);
		final localError = registry.mergeInConfig();
		if (localError != null)
			return 'error merging local config file: ${localError.toString()}';
		registry.setConfigFile(primaryPath);
	}
	return null;
}

/** Upstream currentUserConfigYamlCandidates. */
private function userConfigCandidates():UserConfigCandidates {
	final home = absoluteDirectory(OsPkg.userHomeDir());
	final nativeRoot = absoluteDirectory(OsPkg.userConfigDir());
	return {
		legacy: home == "" ? "" : FilepathPkg.clean(FilepathPkg.join(home, ".beads", "config.yaml")),
		native: nativeRoot == "" ? "" : FilepathPkg.clean(FilepathPkg.join(nativeRoot, "bd", "config.yaml")),
		documented: home == "" ? "" : FilepathPkg.clean(FilepathPkg.join(home, ".config", "bd", "config.yaml"))
	};
}

/** Upstream cleanAbsoluteUserDirectory, with "" for a failed or relative root. */
private function absoluteDirectory(resolved:PathResult):String {
	if (resolved.value2 != null)
		return "";
	final cleaned = FilepathPkg.clean(resolved.value1);
	return FilepathPkg.isAbs(cleaned) ? cleaned : "";
}

/**
	Upstream UserConfigYamlPath: the documented file if it exists, then the native
	one, then the documented location. Null when neither root resolves.
**/
function userConfigYamlPath():Null<String> {
	final candidates = userConfigCandidates();
	if (candidates.documented != "" && FileSystem.exists(candidates.documented))
		return candidates.documented;
	if (candidates.native != candidates.documented && candidates.native != "" && FileSystem.exists(candidates.native))
		return candidates.native;
	if (candidates.documented != "")
		return candidates.documented;
	return candidates.native == "" ? null : candidates.native;
}

/** Go's `%q` for a string, which upstream's override notes use. */
function goQuote(value:String):String {
	return StrconvPkg.quote(value);
}

/** Whether the user config.yaml that upstream GetUserYamlConfig would read exists. */
function userConfigYamlPresent():Bool {
	final path = userConfigYamlPath();
	return path != null && FileSystem.exists(path);
}

/** Upstream UserConfigYamlDisplayPath. */
function userConfigYamlDisplayPath():String {
	final path = userConfigYamlPath();
	return path == null ? "~/.config/bd/config.yaml" : path;
}

/** Upstream worktreeFallbackConfigPath: the main checkout's config.yaml when the directory is a linked worktree. */
private function worktreeFallbackConfigPath(directory:String):String {
	final output = commandOutput(ExecPkg.command("git", "-C", directory, "rev-parse", "--git-dir", "--git-common-dir"));
	if (output == null)
		return "";
	final lines = goTrimSpace(output).split("\n");
	if (lines.length < 2)
		return "";
	final gitDirectory = gitPathForRepository(directory, goTrimSpace(lines[0]));
	final commonDirectory = gitPathForRepository(directory, goTrimSpace(lines[1]));
	if (gitDirectory == "" || commonDirectory == "" || FilepathPkg.clean(gitDirectory) == FilepathPkg.clean(commonDirectory))
		return "";
	if (FilepathPkg.base(commonDirectory) == ".git") {
		return FilepathPkg.join(FilepathPkg.dir(commonDirectory), ".beads", "config.yaml");
	}
	return FilepathPkg.join(commonDirectory, ".beads", "config.yaml");
}

private function gitPathForRepository(repository:String, path:String):String {
	if (path == "")
		return "";
	final joined = FilepathPkg.clean(FilepathPkg.isAbs(path) ? path : FilepathPkg.join(repository, path));
	final resolved = FilepathPkg.evalSymlinks(joined);
	return resolved.value2 == null ? resolved.value1 : joined;
}

/** A process environment variable, or "" when it is unset; `bd config show` reads BEADS_ACTOR and BEADS_MAX_ROWS this way. */
function environmentValue(name:String):String {
	final value = Sys.getEnv(name);
	return value == null ? "" : value;
}

/** Upstream configfile.IsLocalHostString: an empty host, localhost, or a loopback or unspecified address. */
private function isLocalHost(host:String):Bool {
	return ["", "localhost", "127.0.0.1", "::1", "[::1]", "0.0.0.0"].contains(goTrimSpace(host).toLowerCase());
}

/** `git config --get beads.role` in `directory`, or else in the current directory, trimmed, or "" when Git fails. */
function gitBeadsRole(?directory:String):String {
	var command = ExecPkg.command("git", "config", "--get", "beads.role");
	if (directory != null)
		command = ExecPkg.command("git", "-C", directory, "config", "--get", "beads.role");
	final output = commandOutput(command);
	return output == null ? "" : goTrimSpace(output);
}

/** Upstream primeHasGitRemote for a selected workspace: `git remote` in the current directory prints a name. */
function gitHasRemote():Bool {
	final output = commandOutput(ExecPkg.command("git", "remote"));
	return output != null && goTrimSpace(output) != "";
}

/** A finished command's stdout as text, or null when it failed to start or exited non-zero. */
private function commandOutput(command:Cmd):Null<String> {
	final result = command.output();
	return result.value2 != null ? null : BytesPkg.newBuffer(result.value1).stringValue();
}
