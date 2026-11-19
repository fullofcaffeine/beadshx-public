package beadshx.cli;

import haxe.Json;

/** A JSON value whose object fields print in the listed order. */
enum CatalogJson {
	JsonText(value:String);
	JsonNumber(token:String);
	JsonList(items:Array<CatalogJson>);
	JsonObject(fields:Array<CatalogField>);
}

typedef CatalogField = {
	final key:String;
	final value:CatalogJson;
}

private typedef CoreType = {
	final name:String;
	final description:String;

	/** The headings of upstream's RequiredSections; chore and milestone have none. */
	final sections:Array<String>;
}

/** Upstream coreWorkTypes, in its order. */
private function coreTypes():Array<CoreType> {
	return [
		{name: "task", description: "General work item (default)", sections: ["## Acceptance Criteria"]},
		{name: "bug", description: "Bug report or defect", sections: ["## Steps to Reproduce", "## Acceptance Criteria"]},
		{name: "feature", description: "New feature or enhancement", sections: ["## Acceptance Criteria"]},
		{name: "chore", description: "Maintenance or housekeeping", sections: []},
		{name: "epic", description: "Large body of work spanning multiple issues", sections: ["## Success Criteria"]},
		{
			name: "decision",
			description: "Architecture decision record (ADR)",
			sections: ["## Decision", "## Rationale", "## Alternatives Considered"]
		},
		{
			name: "spike",
			description: "Timeboxed investigation to reduce uncertainty before committing to a story",
			sections: ["## Goal", "## Findings"]
		},
		{name: "story", description: "User story describing a feature from the user's perspective", sections: ["## Acceptance Criteria"]},
		{name: "milestone", description: "Marks completion of a set of related issues (contains no work itself)", sections: []}
	];
}

/** Upstream renderTypes text output. */
function renderTypesText(customTypes:Array<String>):String {
	final rendered = new StringBuf();
	rendered.add("Core work types (built-in):\n");
	for (type in coreTypes())
		rendered.add('  ${padRunes(type.name, 14)} ${type.description}\n');
	if (customTypes.length > 0) {
		rendered.add("\nConfigured custom types:\n");
		for (name in customTypes)
			rendered.add('  ${name}\n');
	} else {
		rendered.add("\nNo custom types configured.\n");
		rendered.add('Configure with: bd config set types.custom "type1,type2,..."\n');
	}
	return rendered.toString();
}

/**
	Upstream renderTypes JSON. The legacy output passes through a Go map, which sorts
	the keys; BD_JSON_ENVELOPE keeps the struct's field order (`structOrder`). An empty
	custom list is left out. schema_version comes last so the envelope can drop it.
**/
function renderTypesJson(customTypes:Array<String>, structOrder:Bool):String {
	final core = [
		for (type in coreTypes())
			JsonObject(orderFields([
				field("name", JsonText(type.name)),
				field("description", JsonText(type.description))
			], structOrder))
	];
	final fields = [field("core_types", JsonList(core))];
	if (customTypes.length > 0)
		fields.push(field("custom_types", JsonList([for (name in customTypes) JsonText(name)])));
	fields.push(field("schema_version", JsonNumber("1")));
	return renderCatalogJson(JsonObject(fields));
}

/** Upstream printSections text output. */
function renderTypeSectionsText():String {
	final rendered = new StringBuf();
	rendered.add("Required sections by type:\n");
	for (type in coreTypes())
		rendered.add('  ${padRunes(type.name, 14)} ${type.sections.length == 0 ? "(none)" : type.sections.join(", ")}\n');
	return rendered.toString();
}

/** Upstream printSections JSON: a list, so upstream adds no schema_version and keeps struct order. */
function renderTypeSectionsJson():String {
	return renderCatalogJson(JsonList([
		for (type in coreTypes())
			JsonObject([
				field("name", JsonText(type.name)),
				type.sections.length == 0 ? field("hint",
					JsonText("no required sections")) : field("sections", JsonList([for (heading in type.sections) JsonText(heading)]))
			])
	]));
}

/**
	Go's json.Encoder with SetIndent("", "  "), followed by its newline. haxe.go's
	Json.stringify quotes strings like Go; the caller escapes `<`, `>` and `&`.
**/
function renderCatalogJson(value:CatalogJson):String {
	return encode(value, "") + "\n";
}

private function encode(value:CatalogJson, indent:String):String {
	final inner = indent + "  ";
	return switch value {
		case JsonText(text): Json.stringify(text);
		case JsonNumber(token): token;
		case JsonList(items):
			items.length == 0 ? "[]" : "[\n" + [for (item in items) inner + encode(item, inner)].join(",\n")
				+ "\n"
				+ indent
				+ "]";
		case JsonObject(fields):
			fields.length == 0 ? "{}" : "{\n" + [
				for (entry in fields)
					inner + Json.stringify(entry.key) + ": " + encode(entry.value, inner)
			].join(",\n") + "\n" + indent + "}";
	};
}

function field(key:String, value:CatalogJson):CatalogField {
	return {key: key, value: value};
}

/** The fields as given for a Go struct, or sorted by key for a Go map. */
function orderFields(fields:Array<CatalogField>, structOrder:Bool):Array<CatalogField> {
	if (structOrder)
		return fields;
	final sorted = fields.copy();
	sorted.sort((left, right) -> left.key < right.key ? -1 : (left.key > right.key ? 1 : 0));
	return sorted;
}

/** Go's `%-Ns`: pads with spaces to N runes, which is Haxe string length here; never cuts. */
function padRunes(value:String, width:Int):String {
	final padded = new StringBuf();
	padded.add(value);
	for (_ in value.length...width)
		padded.add(" ");
	return padded.toString();
}
