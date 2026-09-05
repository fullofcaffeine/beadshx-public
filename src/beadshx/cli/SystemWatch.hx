package beadshx.cli;

/** Owns the native timer and interrupt channel while Haxe owns watch policy. */
@:goNative
final class SystemWatch implements WatchPort {
	final control:NativeWatchControl;

	public function new() {
		control = NativeWatchControl.create();
	}

	public function start():Void {
		control.start();
	}

	public function waitForStop():Bool {
		return control.waitForStop();
	}

	public function close():Void {
		control.close();
	}
}

@:go.import("github.com/steveyegge/beads/internal/beadshx/watchfacade")
@:go.name("Control")
private extern class NativeWatchControl {
	@:go.name("NewControl") static function create():NativeWatchControl;
	@:go.name("Start") function start():Void;
	@:go.name("WaitForStop") function waitForStop():Bool;
	@:go.name("Close") function close():Void;
}
