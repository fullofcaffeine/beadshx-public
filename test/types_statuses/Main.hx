import beadshx.cli.CatalogViews.padRunes;
import beadshx.cli.CatalogViews.renderStatusesJson;
import beadshx.cli.CatalogViews.renderStatusesText;
import beadshx.cli.CatalogViews.renderTypeSectionsText;
import beadshx.cli.CatalogViews.renderTypesJson;
import beadshx.cli.CatalogViews.renderTypesText;
import beadshx.store.CustomConfig.CustomStatus;
import beadshx.store.CustomConfig.backfilledStatuses;
import beadshx.store.CustomConfig.backfilledTypeNames;
import beadshx.store.CustomConfig.effectiveCustomStatuses;
import beadshx.store.CustomConfig.effectiveCustomTypes;
import beadshx.store.CustomConfig.goTrimSpace;
import beadshx.store.CustomConfig.parseCustomStatusConfig;
import beadshx.store.CustomConfig.parseStatusFallback;
import beadshx.store.CustomConfig.parseTypesConfigValue;

/**
	Pins the `bd types` and `bd statuses` config parsing against upstream
	issueops.ParseTypesConfigValue and types.ParseCustomStatusConfig, the custom
	table backfill, and the config.yaml and BD_ overlay (mergeWithYAMLCustomTypes
	and ParseStatusFallback), by hand. Parity covers the real runs.
**/
class Main {
	static function main():Void {
		typeContracts();
		statusContracts();
		layeredContracts();
		renderContracts();
		Sys.println("types and statuses Haxe contracts: PASS");
	}

	static function typeContracts():Void {
		// A comma list is trimmed, empty entries are dropped and repeats kept.
		equal(parseTypesConfigValue(" b , a ,b,, ").join("|"), "b|a|b");
		// A JSON string array is decoded first; null elements become empty and are dropped.
		equal(parseTypesConfigValue('["x", " y ", "", null, "x"]').join("|"), "x|y|x");
		equal(parseTypesConfigValue("[]").length, 0);
		equal(parseTypesConfigValue(" null ").length, 0);
		equal(parseTypesConfigValue("").length, 0);
		// Anything that is not a JSON string array is a comma list.
		equal(parseTypesConfigValue('[1,"a"]').join("|"), '[1|"a"]');
		equal(parseTypesConfigValue('"quoted"').join("|"), '"quoted"');
		// Go trims Unicode spaces such as U+00A0, but not other control characters.
		equal(goTrimSpace(" \t x \n "), "x");
		equal(goTrimSpace("\x01x"), "\x01x");
		// The backfill keeps each name once, in byte order: upper case first.
		equal(backfilledTypeNames(["zeta", "alpha", "zeta", "Beta", "über", " spaced"]).join("|"), " spaced|Beta|alpha|zeta|über");
	}

	static function statusContracts():Void {
		// Entries keep their order; a bare name has the unspecified category.
		equal(statuses(parseCustomStatusConfig(" zz:active , qa:wip,legacy,, hold:frozen ")), "zz:active qa:wip legacy:unspecified hold:frozen");
		equal(statuses(parseCustomStatusConfig("  ")), "");
		// Any invalid entry rejects the whole value.
		for (value in [
			"good:active,Bad",
			"review:",
			"review:later",
			"open:active",
			"hooked",
			"qa,qa:wip",
			"1st",
			"has space",
			"a:b:c"
		])
			equal(parseCustomStatusConfig(value), null);
		equal(statuses(parseCustomStatusConfig("a-1_b:done")), "a-1_b:done");
		equal(parseCustomStatusConfig([for (index in 0...51) 's$index'].join(",")), null);
		equal(parseCustomStatusConfig([for (index in 0...50) 's$index'].join(",")).length, 50);
		// The backfill reads the table by name, in byte order.
		equal(statuses(backfilledStatuses(parseCustomStatusConfig("zz:active,qa:wip,hold:frozen"))), "hold:frozen qa:wip zz:active");
	}

