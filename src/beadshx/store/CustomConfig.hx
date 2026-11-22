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

/**
	What `bd types` reads in the database, before upstream adds the types.custom
	list from config.yaml and BD_TYPES_CUSTOM.
**/
enum DatabaseCustomTypes {
	/** ResolveCustomTypesInTx's database layer: the custom_types rows, or else the types.custom value. */
	StoredTypes(names:Array<String>);

	/** The table read failed; upstream's GetCustomTypes then returns the layered list as it is. */
	UnreadableTypes;
}

/**
	What `bd statuses` reads in the database. Upstream reads the status.custom
	list from config.yaml and BD_STATUS_CUSTOM only when the database has no answer.
**/
enum DatabaseCustomStatuses {
	/** The custom_statuses rows, or else the status.custom value; an invalid or blank value gives none. */
	StoredStatuses(statuses:Array<CustomStatus>);

	/** No rows and an empty or missing status.custom value, or a failed read. */
	NoStoredStatuses;
}

/**
	Upstream EmbeddedDoltStore.GetCustomTypes: ResolveCustomTypesInTx adds the
	layered names (getConfigList("types.custom")) after the database names, and
	a failed read gives the layered names alone, as listed.
**/
function effectiveCustomTypes(database:DatabaseCustomTypes, layered:Array<String>):Array<String> {
	return switch database {
		case StoredTypes(names): mergeLayeredTypes(names, layered);
		case UnreadableTypes: layered;
	};
}

/**
	Upstream mergeWithYAMLCustomTypes: without layered names the database names
	stay as read. Otherwise both lists, database names first, are trimmed, empty
	names dropped and each name kept at its first position.
**/
function mergeLayeredTypes(stored:Array<String>, layered:Array<String>):Array<String> {
	if (layered.length == 0)
		return stored;
	final merged = new Array<String>();
	final seen = new Map<String, Bool>();
	for (name in stored.concat(layered)) {
		final trimmed = goTrimSpace(name);
		if (trimmed == "" || seen.exists(trimmed))
			continue;
		seen.set(trimmed, true);
		merged.push(trimmed);
	}
	return merged;
}

/**
	Upstream EmbeddedDoltStore.GetCustomStatusesDetailed over
	ResolveCustomStatusesDetailedInTx: the database answer when there is one,
	else the layered entries (getConfigList("status.custom")).
**/
function effectiveCustomStatuses(database:DatabaseCustomStatuses, layered:Array<String>):Array<CustomStatus> {
	return switch database {
		case StoredStatuses(statuses): statuses;
		case NoStoredStatuses: parseStatusFallback(layered);
	};
}

/**
	Upstream issueops.ParseStatusFallback: the entries as one status.custom value,
	in their order, or, when that value is invalid, each entry by name with the
	unspecified category, repeats and invalid names included.
**/
function parseStatusFallback(entries:Array<String>):Array<CustomStatus> {
	final parsed = parseCustomStatusConfig(entries.join(","));
	if (parsed != null)
		return parsed;
	final statuses = new Array<CustomStatus>();
	for (entry in entries) {
		final name = goTrimSpace(entry);
		if (name != "")
			statuses.push({name: name, category: "unspecified"});
	}
	return statuses;
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

/** Go's unicode.IsSpace, which matches the spaces that fmt's scanning skips. */
function isGoSpace(code:Null<Int>):Bool {
	if (code == null)
		return false;
	return switch code {
		case 0x09 | 0x0A | 0x0B | 0x0C | 0x0D | 0x20 | 0x85 | 0xA0 | 0x1680 | 0x2028 | 0x2029 | 0x202F | 0x205F | 0x3000: true;
		case _: code >= 0x2000 && code <= 0x200A;
	};
}
