package beadshx.cli;

/**
	Upstream ui.GetStatusIcon, which is also what ui.RenderStatusIcon prints with
	colors off. A status without its own symbol is a custom one.
**/
function statusIcon(status:String):String {
	return switch status {
		case "open": "○";
		case "in_progress": "◐";
		case "blocked": "●";
		case "closed": "✓";
		case "deferred": "❄";
		case "pinned": "📌";
		case _: "◇";
	};
}
