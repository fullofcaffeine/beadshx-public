package beadshx.config;

import beadshx.config.BeadsDirPermissions.beadsDirPermissionWarning;
import beadshx.config.ConfigDrift.isFalsyBool;
import beadshx.config.ConfigDrift.testDatabaseRefusal;
import beadshx.config.ConfigDrift.unreachableServerMessage;
import beadshx.config.ConfigValidate.ParsedUrl;
import beadshx.config.ConfigValidate.PathStat;
import beadshx.config.ConfigValidate.ValidationHost;
import beadshx.config.ConfigValidate.ValidationYaml;
import beadshx.nativeextern.bytes.BytesPkg;
import beadshx.nativeextern.exec.Cmd;
import beadshx.nativeextern.exec.ExecPkg;
import beadshx.nativeextern.filepath.FilepathPkg;
import beadshx.nativeextern.net.NetPkg;
import beadshx.nativeextern.os.OsPkg;
import beadshx.nativeextern.path.PathPkg;
import beadshx.nativeextern.strconv.StrconvPkg;
import beadshx.nativeextern.syscall.SyscallPkg;
import beadshx.nativeextern.time.TimePkg;
import beadshx.nativeextern.url.UrlPkg;
import beadshx.nativeextern.viper.ViperPkg;
import beadshx.store.CustomConfig.goTrimSpace;
import beadshx.store.DoltConfigPort;
import sys.io.File;

/** A config.yaml read for validation: the registry view, or Viper's read error. */
enum ValidationYamlRead {
	YamlLoaded(yaml:ValidationYaml);
	YamlFailed(message:String);
}

/** Upstream's read-only Dolt server store open, as `bd config validate` and `bd config drift` attempt it. */
enum ServerStoreProbe {
	/** A configured endpoint this build does not dial: an address, port, socket or shared server. */
	ProbeEndpointConfigured;

	/** The open failed with this error text, which upstream reports. */
	ProbeFailed(message:String);

	/** Something accepted the connection, so upstream would go on to speak SQL; this build does not. */
	ProbeAnswered;
}

/**
	The host facts behind `bd config validate` and `bd config drift`: private
	config.yaml registries, file information, git's hook directory, the server
	pid file and the server store dial.

	Why: upstream reads these through the operating system, git and Go's
	standard library; the rules that judge them live in ConfigValidate and
	ConfigDrift. What: each probe mirrors one upstream call and nothing writes.
	How: precise standard-library externs; git runs in the current directory,
	as upstream's does.
**/
@:goNative
final class ConfigProbes {
	/** The address upstream dials for an embedded workspace: no host, port or socket is configured, so port 0 on localhost. */
	public static final DEFAULT_SERVER_ADDRESS = "127.0.0.1:0";

	/** Environment variables that move upstream's server dial to another address, port, socket, database or mode. */
	static final ENDPOINT_VARIABLES = [
		"BEADS_DOLT_SERVER_HOST",
		"BEADS_DOLT_SERVER_PORT",
		"BEADS_DOLT_PORT",
		"BEADS_DOLT_SERVER_SOCKET",
		"BEADS_DOLT_SERVER_DATABASE",
		"BEADS_DOLT_SERVER_MODE",
		"BEADS_CENTRAL_CONFIG",
		// Also moves the Dolt directory whose config.yaml can name a listener port.
		"BEADS_DOLT_DATA_DIR"
	];

	/** One YAML file in a private Viper registry, as upstream's validators read it: no defaults and no environment. */
	public static function readValidationYaml(path:String):ValidationYamlRead {
		final registry = ViperPkg.create();
		registry.setConfigType("yaml");
		registry.setConfigFile(path);
		final error = registry.readInConfig();
		if (error != null)
			return YamlFailed(error.toString());
		return YamlLoaded({
			isSet: key -> registry.isSet(key),
			getString: key -> registry.getString(key),
			getStringSlice: key -> {
				final slice = registry.getStringSlice(key);
				[for (index in 0...slice.length) slice[index]];
			}
		});
	}

	/** The workspace config.yaml, which upstream's sync checks read alone. */
	public static function workspaceConfigPath(beadsDir:String):String {
		return FilepathPkg.join(beadsDir, "config.yaml");
	}

	/**
		Whether upstream's ResolveBeadsDirForRepo, given this directory's parent,
		finds this directory again: it is named `.beads` and holds no redirect of
		its own.
	**/
	public static function resolvesFromRepository(beadsDir:String):Bool {
		return FilepathPkg.base(beadsDir) == ".beads" && !statSucceeds(FilepathPkg.join(beadsDir, "redirect"));
	}

	/** Upstream doctor findConfigPath: the workspace config.yaml, then the user config directory's, then ~/.beads's; "" for none. */
	public static function validationConfigPath(beadsDir:String):String {
		final project = workspaceConfigPath(beadsDir);
		if (statSucceeds(project))
			return project;
		final configRoot = OsPkg.userConfigDir();
		if (configRoot.value2 == null) {
			final path = FilepathPkg.join(configRoot.value1, "bd", "config.yaml");
			if (statSucceeds(path))
				return path;
		}
		final home = OsPkg.userHomeDir();
		if (home.value2 == null) {
			final path = FilepathPkg.join(home.value1, ".beads", "config.yaml");
			if (statSucceeds(path))
				return path;
		}
		return "";
	}