	static function layeredContracts():Void {
		// Without layered names the database names stay as read, untrimmed.
		equal(effectiveCustomTypes(StoredTypes([" spaced", "gate"]), []).join("|"), " spaced|gate");
		// Otherwise both lists are trimmed and each name kept once, database names first.
		equal(effectiveCustomTypes(StoredTypes([" spaced", "Alpha", "spaced", "zeta"]), ["alpha", "zeta", "Alpha", "new", "new"]).join("|"),
			"spaced|Alpha|zeta|alpha|new");
		equal(effectiveCustomTypes(StoredTypes([]), ["b", "a", "b"]).join("|"), "b|a");
		// A failed table read gives the layered names as listed, repeats included.
		equal(effectiveCustomTypes(UnreadableTypes, ["b", "a", "b"]).join("|"), "b|a|b");
		equal(effectiveCustomTypes(UnreadableTypes, []).length, 0);
		// Stored statuses decide, even when none are valid; the layered entries are a fallback only.
		equal(statuses(effectiveCustomStatuses(StoredStatuses([]), ["zz:active"])), "");
		equal(statuses(effectiveCustomStatuses(NoStoredStatuses, ["zz:active", "qa:wip", "legacy"])), "zz:active qa:wip legacy:unspecified");
		equal(statuses(effectiveCustomStatuses(NoStoredStatuses, [])), "");
		// Entries that do not parse together are listed by name, unspecified, repeats and built-ins included.
		equal(statuses(parseStatusFallback(["review:bogus", "open", "Bad", "qa", "qa"])),
			"review:bogus:unspecified open:unspecified Bad:unspecified qa:unspecified qa:unspecified");
	}

	static function statuses(values:Null<Array<CustomStatus>>):String {
		return values == null ? "null" : [for (status in values) '${status.name}:${status.category}'].join(" ");
	}

	static function renderContracts():Void {
		equal(padRunes("ab", 4), "ab  ");
		equal(padRunes("abcdef", 4), "abcdef");
		final text = renderTypesText(["gate"]);
		equal(StringTools.startsWith(text, "Core work types (built-in):\n  task           General work item (default)\n"), true);
		equal(StringTools.endsWith(text, "\nConfigured custom types:\n  gate\n"), true);
		equal(StringTools.endsWith(renderTypesText([]), '\nNo custom types configured.\nConfigure with: bd config set types.custom "type1,type2,..."\n'), true);
		// The legacy JSON sorts keys like a Go map; the envelope keeps struct order.
		final legacy = renderTypesJson(["gate"], false);
		equal(StringTools.startsWith(legacy,
			'{\n  "core_types": [\n    {\n      "description": "General work item (default)",\n      "name": "task"\n    },\n'),
			true);
		equal(StringTools.endsWith(legacy, '  ],\n  "custom_types": [\n    "gate"\n  ],\n  "schema_version": 1\n}\n'), true);
		final envelope = renderTypesJson([], true);
		equal(StringTools.startsWith(envelope,
			'{\n  "core_types": [\n    {\n      "name": "task",\n      "description": "General work item (default)"\n    },\n'),
			true);
		equal(envelope.indexOf("custom_types"), -1);
		equal(renderTypeSectionsText().indexOf("  chore          (none)\n") > 0, true);
		// A built-in name keeps its icon, hooked follows its category, and an unknown category is a diamond.
		final custom:Array<CustomStatus> = [
			{name: "hooked", category: "done"},
			{name: "open", category: "weird"},
			{name: "a-very-long-status-name", category: "unspecified"}
		];
		equal(StringTools.endsWith(renderStatusesText(custom),
			"\nCustom statuses:\n  ✓ hooked         [done  ]\n  ○ open           [weird ]\n  ◇ a-very-long-status-name [unspecified]\n"),
			true);
		equal(renderStatusesText([]).indexOf("  ◇ hooked         [wip   ]  Attached to an agent's hook\n") > 0, true);
		final legacy = renderStatusesJson(custom, false);
		equal(StringTools.startsWith(legacy,
			'{\n  "built_in_statuses": [\n    {\n      "category": "active",\n      "description": "Available to work (default)",\n      "icon": "○",\n      "name": "open"\n    },\n'),
			true);
		equal(legacy.indexOf('    {\n      "category": "done",\n      "name": "hooked"\n    },\n') > 0, true);
		final envelope = renderStatusesJson([], true);
		equal(StringTools.startsWith(envelope, '{\n  "built_in_statuses": [\n    {\n      "name": "open",\n      "category": "active",\n'), true);
		equal(envelope.indexOf("custom_statuses"), -1);
		equal(renderTypeSectionsText().indexOf("  bug            ## Steps to Reproduce, ## Acceptance Criteria\n") > 0, true);
	}

	static function equal<T>(actual:T, expected:T):Void {
		if (actual != expected)
			throw 'expected ${expected}, got ${actual}';
	}
}
