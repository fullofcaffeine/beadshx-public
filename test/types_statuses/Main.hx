import beadshx.cli.CatalogViews.padRunes;
import beadshx.cli.CatalogViews.renderTypeSectionsText;
import beadshx.cli.CatalogViews.renderTypesJson;
import beadshx.cli.CatalogViews.renderTypesText;
import beadshx.store.CustomConfig.backfilledTypeNames;
import beadshx.store.CustomConfig.goTrimSpace;
import beadshx.store.CustomConfig.parseTypesConfigValue;

/**
	Pins the `bd types` config parsing against upstream issueops.ParseTypesConfigValue
	and the custom_types backfill, by hand. Parity covers the real runs.
**/
class Main {
	static function main():Void {
		typeContracts();
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
		equal(renderTypeSectionsText().indexOf("  bug            ## Steps to Reproduce, ## Acceptance Criteria\n") > 0, true);
	}

	static function equal<T>(actual:T, expected:T):Void {
		if (actual != expected)
			throw 'expected ${expected}, got ${actual}';
	}
}
