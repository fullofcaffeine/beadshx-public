package beadshx.identity;

import haxe.Exception;
import sys.io.Process;

/**
	Resolves the Beads actor through the documented compatibility order.

	The Git subprocess is contained here so command handlers only receive a
	concrete actor string and tests can replace the complete effect boundary.
**/
@:goNative
final class SystemActor implements ActorPort {
	public function new() {}

	public function resolve(explicit:String):String {
		if (explicit != "")
			return explicit;
		final beadsActor = environment("BEADS_ACTOR");
		if (beadsActor != "")
			return beadsActor;
		final deprecatedActor = environment("BD_ACTOR");
		if (deprecatedActor != "")
			return deprecatedActor;
		final gitActor = gitUserName();
		if (gitActor != "")
			return gitActor;
		final user = environment("USER");
		return user == "" ? "unknown" : user;
	}

	function environment(name:String):String {
		final value = Sys.getEnv(name);
		return value == null ? "" : value;
	}

	function gitUserName():String {
		try {
			final process = new Process("git", ["config", "user.name"]);
			final value = process.stdout.readAll().toString();
			final succeeded = process.exitCode() == 0;
			process.close();
			return succeeded ? StringTools.trim(value) : "";
		} catch (failure:Exception) {
			return "";
		}
		return "";
	}
}
