package beadshx.relation;

/** Only the relation keys belong to this policy; the caller retains the full record type. */
typedef RelationNeighbor = {
	final id:String;
	final dependencyType:String;
}

/** A relation read must name its direction; an absent value cannot invert a graph query. */
enum RelationDirection {
	Outgoing;
	Incoming;
}

/** Validated attempt-local request; the caller's type filter is never mutated. */
typedef RelationReadPlan = {
	final anchor:String;
	final direction:RelationDirection;
	final allowedTypes:Array<DependencyKind>;
}

enum RelationPlanResult {
	RelationPlanReady(plan:RelationReadPlan);
	RelationPlanInvalid(message:String);
}

/** Narrow protocol strings at the relation boundary, preserving the pinned validation order. */
function prepareRelationRead(id:String, direction:String, types:Array<String>):RelationPlanResult {
	if (id == "")
		return RelationPlanInvalid("validation failed: related requires an issue ID");
	final selected = switch direction {
		case "out": Outgoing;
		case "in": Incoming;
		case _: return RelationPlanInvalid('validation failed: related requires a direction ("out" or "in"), and has no default');
	};
	final allowed = new Array<DependencyKind>();
	for (index in 0...types.length)
		switch DependencyKind.parse(types[index]) {
			case DependencyKindInvalid:
				return RelationPlanInvalid('validation failed: related type ${index} is not a usable dependency type (non-empty, max 32 chars)');
			case DependencyKindValid(kind):
				allowed.push(kind);
		}
	return RelationPlanReady({anchor: id, direction: selected, allowedTypes: allowed});
}

/**
	Apply the open-vocabulary type filter and stable UTF-8 neighbor/type order.

	Storage supplies concrete neighbor records, omitting edges with no local
	issue or wisp. Preserve equal-key rows and caller-owned order: Go's stable
	sort is observable when two dependency planes supply the same neighbor.
**/
function finishRelationRead<T:RelationNeighbor>(plan:RelationReadPlan, rows:Array<T>):Array<T> {
	final allowed = new Map<String, Bool>();
	for (kind in plan.allowedTypes)
		allowed.set(kind.toString(), true);
	final ordered = [
		for (index in 0...rows.length)
			if (plan.allowedTypes.length == 0 || allowed.exists(rows[index].dependencyType)) {index: index, row: rows[index]}
	];
	ordered.sort((left, right) -> {
		final compared = DependencyRead.compareTargetAndType(left.row.id, left.row.dependencyType, right.row.id, right.row.dependencyType);
		return compared != 0 ? compared : (left.index < right.index ? -1 : (left.index == right.index ? 0 : 1));
	});
	return [for (entry in ordered) entry.row];
}