	public static function validationHost():ValidationHost {
		return {
			stat: statPath,
			expandHome: expandHome,
			quote: value -> StrconvPkg.quote(value),
			parseUrl: parseUrl,
			matchPattern: (pattern, name) -> {
				final matched = PathPkg.match(pattern, name);
				matched.value2 == null
				&& matched.value1;
			}};
	}

	/** os.Stat succeeded, as upstream's `err == nil` checks ask. */
	public static function statSucceeds(path:String):Bool {
		return OsPkg.stat(path).value2 == null;
	}

	/** os.Stat failed with a not-exist error, as upstream's `os.IsNotExist(err)` checks ask. */
	public static function statMissing(path:String):Bool {
		final error = OsPkg.stat(path).value2;
		return error != null && OsPkg.isNotExist(error);
	}

	/**
		Upstream config.CheckBeadsDirPermissions: the warning for the directory
		`path`, as upstream names it, when group or others have a permission
		bit on it (see beadsDirPermissionWarning). The bits come from os.Stat,
		which follows a symbolic link. Null when os.Stat fails, when the bits
		are private, and on Windows, where upstream's check does nothing.
	**/
	public static function beadsDirPermissions(path:String):Null<String> {
		if (Sys.systemName() == "Windows")
			return null;
		final result = OsPkg.stat(path);
		final information = result.value1;
		if (result.value2 != null || information == null)
			return null;
		return beadsDirPermissionWarning(path, information.mode().perm().toString());
	}

	/** os.Stat of `path`, narrowed to the answers upstream's path checks read. */
	public static function statPath(path:String):PathStat {
		final result = OsPkg.stat(path);
		final error = result.value2;
		if (error != null)
			return OsPkg.isNotExist(error) ? StatMissing : StatFailed(error.text());
		final information = result.value1;
		return information != null && information.isDir() ? StatDirectory : StatNotDirectory;
	}

	/** Upstream doctor expandPath: a leading `~` becomes the home directory when Go resolves one. */
	static function expandHome(path:String):String {
		if (!StringTools.startsWith(path, "~"))
			return path;
		final home = OsPkg.userHomeDir();
		return home.value2 == null ? FilepathPkg.join(home.value1, path.substr(1)) : path;
	}

	static function parseUrl(raw:String):ParsedUrl {
		final parsed = UrlPkg.parse(raw);
		final error = parsed.value2;
		if (error != null)
			return UrlMalformed(error.text());
		final url = parsed.value1;
		return url == null ? UrlParts("", "") : UrlParts(url.host, url.path);
	}

	/**
		Upstream git.GetGitHooksDir: core.hooksPath (with `~` expanded, and a
		relative path taken from the repository root), or the common git
		directory's hooks folder. Null when git reports no repository.
	**/
	public static function gitHooksDirectory():Null<String> {
		final configured = commandOutput(ExecPkg.command("git", "config", "--get", "core.hooksPath"));
		if (configured != null) {
			var hooksPath = goTrimSpace(configured);
			if (hooksPath != "") {
				final home = OsPkg.userHomeDir();
				if (StringTools.startsWith(hooksPath, "~/") || StringTools.startsWith(hooksPath, "~\\")) {
					if (home.value2 == null)
						hooksPath = FilepathPkg.join(home.value1, hooksPath.substr(2));
				} else if (hooksPath == "~" && home.value2 == null)
					hooksPath = home.value1;
				if (FilepathPkg.isAbs(hooksPath))
					return hooksPath;
				final repository = gitRepository();
				return repository == null ? null : FilepathPkg.join(repository.root, hooksPath);
			}
		}
		final repository = gitRepository();
		return repository == null ? null : FilepathPkg.join(repository.commonDirectory, "hooks");
	}

	/** Upstream initGitContext's single `git rev-parse`; the common directory is made absolute from the current directory. */
	static function gitRepository():Null<{commonDirectory:String, root:String}> {
		final output = commandOutput(ExecPkg.command("git", "rev-parse", "--git-dir", "--git-common-dir", "--show-toplevel"));
		if (output == null)
			return null;
		final lines = goTrimSpace(output).split("\n");
		if (lines.length < 3)
			return null;
		final common = goTrimSpace(lines[1]);
		return {
			commonDirectory: FilepathPkg.isAbs(common) ? FilepathPkg.clean(common) : FilepathPkg.join(Sys.getCwd(), common),
			root: goTrimSpace(lines[2])
		};
	}

	/** A hook file's text, or null when it cannot be read, which upstream counts as not installed. */
	public static function readHook(directory:String, name:String):Null<String> {
		return try File.getContent(FilepathPkg.join(directory, name)) catch (_:haxe.Exception) null;
	}

