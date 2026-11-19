package beadshx.store;

import beadshx.relation.DependencyRead.compareUtf8;

/**
	Upstream issueops.ParseTypesConfigValue: a JSON string array, or else a
	comma-separated list. Each name is trimmed like Go's strings.TrimSpace; empty
	names are dropped and repeated names kept.
**/
function parseTypesConfigValue(value:String):Array<String> {
	final trimmed = goTrimSpace(value);
	// Go decodes the JSON literal null into an empty list without an error.
	if (trimmed == "" || trimmed == "null")
		return [];
	final entries = switch JsonValue.parseStringArrayNullAsEmpty(trimmed, "types.custom") {
		case Success(names): names;
		case Failure(_): trimmed.split(",");
	};
	final names = new Array<String>();
	for (entry in entries) {
		final name = goTrimSpace(entry);
		if (name != "")
			names.push(name);
	}
	return names;
}

/**
	What an empty custom_types table holds after upstream's schema migration fills
	it from these names: INSERT IGNORE keeps each name once, and ORDER BY name in
	the column's binary collation reads them in byte order.
**/
function backfilledTypeNames(names:Array<String>):Array<String> {
	final unique = new Array<String>();
	final seen = new Map<String, Bool>();
	for (name in names)
		if (!seen.exists(name)) {
			seen.set(name, true);
			unique.push(name);
		}
	unique.sort(compareUtf8);
	return unique;
}

/** Go's strings.TrimSpace, which also trims Unicode spaces such as U+00A0. */
function goTrimSpace(value:String):String {
	var start = 0;
	var end = value.length;
	while (start < end && isGoSpace(value.charCodeAt(start)))
		start++;
	while (end > start && isGoSpace(value.charCodeAt(end - 1)))
		end--;
	return value.substring(start, end);
}

/** Go's unicode.IsSpace. */
private function isGoSpace(code:Null<Int>):Bool {
	if (code == null)
		return false;
	return switch code {
		case 0x09 | 0x0A | 0x0B | 0x0C | 0x0D | 0x20 | 0x85 | 0xA0 | 0x1680 | 0x2028 | 0x2029 | 0x202F | 0x205F | 0x3000: true;
		case _: code >= 0x2000 && code <= 0x200A;
	};
}
