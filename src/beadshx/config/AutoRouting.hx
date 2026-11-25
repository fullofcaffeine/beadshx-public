package beadshx.config;

/** The rules of upstream routing.DetermineTargetRepoWithRule that name a planning repository. */
enum AutoRouteRule {
	MaintainerRule;
	ContributorRule;
	DefaultRule;
}

/** The planning repository that contributor auto-routing names, and the rule that named it. */
typedef AutoRouteTarget = {
	final repository:String;
	final rule:AutoRouteRule;
}

/** Where upstream's contributor auto-routing (openRoutedReadStore) sends a read. */
enum AutoRoute {
	/** No planning repository, or ".": upstream reads this store and prints no note. */
	NoAutoRoute;

	/** A planning repository whose `.beads` is this store's: upstream opens this store a second time. */
	AutoRouteToCurrent(rule:AutoRouteRule);

	/** Another repository. */
	AutoRouteElsewhere;
}

/**
	The planning repository of upstream determineAutoRoutedRepoPath
	(cmd/bd/routing_read.go:51-95), or null when it names none or ".".

	`setting` gives each routing setting after upstream's precedence: a
	trimmed config.yaml or environment value that is not empty, or else the
	trimmed value from the database. routing.mode auto, or
	contributor.auto_route true without a mode, sends a maintainer to
	routing.maintainer and a contributor to routing.contributor, or else
	contributor.planning_repo. Otherwise routing.default applies. `role` is
	upstream routing.DetectUserRole without its warning; it is asked in auto
	mode only, as no other branch reads it.
**/
function autoRouteTarget(setting:String->String, role:() -> String):Null<AutoRouteTarget> {
	var mode = setting("routing.mode");
	if (mode == "" && setting("contributor.auto_route") == "true")
		mode = "auto";
	var target:Null<AutoRouteTarget> = null;
	if (mode == "auto") {
		final detected = role();
		final maintainerRepository = setting("routing.maintainer");
		var contributorRepository = setting("routing.contributor");
		if (contributorRepository == "")
			contributorRepository = setting("contributor.planning_repo");
		if (detected == "maintainer" && maintainerRepository != "")
			target = {repository: maintainerRepository, rule: MaintainerRule};
		else if (detected == "contributor" && contributorRepository != "")
			target = {repository: contributorRepository, rule: ContributorRule};
	}
	if (target == null) {
		final defaultRepository = setting("routing.default");
		if (defaultRepository != "")
			target = {repository: defaultRepository, rule: DefaultRule};
	}
	return target == null || target.repository == "." ? null : target;
}

/**
	Upstream printContributorRoutingNotice (cmd/bd/routing_read.go:118-156)
	with routingNoticeText: the two lines that list and ready print on stderr
	when they read the auto-routed store. `total` is the number of rows of the
	issues table, or null when upstream could not count them.
**/
function autoRouteNote(rule:AutoRouteRule, total:Null<Int>):String {
	final reason = switch rule {
		case ContributorRule:
			"contributor routing (beads.role=contributor, or inferred from the origin URL) routes bd list/ready to the contributor planning store, not this project";
		case MaintainerRule: "routing.maintainer routes bd list/ready to a different planning store than this project";
		case DefaultRule: "routing.default routes bd list/ready to a different planning store than this project";
	};
	final fix = switch rule {
		case ContributorRule: "git config beads.role maintainer";
		case MaintainerRule: "bd config unset routing.maintainer";
		case DefaultRule: "bd config unset routing.default";
	};
	final count = total == null ? "" : ' (this project has ${total} total issue(s))';
	return 'note: ${reason}${count}.\n  Fix: ${fix}\n';
}

/** The refusal of a lookup that upstream would resolve in another repository. */
function routedLookupUnavailable(command:String):String {
	return '${command} of an issue in another repository is not available yet in this build';
}

/** The refusal of list, ready or children where upstream would read another repository's planning store. */
function routedListUnavailable(command:String):String {
	return '${command} of a planning store in another repository is not available yet in this build';
}

/**
	The refusal of list, ready or children in a server-mode workspace when
	auto-routing names the workspace itself: upstream's note counts its
	issues, which this build cannot read in server mode yet.
**/
function routedListServerUnavailable(command:String):String {
	return '${command} with contributor auto-routing is not available yet for server-mode workspaces in this build';
}