	/**
		Upstream isServerProbablyRunning: the pid file's trimmed decimal pid, if
		positive, names a process that signal 0 reaches. Nothing is removed.
	**/
	public static function serverProbablyRunning(serverDirectory:String):Bool {
		final content = try File.getContent(FilepathPkg.join(serverDirectory, "dolt-server.pid")) catch (_:haxe.Exception) null;
		if (content == null)
			return false;
		final pid = StrconvPkg.atoi(goTrimSpace(content));
		if (pid.value2 != null || pid.value1 <= 0)
			return false;
		final found = OsPkg.findProcess(pid.value1);
		final process = found.value1;
		if (found.value2 != null || process == null)
			return false;
		return process.signal(SyscallPkg.signal(0)) == null;
	}

	/**
		Upstream dolt.NewFromConfigWithOptions with ReadOnly and DisableAutoStart
		for an embedded workspace (validate's CLI-options open resolves the same
		way). Without a configured endpoint it dials 127.0.0.1:0, which fails at
		once; disabled auto-start keeps it from writing circuit-breaker state.
		`doltDirectory` is upstream's resolved Dolt data directory, whose
		config.yaml can name a listener port.
	**/
	public static function probeServerStore(beadsDir:String, doltDirectory:String, metadata:Map<String, String>, config:LayeredConfig):ServerStoreProbe {
		for (name in ENDPOINT_VARIABLES)
			if (environment(name) != "")
				return ProbeEndpointConfigured;
		if (environment("BEADS_TEST_MODE") == "1")
			return ProbeEndpointConfigured;
		for (tag in ["dolt_server_host", "dolt_server_socket"])
			if (metadata.exists(tag) && metadata.get(tag) != "")
				return ProbeEndpointConfigured;
		if (metadata.exists("dolt_server_port") && metadata.get("dolt_server_port") != "0")
			return ProbeEndpointConfigured;
		if (config.sharedServerMode() || config.getString("dolt.host") != "" || config.getString("dolt.port") != "")
			return ProbeEndpointConfigured;
		if (DoltConfigPort.read(doltDirectory) > 0)
			return ProbeEndpointConfigured;
		final home = OsPkg.userHomeDir();
		final centralConfig = home.value2 == null ? FilepathPkg.join(home.value1, ".config", "beads", "server.json") : "";
		for (path in [FilepathPkg.join(beadsDir, "dolt-server.port"), centralConfig])
			if (path != "" && !statMissing(path))
				return ProbeEndpointConfigured;
		final configuredDatabase = metadata.exists("dolt_database") ? metadata.get("dolt_database") : "";
		final database = configuredDatabase == null || configuredDatabase == "" ? "beads" : configuredDatabase;
		final refusal = testDatabaseRefusal(database, DEFAULT_SERVER_ADDRESS, environment("BEADS_TEST_SERVER") == "1", value -> StrconvPkg.quote(value));
		if (refusal != null)
			return ProbeFailed(refusal);
		final timeout = TimePkg.parseDuration("500ms").value1;
		final dialed = NetPkg.dialTimeout("tcp", DEFAULT_SERVER_ADDRESS, timeout);
		final error = dialed.value2;
		if (error == null) {
			final connection = dialed.value1;
			if (connection != null)
				connection.close();
			return ProbeAnswered;
		}
		final autoStartDisabled = isFalsyBool(environment("BEADS_DOLT_AUTO_START")) || isFalsyBool(config.getString("dolt.auto-start"));
		return ProbeFailed(unreachableServerMessage(DEFAULT_SERVER_ADDRESS, error.text(), autoStartDisabled));
	}

	/**
		Upstream configfile.DatabasePath, which doctor's getDatabasePath and
		doltserver's Dolt directory both use: BEADS_DOLT_DATA_DIR or
		dolt_data_dir, an absolute `database`, or `.beads/dolt`.
	**/
	public static function doltDirectory(beadsDir:String, metadata:Null<Map<String, String>>):String {
		final fields = metadata == null ? new Map<String, String>() : metadata;
		final custom = environment("BEADS_DOLT_DATA_DIR") != "" ? environment("BEADS_DOLT_DATA_DIR") : field(fields, "dolt_data_dir");
		if (metadata != null && custom != "")
			return FilepathPkg.isAbs(custom) ? custom : FilepathPkg.join(beadsDir, custom);
		final database = field(fields, "database");
		if (metadata != null && database != "" && FilepathPkg.isAbs(database))
			return database;
		return FilepathPkg.join(beadsDir, "dolt");
	}

	static function field(fields:Map<String, String>, tag:String):String {
		final value = fields.get(tag);
		return value == null ? "" : value;
	}

	static function environment(name:String):String {
		final value = Sys.getEnv(name);
		return value == null ? "" : value;
	}

	/** A finished command's stdout as text, or null when it failed to start or exited non-zero. */
	static function commandOutput(command:Cmd):Null<String> {
		final result = command.output();
		return result.value2 != null ? null : BytesPkg.newBuffer(result.value1).stringValue();
	}
}
