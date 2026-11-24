import beadshx.bootstrap.CommandProcess.commandApplication;
import beadshx.cli.OutputPort;
import beadshx.cli.TerminalStyles.StyleSpec;
import beadshx.cli.TerminalStyles.TextStyle;
import beadshx.workspace.WorkspaceDiscovery;
import beadshx.workspace.WorkspacePort;
import sys.FileSystem;
import sys.io.File;

/** One command and the native discoveries it may ask for. */
private typedef DiscoveryCase = {
	final name:String;
	final arguments:Array<String>;

	/** The selected workspace's `.beads/.env`, or null for none. */
	final dotenv:Null<String>;

	final discoveries:Int;
}

/**
	Stands in for the native discovery and counts its calls.

	Like the native discovery, a set BEADS_DIR chooses the workspace. The
	workspace has no database, so no command reaches the store.
**/
final class CountingDiscovery implements WorkspacePort {
	public var calls = 0;

	final defaultWorkspace:String;

	public function new(defaultWorkspace:String) {
		this.defaultWorkspace = defaultWorkspace;
	}

	public function discover(directory:String, databasePath:String):WorkspaceDiscovery {
		calls++;
		final selected = Sys.getEnv("BEADS_DIR");
		return Found({
			path: selected == null || selected == "" ? defaultWorkspace : selected,
			redirectedFrom: "",
			yamlPrefix: "test",
			databasePath: "",
			databaseName: "",
			databaseMissing: true,
			proxiedServer: false,
			listLimitConfigured: false,
			listLimit: 0
		});
	}
}

final class DiscardedOutput implements OutputPort {
	public function new() {}

	public function writeStdout(value:String):Void {}

	public function writeStderr(value:String):Void {}

	public function renderMarkdown(value:String):String {
		return value;
	}

	public function usesJsonEnvelope():Bool {
		return false;
	}

	public function shouldEmitJsonDeprecation():Bool {
		return false;
	}

	public function isStdoutTerminal():Bool {
		return false;
	}

	public function isStderrTerminal():Bool {
		return false;
	}

	public function stdoutColumns():Int {
		return 0;
	}

	public function displayWidth(value:String):Int {
		return value.length;
	}

	public function hasDarkBackground():Bool {
		return true;
	}

	public function textStyle(spec:StyleSpec):TextStyle {
		return new UnstyledText();
	}
}

/** A style that leaves the text as it is. */
final class UnstyledText implements TextStyle {
	public function new() {}

	public function render(text:String):String {
		return text;
	}
}

/**
	Each command asks the native workspace discovery once, and once more only
	when its `.beads/.env` changes the environment or --db selects another
	workspace than the current directory's. The cases run the production
	object graph of one process, with a counting discovery in place of the
	native one.
**/
@:goNative
class Main {
	static function main():Void {
		final temporary = Sys.getEnv("TMPDIR");
		final root = '${temporary == null || temporary == "" ? "/tmp" : temporary}/beadshx-discovery-contract-${Date.now().getTime()}-${Std.random(1000000)}';
		final workspace = '$root/work/.beads';
		FileSystem.createDirectory(workspace);
		FileSystem.createDirectory('$root/profile');
		FileSystem.createDirectory('$root/other/.beads');
		// The cases select through -C, --db and .env alone; the user config is empty.
		for (name in ["BEADS_DIR", "BEADS_DB", "BD_DB", "BD_JSON", "BD_ROUTING_PROBE"])
			Sys.putEnv(name, null);
		Sys.putEnv("HOME", '$root/profile');
		Sys.putEnv("XDG_CONFIG_HOME", '$root/profile/config');
		Sys.setCwd('$root/work');

		final cases:Array<DiscoveryCase> = [
			{
				name: "count",
				arguments: ["count"],
				dotenv: null,
				discoveries: 1
			},
			{
				name: "version",
				arguments: ["version"],
				dotenv: null,
				discoveries: 1
			},
			{
				name: "where",
				arguments: ["where"],
				dotenv: null,
				discoveries: 1
			},
			{
				name: "config get",
				arguments: ["config", "get", "routing.probe"],
				dotenv: null,
				discoveries: 1
			},
			{
				name: "-C where",
				arguments: ["-C", '$root/work', "where"],
				dotenv: null,
				discoveries: 1
			},
			// The .env step finds the current directory's workspace before --db selects one.
			{
				name: "--db count",
				arguments: ["--db", '$root/other/.beads/embeddeddolt', "count"],
				dotenv: null,
				discoveries: 2
			},
			// A variable from .env changes the environment, so the next lookup asks again.
			{
				name: ".env setting",
				arguments: ["config", "get", "routing.probe"],
				dotenv: "BD_ROUTING_PROBE=dotenv\n",
				discoveries: 2
			},
			// Last: it sets BEADS_DIR for the rest of the process.
			{
				name: ".env selector",
				arguments: ["count"],
				dotenv: 'BEADS_DIR=$root/other/.beads\n',
				discoveries: 2
			}
		];
		final failures = new Array<String>();
		for (testCase in cases) {
			if (testCase.dotenv == null) {
				if (FileSystem.exists('$workspace/.env'))
					FileSystem.deleteFile('$workspace/.env');
			} else
				File.saveContent('$workspace/.env', testCase.dotenv);
			final discovery = new CountingDiscovery(workspace);
			commandApplication(discovery, new DiscardedOutput()).run(testCase.arguments);
			if (discovery.calls != testCase.discoveries)
				failures.push('${testCase.name}: ${discovery.calls} native discoveries, expected ${testCase.discoveries}');
			Sys.putEnv("BD_ROUTING_PROBE", null);
		}
		removeTree(root);
		if (failures.length != 0) {
			for (failure in failures)
				Sys.println(failure);
			Sys.exit(1);
		}
		Sys.println("workspace discovery contracts: PASS");
	}

	static function removeTree(path:String):Void {
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				removeTree('$path/$entry');
			FileSystem.deleteDirectory(path);
		} else
			FileSystem.deleteFile(path);
	}
}
