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

/** One custom status, as upstream types.CustomStatus. */
typedef CustomStatus = {
	final name:String;

	/** active, wip, done, frozen or unspecified; a stored row can hold any text. */
	final category:String;
}

/**
	Upstream types.ParseCustomStatusConfig: comma-separated `name` or
	`name:category` entries, in the given order. Null where upstream returns an
	error, which leaves no custom statuses.
**/
function parseCustomStatusConfig(value:String):Null<Array<CustomStatus>> {
	final statuses = new Array<CustomStatus>();
	final seen = new Map<String, Bool>();
	for (entry in goTrimSpace(value).split(",")) {
		final part = goTrimSpace(entry);
		if (part == "")
			continue;
		final colon = part.indexOf(":");
		final name = colon < 0 ? part : part.substr(0, colon);
		final category = colon < 0 ? "unspecified" : part.substr(colon + 1);
		if (colon >= 0 && !isStatusCategory(category))
			return null;
		if (!isStatusName(name) || isBuiltInStatus(name) || seen.exists(name))
			return null;
		seen.set(name, true);
		statuses.push({name: name, category: category});
	}
	return statuses.length > 50 ? null : statuses;
}

/**
	What an empty custom_statuses table holds after upstream's schema migration
	fills it from parsed status.custom entries: ORDER BY name in the column's
	binary collation reads them in byte order.
**/
function backfilledStatuses(statuses:Array<CustomStatus>):Array<CustomStatus> {
	final sorted = statuses.copy();
	sorted.sort((left, right) -> compareUtf8(left.name, right.name));
	return sorted;
}

private function isStatusCategory(category:String):Bool {
	return switch category {
		case "active" | "wip" | "done" | "frozen": true;
		case _: false;
	};
}

private function isBuiltInStatus(name:String):Bool {
	return switch name {
		case "open" | "in_progress" | "blocked" | "deferred" | "closed" | "pinned" | "hooked": true;
		case _: false;
	};
}

/** Upstream's status name pattern `^[a-z][a-z0-9_-]*$`. */
private function isStatusName(name:String):Bool {
	if (name == "")
		return false;
	for (index in 0...name.length) {
		final code:Int = name.charCodeAt(index);
		final lower = code >= "a".code && code <= "z".code;
		if (!(lower || (index > 0 && ((code >= "0".code && code <= "9".code) || code == "_".code || code == "-".code))))
			return false;
	}
	return true;
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
