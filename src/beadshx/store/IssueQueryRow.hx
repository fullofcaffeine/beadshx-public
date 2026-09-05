package beadshx.store;

/**
	One query candidate: the existing public row plus predicate-only facts.

	The sidecar keeps query mechanics out of ordinary list JSON while preserving
	exact flags and timestamps for Haxe-owned predicate evaluation.
**/
typedef IssueQueryRow = {
	final item:IssueListItem;
	final pinned:Bool;
	final ephemeral:Bool;
	final template:Bool;
	final created:QueryInstant;
	final updated:QueryInstant;
	final started:OptionalQueryInstant;
	final closed:OptionalQueryInstant;
}
