package beadshx.cli;

import beadshx.identity.ActorPort;
import beadshx.git.GitHistoryPort;
import beadshx.cli.InfoChanges.VersionChange;
import beadshx.workspace.WorkspaceDiscovery;
import beadshx.workspace.WorkspaceLocation;
import beadshx.workspace.WorkspacePort;
import beadshx.store.InfoSnapshot;
import beadshx.store.EpicProgress;
import beadshx.store.IssueComment;
import beadshx.store.IssueDependency;
import beadshx.store.IssueDetails;
import beadshx.store.IssueDetailsLookup;
import beadshx.store.IssueDetailsRequest;
import beadshx.store.IssueLookup;
import beadshx.store.IssueQueryPort;
import beadshx.store.CountResult;
import beadshx.store.ReadyLoadResult;
import beadshx.store.ReadyResult;
import beadshx.store.ReadyTotal;
import beadshx.store.IssueListItem;
import beadshx.store.IssueListPage;
import beadshx.store.IssueListRequest;
import beadshx.store.IssueListRequests;
import beadshx.store.IssueListResult;
import beadshx.store.IssueRecord;
import beadshx.store.IssueStatus;
import beadshx.store.IssueSummary;
import beadshx.store.IssueType;
import beadshx.store.OptionalInt;
import beadshx.store.PingSnapshot;
import beadshx.store.ReadonlyStorePort;
import beadshx.store.StatusSnapshot;
import beadshx.store.StoreResult;
import beadshx.store.IssueLongFields;
import beadshx.store.StaleIssue;
import beadshx.query.QuerySyntax;
import beadshx.query.QuerySyntax.QuerySyntaxResult;
import beadshx.query.QueryPage;
import beadshx.query.QueryPage.QueryPageResult;
import beadshx.query.QueryPlan.QueryExecutionPlan;
import beadshx.query.QueryPlanner;
import beadshx.store.OrphanCandidate;
import beadshx.store.OrphanCandidateScan;
import beadshx.store.OrphanIssue;
import beadshx.store.QueryRowResult;
import beadshx.store.QueryStorageRequest;
import beadshx.store.QueryStorageRequest.QueryFetch;
import beadshx.ready.MoleculeDependency;
import beadshx.ready.MoleculeParallelInfo;
import beadshx.ready.MoleculeReady;
import beadshx.ready.MoleculeReadyAnalysis;
import beadshx.ready.MoleculeStep;
import beadshx.ready.MoleculeSubgraph;
import beadshx.ready.GatedMolecule;
import beadshx.ready.GatedReady;
import beadshx.ready.ReadyExplain;
import beadshx.ready.ReadyExplanation;
import beadshx.relation.DependencyRead;
import beadshx.profile.ProfilePort;
import haxe.Json;
import haxe.ds.StringMap;

private typedef CompatibilityIdentity = {
	final project:String;
	final version:String;
	final commit:String;
}

private typedef VersionDocument = {
	final schema_version:Int;
	final version:String;
	final build:String;
	final compatibility:CompatibilityIdentity;
	final identity:String;
}

private typedef DiagnosticDocument = {
	final schema_version:Int;
	final error:String;
	final message:String;
	final hint:String;
}

private enum DatabaseSelectionValidation {
	Accepted;
	PlainFailure(message:String);
	ModeAwareFailure(message:String);
}

private typedef PingDocument = {
	final schema_version:Int;
	final status:String;
	final resolve_ms:Int;
	final store_ms:Int;
	final query_ms:Int;
	final total_ms:Int;
}

private typedef WhatsNewDocument = {
	final schema_version:Int;
	final current_version:String;
	final recent_changes:Array<VersionChange>;
}

private typedef StatusSummaryCore = {
	final total_issues:Int;
	final open_issues:Int;
	final in_progress_issues:Int;
	final closed_issues:Int;
	final deferred_issues:Int;
	final pinned_issues:Int;
	final epics_eligible_for_closure:Int;
	final average_lead_time_hours:Float;
}

private typedef StatusSummaryDocument = {
	> StatusSummaryCore,
	final blocked_issues:Int;
	final ready_issues:Int;
}

private typedef SkippedStatusSummaryDocument = {
	> StatusSummaryCore,
	final blocked_issues:Null<Int>;
	final ready_issues:Null<Int>;
}

private typedef StatusDocument = {
	final schema_version:Int;
	final summary:StatusSummaryDocument;
}

private typedef SkippedStatusDocument = {
	final schema_version:Int;
	final summary:SkippedStatusSummaryDocument;
	final blocked_count_skipped:Bool;
}

private typedef HumanDependencyRelation = {
	final canonical:String;
	final outgoingHeading:String;
	final incomingHeading:String;
	final outgoingGlyph:String;
	final incomingGlyph:String;
	final order:Int;
	final related:Bool;
}

private typedef HumanDependencyGroup = {
	final relation:HumanDependencyRelation;
	final dependencies:Array<IssueDependency>;
}

private typedef ListChildGroup = {
	final parent:String;
	final children:Array<IssueListItem>;
}

private typedef ListDependencyPresentation = {
	final label:String;
	final scheduling:Bool;
}

private typedef ListDependencyRow = {
	final label:String;
	final target:String;
	final title:String;
}

private typedef ShowDependencyGroup = {
	final issueId:String;
	final items:Array<IssueDependency>;
}

private typedef ThreadEntry = {
	final issue:IssueDetails;
	final parentId:String;
}

private typedef RawIssueRecord = {
	> IssueRecord,
	final longFields:IssueLongFields;
}

private enum HumanShowMode {
	StandardShow;
	WatchedShow;
}

/** Haxe-owned read-only command application. */
final class Application {
	static final identity = "BeadsHX 0.0.0-development (compatible with Beads v1.2.1 at 634cbbc4bc580fa5124f63fdf65d137a46d5b4ff)";
	static final noWorkspaceMessage = "No active beads workspace found.";
	static final noWorkspaceHint = "check BEADS_DIR/worktree setup, or run 'bd init' to create a new database";
	static final jsonDeprecation = "NOTE: bd --json output format will change in v2.0. Set BD_JSON_ENVELOPE=1 to opt in early. See docs/reference/json-schema.md for migration details.";

	final parser:Parser;
	final output:OutputPort;
	final actor:ActorPort;
	final gitHistory:GitHistoryPort;
	final workspace:WorkspacePort;
	final store:ReadonlyStorePort;
	final profiler:ProfilePort;
	final watch:WatchPort;
	var jsonDeprecationEmitted = false;

	public function new(parser:Parser, output:OutputPort, actor:ActorPort, gitHistory:GitHistoryPort, workspace:WorkspacePort, store:ReadonlyStorePort,
			profiler:ProfilePort, watch:WatchPort) {
		this.parser = parser;
		this.output = output;
		this.actor = actor;
		this.gitHistory = gitHistory;
		this.workspace = workspace;
		this.store = store;
		this.profiler = profiler;
		this.watch = watch;
	}

	public function run(args:Array<String>):Int {
		return switch parser.parse(args) {
			case UsageFailure(message):
				output.writeStderr('Error: ${message}\n');
				1;
			case OutputFailure(mode, message):
				runModeAwareFailure(mode, message);
			case ExactFailure(message, exitCode):
				output.writeStderr(message);
				exitCode;
			case UnknownCommand(name):
				output.writeStderr('Error: unknown command "${name}" for "bd"\n');
				output.writeStderr("Run 'bd --help' for usage.\n");
				1;
			case Parsed(invocation):
				if (invocation.cpuProfile && !invocation.showHelp && usesStore(invocation.command))
					profiler.startCpu(commandName(invocation.command));
				final exitCode = runInvocation(invocation);
				if (exitCode == 0 && !invocation.showHelp)
					profiler.finish(invocation.memProfilePath);
				exitCode;
		};
	}

	static function usesStore(command:Command):Bool {
		return switch command {
			case Info | Ping | Status | Count | Ready | Search | Query | Stale | Orphans | Children | DepList | List | Show: true;
			case RootHelp | Version | Where: false;
		};
	}

	static function commandName(command:Command):String {
		return switch command {
			case Info: "info";
			case Ping: "ping";
			case Status: "status";
			case Count: "count";
			case Ready: "ready";
			case Search: "search";
			case Query: "query";
			case Stale: "stale";
			case Orphans: "orphans";
			case Children: "children";
			case DepList: "dep-list";
			case List: "list";
			case Show: "show";
			case RootHelp: "bd";
			case Version: "version";
			case Where: "where";
		};
	}

	function runInvocation(invocation:Invocation):Int {
		if (invocation.showHelp) {
			output.writeStdout(commandHelp(invocation.command));
			return 0;
		}
		if (invocation.listWarning != "")
			output.writeStderr(invocation.listWarning);
		return switch invocation.command {
			case RootHelp:
				runRootHelp(invocation);
			case Version:
				runVersion(invocation);
			case Where:
				runWhere(invocation);
			case Info:
				runInfo(invocation);
			case Ping:
				runPing(invocation);
			case Status:
				runStatus(invocation);
			case Count:
				runCount(invocation);
			case Ready:
				runReady(invocation);
			case Search:
				runSearch(invocation);
			case Query:
				runQuery(invocation);
			case Stale:
				runStale(invocation);
			case Orphans:
				runOrphans(invocation);
			case Children:
				runList(invocation);
			case DepList:
				runDepList(invocation);
			case List:
				runList(invocation);
			case Show:
				runShow(invocation);
		};
	}

	function writeJsonStdout(value:String):Void {
		output.writeStdout(output.usesJsonEnvelope() ? wrapJsonDocument(value) : value);
		if (!jsonDeprecationEmitted && output.shouldEmitJsonDeprecation()) {
			jsonDeprecationEmitted = true;
			output.writeStderr(jsonDeprecation + "\n");
		}
	}

	/**
		Wraps one already-serialized top-level object at the JSON output boundary.
		Every caller supplies pretty JSON with a top-level schema_version field;
		the envelope owns that field instead, so data retains the legacy payload.
	**/
	static function wrapJsonDocument(value:String):String {
		final trailingNewline = StringTools.endsWith(value, "\n");
		var data = trailingNewline ? value.substr(0, value.length - 1) : value;
		data = StringTools.replace(data, '  "schema_version": 1,\n', "");
		final schemaSuffix = ',\n  "schema_version": 1\n}';
		if (StringTools.endsWith(data, schemaSuffix))
			data = data.substr(0, data.length - schemaSuffix.length) + "\n}";
		data = StringTools.replace(data, "\n", "\n  ");
		return '{\n  "data": ${data},\n  "schema_version": 1\n}\n';
	}

	function runRootHelp(invocation:Invocation):Int {
		if (StringTools.trim(invocation.directory) != "") {
			switch workspace.discover(invocation.directory, "") {
				case InvalidSelection(message):
					return runStoreFailure(message);
				case Found(_) | NotFound:
			}
		}
		output.writeStdout(rootHelp());
		return 0;
	}

	function runVersion(invocation:Invocation):Int {
		if (StringTools.trim(invocation.directory) != "") {
			switch workspace.discover(invocation.directory, "") {
				case InvalidSelection(message):
					return runStoreFailure(message);
				case Found(_) | NotFound:
			}
		}
		switch invocation.output {
			case Human:
				output.writeStdout(identity + "\n");
			case Json:
				final document:VersionDocument = {
					schema_version: 1,
					version: "0.0.0-development",
					build: "development",
					compatibility: {
						project: "Beads",
						version: "v1.2.1",
						commit: "634cbbc4bc580fa5124f63fdf65d137a46d5b4ff"
					},
					identity: identity
				};
				writeJsonStdout(Json.stringify(document, null, "  ") + "\n");
		}
		return 0;
	}

	function runWhere(invocation:Invocation):Int {
		return switch workspace.discover(invocation.directory, invocation.databasePath) {
			case Found(location):
				switch invocation.output {
					case Human: output.writeStdout(renderWhereHuman(location));
					case Json: writeJsonStdout(renderWhereJson(location));
				}
				0;
			case NotFound:
				switch invocation.output {
					case Human:
						output.writeStderr('Error: ${noWorkspaceMessage}\nHint: ${noWorkspaceHint}\n');
					case Json:
						final document:DiagnosticDocument = {
							schema_version: 1,
							error: "no_beads_directory",
							message: noWorkspaceMessage,
							hint: noWorkspaceHint
						};
						writeJsonStdout(Json.stringify(document, null, "  ") + "\n");
				}
				1;
			case InvalidSelection(message):
				runStoreFailure(message);
		};
	}

	function runInfo(invocation:Invocation):Int {
		return switch workspace.discover(invocation.directory, invocation.databasePath) {
			case InvalidSelection(message):
				runStoreFailure(message);
			case NotFound:
				runDatabaseNotFound();
			case Found(location):
				switch validateDatabaseSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!hasSelectedDatabase(location)) {
							runDatabaseNotFound();
						} else if (invocation.infoWhatsNew) {
							if (invocation.global) {
								switch store.validate(location.path, true) {
									case Failure(message): runStoreFailure(message);
									case Success(_):
										renderWhatsNew(invocation.output);
										0;
								}
							} else {
								renderWhatsNew(invocation.output);
								0;
							}
						} else {
							switch store.info(location.path, invocation.infoSchema, invocation.global) {
								case Failure(message): runStoreFailure(message);
								case Success(snapshot):
									switch invocation.output {
										case Human: output.writeStdout(renderInfoHuman(snapshot, invocation.infoSchema));
										case Json: writeJsonStdout(renderInfoJson(snapshot, invocation.infoSchema));
									}
									0;
							}
						}
				}
		};
	}

	function renderWhatsNew(mode:OutputMode):Void {
		switch mode {
			case Json:
				final document:WhatsNewDocument = {
					schema_version: 1,
					current_version: InfoChanges.currentVersion,
					recent_changes: InfoChanges.recent
				};
				writeJsonStdout(Json.stringify(document, null, "  ") + "\n");
			case Human:
				var rendered = '\n🆕 What\'s New in bd (Current: v${InfoChanges.currentVersion})\n';
				rendered += "=============================================================\n\n";
				for (entry in InfoChanges.recent) {
					final marker = entry.version == InfoChanges.currentVersion ? " ← current" : "";
					rendered += '## v${entry.version} (${entry.date})${marker}\n\n';
					for (change in entry.changes)
						rendered += '  • ${change}\n';
					rendered += "\n";
				}
				rendered += "💡 Tip: Use `bd info --whats-new --json` for machine-readable output\n\n";
				output.writeStdout(rendered);
		}
	}

	function runPing(invocation:Invocation):Int {
		return switch workspace.discover(invocation.directory, invocation.databasePath) {
			case InvalidSelection(message):
				runStoreFailure(message);
			case NotFound:
				runDatabaseNotFound();
			case Found(location):
				switch validateDatabaseSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!hasSelectedDatabase(location)) runDatabaseNotFound(); else switch store.ping(location.path, invocation.global) {
							case Failure(message): runStoreFailure(message);
							case Success(snapshot):
								renderPing(invocation.output, snapshot);
								0;
						}
				}
		};
	}

	function runStatus(invocation:Invocation):Int {
		final assignee = invocation.statusAssigned ? actor.resolve(invocation.actor) : "";
		return switch workspace.discover(invocation.directory, invocation.databasePath) {
			case InvalidSelection(message):
				runStoreFailure(message);
			case NotFound:
				runDatabaseNotFound();
			case Found(location):
				switch validateDatabaseSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!hasSelectedDatabase(location)) runDatabaseNotFound(); else switch store.status(location.path, invocation.statusSkipBlocked,
							assignee, invocation.global) {
							case Failure(message): runStoreFailure(message);
							case Success(snapshot):
								renderStatus(invocation.output, snapshot);
								0;
						}
				}
		};
	}

	function runShow(invocation:Invocation):Int {
		return switch workspace.discover(invocation.directory, invocation.databasePath) {
			case InvalidSelection(message):
				runStoreFailure(message);
			case NotFound:
				runDatabaseNotFound();
			case Found(location):
				switch validateDatabaseSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!hasSelectedDatabase(location)) runDatabaseNotFound(); else switch store.openIssueQuery(location.path,
							selectedDatabaseName(invocation, location), location.proxiedServer, invocation.global) {
							case Failure(message): runStoreFailure(message);
							case Success(query): closeIssueQuery(query, runShowQuery(invocation, location, query));
						}
				}
		};
	}

	function runShowQuery(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.watchMode)
			return runShowWatch(invocation, location, query);
		if (invocation.showThread)
			return runShowThread(invocation, location, query);
		if (invocation.showRefs)
			return runShowRefs(invocation, location, query);
		if (invocation.showChildren)
			return runShowChildren(invocation, location, query);
		if (invocation.showShort)
			return runShowShort(invocation, location, query);
		return switch invocation.output {
			case Human: runShowHuman(invocation, location, query);
			case Json: runShowJson(invocation, location, query);
		};
	}

	function runList(invocation:Invocation):Int {
		return switch workspace.discover(invocation.directory, invocation.databasePath) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFound();
			case Found(location):
				switch validateDatabaseSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						final positiveOffset = switch invocation.listRequest.offset {
							case IntPresent(value): value > 0;
							case IntAbsent: false;
						};
						if (positiveOffset && !location.proxiedServer) {
							runStoreFailure("--offset is only supported under --proxied-server");
						} else if (!hasSelectedDatabase(location)) {
							runDatabaseNotFound();
						} else {
							final effectiveLimit = resolveListLimit(invocation, location);
							switch store.openIssueQuery(location.path, selectedDatabaseName(invocation, location), location.proxiedServer, invocation.global) {
								case Failure(message): runStoreFailure(message);
								case Success(query):
									final result = invocation.watchMode ? runListWatch(invocation, location, effectiveLimit,
										query) : renderListResult(invocation, loadListResult(invocation, location, effectiveLimit, query));
									closeIssueQuery(query, result);
							}
						}
				}
		};
	}

	function runDepList(invocation:Invocation):Int {
		return switch workspace.discover(invocation.directory, invocation.databasePath) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFound();
			case Found(location):
				switch validateDatabaseSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!hasSelectedDatabase(location)) runDatabaseNotFound(); else switch store.openIssueQuery(location.path,
							selectedDatabaseName(invocation, location), location.proxiedServer, invocation.global) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = runDepListQuery(invocation, location, query);
								closeIssueQuery(query, result);
						}
				}
		};
	}

	function runDepListQuery(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		final batch = invocation.showIds.length > 1;
		if (invocation.depType != "" && haxe.io.Bytes.ofString(invocation.depType).length > 32) {
			final role = batch ? "read edges" : "related";
			return runModeAwareFailure(invocation.output, 'validation failed: ${role} type 0 is not a usable dependency type (non-empty, max 32 chars)');
		}
		final resolved = new Array<String>();
		for (id in invocation.showIds)
			switch lookupIssueSummary(location, id, invocation.global, query) {
				case Failure(message):
					if (!batch)
						return runModeAwareFailure(invocation.output, 'resolving ${id}: ${message}');
					output.writeStderr('warning: resolving ${id}: ${message} (skipped)\n');
				case Success(IssueMissing):
					final message = 'no issue found matching "${id}"';
					if (!batch)
						return runModeAwareFailure(invocation.output, 'resolving ${id}: ${message}');
					output.writeStderr('warning: resolving ${id}: ${message} (skipped)\n');
				case Success(IssueFound(summary)):
					resolved.push(summary.id);
			}
		if (resolved.length == 0) {
			if (invocation.output == Json)
				writeJsonStdout("[]\n");
			else
				output.writeStderr("no resolvable issues in batch\n");
			return 0;
		}
		final dependencyTypes = invocation.depType == "" ? [] : [invocation.depType];
		if (!batch)
			return switch query.issueDetails(location.path, resolved[0], {
				includeDependents: false,
				includeComments: false,
				briefDependencies: false
			}, invocation.global) {
				case Failure(message): runModeAwareFailure(invocation.output, message);
				case Success(DetailsMissing): runModeAwareFailure(invocation.output, 'no issue found: ${resolved[0]}');
				case Success(DetailsFound(details)):
					final dependencies = [
						for (dependency in details.dependencies)
							if (dependencyTypes.length == 0 || dependencyTypes.indexOf(dependency.dependencyType) >= 0) dependency
					];
					renderSingleDepList(invocation, resolved[0], dependencies);
			};
		return switch query.dependencyEdges(location.path, location.databaseName, resolved, dependencyTypes, invocation.global) {
			case DependencyEdgeFailure(message): runModeAwareFailure(invocation.output, message);
			case DependencyEdges(anchors): renderDepList(invocation, anchors);
		};
	}

	function renderSingleDepList(invocation:Invocation, id:String, dependencies:Array<IssueDependency>):Int {
		dependencies.sort((left, right) -> DependencyRead.compareTargetAndType(left.id, left.dependencyType, right.id, right.dependencyType));
		switch invocation.output {
			case Json:
				writeJsonStdout(renderDependencyIssuesJson(dependencies));
			case Human:
				if (dependencies.length == 0) {
					output.writeStdout('\n${id} has no dependencies\n');
				} else {
					for (dependency in dependencies)
						output.writeStdout('  ${dependency.id}: ${dependency.title} [P${dependency.priority}] (${dependency.status}) via ${dependency.dependencyType}\n');
					output.writeStdout("\n");
				}
		}
		return 0;
	}

	static function renderDependencyIssuesJson(dependencies:Array<IssueDependency>):String {
		if (dependencies.length == 0)
			return "[]\n";
		final lines = ["["];
		for (index in 0...dependencies.length) {
			final dependency = dependencies[index];
			final fields = renderIssueRecordFields(dependency, "    ");
			fields.push('"dependency_type": ${Json.stringify(dependency.dependencyType)}');
			lines.push("  {");
			for (fieldIndex in 0...fields.length)
				lines.push('    ${fields[fieldIndex]}${fieldIndex == fields.length - 1 ? "" : ","}');
			lines.push(index == dependencies.length - 1 ? "  }" : "  },");
		}
		lines.push("]");
		return lines.join("\n") + "\n";
	}

	function renderDepList(invocation:Invocation, anchors:Array<beadshx.relation.DependencyAnchor>):Int {
		for (anchor in anchors)
			if (anchor.missing)
				output.writeStderr('warning: no issue found: ${anchor.id} (skipped)\n');
		switch invocation.output {
			case Json:
				final edges = new Array<beadshx.relation.DependencyEdge>();
				for (anchor in anchors)
					for (edge in anchor.edges)
						edges.push(edge);
				writeJsonStdout(renderDependencyEdgesJson(edges));
			case Human:
				final rendered = new StringBuf();
				for (anchor in anchors) {
					if (anchor.missing)
						continue;
					if (anchor.edges.length == 0) {
						rendered.add('\n${anchor.id} has no dependencies\n');
						continue;
					}
					rendered.add('\nDependencies of ${anchor.id}:\n\n');
					for (edge in anchor.edges)
						rendered.add('  ${edge.dependsOnId} via ${edge.dependencyType.toString()}\n');
				}
				rendered.add("\n");
				output.writeStdout(rendered.toString());
		}
		return 0;
	}

	static function renderDependencyEdgesJson(edges:Array<beadshx.relation.DependencyEdge>):String {
		if (edges.length == 0)
			return "[]\n";
		final lines = ["["];
		for (index in 0...edges.length) {
			final edge = edges[index];
			final fields = new Array<String>();
			fields.push('"issue_id": ${Json.stringify(edge.issueId)}');
			fields.push('"depends_on_id": ${Json.stringify(edge.dependsOnId)}');
			fields.push('"type": ${Json.stringify(edge.dependencyType.toString())}');
			fields.push('"created_at": ${Json.stringify(edge.createdAt)}');
			if (edge.createdBy != "")
				fields.push('"created_by": ${Json.stringify(edge.createdBy)}');
			if (edge.metadata != "")
				fields.push('"metadata": ${Json.stringify(edge.metadata)}');
			if (edge.threadId != "")
				fields.push('"thread_id": ${Json.stringify(edge.threadId)}');
			lines.push("  {");
			for (fieldIndex in 0...fields.length)
				lines.push('    ${fields[fieldIndex]}${fieldIndex == fields.length - 1 ? "" : ","}');
			lines.push(index == edges.length - 1 ? "  }" : "  },");
		}
		lines.push("]");
		return lines.join("\n") + "\n";
	}

	function runCount(invocation:Invocation):Int {
		return switch workspace.discover(invocation.directory, invocation.databasePath) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFound();
			case Found(location):
				switch validateDatabaseSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!hasSelectedDatabase(location)) runDatabaseNotFound(); else switch store.openIssueQuery(location.path,
							selectedDatabaseName(invocation, location), location.proxiedServer, invocation.global) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = switch query.issueCount(location.path, invocation.countRequest, invocation.countGroup, invocation.global) {
									case Failure(message): runStoreFailure(message);
									case Success(count): renderCount(invocation, count);
								};
								closeIssueQuery(query, result);
						}
				}
		};
	}

	function runReady(invocation:Invocation):Int {
		if (invocation.readyClaim)
			return runModeAwareFailure(invocation.output, "operation 'ready --claim' is not allowed in read-only mode");
		return switch workspace.discover(invocation.directory, invocation.databasePath) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFound();
			case Found(location):
				switch validateDatabaseSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						final offset = switch invocation.readyRequest.offset {
							case IntPresent(value): value;
							case IntAbsent: 0;
						};
						if (!location.proxiedServer && offset > 0) {
							runModeAwareFailure(invocation.output, "--offset is only supported under --proxied-server");
						} else if (location.proxiedServer && offset < 0) {
							runStoreFailure("--offset must be >= 0");
						} else if (!hasSelectedDatabase(location)) {
							runDatabaseNotFound();
						} else switch store.openIssueQuery(location.path, selectedDatabaseName(invocation, location), location.proxiedServer,
							invocation.global) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = if (invocation.readyGated) {
									runReadyGated(invocation, location, query);
								} else if (invocation.readyMolecule != "") {
									runReadyMolecule(invocation, location, query);
								} else if (invocation.readyExplain) {
									runReadyExplain(invocation, location, query);
								} else switch query.issueReady(location.path, invocation.readyRequest, invocation.global) {
									case ReadyFailure(message): runStoreFailure(message);
									case ReadyRowLimitExceeded(found, source, cap): runListRowLimitExceeded(found, source, cap);
									case ReadySuccess(ready): renderReady(invocation, location.proxiedServer, ready, query, location);
								};
								closeIssueQuery(query, result);
						}
				}
		};
	}

	function runReadyGated(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		return switch query.issueReady(location.path, readyExplainRequest(), invocation.global) {
			case ReadyFailure(message): runStoreFailure(message);
			case ReadyRowLimitExceeded(found, source, cap): runListRowLimitExceeded(found, source, cap);
			case ReadySuccess(ready):
				switch query.issueList(location.path, IssueListRequests.moleculeCandidates(), 0, invocation.global) {
					case ListFailure(message): runStoreFailure(message);
					case ListRowLimitExceeded(found, source, cap): runListRowLimitExceeded(found, source, cap);
					case ListSuccess(candidates):
						final molecules = GatedReady.discover(ready.page.items, candidates.items);
						if (invocation.output == Json)
							writeJsonStdout(renderGatedReadyJson(molecules));
						else
							output.writeStdout(renderGatedReadyHuman(molecules));
						0;
				}
		};
	}

	function runReadyExplain(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		return switch query.issueReady(location.path, readyExplainRequest(), invocation.global) {
			case ReadyFailure(message): runStoreFailure(message);
			case ReadyRowLimitExceeded(found, source, cap): runListRowLimitExceeded(found, source, cap);
			case ReadySuccess(ready):
				switch query.issueList(location.path, IssueListRequests.readyExplainCandidates(), 0, invocation.global) {
					case ListFailure(message): runStoreFailure(message);
					case ListRowLimitExceeded(found, source, cap): runListRowLimitExceeded(found, source, cap);
					case ListSuccess(candidates):
						final explanation = ReadyExplain.build(ready.page.items, candidates.items);
						if (invocation.output == Json)
							writeJsonStdout(renderReadyExplanationJson(explanation));
						else
							output.writeStdout(renderReadyExplanationHuman(explanation));
						0;
				}
		};
	}

	static function readyExplainRequest():beadshx.store.ReadyRequest {
		return {
			issueType: "",
			assignee: "",
			unassigned: false,
			labels: [],
			labelsAny: [],
			excludeLabels: [],
			labelPattern: "",
			labelRegex: "",
			priority: IntAbsent,
			parentId: "",
			moleculeType: "",
			includeDeferred: false,
			includeEphemeral: false,
			excludeTypes: [],
			metadataFields: [],
			hasMetadataKey: "",
			sort: beadshx.store.ReadySort.Priority,
			limit: IntPresent(0),
			offset: IntAbsent,
			brief: false,
			maxRows: IntAbsent,
			maxRowsSource: ""
		};
	}

	function runReadyMolecule(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		return switch lookupIssueSummary(location, invocation.readyMolecule, invocation.global, query) {
			case Failure(_): runModeAwareFailure(invocation.output, 'molecule \'${invocation.readyMolecule}\' not found');
			case Success(IssueMissing): runModeAwareFailure(invocation.output, 'molecule \'${invocation.readyMolecule}\' not found');
			case Success(IssueFound(root)):
				switch loadMoleculeItems(location, root.id, query, invocation.global) {
					case ListFailure(message): runStoreFailure('loading molecule: ${message}');
					case ListRowLimitExceeded(found, source, cap): runListRowLimitExceeded(found, source, cap);
					case ListSuccess(page):
						final steps = new Array<MoleculeStep>();
						final dependencies = new Array<MoleculeDependency>();
						for (item in page.items) {
							steps.push({
								id: item.id,
								title: item.title,
								status: item.status,
								priority: item.priority,
								issueType: item.issueType
							});
							for (dependency in item.dependencies)
								dependencies.push({
									issueId: dependency.issueId,
									dependsOnId: dependency.dependsOnId,
									dependencyType: dependency.dependencyType,
									metadata: dependency.metadata
								});
						}
						final analysis = MoleculeReady.analyze(root.id, steps, dependencies);
						if (invocation.output == Json) {
							writeJsonStdout(renderMoleculeReadyJson(root.title, page.items, analysis));
							0;
						} else {
							output.writeStdout(renderMoleculeReadyHuman(root.title, page.items, analysis));
							0;
						}
				}
		};
	}

	function loadMoleculeItems(location:WorkspaceLocation, rootId:String, query:IssueQueryPort, global:Bool):IssueListResult {
		return switch query.issueList(location.path, IssueListRequests.exact(rootId), 0, global) {
			case ListFailure(message): ListFailure(message);
			case ListRowLimitExceeded(found, source, cap): ListRowLimitExceeded(found, source, cap);
			case ListSuccess(rootPage):
				if (rootPage.items.length == 0) {
					ListFailure('template ${rootId} not found');
				} else switch query.issueList(location.path, IssueListRequests.moleculeCandidates(), 0, global) {
					case ListFailure(message): ListFailure(message);
					case ListRowLimitExceeded(found, source, cap): ListRowLimitExceeded(found, source, cap);
					case ListSuccess(candidates):
						final byId = new Map<String, IssueListItem>();
						byId.set(rootId, rootPage.items[0]);
						final nodes = [];
						for (item in candidates.items) {
							byId.set(item.id, item);
							final parents = [
								for (dependency in item.dependencies)
									if (dependency.dependencyType == "parent-child") dependency.dependsOnId
							];
							nodes.push({id: item.id, parents: parents});
						}
						final items = [
							for (id in MoleculeSubgraph.collectIds(rootId, nodes))
								if (byId.exists(id)) byId.get(id)
						];
						ListSuccess({items: items, hasMore: false, formatted: ""});
				}
		};
	}

	function runSearch(invocation:Invocation):Int {
		return switch workspace.discover(invocation.directory, invocation.databasePath) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFound();
			case Found(location):
				switch validateDatabaseSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!hasSelectedDatabase(location)) {
							runDatabaseNotFound();
						} else if (invocation.searchQuery == "") {
							output.writeStdout(searchHelp());
							if (location.proxiedServer)
								runModeAwareFailure(invocation.output, "search query is required");
							else
								runStoreFailure("search query is required");
						} else switch store.openIssueQuery(location.path, selectedDatabaseName(invocation, location), location.proxiedServer,
							invocation.global) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = switch query.issueSearch(location.path, invocation.searchQuery, invocation.listRequest, invocation.global) {
									case ListFailure(message): runStoreFailure(message);
									case ListRowLimitExceeded(found, source, cap): runListRowLimitExceeded(found, source, cap);
									case ListSuccess(page): renderSearch(invocation, page);
								};
								closeIssueQuery(query, result);
						}
				}
		};
	}

	function runQuery(invocation:Invocation):Int {
		return switch workspace.discover(invocation.directory, invocation.databasePath) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFound();
			case Found(location):
				switch validateDatabaseSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!hasSelectedDatabase(location)) {
							runDatabaseNotFound();
						} else if (!invocation.queryRequest.provided) {
							output.writeStderr("Error: query expression is required\n\n");
							output.writeStderr(queryHelp());
							1;
						} else if (invocation.queryRequest.parseOnly) {
							switch QuerySyntax.parse(invocation.queryRequest.expression) {
								case Parsed(expression):
									output.writeStdout('Parsed query: ${QuerySyntax.render(expression)}\n');
									0;
								case Invalid(message): runModeAwareFailure(invocation.output, 'invalid query expression: ${message}');
							}
						} else if (!location.proxiedServer && invocation.queryRequest.offset > 0) {
							runModeAwareFailure(invocation.output, "--offset is only supported under --proxied-server");
						} else switch store.openIssueQuery(location.path, selectedDatabaseName(invocation, location), location.proxiedServer,
							invocation.global) {
							case Failure(message): runStoreFailure(message);
							case Success(query): closeIssueQuery(query, executeQuery(invocation, location, query));
						}
				}
		};
	}

	function executeQuery(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		return switch QuerySyntax.parse(invocation.queryRequest.expression) {
			case Invalid(message): runModeAwareFailure(invocation.output, 'invalid query expression: ${message}');
			case Parsed(expression):
				switch QueryPlanner.plan(expression, invocation.queryRequest, query) {
					case PlanInvalid(message): runModeAwareFailure(invocation.output, message);
					case Planned(plan): executeQueryPlan(invocation, location, query, plan);
				}
		};
	}

	function executeQueryPlan(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort, plan:QueryExecutionPlan):Int {
		final storageRequest:QueryStorageRequest = switch plan {
			case ExactQuery(filter, page):
				{filter: filter, fetch: OrderedPage(page.limit, page.offset, page.sortBy, page.reverse)};
			case PredicateQuery(filter, _, _): {filter: filter, fetch: CompleteCandidates};
		};
		return switch query.issueQuery(location.path, storageRequest, invocation.global) {
			case QueryRowsFailure(message): runStoreFailure(message);
			case QueryRows(source):
				switch finishQueryPage(plan, source) {
					case Failure(message): runStoreFailure(message);
					case Success(page): renderQuery(invocation, page.rows, page.hasMore);
				}
		};
	}

	static function finishQueryPage(plan:QueryExecutionPlan, source:beadshx.store.QueryStorageRequest.QueryRowPage):StoreResult<QueryPageResult> {
		return switch plan {
			case ExactQuery(_, _): Success(QueryPage.exactPage(source.rows, source.sourceHasMore));
			case PredicateQuery(_, compiledPredicate, policy):
				if (!source.complete) Failure("native query source returned an incomplete candidate set"); else Success(QueryPage.predicatePage(source.rows,
					compiledPredicate, policy));
		};
	}

	function renderQuery(invocation:Invocation, rows:Array<beadshx.store.IssueQueryRow>, hasMore:Bool):Int {
		final items = [for (row in rows) row.item];
		if (invocation.output == Json) {
			writeJsonStdout(renderListJsonArray({items: items, hasMore: hasMore, formatted: ""}, false, false));
		} else if (items.length == 0) {
			output.writeStdout('No issues found matching query: ${invocation.queryRequest.expression}\n');
		} else if (invocation.queryRequest.longFormat) {
			final rendered = new StringBuf();
			rendered.add('\nFound ${items.length} issues:\n\n');
			for (issue in items) {
				rendered.add('${issue.id} [P${issue.priority}] [${issue.issueType}] ${issue.status}\n');
				rendered.add('  ${issue.title}\n');
				if (issue.assignee != "")
					rendered.add('  Assignee: ${issue.assignee}\n');
				if (issue.labels.length > 0)
					rendered.add('  Labels: [${issue.labels.join(" ")}]\n');
				rendered.add("\n");
			}
			output.writeStdout(rendered.toString());
		} else {
			final rendered = new StringBuf();
			rendered.add('Found ${items.length} issues:\n');
			for (issue in items) {
				final assignee = issue.assignee == "" ? "" : ' @${issue.assignee}';
				final labels = issue.labels.length == 0 ? "" : ' [${issue.labels.join(" ")}]';
				rendered.add('${statusIcon(issue.status)} ${issue.id} [P${issue.priority}] [${issue.issueType}]${assignee}${labels} - ${issue.title}\n');
			}
			output.writeStdout(rendered.toString());
		}
		if (hasMore && invocation.queryRequest.limit > 0 && output.isStderrTerminal())
			output.writeStderr('\nShowing ${invocation.queryRequest.limit} issues; more results matched but were hidden by --limit. Use --limit 0 for all, or --limit N to raise the cap.\n');
		return 0;
	}

	function renderSearch(invocation:Invocation, page:IssueListPage):Int {
		if (invocation.output == Json) {
			writeJsonStdout(renderListJsonArray(page, false, false, false));
			return 0;
		}
		if (page.items.length == 0) {
			output.writeStdout('No issues found matching \'${invocation.searchQuery}\'\n');
			return 0;
		}
		final rendered = new StringBuf();
		if (invocation.listLong) {
			rendered.add('\nFound ${page.items.length} issues matching \'${invocation.searchQuery}\':\n\n');
			for (issue in page.items) {
				rendered.add('${issue.id} [P${issue.priority}] [${issue.issueType}] ${issue.status}\n');
				rendered.add('  ${issue.title}\n');
				if (issue.assignee != "")
					rendered.add('  Assignee: ${issue.assignee}\n');
				if (issue.labels.length > 0)
					rendered.add('  Labels: [${issue.labels.join(" ")}]\n');
				rendered.add("\n");
			}
		} else {
			rendered.add('Found ${page.items.length} issues matching \'${invocation.searchQuery}\':\n');
			for (issue in page.items) {
				final assignee = issue.assignee == "" ? "" : ' @${issue.assignee}';
				final labels = issue.labels.length == 0 ? "" : ' [${issue.labels.join(" ")}]';
				rendered.add('${issue.id} [P${issue.priority}] [${issue.issueType}] ${issue.status}${assignee}${labels} - ${issue.title}\n');
			}
		}
		output.writeStdout(rendered.toString());
		return 0;
	}

	function runStale(invocation:Invocation):Int {
		return switch workspace.discover(invocation.directory, invocation.databasePath) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFound();
			case Found(location):
				switch validateDatabaseSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!hasSelectedDatabase(location)) {
							runDatabaseNotFound();
						} else if (invocation.staleRequest.days < 1) {
							runModeAwareFailure(invocation.output, "--days must be at least 1");
						} else if (!validStaleStatus(invocation.staleRequest.status)) {
							runModeAwareFailure(invocation.output,
								'invalid status \'${invocation.staleRequest.status}\'. Valid values: open, in_progress, blocked, deferred');
						} else switch store.openIssueQuery(location.path, selectedDatabaseName(invocation, location), location.proxiedServer,
							invocation.global) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = switch query.issueStale(location.path, invocation.staleRequest, invocation.global) {
									case Failure(message): runStoreFailure(message);
									case Success(issues): renderStale(invocation, issues);
								};
								closeIssueQuery(query, result);
						}
				}
		};
	}

	static function validStaleStatus(status:String):Bool {
		return status == "" || status == "open" || status == "in_progress" || status == "blocked" || status == "deferred";
	}

	function renderStale(invocation:Invocation, issues:Array<StaleIssue>):Int {
		if (invocation.output == Json) {
			writeJsonStdout(renderRawIssuesJson(issues));
			return 0;
		}
		if (issues.length == 0) {
			output.writeStdout("\n✨ No stale issues found (all active)\n\n");
			return 0;
		}
		final rendered = new StringBuf();
		rendered.add('\n⏰ Stale issues (${issues.length} not updated in ${invocation.staleRequest.days}+ days):\n\n');
		final now = Date.now().getTime();
		for (index in 0...issues.length) {
			final issue = issues[index];
			final daysStale = Std.int((now - issue.updatedAtMillis) / 86400000.0);
			rendered.add('${index + 1}. [P${issue.priority}] ${issue.id}: ${issue.title}\n');
			rendered.add('   Status: ${issue.status}, Last updated: ${daysStale} days ago\n');
			if (issue.assignee != "")
				rendered.add('   Assignee: ${issue.assignee}\n');
			rendered.add("\n");
		}
		output.writeStdout(rendered.toString());
		return 0;
	}

	function runOrphans(invocation:Invocation):Int {
		if (invocation.orphansFix)
			return runModeAwareFailure(invocation.output, "operation 'orphans --fix' is not allowed in read-only mode");
		return switch workspace.discover(invocation.directory, invocation.databasePath) {
			case InvalidSelection(message): runStoreFailure(message);
			case NotFound: runDatabaseNotFound();
			case Found(location):
				switch validateDatabaseSelection(invocation, location) {
					case PlainFailure(message): runStoreFailure(message);
					case ModeAwareFailure(message): runModeAwareFailure(invocation.output, message);
					case Accepted:
						if (!hasSelectedDatabase(location)) {
							runDatabaseNotFound();
						} else switch store.openIssueQuery(location.path, selectedDatabaseName(invocation, location), location.proxiedServer,
							invocation.global) {
							case Failure(message): runStoreFailure(message);
							case Success(query):
								final result = switch query.issueOrphanCandidates(location.path, invocation.listRequest, invocation.global) {
									case Failure(message): runModeAwareFailure(invocation.output, 'unable to find orphaned issues: ${message}');
									case Success(scan): loadAndRenderOrphans(invocation, location.prefix, scan);
								};
								closeIssueQuery(query, result);
						}
				}
		};
	}

	function loadAndRenderOrphans(invocation:Invocation, configuredPrefix:String, scan:OrphanCandidateScan):Int {
		if (scan.candidates.length == 0)
			return renderOrphans(invocation, []);
		final gitDirectory = invocation.directory == "" ? "." : invocation.directory;
		return switch gitHistory.log(gitDirectory) {
			case Failure(message): runModeAwareFailure(invocation.output, 'unable to find orphaned issues: ${message}');
			case Success(log):
				final storedPrefix = scan.prefix == "" ? "bd" : scan.prefix;
				final prefix = configuredPrefix == "" ? storedPrefix : configuredPrefix;
				renderOrphans(invocation, findOrphanedIssues(scan.candidates, prefix, log));
		};
	}

	static function findOrphanedIssues(candidates:Array<OrphanCandidate>, prefix:String, log:String):Array<OrphanIssue> {
		final candidatesById = new StringMap<OrphanCandidate>();
		for (candidate in candidates)
			candidatesById.set(candidate.id, candidate);
		final recorded = new StringMap<Bool>();
		final issues = new Array<OrphanIssue>();
		final reference = new EReg('\\(${EReg.escape(prefix)}-[a-z0-9.]+\\)', "");
		for (line in log.split("\n")) {
			if (line == "")
				continue;
			final separator = line.indexOf(" ");
			if (separator < 0)
				continue;
			final commit = line.substr(0, separator);
			final message = line.substr(separator + 1);
			var offset = 0;
			while (offset < line.length && reference.matchSub(line, offset)) {
				final position = reference.matchedPos();
				final matched = reference.matched(0);
				final issueId = matched.substr(1, matched.length - 2);
				final candidate = candidatesById.get(issueId);
				if (candidate != null && !recorded.exists(issueId)) {
					recorded.set(issueId, true);
					issues.push({
						id: candidate.id,
						title: candidate.title,
						status: candidate.status,
						latestCommit: commit,
						latestCommitMessage: message
					});
				}
				offset = position.pos + position.len;
			}
		}
		return issues;
	}

	function renderOrphans(invocation:Invocation, issues:Array<OrphanIssue>):Int {
		if (invocation.output == Json) {
			writeJsonStdout(renderOrphansJson(issues));
			return 0;
		}
		if (issues.length == 0) {
			output.writeStdout("✓ No orphaned issues found\n");
			return 0;
		}
		issues.sort((left, right) -> left.id < right.id ? -1 : left.id == right.id ? 0 : 1);
		final rendered = new StringBuf();
		rendered.add('\n⚠ Found ${issues.length} orphaned issue(s):\n\n');
		for (index in 0...issues.length) {
			final issue = issues[index];
			rendered.add('${index + 1}. ${issue.id}: ${issue.title}\n');
			rendered.add('   Status: ${issue.status}\n');
			if (invocation.orphansDetails)
				rendered.add('   Latest commit: ${issue.latestCommit} - ${issue.latestCommitMessage}\n');
		}
		output.writeStdout(rendered.toString());
		return 0;
	}

	static function renderOrphansJson(issues:Array<OrphanIssue>):String {
		if (issues.length == 0)
			return "null\n";
		final lines = ["["];
		for (index in 0...issues.length) {
			final issue = issues[index];
			lines.push("  {");
			lines.push('    "issue_id": ${Json.stringify(issue.id)},');
			lines.push('    "title": ${Json.stringify(issue.title)},');
			lines.push('    "status": ${Json.stringify(issue.status)},');
			lines.push('    "latest_commit": ${Json.stringify(issue.latestCommit)},');
			lines.push('    "latest_commit_message": ${Json.stringify(issue.latestCommitMessage)}');
			lines.push(index == issues.length - 1 ? "  }" : "  },");
		}
		lines.push("]");
		return lines.join("\n") + "\n";
	}

	static function renderMoleculeReadyHuman(title:String, items:Array<IssueListItem>, analysis:MoleculeReadyAnalysis):String {
		final byId = new Map<String, IssueListItem>();
		for (item in items)
			byId.set(item.id, item);
		final rendered = new StringBuf();
		rendered.add('\n🧪 Ready steps in molecule: ${title}\n');
		rendered.add('   ID: ${analysis.moleculeId}\n');
		rendered.add('   Total: ${analysis.totalSteps} steps, ${analysis.readySteps} ready\n');
		if (analysis.readySteps == 0) {
			rendered.add("\n✨ No ready steps (all blocked or completed)\n\n");
			return rendered.toString();
		}
		if (analysis.groups.length > 0) {
			rendered.add("\n⚡ Parallel Groups:\n");
			for (group in analysis.groups) {
				var ready = 0;
				for (id in group.members) {
					final info = findMoleculeInfo(analysis.steps, id);
					if (info != null && info.isReady)
						ready++;
				}
				if (ready > 0)
					rendered.add('   ${group.name}: ${ready} ready\n');
			}
		}
		rendered.add("\n📋 Ready steps:\n\n");
		var index = 0;
		for (info in analysis.steps) {
			if (!info.isReady)
				continue;
			final issue = byId.get(info.stepId);
			if (issue == null)
				continue;
			index++;
			final group = info.parallelGroup == "" ? "" : ' [${info.parallelGroup}]';
			rendered.add('${index}. [P${issue.priority}] [${issue.issueType}] ${issue.id}: ${issue.title}${group}\n');
			final readyParallel = new Array<String>();
			for (id in info.canParallel) {
				final parallel = findMoleculeInfo(analysis.steps, id);
				if (parallel != null && parallel.isReady)
					readyParallel.push(id);
			}
			if (readyParallel.length > 0)
				rendered.add('   Can run with: [${readyParallel.join(" ")}]\n');
		}
		rendered.add("\n");
		return rendered.toString();
	}

	static function renderMoleculeReadyJson(title:String, items:Array<IssueListItem>, analysis:MoleculeReadyAnalysis):String {
		final byId = new Map<String, IssueListItem>();
		for (item in items)
			byId.set(item.id, item);
		final ready = [for (info in analysis.steps) if (info.isReady) info];
		final lines = [
			"{",
			'  "molecule_id": ${Json.stringify(analysis.moleculeId)},',
			'  "molecule_title": ${Json.stringify(title)},',
			'  "total_steps": ${analysis.totalSteps},',
			'  "ready_steps": ${analysis.readySteps},',
			'  "steps": ['
		];
		for (index in 0...ready.length) {
			final info = ready[index];
			final issue = byId.get(info.stepId);
			if (issue == null)
				continue;
			lines.push("    {");
			lines.push('      "issue": {');
			final issueFields = renderRawIssueFields(issue);
			for (fieldIndex in 0...issueFields.length) {
				final suffix = fieldIndex == issueFields.length - 1 ? "" : ",";
				lines.push('        ${issueFields[fieldIndex]}${suffix}');
			}
			lines.push("      },");
			lines.push('      "parallel_info": {');
			lines.push('        "step_id": ${Json.stringify(info.stepId)},');
			lines.push('        "status": ${Json.stringify(info.status)},');
			lines.push('        "is_ready": ${info.isReady},');
			lines.push('        "parallel_group": ${Json.stringify(info.parallelGroup)},');
			appendJsonStringArray(lines, "        ", "blocked_by", info.blockedBy, true);
			appendJsonStringArray(lines, "        ", "blocks", info.blocks, true);
			appendJsonStringArray(lines, "        ", "can_parallel", info.canParallel, false);
			lines.push(info.parallelGroup == "" ? "      }" : "      },");
			if (info.parallelGroup != "")
				lines.push('      "parallel_group": ${Json.stringify(info.parallelGroup)}');
			lines.push(index == ready.length - 1 ? "    }" : "    },");
		}
		lines.push("  ],");
		lines.push('  "parallel_groups": {');
		for (index in 0...analysis.groups.length) {
			final group = analysis.groups[index];
			appendJsonStringArray(lines, "    ", group.name, group.members, index != analysis.groups.length - 1);
		}
		lines.push("  },");
		lines.push('  "schema_version": 1');
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	static function renderReadyExplanationHuman(explanation:ReadyExplanation):String {
		final rendered = new StringBuf();
		rendered.add("\n📊 Ready Work Explanation\n\n");
		if (explanation.ready.length == 0) {
			rendered.add("○ No ready work\n\n");
		} else {
			rendered.add('● Ready (${explanation.ready.length} issues):\n\n');
			for (item in explanation.ready) {
				rendered.add('  ${item.issue.id} [P${item.issue.priority}] ${item.issue.title}\n');
				rendered.add('    Reason: ${item.reason}\n');
				if (item.resolvedBlockers != null && item.resolvedBlockers.length > 0)
					rendered.add('    Resolved blockers: ${item.resolvedBlockers.join(", ")}\n');
				if (item.dependentCount > 0)
					rendered.add('    Unblocks: ${item.dependentCount} issue(s)\n');
				rendered.add("\n");
			}
		}
		if (explanation.blocked.length > 0) {
			rendered.add('● Blocked (${explanation.blocked.length} issues):\n\n');
			for (item in explanation.blocked) {
				rendered.add('  ${item.issue.id} [P${item.issue.priority}] ${item.issue.title}\n');
				for (blocker in item.blockedBy)
					rendered.add('    ← blocked by ${blocker.id}: ${blocker.title} [${blocker.status}]\n');
				rendered.add("\n");
			}
		}
		if (explanation.cycles.length > 0) {
			rendered.add('⚠ Cycles detected (${explanation.cycles.length}):\n\n');
			for (cycle in explanation.cycles)
				rendered.add('  ${cycle.join(" → ")} → ${cycle[0]}\n');
			rendered.add("\n");
		}
		rendered.add('─ Summary: ${explanation.ready.length} ready, ${explanation.blocked.length} blocked');
		if (explanation.cycles.length > 0)
			rendered.add(', ${explanation.cycles.length} cycle(s)');
		rendered.add("\n\n");
		return rendered.toString();
	}

	static function renderGatedReadyHuman(molecules:Array<GatedMolecule>):String {
		if (molecules.length == 0)
			return "\n No molecules ready for gate-resume dispatch\n\n";
		final rendered = new StringBuf();
		rendered.add('\n Molecules ready for gate-resume dispatch (${molecules.length}):\n\n');
		for (index in 0...molecules.length) {
			final molecule = molecules[index];
			rendered.add('${index + 1}. ${molecule.moleculeId}: ${molecule.moleculeTitle}\n');
			rendered.add('   Gate closed: ${molecule.closedGate.id} (${molecule.closedGate.longFields.awaitType})\n');
			rendered.add('   Ready step: ${molecule.readyStep.id} - ${molecule.readyStep.title}\n\n');
		}
		rendered.add("To dispatch a molecule:\n");
		rendered.add("  bd sling <agent> --mol <molecule-id>\n");
		return rendered.toString();
	}

	static function renderGatedReadyJson(molecules:Array<GatedMolecule>):String {
		final lines = ["{", '  "count": ${molecules.length},', '  "molecules": ['];
		for (index in 0...molecules.length) {
			final molecule = molecules[index];
			final fields = [
				renderGatedIssueField("closed_gate", molecule.closedGate),
				'"molecule_id": ${Json.stringify(molecule.moleculeId)}',
				'"molecule_title": ${Json.stringify(molecule.moleculeTitle)}',
				renderGatedIssueField("ready_step", molecule.readyStep)
			];
			fields.sort(compareJsonFields);
			lines.push("    {");
			for (fieldIndex in 0...fields.length) {
				final suffix = fieldIndex == fields.length - 1 ? "" : ",";
				lines.push('      ${fields[fieldIndex]}${suffix}');
			}
			lines.push(index == molecules.length - 1 ? "    }" : "    },");
		}
		lines.push("  ],");
		lines.push('  "schema_version": 1');
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	static function renderGatedIssueField(name:String, issue:IssueListItem):String {
		final fields = renderRawIssueFields(issue, true, "        ");
		if (issue.labels.length > 0)
			fields.push(renderRawStringArray("labels", issue.labels, "        "));
		fields.sort(compareJsonFields);
		final lines = ['${Json.stringify(name)}: {'];
		for (index in 0...fields.length) {
			final suffix = index == fields.length - 1 ? "" : ",";
			lines.push('        ${fields[index]}${suffix}');
		}
		lines.push("      }");
		return lines.join("\n");
	}

	static function renderReadyExplanationJson(explanation:ReadyExplanation):String {
		final lines = ["{"];
		lines.push('  "blocked": [');
		for (index in 0...explanation.blocked.length) {
			final item = explanation.blocked[index];
			final fields = renderRawIssueFields(item.issue, true, "      ");
			if (item.issue.labels.length > 0)
				fields.push(renderRawStringArray("labels", item.issue.labels, "      "));
			final blockerLines = ['"blocked_by": ['];
			for (blockerIndex in 0...item.blockedBy.length) {
				final blocker = item.blockedBy[blockerIndex];
				blockerLines.push("        {");
				blockerLines.push('          "id": ${Json.stringify(blocker.id)},');
				blockerLines.push('          "priority": ${blocker.priority},');
				blockerLines.push('          "status": ${Json.stringify(blocker.status)},');
				blockerLines.push('          "title": ${Json.stringify(blocker.title)}');
				blockerLines.push(blockerIndex == item.blockedBy.length - 1 ? "        }" : "        },");
			}
			blockerLines.push("      ]");
			fields.push(blockerLines.join("\n"));
			fields.push('"blocked_by_count": ${item.blockedByCount}');
			fields.sort(compareJsonFields);
			lines.push("    {");
			for (fieldIndex in 0...fields.length) {
				final suffix = fieldIndex == fields.length - 1 ? "" : ",";
				lines.push('      ${fields[fieldIndex]}${suffix}');
			}
			lines.push(index == explanation.blocked.length - 1 ? "    }" : "    },");
		}
		lines.push(explanation.cycles.length == 0 ? "  ]," : "  ],");
		if (explanation.cycles.length > 0) {
			lines.push('  "cycles": [');
			for (cycleIndex in 0...explanation.cycles.length) {
				final cycle = explanation.cycles[cycleIndex];
				lines.push("    [");
				for (memberIndex in 0...cycle.length) {
					final suffix = memberIndex == cycle.length - 1 ? "" : ",";
					lines.push('      ${Json.stringify(cycle[memberIndex])}${suffix}');
				}
				lines.push(cycleIndex == explanation.cycles.length - 1 ? "    ]" : "    ],");
			}
			lines.push("  ],");
		}
		lines.push('  "ready": [');
		for (index in 0...explanation.ready.length) {
			final item = explanation.ready[index];
			final fields = renderRawIssueFields(item.issue, true, "      ");
			if (item.issue.labels.length > 0)
				fields.push(renderRawStringArray("labels", item.issue.labels, "      "));
			fields.push('"reason": ${Json.stringify(item.reason)}');
			if (item.resolvedBlockers == null) {
				fields.push('"resolved_blockers": null');
			} else {
				final resolvedLines = ['"resolved_blockers": ['];
				for (resolvedIndex in 0...item.resolvedBlockers.length) {
					final suffix = resolvedIndex == item.resolvedBlockers.length - 1 ? "" : ",";
					resolvedLines.push('        ${Json.stringify(item.resolvedBlockers[resolvedIndex])}${suffix}');
				}
				resolvedLines.push("      ]");
				fields.push(resolvedLines.join("\n"));
			}
			fields.push('"dependency_count": ${item.dependencyCount}');
			fields.push('"dependent_count": ${item.dependentCount}');
			if (item.parent != null)
				fields.push('"parent": ${Json.stringify(item.parent)}');
			fields.sort(compareJsonFields);
			lines.push("    {");
			for (fieldIndex in 0...fields.length) {
				final suffix = fieldIndex == fields.length - 1 ? "" : ",";
				lines.push('      ${fields[fieldIndex]}${suffix}');
			}
			lines.push(index == explanation.ready.length - 1 ? "    }" : "    },");
		}
		lines.push("  ],");
		lines.push('  "schema_version": 1,');
		lines.push('  "summary": {');
		lines.push('    "cycle_count": ${explanation.cycles.length},');
		lines.push('    "total_blocked": ${explanation.blocked.length},');
		lines.push('    "total_ready": ${explanation.ready.length}');
		lines.push("  }");
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	static function appendJsonStringArray(lines:Array<String>, indent:String, name:String, values:Array<String>, comma:Bool):Void {
		final suffix = comma ? "," : "";
		if (values.length == 0) {
			lines.push('${indent}${Json.stringify(name)}: []${suffix}');
			return;
		}
		lines.push('${indent}${Json.stringify(name)}: [');
		for (index in 0...values.length) {
			final valueSuffix = index == values.length - 1 ? "" : ",";
			lines.push('${indent}  ${Json.stringify(values[index])}${valueSuffix}');
		}
		lines.push('${indent}]${suffix}');
	}

	static function findMoleculeInfo(infos:Array<MoleculeParallelInfo>, id:String):Null<MoleculeParallelInfo> {
		for (info in infos)
			if (info.stepId == id)
				return info;
		return null;
	}

	function renderReady(invocation:Invocation, proxied:Bool, result:ReadyResult, query:IssueQueryPort, location:WorkspaceLocation):Int {
		if (invocation.output == Json) {
			final legacy = renderListJsonArray(result.page, false, false);
			if (result.truncated && output.usesJsonEnvelope()) {
				output.writeStdout(renderReadyEnvelope(legacy, result));
			} else {
				writeJsonStdout(legacy);
			}
			if (result.truncated) {
				if (proxied) {
					output.writeStderr('Showing ${result.page.items.length} ready issues; more matched but were hidden by --limit. Use --limit 0 for all, or --limit N to raise the cap.\n');
				} else
					switch result.total {
						case TotalKnown(total):
							output.writeStderr('Showing ${result.page.items.length} of ${total.wireValue()} ready issues. Use --limit 0 for all, or --limit N to raise the cap.\n');
						case TotalUnknown:
					}
			}
			return 0;
		}

		if (result.page.items.length == 0) {
			output.writeStdout(result.hasOpenIssues ? "\n✨ No ready work found (all issues have blocking dependencies)\n\n" : "\n✨ No open issues\n\n");
			return 0;
		}
		if (invocation.readyPlain || !invocation.readyPretty) {
			output.writeStdout(renderReadyPlain(result.page));
		} else {
			output.writeStdout(renderReadyPretty(result.page, query, location, invocation.global));
		}
		if (result.truncated) {
			if (proxied) {
				output.writeStdout('Showing ${result.page.items.length} ready issues; more matched but were hidden by --limit. Use --limit 0 for all, or --limit N to raise the cap.\n\n');
			} else
				switch result.total {
					case TotalKnown(total):
						output.writeStdout('Showing ${result.page.items.length} of ${total.wireValue()} ready issues. Use -n to show more.\n\n');
					case TotalUnknown:
				}
		}
		return 0;
	}

	static function renderReadyEnvelope(legacy:String, result:ReadyResult):String {
		var data = StringTools.endsWith(legacy, "\n") ? legacy.substr(0, legacy.length - 1) : legacy;
		data = StringTools.replace(data, "\n", "\n  ");
		final lines = [
			"{",
			'  "data": ${data},',
			'  "pagination": {',
			'    "returned": ${result.page.items.length},'
		];
		switch result.total {
			case TotalKnown(total):
				lines.push('    "total": ${total.wireValue()},');
			case TotalUnknown:
		}
		lines.push('    "truncated": true');
		lines.push("  },");
		lines.push('  "schema_version": 1');
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	static function renderReadyPlain(page:IssueListPage):String {
		var rendered = '\n📋 Ready work (${page.items.length} issues with no active blockers):\n\n';
		for (index in 0...page.items.length) {
			final issue = page.items[index];
			rendered += '${index + 1}. [P${issue.priority}] [${issue.issueType}] ${issue.id}: ${issue.title}\n';
			switch issue.estimatedMinutes {
				case IntPresent(value):
					rendered += '   Estimate: ${value} min\n';
				case IntAbsent:
			}
			if (issue.assignee != "")
				rendered += '   Assignee: ${issue.assignee}\n';
		}
		return rendered + "\n";
	}

	function renderReadyPretty(page:IssueListPage, query:IssueQueryPort, location:WorkspaceLocation, global:Bool):String {
		final parentTitles = new Map<String, String>();
		for (issue in page.items) {
			if (issue.parent == "" || parentTitles.exists(issue.parent))
				continue;
			var title = "";
			switch query.issueDetails(location.path, issue.parent, {includeDependents: false, includeComments: false, briefDependencies: true}, global) {
				case Success(DetailsFound(parent)) if (parent.issueType == "epic"):
					title = parent.title;
				case Failure(_) | Success(DetailsMissing) | Success(DetailsFound(_)):
			}
			parentTitles.set(issue.parent, title);
		}
		var rendered = "";
		for (issue in page.items) {
			var line = StringTools.trim(renderListLine(issue));
			final parentTitle = issue.parent == "" ? null : parentTitles.get(issue.parent);
			if (parentTitle != null && parentTitle != "")
				line += ' ← ${parentTitle}';
			rendered += line + "\n";
		}
		rendered += "\n" + StringTools.rpad("", "-", 80) + "\n";
		rendered += 'Ready: ${page.items.length} issues with no active blockers\n\n';
		rendered += "Status: ○ open  ◐ in_progress  ● blocked  ✓ closed  ❄ deferred\n";
		rendered += "Priority: P0–P4 (label only; not a status icon)\n";
		return rendered;
	}

	function renderCount(invocation:Invocation, result:CountResult):Int {
		switch invocation.output {
			case Human:
				if (result.groups.length == 0) {
					output.writeStdout(result.total.wireValue() + "\n");
				} else {
					var rendered = 'Total: ${result.total.wireValue()}\n\n';
					for (group in result.groups)
						rendered += '${group.group}: ${group.count.wireValue()}\n';
					output.writeStdout(rendered);
				}
			case Json:
				if (result.groups.length == 0) {
					writeJsonStdout('{\n  "count": ${result.total.wireValue()},\n  "schema_version": 1\n}\n');
				} else {
					final lines = ["{", '  "groups": ['];
					for (index in 0...result.groups.length) {
						final group = result.groups[index];
						final suffix = index + 1 == result.groups.length ? "" : ",";
						lines.push("    {");
						lines.push('      "count": ${group.count.wireValue()},');
						lines.push('      "group": ${Json.stringify(group.group)}');
						lines.push('    }${suffix}');
					}
					lines.push("  ],");
					lines.push('  "schema_version": 1,');
					lines.push('  "total": ${result.total.wireValue()}');
					lines.push("}");
					writeJsonStdout(lines.join("\n") + "\n");
				}
		}
		return 0;
	}

	function loadListResult(invocation:Invocation, location:WorkspaceLocation, effectiveLimit:Int, query:IssueQueryPort):IssueListResult {
		final hierarchical = invocation.listRequest.parentId != ""
			&& !invocation.listRequest.ready
			&& (invocation.watchMode || (invocation.output == Human && invocation.listRequest.format == ""));
		return hierarchical ? loadIssueHierarchy(invocation, location, effectiveLimit,
			query) : query.issueList(location.path, invocation.listRequest, effectiveLimit, invocation.global);
	}

	/**
		Reconstructs the recursive parent view in Haxe from typed list reads.

		The storage port returns direct children only. Haxe owns parent validation,
		cycle defense, traversal order, and the upstream-compatible error context.
	**/
	function loadIssueHierarchy(invocation:Invocation, location:WorkspaceLocation, effectiveLimit:Int, query:IssueQueryPort):IssueListResult {
		final request = invocation.listRequest;
		switch query.issueList(location.path, request, effectiveLimit, invocation.global) {
			case ListFailure(message):
				return ListFailure(message);
			case ListRowLimitExceeded(found, source, cap):
				return ListRowLimitExceeded(found, source, cap);
			case ListSuccess(_):
		}

		final parent = switch query.issueList(location.path, IssueListRequests.exact(request.parentId), 0, invocation.global) {
			case ListFailure(message): return ListFailure('error checking parent issue: ${message}');
			case ListRowLimitExceeded(found, source, cap): return ListRowLimitExceeded(found, source, cap);
			case ListSuccess(page):
				if (page.items.length == 0)
					return ListFailure('error checking parent issue: not found: issue ${request.parentId}');
				page.items[0];
		};

		final seen = new StringMap<Bool>();
		seen.set(request.parentId, true);
		return switch collectIssueDescendants(invocation, location, query, request, request.parentId, seen) {
			case ListFailure(message): ListFailure('error finding descendants: ${message}');
			case ListRowLimitExceeded(found, source, cap): ListRowLimitExceeded(found, source, cap);
			case ListSuccess(page):
				if (page.items.length > 0)
					page.items.push(parent);
				ListSuccess(page);
		};
	}

	function collectIssueDescendants(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort, request:IssueListRequest, parentId:String,
			seen:StringMap<Bool>):IssueListResult {
		final childRequest = IssueListRequests.descendants(request, parentId);
		return switch query.issueList(location.path, childRequest, 0, invocation.global) {
			case ListFailure(message): ListFailure(message);
			case ListRowLimitExceeded(found, source, cap): ListRowLimitExceeded(found, source, cap);
			case ListSuccess(page):
				final descendants = new Array<IssueListItem>();
				for (child in page.items) {
					if (seen.exists(child.id))
						continue;
					seen.set(child.id, true);
					descendants.push(child);
					switch collectIssueDescendants(invocation, location, query, request, child.id, seen) {
						case ListFailure(message): return ListFailure(message);
						case ListRowLimitExceeded(found, source, cap): return ListRowLimitExceeded(found, source, cap);
						case ListSuccess(nested):
							for (item in nested.items)
								descendants.push(item);
					}
				}
				ListSuccess({items: descendants, hasMore: false, formatted: ""});
		};
	}

	/**
		Keeps list polling policy in Haxe while WatchPort owns only timer and signal lifecycle.

		The first read must succeed because there is no last good screen yet. Later read
		failures are reported without discarding that screen or stopping the watcher.
	**/
	function runListWatch(invocation:Invocation, location:WorkspaceLocation, effectiveLimit:Int, query:IssueQueryPort):Int {
		var current:Null<IssueListPage> = null;
		switch loadListResult(invocation, location, effectiveLimit, query) {
			case ListFailure(message):
				return runStoreFailure('querying issues: ${message}');
			case ListRowLimitExceeded(found, source, cap):
				return runListRowLimitExceeded(found, source, cap);
			case ListSuccess(page):
				current = page;
		}
		if (current == null)
			return 1;

		output.writeStdout(renderWatchedList(current));
		var snapshot = issueListWatchSnapshot(current);
		output.writeStderr("\nWatching for changes... (Press Ctrl+C to exit)\n");
		watch.start();
		var stopped = false;
		while (!stopped) {
			stopped = watch.waitForStop();
			if (stopped)
				continue;
			switch loadListResult(invocation, location, effectiveLimit, query) {
				case ListFailure(message):
					output.writeStderr('Error refreshing issues: ${message}\n');
				case ListRowLimitExceeded(found, source, cap):
					output.writeStderr('Error refreshing issues: ${listRowLimitMessage(found, source, cap)}\n');
				case ListSuccess(page):
					final nextSnapshot = issueListWatchSnapshot(page);
					if (nextSnapshot != snapshot) {
						snapshot = nextSnapshot;
						output.writeStdout(renderWatchedList(page));
						output.writeStderr("\nWatching for changes... (Press Ctrl+C to exit)\n");
					}
			}
		}
		watch.close();
		output.writeStderr("\nStopped watching.\n");
		return 0;
	}

	static function listRowLimitMessage(found:Int, source:String, cap:Int):String {
		return source == "" ? 'search returned ${found} rows, exceeding cap of ${cap}' : 'search returned ${found} rows, exceeding ${source} cap of ${cap}';
	}

	static function renderWatchedList(page:IssueListPage):String {
		final now = Date.now();
		final time = '${twoDigits(now.getHours())}:${twoDigits(now.getMinutes())}:${twoDigits(now.getSeconds())}';
		return "\x1b[2J\x1b[H" + StringTools.rpad("", "=", 80) + "\n" + 'Beads - Open & In Progress (${time})\n' + StringTools.rpad("", "=", 80) + "\n\n"
			+ renderListHuman(page, false, "");
	}

	static function twoDigits(value:Int):String {
		return value < 10 ? '0${value}' : Std.string(value);
	}

	static function issueListWatchSnapshot(page:IssueListPage):String {
		final snapshot = new StringBuf();
		for (issue in page.items)
			snapshot.add('${issue.id}:${issue.status}:${issue.updatedAt};');
		return snapshot.toString();
	}

	function renderListResult(invocation:Invocation, result:IssueListResult):Int {
		return switch result {
			case ListFailure(message): runStoreFailure(message);
			case ListRowLimitExceeded(found, source, cap): runListRowLimitExceeded(found, source, cap);
			case ListSuccess(page):
				if (invocation.listRequest.format != "") {
					output.writeStdout(page.formatted);
				} else
					switch invocation.output {
						case Human:
							if (page.items.length == 0
								&& invocation.listRequest.parentId != ""
								&& !invocation.listRequest.ready) output.writeStdout('Issue \'${invocation.listRequest.parentId}\' has no children\n'); else
								output.writeStdout(invocation.listFlat ? renderListFlat(page, invocation.listLong, invocation.listRequest.skipLabels,
								invocation.listRequest.brief) : renderListHuman(page, invocation.listRequest.skipLabels, invocation.listDepsMode));
						case Json: writeJsonStdout(renderListJson(page, invocation.listRequest.skipLabels));
					}
				0;
		};
	}

	function resolveListLimit(invocation:Invocation, location:WorkspaceLocation):Int {
		return switch invocation.listRequest.limit {
			case IntPresent(value): value;
			case IntAbsent:
				if (invocation.listRequest.all) 0; else if (location.listLimitConfigured) location.listLimit; else if (!output.isStdoutTerminal()) 0; else
					if (invocation.listAgentMode) 20; else 50;
		};
	}

	function runListRowLimitExceeded(found:Int, source:String, cap:Int):Int {
		final attributedSource = source == "" ? "BEADS_MAX_ROWS" : source;
		output.writeStderr('Error: too many rows: ${found} found, ${attributedSource}=${cap} exceeded.\n');
		output.writeStderr("       Refine the query (add filters, set --limit), or raise the cap with\n");
		output.writeStderr("       --max-rows N or BEADS_MAX_ROWS=N.\n");
		return 2;
	}

	static function renderListHuman(page:IssueListPage, skipLabels:Bool, depsMode:String):String {
		if (page.items.length == 0)
			return appendSkipLabelsFooter("No issues found.\n", skipLabels);
		final byId = new Map<String, IssueListItem>();
		for (item in page.items)
			byId.set(item.id, item);
		final childGroups = new Array<ListChildGroup>();
		var roots = new Array<IssueListItem>();
		for (item in page.items) {
			var parent = item.parent;
			if (parent == "") {
				final separator = item.id.lastIndexOf(".");
				if (separator > 0) {
					final dottedParent = item.id.substr(0, separator);
					if (byId.exists(dottedParent))
						parent = dottedParent;
				}
			}
			if (parent != "" && byId.exists(parent)) {
				var group:Null<ListChildGroup> = null;
				for (candidate in childGroups) {
					if (candidate.parent == parent) {
						group = candidate;
						break;
					}
				}
				if (group == null) {
					group = {parent: parent, children: []};
					childGroups.push(group);
				}
				group.children.push(item);
			} else {
				roots.push(item);
			}
		}
		roots = depsMode == "" ? sortedListItems(roots) : orderListItemsByDependencies(roots);
		for (index in 0...childGroups.length) {
			final group = childGroups[index];
			childGroups[index] = {
				parent: group.parent,
				children: depsMode == "" ? sortedListItems(group.children) : orderListItemsByDependencies(group.children)
			};
		}
		final rendered = new StringBuf();
		for (root in roots) {
			rendered.add(renderListLine(root));
			if (depsMode != "")
				rendered.add(renderListDependencyAnnotations(root, "", depsMode, byId));
			renderListChildren(rendered, root.id, "", childGroups, depsMode, byId);
		}
		var open = 0;
		var inProgress = 0;
		for (item in page.items) {
			if (item.status == "open")
				open++;
			else if (item.status == "in_progress")
				inProgress++;
		}
		rendered.add("\n" + StringTools.rpad("", "-", 80) + "\n");
		if (page.hasMore)
			rendered.add('Showing ${page.items.length} issues (${open} open, ${inProgress} in progress); more match (truncated by --limit). Use --limit 0 for all.\n');
		else
			rendered.add('Total: ${page.items.length} issues (${open} open, ${inProgress} in progress)\n');
		rendered.add("\nStatus: ○ open  ◐ in_progress  ● blocked  ✓ closed  ❄ deferred\n");
		rendered.add("Priority: P0–P4 (label only; not a status icon)\n");
		if (depsMode != "")
			rendered.add("Deps:   ╌╌▷ = depends-on / relationship (points to target); siblings ordered so dependencies come first; ↗ = target outside current view\n");
		return appendSkipLabelsFooter(rendered.toString(), skipLabels);
	}

	static function renderListChildren(rendered:StringBuf, parent:String, prefix:String, childGroups:Array<ListChildGroup>, depsMode:String,
			byId:Map<String, IssueListItem>):Void {
		var group:Null<ListChildGroup> = null;
		for (candidate in childGroups) {
			if (candidate.parent == parent) {
				group = candidate;
				break;
			}
		}
		if (group == null)
			return;
		for (index in 0...group.children.length) {
			final child = group.children[index];
			final last = index == group.children.length - 1;
			rendered.add(prefix + (last ? "└── " : "├── ") + renderListLine(child));
			final extension = prefix + (last ? "    " : "│   ");
			if (depsMode != "")
				rendered.add(renderListDependencyAnnotations(child, extension, depsMode, byId));
			renderListChildren(rendered, child.id, extension, childGroups, depsMode, byId);
		}
	}

	static function renderListLine(issue:IssueListItem):String {
		final typeBadge = switch issue.issueType {
			case "epic": "[epic] ";
			case "bug": "[bug] ";
			case _: "";
		};
		return '${statusIcon(issue.status)} ${issue.id} P${issue.priority} ${typeBadge}${issue.title}\n';
	}

	static function compareListItems(left:IssueListItem, right:IssueListItem):Int {
		return left.priority != right.priority ? (left.priority < right.priority ? -1 : 1) : compareIssueIds(left.id, right.id);
	}

	static function sortedListItems(items:Array<IssueListItem>):Array<IssueListItem> {
		final ordered = items.copy();
		ordered.sort(compareListItems);
		return ordered;
	}

	static function orderListItemsByDependencies(items:Array<IssueListItem>):Array<IssueListItem> {
		if (items.length < 2)
			return items.copy();
		final byId = new Map<String, IssueListItem>();
		final indegree = new Map<String, Int>();
		final dependents = new Map<String, Array<String>>();
		for (item in items) {
			byId.set(item.id, item);
			indegree.set(item.id, 0);
		}
		for (item in items) {
			final seen = new Map<String, Bool>();
			for (dependency in item.dependencies) {
				final presentation = listDependencyPresentation(dependency.dependencyType);
				if (presentation == null
					|| !presentation.scheduling
					|| dependency.dependsOnId == item.id
					|| !byId.exists(dependency.dependsOnId)
					|| seen.exists(dependency.dependsOnId))
					continue;
				seen.set(dependency.dependsOnId, true);
				final degree = indegree.get(item.id);
				indegree.set(item.id, (degree == null ? 0 : degree) + 1);
				var targets = dependents.get(dependency.dependsOnId);
				if (targets == null) {
					targets = [];
					dependents.set(dependency.dependsOnId, targets);
				}
				targets.push(item.id);
			}
		}
		final ready = new Array<IssueListItem>();
		for (item in items)
			if (indegree.get(item.id) == 0)
				ready.push(item);
		ready.sort(compareListItems);
		final ordered = new Array<IssueListItem>();
		final emitted = new Map<String, Bool>();
		while (ready.length > 0) {
			final item = ready[0];
			ready.shift();
			ordered.push(item);
			emitted.set(item.id, true);
			final targets = dependents.get(item.id);
			if (targets == null)
				continue;
			var grew = false;
			for (targetId in targets) {
				final degree = indegree.get(targetId);
				final next = (degree == null ? 0 : degree) - 1;
				indegree.set(targetId, next);
				if (next == 0) {
					final target = byId.get(targetId);
					if (target != null)
						ready.push(target);
					grew = true;
				}
			}
			if (grew)
				ready.sort(compareListItems);
		}
		if (ordered.length < items.length) {
			final remainder = new Array<IssueListItem>();
			for (item in items)
				if (!emitted.exists(item.id))
					remainder.push(item);
			remainder.sort(compareListItems);
			for (item in remainder)
				ordered.push(item);
		}
		return ordered;
	}

	static function renderListDependencyAnnotations(item:IssueListItem, prefix:String, depsMode:String, byId:Map<String, IssueListItem>):String {
		final inView = new Array<ListDependencyRow>();
		final outside = new Array<String>();
		final seen = new Map<String, Bool>();
		for (dependency in item.dependencies) {
			final presentation = listDependencyPresentation(dependency.dependencyType);
			if (presentation == null || (depsMode != "all" && !presentation.scheduling))
				continue;
			final key = dependency.dependencyType + "\x00" + dependency.dependsOnId;
			if (seen.exists(key))
				continue;
			seen.set(key, true);
			final target = byId.get(dependency.dependsOnId);
			if (target == null)
				outside.push(dependency.dependsOnId);
			else
				inView.push({label: presentation.label, target: dependency.dependsOnId, title: target.title});
		}
		inView.sort((left, right) -> left.label != right.label ? (left.label < right.label ? -1 : 1) : compareIssueIds(left.target, right.target));
		outside.sort(compareIssueIds);
		final rendered = new StringBuf();
		for (row in inView)
			rendered.add(prefix + "╌╌▷ " + StringTools.rpad('[${row.label}]', " ", 20) + ' ${row.target} ${row.title}\n');
		if (outside.length > 0) {
			final named = outside.length > 4 ? outside.slice(0, 4) : outside;
			final suffix = outside.length > 4 ? ', +${outside.length - 4} more' : "";
			rendered.add(prefix + '╌╌▷ ↗ ${outside.length} outside this view: ${named.join(", ")}${suffix}\n');
		}
		return rendered.toString();
	}

	static function listDependencyPresentation(dependencyType:String):Null<ListDependencyPresentation> {
		return switch dependencyType {
			case "parent-child": null;
			case "blocks": {label: "depends-on", scheduling: true};
			case "conditional-blocks": {label: "conditionally-depends-on", scheduling: true};
			case "waits-for": {label: "waits-for", scheduling: true};
			case "related" | "relates-to": {label: "related", scheduling: false};
			case "discovered-from": {label: "discovered-from", scheduling: false};
			case "duplicates": {label: "duplicates", scheduling: false};
			case "supersedes": {label: "superseded-by", scheduling: false};
			case "replies-to": {label: "replies-to", scheduling: false};
			case _: {label: dependencyType, scheduling: false};
		};
	}

	static function renderListJson(page:IssueListPage, skipLabels:Bool):String {
		final array = renderListJsonArray(page, skipLabels, skipLabels);
		if (!skipLabels)
			return array;
		final rows = array.split("\n");
		final lines = ['{', '  "issues": ${rows[0]}'];
		for (index in 1...(rows.length - 1))
			lines.push("  " + rows[index]);
		lines[lines.length - 1] += ",";
		lines.push('  "meta": {');
		lines.push('    "count": ${page.items.length},');
		lines.push('    "skip_labels": true');
		lines.push("  }");
		lines[lines.length - 1] += ",";
		lines.push('  "schema_version": 1');
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	static function appendSkipLabelsFooter(rendered:String, skipLabels:Bool):String {
		return skipLabels ? rendered + "\nnote: --skip-labels in effect — labels suppressed in output.\n" : rendered;
	}

	static function renderListFlat(page:IssueListPage, long:Bool, skipLabels:Bool, brief:Bool):String {
		if (long)
			return renderListLong(page, skipLabels, brief);
		final rendered = new StringBuf();
		for (issue in page.items) {
			final assignee = issue.assignee == "" ? "" : ' @${issue.assignee}';
			final labels = issue.labels.length == 0 ? "" : ' [${issue.labels.join(" ")}]';
			final dependencyInfo = renderListBlockingInfo(issue);
			final suffix = dependencyInfo == "" ? "" : ' ${dependencyInfo}';
			final renderedStatus = issue.status == "open" && issue.blockedBy.length > 0 ? "blocked" : issue.status;
			rendered.add('${statusIcon(renderedStatus)} ${issue.id} [P${issue.priority}] [${issue.issueType}]${assignee}${labels} - ${issue.title}${suffix}\n');
		}
		return appendSkipLabelsFooter(rendered.toString(), skipLabels);
	}

	static function renderListBlockingInfo(issue:IssueListItem):String {
		final parts = new Array<String>();
		if (issue.blockingParent != "")
			parts.push('parent: ${issue.blockingParent}');
		if (issue.blockedBy.length > 0)
			parts.push('blocked by: ${issue.blockedBy.join(", ")}');
		if (issue.blocks.length > 0)
			parts.push('blocks: ${issue.blocks.join(", ")}');
		return parts.length == 0 ? "" : '(' + parts.join(", ") + ')';
	}

	static function renderListLong(page:IssueListPage, skipLabels:Bool, brief:Bool):String {
		final rendered = new StringBuf();
		rendered.add('\nFound ${page.items.length} issues:\n\n');
		for (issue in page.items) {
			rendered.add('${issue.id} [P${issue.priority}] [${issue.issueType}] ${issue.status}\n');
			rendered.add('  ${issue.title}\n');
			if (issue.assignee != "")
				rendered.add('  Assignee: ${issue.assignee}\n');
			if (brief) {
				rendered.add("  Description: (omitted by --brief)\n");
			} else {
				final description = StringTools.trim(issue.description);
				if (description != "") {
					rendered.add("  Description:\n");
					for (line in description.split("\n"))
						rendered.add('    ${line}\n');
				}
			}
			if (skipLabels)
				rendered.add("  Labels: (suppressed by --skip-labels)\n");
			else if (issue.labels.length > 0)
				rendered.add('  Labels: [${issue.labels.join(" ")}]\n');
			if (!issue.metadata.isAbsent()) {
				final count = issue.metadata.topLevelFieldCount();
				rendered.add(count > 0 ? '  Metadata: ${count} keys\n' : "  Metadata: set\n");
			}
			rendered.add("\n");
		}
		return appendSkipLabelsFooter(rendered.toString(), skipLabels);
	}

	static function renderListJsonArray(page:IssueListPage, forceLabels:Bool, sortFields:Bool, includeRelations:Bool = true):String {
		if (page.items.length == 0)
			return "[]\n";
		final lines = ["["];
		for (index in 0...page.items.length) {
			final item = page.items[index];
			final fields = renderIssueRecordFields(item, "    ", sortFields);
			if (forceLabels) {
				fields.push('"labels": []');
			} else if (item.labels.length > 0) {
				final labelLines = ['"labels": ['];
				for (labelIndex in 0...item.labels.length) {
					final suffix = labelIndex == item.labels.length - 1 ? "" : ",";
					labelLines.push('      ${Json.stringify(item.labels[labelIndex])}${suffix}');
				}
				labelLines.push("    ]");
				fields.push(labelLines.join("\n"));
			}
			if (includeRelations && item.dependencies.length > 0)
				fields.push(renderListDependencies(item, sortFields));
			if (item.sender != "")
				fields.push('"sender": ${Json.stringify(item.sender)}');
			fields.push('"dependency_count": ${item.dependencyCount}');
			fields.push('"dependent_count": ${item.dependentCount}');
			fields.push('"comment_count": ${item.commentCount}');
			if (includeRelations && item.parent != "")
				fields.push('"parent": ${Json.stringify(item.parent)}');
			if (sortFields)
				fields.sort(compareJsonFields);
			lines.push("  {");
			for (fieldIndex in 0...fields.length) {
				final suffix = fieldIndex == fields.length - 1 ? "" : ",";
				lines.push('    ${fields[fieldIndex]}${suffix}');
			}
			lines.push(index == page.items.length - 1 ? "  }" : "  },");
		}
		lines.push("]");
		return lines.join("\n") + "\n";
	}

	static function renderListDependencies(item:IssueListItem, sortFields:Bool):String {
		final lines = ['"dependencies": ['];
		for (index in 0...item.dependencies.length) {
			final dependency = item.dependencies[index];
			final fields = new Array<String>();
			if (dependency.id != "")
				fields.push('"id": ${Json.stringify(dependency.id)}');
			fields.push('"issue_id": ${Json.stringify(dependency.issueId)}');
			fields.push('"depends_on_id": ${Json.stringify(dependency.dependsOnId)}');
			fields.push('"type": ${Json.stringify(dependency.dependencyType)}');
			fields.push('"created_at": ${Json.stringify(dependency.createdAt)}');
			if (dependency.createdBy != "")
				fields.push('"created_by": ${Json.stringify(dependency.createdBy)}');
			if (dependency.metadata != "")
				fields.push('"metadata": ${Json.stringify(dependency.metadata)}');
			if (dependency.threadId != "")
				fields.push('"thread_id": ${Json.stringify(dependency.threadId)}');
			if (sortFields)
				fields.sort(compareJsonFields);
			lines.push("      {");
			for (fieldIndex in 0...fields.length) {
				final suffix = fieldIndex == fields.length - 1 ? "" : ",";
				lines.push('        ${fields[fieldIndex]}${suffix}');
			}
			final suffix = index == item.dependencies.length - 1 ? "" : ",";
			lines.push('      }${suffix}');
		}
		lines.push("    ]");
		return lines.join("\n");
	}

	static function compareJsonFields(left:String, right:String):Int {
		return left < right ? -1 : left == right ? 0 : 1;
	}

	function runShowWatch(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.showCurrent && invocation.showIds.length > 0)
			return runModeAwareFailure(invocation.output, "--current cannot be combined with explicit issue IDs");
		final ids = invocation.showIds.copy();
		if (invocation.showCurrent) {
			final currentId = resolveCurrentIssueId(invocation, location, query);
			if (currentId == "")
				return runModeAwareFailure(invocation.output, "no current issue found (no in-progress, hooked, or recently touched issues)");
			ids.push(currentId);
		}
		if (ids.length != 1)
			return runModeAwareFailure(invocation.output, "watch mode requires exactly one issue ID");

		final requestedId = ids[0];
		var canonicalId = requestedId;
		var current:Null<IssueDetails> = null;
		switch loadWatchedIssue(location, requestedId, invocation.global, true, query) {
			case Failure(message):
				output.writeStderr('Error fetching issue: ${message}\n');
				return 0;
			case Success(DetailsMissing):
				output.writeStdout('Issue not found: ${requestedId}\n');
				return 0;
			case Success(DetailsFound(issue)):
				canonicalId = issue.id;
				current = issue;
		}
		if (current == null)
			return 0;

		output.writeStdout(renderIssueHuman(current, false, WatchedShow));
		var snapshot = issueWatchSnapshot(current);
		output.writeStderr("\nWatching for changes... (Press Ctrl+C to exit)\n");
		watch.start();
		var stopped = false;
		while (!stopped) {
			stopped = watch.waitForStop();
			if (stopped)
				continue;
			switch loadWatchedIssue(location, canonicalId, invocation.global, true, query) {
				case Failure(_) | Success(DetailsMissing):
				case Success(DetailsFound(issue)):
					final nextSnapshot = issueWatchSnapshot(issue);
					if (nextSnapshot != snapshot) {
						snapshot = nextSnapshot;
						output.writeStdout(renderIssueHuman(issue, false, WatchedShow));
						output.writeStderr("\nWatching for changes... (Press Ctrl+C to exit)\n");
					}
			}
		}
		watch.close();
		output.writeStderr("\nStopped watching.\n");
		return 0;
	}

	function loadWatchedIssue(location:WorkspaceLocation, id:String, global:Bool, includeComments:Bool, query:IssueQueryPort):StoreResult<IssueDetailsLookup> {
		return switch lookupIssueSummary(location, id, global, query) {
			case Failure(message): Failure(message);
			case Success(IssueMissing): Success(DetailsMissing);
			case Success(IssueFound(summary)):
				query.issueDetails(location.path, summary.id, {
					includeDependents: true,
					includeComments: includeComments,
					briefDependencies: false
				}, global);
		};
	}

	static function issueWatchSnapshot(issue:IssueDetails):String {
		return '${issue.id}:${issue.status}:${issue.updatedAt}';
	}

	function runShowThread(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.showCurrent && invocation.showIds.length > 0)
			return runModeAwareFailure(invocation.output, "--current cannot be combined with explicit issue IDs");
		final ids = invocation.showIds.copy();
		if (invocation.showCurrent) {
			final currentId = resolveCurrentIssueId(invocation, location, query);
			if (currentId == "")
				return runModeAwareFailure(invocation.output, "no current issue found (no in-progress, hooked, or recently touched issues)");
			ids.push(currentId);
		}
		if (ids.length == 0)
			return runModeAwareFailure(invocation.output, "at least one issue ID is required (use positional args, --id flag, or --current)");

		final requestedId = ids[0];
		var canonicalId = "";
		switch lookupIssueSummary(location, requestedId, invocation.global, query) {
			case Failure(_) | Success(IssueMissing):
				if (invocation.output == Human)
					return runShowHuman(invocation, location, query);
				return runShowJson(invocation, location, query);
			case Success(IssueFound(summary)):
				canonicalId = summary.id;
		}
		final detailRequest:IssueDetailsRequest = {
			includeDependents: true,
			includeComments: false,
			briefDependencies: false
		};
		var root:Null<IssueDetails> = null;
		switch query.issueDetails(location.path, canonicalId, detailRequest, invocation.global) {
			case Failure(message):
				return runStoreFailure('fetching message ${canonicalId}: ${message}');
			case Success(DetailsMissing):
				return runStoreFailure('message ${canonicalId} not found');
			case Success(DetailsFound(issue)):
				root = issue;
		}
		if (root == null)
			return runStoreFailure('message ${canonicalId} not found');
		final ancestors = new Map<String, Bool>();
		ancestors.set(root.id, true);
		while (true) {
			final parentId = threadParentId(root);
			if (parentId == "" || ancestors.exists(parentId))
				break;
			ancestors.set(parentId, true);
			switch query.issueDetails(location.path, parentId, detailRequest, invocation.global) {
				case Failure(_) | Success(DetailsMissing):
					break;
				case Success(DetailsFound(parent)):
					root = parent;
			}
		}

		final entries = new Array<ThreadEntry>();
		entries.push({issue: root, parentId: ""});
		final threadIds = new Map<String, Bool>();
		threadIds.set(root.id, true);
		final queue = [root];
		var queueIndex = 0;
		while (queueIndex < queue.length) {
			final current = queue[queueIndex++];
			for (dependent in current.dependents) {
				if (dependent.dependencyType != "replies-to" || threadIds.exists(dependent.id))
					continue;
				switch query.issueDetails(location.path, dependent.id, detailRequest, invocation.global) {
					case Failure(_) | Success(DetailsMissing):
					case Success(DetailsFound(reply)):
						threadIds.set(reply.id, true);
						entries.push({issue: reply, parentId: current.id});
						queue.push(reply);
				}
			}
		}
		entries.sort((left, right) -> left.issue.createdAt < right.issue.createdAt ? -1 : left.issue.createdAt == right.issue.createdAt ? 0 : 1);
		switch invocation.output {
			case Human:
				output.writeStdout(renderThreadHuman(root.title, entries));
			case Json:
				writeJsonStdout(renderThreadJson(entries));
		}
		return 0;
	}

	static function threadParentId(issue:IssueDetails):String {
		for (dependency in issue.dependencies)
			if (dependency.dependencyType == "replies-to")
				return dependency.id;
		return "";
	}

	static function renderThreadHuman(title:String, entries:Array<ThreadEntry>):String {
		final parents = new Map<String, String>();
		for (entry in entries)
			parents.set(entry.issue.id, entry.parentId);
		var rendered = '\n📬 Thread: ${title}\n' + StringTools.rpad("", "─", 66) + "\n";
		for (entry in entries) {
			var depth = 0;
			var parent = entry.parentId;
			while (parent != "" && depth < 5) {
				depth++;
				final next = parents.get(parent);
				parent = next == null ? "" : next;
			}
			final indent = StringTools.lpad("", " ", depth * 2);
			final issue = entry.issue;
			final icon = issue.status == "closed" ? "✓" : "📧";
			rendered += '${indent}${icon} ${issue.id} ${formatHumanTime(issue.createdAt)}\n';
			rendered += '${indent}  From: ${issue.longFields.sender}  To: ${issue.assignee}\n';
			if (entry.parentId != "")
				rendered += '${indent}  Re: ${entry.parentId}\n';
			rendered += '${indent}  Subject: ${issue.title}\n';
			if (issue.description != "")
				for (line in issue.description.split("\n"))
					rendered += '${indent}  ${line}\n';
			rendered += "\n";
		}
		return rendered + 'Total: ${entries.length} messages in thread\n\n';
	}

	function runShowRefs(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.showCurrent && invocation.showIds.length > 0)
			return runModeAwareFailure(invocation.output, "--current cannot be combined with explicit issue IDs");
		final ids = invocation.showIds.copy();
		if (invocation.showCurrent) {
			final currentId = resolveCurrentIssueId(invocation, location, query);
			if (currentId == "")
				return runModeAwareFailure(invocation.output, "no current issue found (no in-progress, hooked, or recently touched issues)");
			ids.push(currentId);
		}
		if (ids.length == 0)
			return runModeAwareFailure(invocation.output, "at least one issue ID is required (use positional args, --id flag, or --current)");
		final groups = new Array<ShowDependencyGroup>();
		for (id in ids) {
			switch lookupIssueSummary(location, id, invocation.global, query) {
				case Failure(message):
					output.writeStderr('Error resolving ${id}: ${message}\n');
				case Success(IssueMissing):
					output.writeStderr('Issue ${id} not found\n');
				case Success(IssueFound(summary)):
					switch query.issueDependents(location.path, summary.id, invocation.global) {
						case Failure(message): output.writeStderr('Error getting refs for ${id}: ${message}\n');
						case Success(references):
							var replaced = false;
							for (index in 0...groups.length) {
								if (groups[index].issueId == summary.id) {
									groups[index] = {issueId: summary.id, items: references};
									replaced = true;
									break;
								}
							}
							if (!replaced) groups.push({issueId: summary.id, items: references});
					}
			}
		}
		switch invocation.output {
			case Json:
				writeJsonStdout(renderShowDependencyMapJson(groups, output.usesJsonEnvelope(), true));
			case Human:
				for (group in groups)
					output.writeStdout(renderShowRefsGroup(group));
		}
		return 0;
	}

	static function renderShowRefsGroup(group:ShowDependencyGroup):String {
		if (group.items.length == 0)
			return '\n${group.issueId}: No references found\n';
		final sections = new Array<HumanDependencyGroup>();
		for (reference in group.items) {
			final relation = humanDependencyRelation(reference.dependencyType);
			var selected:Null<HumanDependencyGroup> = null;
			for (section in sections)
				if (section.relation.canonical == relation.canonical) {
					selected = section;
					break;
				}
			if (selected == null) {
				selected = {relation: relation, dependencies: []};
				sections.push(selected);
			}
			selected.dependencies.push(reference);
		}
		sections.sort(compareHumanDependencyGroups);
		var rendered = '\n📎 References to ${group.issueId}:\n';
		for (section in sections) {
			rendered += '\n  ${referenceEmoji(section.relation.canonical)} ${section.relation.incomingHeading} (${section.dependencies.length}):\n';
			for (reference in section.dependencies)
				rendered += '    ${reference.id}: ${reference.title} [P${reference.priority} - ${reference.status}]\n';
		}
		return rendered + "\n";
	}

	static function referenceEmoji(dependencyType:String):String {
		return switch dependencyType {
			case "until": "⏳";
			case "caused-by": "⚡";
			case "validates": "✅";
			case "blocks": "🚫";
			case "parent-child": "↳";
			case "related": "↔";
			case "tracks": "👁";
			case "discovered-from": "◊";
			case "supersedes": "⬆";
			case "duplicates": "🔄";
			case "replies-to": "💬";
			case "approved-by": "👍";
			case "authored-by": "✏";
			case "assigned-to": "👤";
			case _: "→";
		};
	}

	function runShowChildren(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.showCurrent && invocation.showIds.length > 0)
			return runModeAwareFailure(invocation.output, "--current cannot be combined with explicit issue IDs");
		final ids = invocation.showIds.copy();
		if (invocation.showCurrent) {
			final currentId = resolveCurrentIssueId(invocation, location, query);
			if (currentId == "")
				return runModeAwareFailure(invocation.output, "no current issue found (no in-progress, hooked, or recently touched issues)");
			ids.push(currentId);
		}
		if (ids.length == 0)
			return runModeAwareFailure(invocation.output, "at least one issue ID is required (use positional args, --id flag, or --current)");
		final groups = new Array<ShowDependencyGroup>();
		for (id in ids) {
			switch lookupIssueSummary(location, id, invocation.global, query) {
				case Failure(message):
					output.writeStderr('Error resolving ${id}: ${message}\n');
				case Success(IssueMissing):
					output.writeStderr('Issue ${id} not found\n');
				case Success(IssueFound(summary)):
					switch query.issueDependents(location.path, summary.id, invocation.global) {
						case Failure(message): output.writeStderr('Error getting children for ${id}: ${message}\n');
						case Success(dependents):
							final children = new Array<IssueDependency>();
							for (dependent in dependents)
								if (dependent.dependencyType == "parent-child")
									children.push(dependent);
							var replaced = false;
							for (index in 0...groups.length) {
								if (groups[index].issueId == summary.id) {
									groups[index] = {issueId: summary.id, items: children};
									replaced = true;
									break;
								}
							}
							if (!replaced) groups.push({issueId: summary.id, items: children});
					}
			}
		}
		switch invocation.output {
			case Json:
				writeJsonStdout(renderShowDependencyMapJson(groups, output.usesJsonEnvelope(), false));
			case Human:
				for (group in groups) {
					if (group.items.length == 0) {
						output.writeStdout('${group.issueId}: No children found\n');
					} else {
						output.writeStdout('↳ Children of ${group.issueId} (${group.items.length}):\n');
						for (child in group.items)
							output.writeStdout(invocation.showShort ? '  ${renderShowChildShort(child)}\n' : '${renderShowChildHuman(child)}\n');
						output.writeStdout("\n");
					}
				}
		}
		return 0;
	}

	static function renderShowChildHuman(child:IssueDependency):String {
		final typeBadge = child.status == "closed" ? "" : switch child.issueType {
			case "epic": "(EPIC) ";
			case "bug": "(BUG) ";
			case _: "";
		};
		return '  ↳ ${statusIcon(child.status)} ${child.id}: ${typeBadge}${child.title} P${child.priority}';
	}

	static function renderShowChildShort(child:IssueDependency):String {
		if (child.status == "closed")
			return '✓ ${child.id} P${child.priority} ${child.issueType} ${child.title}';
		final typeBadge = switch child.issueType {
			case "epic": "[epic] ";
			case "bug": "[bug] ";
			case _: "";
		};
		return '${statusIcon(child.status)} ${child.id} P${child.priority} ${typeBadge}${child.title}';
	}

	static function renderShowDependencyMapJson(groups:Array<ShowDependencyGroup>, envelope:Bool, emptyAsNull:Bool):String {
		final orderedGroups = groups.copy();
		orderedGroups.sort((left, right) -> compareIssueIds(left.issueId, right.issueId));
		final keys = ["schema_version"];
		for (group in orderedGroups)
			keys.push(group.issueId);
		keys.sort(compareIssueIds);
		final lines = ["{"];
		for (keyIndex in 0...keys.length) {
			final key = keys[keyIndex];
			final topSuffix = keyIndex == keys.length - 1 ? "" : ",";
			if (key == "schema_version") {
				lines.push('  "schema_version": 1${topSuffix}');
				continue;
			}
			var selected:Null<ShowDependencyGroup> = null;
			for (group in orderedGroups)
				if (group.issueId == key) {
					selected = group;
					break;
				}
			final children:Array<IssueDependency> = selected == null ? [] : selected.items;
			if (children.length == 0) {
				lines.push('  ${Json.stringify(key)}: ${emptyAsNull ? "null" : "[]"}${topSuffix}');
				continue;
			}
			lines.push('  ${Json.stringify(key)}: [');
			for (childIndex in 0...children.length) {
				final child = children[childIndex];
				final fields = renderIssueRecordFields(child, "      ", !envelope);
				fields.push('"dependency_type": ${Json.stringify(child.dependencyType)}');
				if (!envelope)
					fields.sort(compareJsonFields);
				lines.push("    {");
				for (fieldIndex in 0...fields.length) {
					final fieldSuffix = fieldIndex == fields.length - 1 ? "" : ",";
					lines.push('      ${fields[fieldIndex]}${fieldSuffix}');
				}
				lines.push(childIndex == children.length - 1 ? "    }" : "    },");
			}
			lines.push('  ]${topSuffix}');
		}
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	function runShowHuman(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.showCurrent && invocation.showIds.length > 0)
			return runModeAwareFailure(invocation.output, "--current cannot be combined with explicit issue IDs");
		final ids = invocation.showIds.copy();
		if (invocation.showCurrent) {
			final currentId = resolveCurrentIssueId(invocation, location, query);
			if (currentId == "")
				return runModeAwareFailure(invocation.output, "no current issue found (no in-progress, hooked, or recently touched issues)");
			ids.push(currentId);
		}
		if (ids.length == 0)
			return runModeAwareFailure(invocation.output, "at least one issue ID is required (use positional args, --id flag, or --current)");
		final request:IssueDetailsRequest = {
			includeDependents: true,
			includeComments: true,
			briefDependencies: false
		};
		final found = new Array<IssueDetails>();
		for (id in ids) {
			switch lookupIssueSummary(location, id, invocation.global, query) {
				case Failure(message):
					output.writeStderr('Error fetching ${id}: ${message}\n');
				case Success(IssueMissing):
					output.writeStderr('Issue ${id} not found\n');
				case Success(IssueFound(summary)):
					switch query.issueDetails(location.path, summary.id, request, invocation.global) {
						case Failure(message): output.writeStderr('Error fetching ${id}: ${message}\n');
						case Success(DetailsMissing): output.writeStderr('Issue ${id} not found\n');
						case Success(DetailsFound(details)): found.push(details);
					}
			}
		}
		for (index in 0...found.length) {
			if (index > 0)
				output.writeStdout("\n" + StringTools.rpad("", "─", 60) + "\n\n");
			output.writeStdout(renderIssueHuman(found[index], invocation.showLong));
		}
		return found.length == 0 ? 1 : 0;
	}

	function runShowShort(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.showCurrent && invocation.showIds.length > 0)
			return runModeAwareFailure(invocation.output, "--current cannot be combined with explicit issue IDs");
		final ids = invocation.showIds.copy();
		if (invocation.showCurrent) {
			final currentId = resolveCurrentIssueId(invocation, location, query);
			if (currentId == "")
				return runModeAwareFailure(invocation.output, "no current issue found (no in-progress, hooked, or recently touched issues)");
			ids.push(currentId);
		}
		if (ids.length == 0)
			return runModeAwareFailure(invocation.output, "at least one issue ID is required (use positional args, --id flag, or --current)");
		final found = new Array<IssueSummary>();
		for (id in ids) {
			switch lookupIssueSummary(location, id, invocation.global, query) {
				case Failure(message):
					output.writeStderr('Error fetching ${id}: ${message}\n');
				case Success(IssueMissing):
					output.writeStderr('Error fetching ${id}: no issue found matching "${id}"\n');
				case Success(IssueFound(summary)):
					found.push(summary);
			}
		}
		if (found.length == 0) {
			return switch invocation.output {
				case Human: 1;
				case Json: runModeAwareFailure(invocation.output, "no issues found matching the provided IDs");
			};
		}
		return switch invocation.output {
			case Human:
				for (summary in found)
					output.writeStdout(renderIssueShort(summary) + "\n");
				0;
			case Json:
				// Upstream checks --short before its JSON branch. Preserve the
				// resulting mixed output: compact rows, then the normal JSON error.
				for (summary in found)
					output.writeStdout(renderIssueShort(summary) + "\n");
				runModeAwareFailure(invocation.output, "no issues found matching the provided IDs");
		};
	}

	function runShowJson(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):Int {
		if (invocation.showCurrent && invocation.showIds.length > 0)
			return runModeAwareFailure(invocation.output, "--current cannot be combined with explicit issue IDs");
		final ids = invocation.showIds.copy();
		if (invocation.showCurrent) {
			final currentId = resolveCurrentIssueId(invocation, location, query);
			if (currentId == "")
				return runModeAwareFailure(invocation.output, "no current issue found (no in-progress, hooked, or recently touched issues)");
			ids.push(currentId);
		}
		if (ids.length == 0)
			return runModeAwareFailure(invocation.output, "at least one issue ID is required (use positional args, --id flag, or --current)");

		final found = new Array<IssueDetails>();
		final request:IssueDetailsRequest = {
			includeDependents: invocation.showIncludeDependents,
			includeComments: invocation.showIncludeComments,
			briefDependencies: invocation.showBriefDependencies
		};
		for (id in ids) {
			switch lookupIssueSummary(location, id, invocation.global, query) {
				case Failure(message):
					output.writeStderr('Error fetching ${id}: ${message}\n');
				case Success(IssueMissing):
					output.writeStderr('Error fetching ${id}: no issue found matching "${id}"\n');
				case Success(IssueFound(summary)):
					switch query.issueDetails(location.path, summary.id, request, invocation.global) {
						case Failure(message): output.writeStderr('Error fetching ${id}: ${message}\n');
						case Success(DetailsMissing): output.writeStderr('Error fetching ${id}: no issue found matching "${id}"\n');
						case Success(DetailsFound(details)): found.push(details);
					}
			}
		}
		if (found.length == 0)
			return runModeAwareFailure(invocation.output, "no issues found matching the provided IDs");
		writeJsonStdout(renderShowJson(found));
		return 0;
	}

	function lookupIssueSummary(location:WorkspaceLocation, id:String, global:Bool, query:IssueQueryPort):StoreResult<IssueLookup> {
		final exact = query.issueSummary(location.path, location.databaseName, id, global);
		return switch exact {
			case Success(IssueMissing):
				final prefixed = configuredPrefixCandidate(id, location.prefix);
				final normalized = prefixed == id ? exact : query.issueSummary(location.path, location.databaseName, prefixed, global);
				switch normalized {
					case Success(IssueMissing): resolveAbbreviatedIssue(location, id, prefixed, global, query);
					case Success(IssueFound(_)) | Failure(_): normalized;
				}
			case Success(IssueFound(_)) | Failure(_): exact;
		};
	}

	function resolveAbbreviatedIssue(location:WorkspaceLocation, input:String, normalized:String, global:Bool, query:IssueQueryPort):StoreResult<IssueLookup> {
		final prefix = normalizedPrefix(location.prefix);
		final hashPart = StringTools.startsWith(normalized, prefix) ? normalized.substr(prefix.length) : normalized;
		if (!isPartialIdHash(hashPart))
			return Success(IssueMissing);
		return switch query.searchIssueIds(location.path, location.databaseName, hashPart, global) {
			case Failure(message): Failure('failed to search issues: ${message}');
			case Success(ids):
				final matches = new Array<String>();
				var exactMatch = "";
				for (candidate in ids) {
					final candidateHash = StringTools.startsWith(candidate, prefix) ? candidate.substr(prefix.length) : candidate;
					if (candidate == input || candidateHash == hashPart)
						exactMatch = candidate;
					else if (StringTools.startsWith(candidateHash, hashPart))
						matches.push(candidate);
				}
				if (exactMatch != "") {
					query.issueSummary(location.path, location.databaseName, exactMatch, global);
				} else if (matches.length == 0) {
					Success(IssueMissing);
				} else {
					matches.sort(compareIssueIds);
					if (matches.length > 1)
						Failure('ambiguous issue ID: "${input}" matches ${matches.length} issues: [${matches.join(" ")}]\nUse more characters to disambiguate');
					else
						query.issueSummary(location.path, location.databaseName, matches[0], global);
				}
		};
	}

	static function compareIssueIds(left:String, right:String):Int {
		return left < right ? -1 : left == right ? 0 : 1;
	}

	static function isPartialIdHash(value:String):Bool {
		if (value == "" || value.indexOf(" ") >= 0)
			return false;
		for (index in 0...value.length) {
			final code = value.charCodeAt(index);
			final accepted = code >= 48 && code <= 57 || code >= 97 && code <= 122 || code >= 65 && code <= 90 || code == 45 || code == 46;
			if (!accepted)
				return false;
		}
		return true;
	}

	static function normalizedPrefix(prefix:String):String {
		return StringTools.endsWith(prefix, "-") ? prefix : prefix + "-";
	}

	static function configuredPrefixCandidate(id:String, prefix:String):String {
		return prefix == "" || id.indexOf("-") >= 0 ? id : normalizedPrefix(prefix) + id;
	}

	function resolveCurrentIssueId(invocation:Invocation, location:WorkspaceLocation, query:IssueQueryPort):String {
		final currentActor = actor.resolve(invocation.actor);
		for (status in [IssueStatus.InProgress, IssueStatus.OtherStatus("hooked")]) {
			switch query.assignedIssueId(location.path, location.databaseName, currentActor, status, invocation.global) {
				case Success(id) if (id != ""):
					return id;
				case Success(_) | Failure(_):
			}
		}
		return invocation.global ? "" : store.lastTouchedId(location.path);
	}

	static function renderIssueShort(issue:IssueSummary):String {
		return switch issue.status {
			case Open: renderOpenIssueShort("○", issue);
			case InProgress: renderOpenIssueShort("◐", issue);
			case Blocked: renderOpenIssueShort("●", issue);
			case Closed: '✓ ${issue.id} P${issue.priority} ${issueTypeWireValue(issue.issueType)} ${issue.title}';
			case Deferred: renderOpenIssueShort("❄", issue);
			case Pinned: renderOpenIssueShort("📌", issue);
			case OtherStatus(_): renderOpenIssueShort("◇", issue);
		};
	}

	static function renderOpenIssueShort(icon:String, issue:IssueSummary):String {
		final typeBadge = switch issue.issueType {
			case Epic: "[epic] ";
			case Bug: "[bug] ";
			case OtherType(_): "";
		};
		return '${icon} ${issue.id} P${issue.priority} ${typeBadge}${issue.title}';
	}

	function renderIssueHuman(issue:IssueDetails, longMode:Bool, mode:HumanShowMode = StandardShow):String {
		final typeBadge = switch issue.issueType {
			case "epic": " [EPIC]";
			case "bug": " [BUG]";
			case _: "";
		};
		final compactionMarker = switch issue.longFields.compactionLevel {
			case 1: " 🗜️";
			case 2: " 📦";
			case _: "";
		};
		var rendered = '${statusIcon(issue.status)} ${issue.id}${typeBadge} · ${issue.title}${compactionMarker}   [P${issue.priority} · ${issue.status.toUpperCase()}]\n';
		final metadata = new Array<String>();
		if (issue.createdBy != "")
			metadata.push('Owner: ${issue.createdBy}');
		if (issue.assignee != "")
			metadata.push('Assignee: ${issue.assignee}');
		metadata.push('Type: ${issue.issueType}');
		rendered += metadata.join(" · ") + "\n";
		final dates = ['Created: ${issue.createdAt.substr(0, 10)}'];
		if (issue.startedAt != "")
			dates.push('Started: ${issue.startedAt.substr(0, 10)}');
		dates.push('Updated: ${issue.updatedAt.substr(0, 10)}');
		if (issue.dueAt != "")
			dates.push('Due: ${issue.dueAt.substr(0, 10)}');
		if (issue.deferUntil != "")
			dates.push('Deferred: ${issue.deferUntil.substr(0, 10)}');
		rendered += dates.join(" · ") + "\n";
		if (issue.status == "closed" && issue.closeReason != "")
			rendered += 'Close reason: ${StringTools.trim(issue.closeReason)}\n';
		if (issue.externalRef != "")
			rendered += 'External: ${issue.externalRef}\n';
		if (issue.specId != "")
			rendered += 'Spec: ${issue.specId}\n';
		if (issue.longFields.ephemeral && issue.wispType != "")
			rendered += 'Wisp type: ${issue.wispType}\n';
		final savings = compactionSavingsLine(issue);
		if (savings != "")
			rendered += savings + "\n";
		if (issue.description != "" || mode == StandardShow) {
			rendered += "\nDESCRIPTION\n";
			rendered += issue.description == "" ? "  (none)\n" : output.renderMarkdown(issue.description) + "\n";
		}
		if (issue.design != "")
			rendered += "\nDESIGN\n" + output.renderMarkdown(issue.design) + "\n";
		if (issue.notes != "")
			rendered += "\nNOTES\n" + output.renderMarkdown(issue.notes) + "\n";
		if (issue.acceptanceCriteria != "")
			rendered += "\nACCEPTANCE CRITERIA\n" + output.renderMarkdown(issue.acceptanceCriteria) + "\n";
		if (issue.labels.length > 0)
			rendered += "\nLABELS: " + issue.labels.join(", ") + "\n";
		if (mode == StandardShow) {
			final metadataLines = issue.metadata.renderHumanLines();
			if (metadataLines.length > 0)
				rendered += "\nMETADATA\n" + metadataLines.join("\n") + "\n";
		}
		rendered += renderHumanDependencySections(issue);
		if (issue.comments.length > 0) {
			rendered += "\nCOMMENTS\n";
			for (comment in issue.comments) {
				rendered += '  ${formatHumanTime(comment.createdAt)} ${comment.author}\n';
				final body = trimTrailingNewlines(output.renderMarkdown(comment.text));
				for (line in body.split("\n"))
					rendered += '    ${line}\n';
			}
		}
		if (longMode)
			rendered += renderIssueLongExtras(issue);
		return rendered + "\n";
	}

	static function renderIssueLongExtras(issue:IssueDetails):String {
		final rare = issue.longFields;
		final details = new Array<String>();
		if (issue.closedAt != "")
			details.push('  Closed at: ${formatHumanTime(issue.closedAt)}');
		if (issue.closedBySession != "")
			details.push('  Closed by session: ${issue.closedBySession}');
		switch issue.estimatedMinutes {
			case IntAbsent:
			case IntPresent(value):
				details.push('  Estimated: ${value} minutes');
		}
		if (issue.sourceSystem != "")
			details.push('  Source system: ${issue.sourceSystem}');
		if (rare.sender != "")
			details.push('  Sender: ${rare.sender}');
		if (rare.ephemeral)
			details.push("  Ephemeral: yes");
		if (rare.pinned)
			details.push("  Pinned: yes");
		if (rare.template)
			details.push("  Template: yes");
		if (issue.moleculeType != "")
			details.push('  Mol type: ${issue.moleculeType}');
		if (rare.workType != "")
			details.push('  Work type: ${rare.workType}');
		final sections = new Array<String>();
		if (details.length > 0)
			sections.push("EXTENDED DETAILS\n" + details.join("\n"));
		if (rare.compactionLevel > 0) {
			final compaction = ['  Level: ${rare.compactionLevel}'];
			if (rare.compactedAt != "")
				compaction.push('  Compacted at: ${formatHumanTime(rare.compactedAt)}');
			if (rare.compactedAtCommit != "")
				compaction.push('  Compacted at commit: ${rare.compactedAtCommit}');
			if (rare.originalSize > 0)
				compaction.push('  Original size: ${rare.originalSize} bytes');
			sections.push("COMPACTION\n" + compaction.join("\n"));
		}
		final gate = new Array<String>();
		if (rare.awaitType != "")
			gate.push('  Await type: ${rare.awaitType}');
		if (rare.awaitId != "")
			gate.push('  Await ID: ${rare.awaitId}');
		if (rare.timeout != "")
			gate.push('  Timeout: ${rare.timeout}');
		if (rare.waiters.length > 0)
			gate.push('  Waiters: ${rare.waiters.join(", ")}');
		if (gate.length > 0)
			sections.push("GATE\n" + gate.join("\n"));
		final source = new Array<String>();
		if (rare.sourceFormula != "")
			source.push('  Formula: ${rare.sourceFormula}');
		if (rare.sourceLocation != "")
			source.push('  Location: ${rare.sourceLocation}');
		if (source.length > 0)
			sections.push("SOURCE TRACING\n" + source.join("\n"));
		if (rare.bondedFrom.length > 0) {
			final references = new Array<String>();
			for (reference in rare.bondedFrom)
				references.push('  ${reference.sourceId} (${reference.bondType})');
			sections.push("BONDED FROM\n" + references.join("\n"));
		}
		final event = new Array<String>();
		if (rare.eventKind != "")
			event.push('  Kind: ${rare.eventKind}');
		if (rare.actor != "")
			event.push('  Actor: ${rare.actor}');
		if (rare.target != "")
			event.push('  Target: ${rare.target}');
		if (rare.payload != "")
			event.push('  Payload: ${rare.payload}');
		if (event.length > 0)
			sections.push("EVENT\n" + event.join("\n"));
		return sections.length == 0 ? "" : "\n" + sections.join("\n\n") + "\n";
	}

	static function compactionSavingsLine(issue:IssueDetails):String {
		final original = issue.longFields.originalSize;
		if (issue.longFields.compactionLevel == 0 || original <= 0)
			return "";
		final current = haxe.io.Bytes.ofString(issue.description).length + haxe.io.Bytes.ofString(issue.design).length
			+ haxe.io.Bytes.ofString(issue.notes).length + haxe.io.Bytes.ofString(issue.acceptanceCriteria).length;
		final saved = original - current;
		if (saved <= 0)
			return "";
		final reduction = Math.round(saved / original * 100);
		return '📊 ${original} → ${current} bytes (${reduction}% reduction)';
	}

	static function renderHumanDependencySections(issue:IssueDetails):String {
		final related = new Map<String, IssueDependency>();
		var rendered = renderHumanDependencyDirection(issue.dependencies, true, related, false);
		rendered += renderHumanDependencyDirection(issue.dependents, false, related, issue.issueType == "epic");
		final relatedIds = [for (id in related.keys()) id];
		relatedIds.sort(compareIssueIds);
		if (relatedIds.length > 0) {
			rendered += "\nRELATED\n";
			for (id in relatedIds)
				rendered += renderHumanDependencyLine("↔", related.get(id));
		}
		return rendered;
	}

	static function renderHumanDependencyDirection(dependencies:Array<IssueDependency>, outgoing:Bool, related:Map<String, IssueDependency>, epic:Bool):String {
		final groups = new Array<HumanDependencyGroup>();
		for (dependency in dependencies) {
			final relation = humanDependencyRelation(dependency.dependencyType);
			if (relation.related) {
				related.set(dependency.id, dependency);
				continue;
			}
			var group:Null<HumanDependencyGroup> = null;
			for (candidate in groups) {
				if (candidate.relation.canonical == relation.canonical) {
					group = candidate;
					break;
				}
			}
			if (group == null) {
				group = {relation: relation, dependencies: []};
				groups.push(group);
			}
			group.dependencies.push(dependency);
		}
		groups.sort(compareHumanDependencyGroups);
		var rendered = "";
		for (group in groups) {
			final heading = outgoing ? group.relation.outgoingHeading : group.relation.incomingHeading;
			final glyph = outgoing ? group.relation.outgoingGlyph : group.relation.incomingGlyph;
			rendered += '\n${heading}\n';
			for (dependency in group.dependencies)
				rendered += renderHumanDependencyLine(glyph, dependency);
			if (!outgoing && epic && group.relation.canonical == "parent-child")
				rendered += renderEpicChildProgress(group.dependencies);
		}
		return rendered;
	}

	static function renderHumanDependencyLine(glyph:String, dependency:IssueDependency):String {
		final notableType = switch dependency.issueType {
			case "epic": "(EPIC) ";
			case "bug": "(BUG) ";
			case _: "";
		};
		return '  ${glyph} ${statusIcon(dependency.status)} ${dependency.id}: ${notableType}${dependency.title} P${dependency.priority}\n';
	}

	static function renderEpicChildProgress(children:Array<IssueDependency>):String {
		var closed = 0;
		for (child in children)
			if (child.status == "closed")
				closed++;
		final percentage = Std.int(closed * 100 / children.length);
		return
			closed == children.length ? '  ✓ ${closed}/${children.length} complete (${percentage}%) — eligible for close\n' : '  ◐ ${closed}/${children.length} complete (${percentage}%)\n';
	}

	static function compareHumanDependencyGroups(left:HumanDependencyGroup, right:HumanDependencyGroup):Int {
		if (left.relation.order != right.relation.order)
			return left.relation.order < right.relation.order ? -1 : 1;
		return compareIssueIds(left.relation.canonical, right.relation.canonical);
	}

	static function humanDependencyRelation(value:String):HumanDependencyRelation {
		return switch value {
			case "parent-child": dependencyRelation(value, "PARENT", "CHILDREN", "↑", "↳", 0);
			case "blocks": dependencyRelation(value, "DEPENDS ON", "BLOCKS", "→", "←", 1);
			case "conditional-blocks": dependencyRelation(value, "CONDITIONALLY DEPENDS ON", "CONDITIONALLY BLOCKS", "→", "←", 2);
			case "waits-for": dependencyRelation(value, "WAITS FOR", "AWAITED BY", "→", "←", 3);
			case "discovered-from": dependencyRelation(value, "DISCOVERED FROM", "DISCOVERED", "◊", "◊", 4);
			case "replies-to": dependencyRelation(value, "IN REPLY TO", "REPLIES", "→", "←", 5);
			case "duplicates": dependencyRelation(value, "DUPLICATE OF", "DUPLICATED BY", "→", "←", 6);
			case "supersedes": dependencyRelation(value, "SUPERSEDED BY", "SUPERSEDES", "→", "←", 7);
			case "authored-by": dependencyRelation(value, "AUTHORED BY", "AUTHORED", "→", "←", 8);
			case "assigned-to": dependencyRelation(value, "ASSIGNED TO", "ASSIGNED", "→", "←", 9);
			case "approved-by": dependencyRelation(value, "APPROVED BY", "APPROVED", "→", "←", 10);
			case "attests": dependencyRelation(value, "ATTESTS", "ATTESTED BY", "→", "←", 11);
			case "tracks": dependencyRelation(value, "TRACKS", "TRACKED BY", "→", "←", 12);
			case "until": dependencyRelation(value, "ACTIVE UNTIL", "KEEPS ACTIVE", "→", "←", 13);
			case "caused-by": dependencyRelation(value, "CAUSED BY", "CAUSED", "→", "←", 14);
			case "validates": dependencyRelation(value, "VALIDATES", "VALIDATED BY", "→", "←", 15);
			case "delegated-from": dependencyRelation(value, "DELEGATED FROM", "DELEGATED TO", "→", "←", 16);
			case "related" | "relates-to": {
					canonical: "related",
					outgoingHeading: "RELATED",
					incomingHeading: "RELATED",
					outgoingGlyph: "↔",
					incomingGlyph: "↔",
					order: 17,
					related: true
				};
			case _:
				final heading = value.toUpperCase();
				dependencyRelation(value, heading, heading + " (INBOUND)", "→", "←", 100);
		};
	}

	static function dependencyRelation(canonical:String, outgoingHeading:String, incomingHeading:String, outgoingGlyph:String, incomingGlyph:String,
			order:Int):HumanDependencyRelation {
		return {
			canonical: canonical,
			outgoingHeading: outgoingHeading,
			incomingHeading: incomingHeading,
			outgoingGlyph: outgoingGlyph,
			incomingGlyph: incomingGlyph,
			order: order,
			related: false
		};
	}

	static function formatHumanTime(value:String):String {
		return value.length < 16 ? value : value.substr(0, 10) + " " + value.substr(11, 5);
	}

	static function trimTrailingNewlines(value:String):String {
		var end = value.length;
		while (end > 0 && value.charAt(end - 1) == "\n")
			end--;
		return value.substr(0, end);
	}

	static function statusIcon(status:String):String {
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

	static function renderThreadJson(entries:Array<ThreadEntry>):String {
		final lines = ["["];
		for (index in 0...entries.length) {
			final fields = renderRawIssueFields(entries[index].issue);
			lines.push("  {");
			for (fieldIndex in 0...fields.length) {
				final suffix = fieldIndex == fields.length - 1 ? "" : ",";
				lines.push('    ${fields[fieldIndex]}${suffix}');
			}
			lines.push(index == entries.length - 1 ? "  }" : "  },");
		}
		lines.push("]");
		return lines.join("\n") + "\n";
	}

	static function renderRawIssuesJson(issues:Array<StaleIssue>):String {
		final lines = ["["];
		for (index in 0...issues.length) {
			final fields = renderRawIssueFields(issues[index]);
			lines.push("  {");
			for (fieldIndex in 0...fields.length) {
				final suffix = fieldIndex == fields.length - 1 ? "" : ",";
				lines.push('    ${fields[fieldIndex]}${suffix}');
			}
			lines.push(index == issues.length - 1 ? "  }" : "  },");
		}
		lines.push("]");
		return lines.join("\n") + "\n";
	}

	/** Renders the pinned generic Issue JSON used by `show --thread --json`. */
	static function renderRawIssueFields(issue:RawIssueRecord, sortMetadata:Bool = false, fieldIndent:String = "    "):Array<String> {
		final rare = issue.longFields;
		final fields = new Array<String>();
		fields.push('"id": ${Json.stringify(issue.id)}');
		fields.push('"title": ${Json.stringify(issue.title)}');
		if (issue.description != "")
			fields.push('"description": ${Json.stringify(issue.description)}');
		if (issue.design != "")
			fields.push('"design": ${Json.stringify(issue.design)}');
		if (issue.acceptanceCriteria != "")
			fields.push('"acceptance_criteria": ${Json.stringify(issue.acceptanceCriteria)}');
		if (issue.notes != "")
			fields.push('"notes": ${Json.stringify(issue.notes)}');
		if (issue.specId != "")
			fields.push('"spec_id": ${Json.stringify(issue.specId)}');
		if (issue.status != "")
			fields.push('"status": ${Json.stringify(issue.status)}');
		fields.push('"priority": ${issue.priority}');
		if (issue.issueType != "")
			fields.push('"issue_type": ${Json.stringify(issue.issueType)}');
		if (rare.isBlocked)
			fields.push('"is_blocked": true');
		if (issue.assignee != "")
			fields.push('"assignee": ${Json.stringify(issue.assignee)}');
		if (issue.owner != "")
			fields.push('"owner": ${Json.stringify(issue.owner)}');
		switch issue.estimatedMinutes {
			case IntAbsent:
			case IntPresent(value):
				fields.push('"estimated_minutes": ${value}');
		}
		fields.push('"created_at": ${Json.stringify(issue.createdAt)}');
		if (issue.createdBy != "")
			fields.push('"created_by": ${Json.stringify(issue.createdBy)}');
		fields.push('"updated_at": ${Json.stringify(issue.updatedAt)}');
		if (issue.startedAt != "")
			fields.push('"started_at": ${Json.stringify(issue.startedAt)}');
		if (issue.closedAt != "")
			fields.push('"closed_at": ${Json.stringify(issue.closedAt)}');
		if (issue.closeReason != "")
			fields.push('"close_reason": ${Json.stringify(issue.closeReason)}');
		if (issue.closedBySession != "")
			fields.push('"closed_by_session": ${Json.stringify(issue.closedBySession)}');
		if (rare.leaseExpiresAt != "")
			fields.push('"lease_expires_at": ${Json.stringify(rare.leaseExpiresAt)}');
		if (rare.heartbeatAt != "")
			fields.push('"heartbeat_at": ${Json.stringify(rare.heartbeatAt)}');
		if (rare.leaseGrantedNode != "")
			fields.push('"lease_granted_node": ${Json.stringify(rare.leaseGrantedNode)}');
		if (issue.dueAt != "")
			fields.push('"due_at": ${Json.stringify(issue.dueAt)}');
		if (issue.deferUntil != "")
			fields.push('"defer_until": ${Json.stringify(issue.deferUntil)}');
		if (issue.externalRef != "")
			fields.push('"external_ref": ${Json.stringify(issue.externalRef)}');
		if (issue.sourceSystem != "")
			fields.push('"source_system": ${Json.stringify(issue.sourceSystem)}');
		if (!issue.metadata.isAbsent() && issue.metadata.topLevelFieldCount() > 0) {
			final metadata = sortMetadata ? issue.metadata.renderSortedIndented(fieldIndent, "  ") : issue.metadata.renderIndented(fieldIndent, "  ");
			fields.push('"metadata": ${metadata}');
		}
		if (rare.compactionLevel != 0)
			fields.push('"compaction_level": ${rare.compactionLevel}');
		if (rare.compactedAt != "")
			fields.push('"compacted_at": ${Json.stringify(rare.compactedAt)}');
		if (rare.compactedAtCommit != "")
			fields.push('"compacted_at_commit": ${Json.stringify(rare.compactedAtCommit)}');
		if (rare.originalSize != 0)
			fields.push('"original_size": ${rare.originalSize}');
		if (rare.sender != "")
			fields.push('"sender": ${Json.stringify(rare.sender)}');
		if (rare.ephemeral)
			fields.push('"ephemeral": true');
		if (rare.noHistory)
			fields.push('"no_history": true');
		if (issue.wispType != "")
			fields.push('"wisp_type": ${Json.stringify(issue.wispType)}');
		if (rare.storageClass != "")
			fields.push('"storage_class": ${Json.stringify(rare.storageClass)}');
		if (rare.pinned)
			fields.push('"pinned": true');
		if (rare.template)
			fields.push('"is_template": true');
		if (rare.bondedFrom.length > 0)
			fields.push(renderRawBondedFrom(rare.bondedFrom, fieldIndent));
		if (rare.awaitType != "")
			fields.push('"await_type": ${Json.stringify(rare.awaitType)}');
		if (rare.awaitId != "")
			fields.push('"await_id": ${Json.stringify(rare.awaitId)}');
		if (rare.timeoutNanos.wireValue() != "0")
			fields.push('"timeout": ${rare.timeoutNanos.wireValue()}');
		if (rare.waiters.length > 0)
			fields.push(renderRawStringArray("waiters", rare.waiters, fieldIndent));
		if (rare.sourceFormula != "")
			fields.push('"source_formula": ${Json.stringify(rare.sourceFormula)}');
		if (rare.sourceLocation != "")
			fields.push('"source_location": ${Json.stringify(rare.sourceLocation)}');
		if (issue.moleculeType != "")
			fields.push('"mol_type": ${Json.stringify(issue.moleculeType)}');
		if (rare.workType != "")
			fields.push('"work_type": ${Json.stringify(rare.workType)}');
		if (rare.eventKind != "")
			fields.push('"event_kind": ${Json.stringify(rare.eventKind)}');
		if (rare.actor != "")
			fields.push('"actor": ${Json.stringify(rare.actor)}');
		if (rare.target != "")
			fields.push('"target": ${Json.stringify(rare.target)}');
		if (rare.payload != "")
			fields.push('"payload": ${Json.stringify(rare.payload)}');
		return fields;
	}

	static function renderRawBondedFrom(references:Array<beadshx.store.IssueBondReference>, fieldIndent:String):String {
		final nestedIndent = fieldIndent + "  ";
		final valueIndent = nestedIndent + "  ";
		final lines = ['"bonded_from": ['];
		for (index in 0...references.length) {
			final reference = references[index];
			lines.push('${nestedIndent}{');
			lines.push('${valueIndent}"source_id": ${Json.stringify(reference.sourceId)},');
			final bondTypeSuffix = reference.bondPoint == "" ? "" : ",";
			lines.push('${valueIndent}"bond_type": ${Json.stringify(reference.bondType)}${bondTypeSuffix}');
			if (reference.bondPoint != "")
				lines.push('${valueIndent}"bond_point": ${Json.stringify(reference.bondPoint)}');
			lines.push(index == references.length - 1 ? '${nestedIndent}}' : '${nestedIndent}},');
		}
		lines.push('${fieldIndent}]');
		return lines.join("\n");
	}

	static function renderRawStringArray(name:String, values:Array<String>, fieldIndent:String):String {
		final lines = ['${Json.stringify(name)}: ['];
		for (index in 0...values.length) {
			final suffix = index == values.length - 1 ? "" : ",";
			lines.push('${fieldIndent}  ${Json.stringify(values[index])}${suffix}');
		}
		lines.push('${fieldIndent}]');
		return lines.join("\n");
	}

	/** Renders the pinned Beads field order and zero-value omission rules. */
	static function renderShowJson(issues:Array<IssueDetails>):String {
		final lines = ["["];
		for (index in 0...issues.length) {
			final issue = issues[index];
			final fields = renderIssueRecordFields(issue, "    ");
			if (issue.labels.length > 0) {
				final labelLines = ['"labels": ['];
				for (labelIndex in 0...issue.labels.length) {
					final suffix = labelIndex == issue.labels.length - 1 ? "" : ",";
					labelLines.push('      ${Json.stringify(issue.labels[labelIndex])}${suffix}');
				}
				labelLines.push("    ]");
				fields.push(labelLines.join("\n"));
			}
			if (issue.dependencies.length > 0)
				fields.push(renderIssueRelations("dependencies", issue.dependencies));
			if (issue.dependents.length > 0)
				fields.push(renderIssueRelations("dependents", issue.dependents));
			if (issue.comments.length > 0)
				fields.push(renderIssueComments(issue.comments));
			if (issue.parent != "")
				fields.push('"parent": ${Json.stringify(issue.parent)}');
			fields.push('"dependent_count": ${issue.dependentCount}');
			fields.push('"dependency_count": ${issue.dependencyCount}');
			fields.push('"comment_count": ${issue.commentCount}');
			if (issue.commentsOmitted)
				fields.push('"comments_omitted": true');
			switch issue.epicProgress {
				case NoEpicProgress:
				case HasEpicProgress(totalChildren, closedChildren, closeable):
					fields.push('"epic_total_children": ${totalChildren}');
					fields.push('"epic_closed_children": ${closedChildren}');
					fields.push('"epic_closeable": ${closeable}');
			}
			fields.push('"revision": ${issue.revision.wireValue()}');
			lines.push("  {");
			for (fieldIndex in 0...fields.length) {
				final suffix = fieldIndex == fields.length - 1 ? "" : ",";
				lines.push('    ${fields[fieldIndex]}${suffix}');
			}
			final suffix = index == issues.length - 1 ? "" : ",";
			lines.push('  }${suffix}');
		}
		lines.push("]");
		return lines.join("\n") + "\n";
	}

	static function renderIssueRecordFields(issue:IssueRecord, fieldIndent:String, sortMetadata:Bool = false):Array<String> {
		final fields = new Array<String>();
		fields.push('"id": ${Json.stringify(issue.id)}');
		fields.push('"title": ${Json.stringify(issue.title)}');
		if (issue.description != "")
			fields.push('"description": ${Json.stringify(issue.description)}');
		if (issue.design != "")
			fields.push('"design": ${Json.stringify(issue.design)}');
		if (issue.acceptanceCriteria != "")
			fields.push('"acceptance_criteria": ${Json.stringify(issue.acceptanceCriteria)}');
		if (issue.notes != "")
			fields.push('"notes": ${Json.stringify(issue.notes)}');
		if (issue.specId != "")
			fields.push('"spec_id": ${Json.stringify(issue.specId)}');
		if (issue.status != "")
			fields.push('"status": ${Json.stringify(issue.status)}');
		fields.push('"priority": ${issue.priority}');
		if (issue.issueType != "")
			fields.push('"issue_type": ${Json.stringify(issue.issueType)}');
		if (issue.assignee != "")
			fields.push('"assignee": ${Json.stringify(issue.assignee)}');
		if (issue.owner != "")
			fields.push('"owner": ${Json.stringify(issue.owner)}');
		switch issue.estimatedMinutes {
			case IntAbsent:
			case IntPresent(value):
				fields.push('"estimated_minutes": ${value}');
		}
		fields.push('"created_at": ${Json.stringify(issue.createdAt)}');
		if (issue.createdBy != "")
			fields.push('"created_by": ${Json.stringify(issue.createdBy)}');
		fields.push('"updated_at": ${Json.stringify(issue.updatedAt)}');
		if (issue.startedAt != "")
			fields.push('"started_at": ${Json.stringify(issue.startedAt)}');
		if (issue.closedAt != "")
			fields.push('"closed_at": ${Json.stringify(issue.closedAt)}');
		if (issue.closeReason != "")
			fields.push('"close_reason": ${Json.stringify(issue.closeReason)}');
		if (issue.closedBySession != "")
			fields.push('"closed_by_session": ${Json.stringify(issue.closedBySession)}');
		if (issue.dueAt != "")
			fields.push('"due_at": ${Json.stringify(issue.dueAt)}');
		if (issue.deferUntil != "")
			fields.push('"defer_until": ${Json.stringify(issue.deferUntil)}');
		if (issue.externalRef != "")
			fields.push('"external_ref": ${Json.stringify(issue.externalRef)}');
		if (issue.sourceSystem != "")
			fields.push('"source_system": ${Json.stringify(issue.sourceSystem)}');
		if (!issue.metadata.isAbsent() && issue.metadata.topLevelFieldCount() > 0) {
			final metadata = sortMetadata ? issue.metadata.renderSortedIndented(fieldIndent, "  ") : issue.metadata.renderIndented(fieldIndent, "  ");
			fields.push('"metadata": ${metadata}');
		}
		if (issue.wispType != "")
			fields.push('"wisp_type": ${Json.stringify(issue.wispType)}');
		if (issue.moleculeType != "")
			fields.push('"mol_type": ${Json.stringify(issue.moleculeType)}');
		return fields;
	}

	static function renderIssueRelations(fieldName:String, relations:Array<IssueDependency>):String {
		final lines = ['${Json.stringify(fieldName)}: ['];
		for (index in 0...relations.length) {
			final dependency = relations[index];
			final fields = renderIssueRecordFields(dependency, "        ");
			fields.push('"dependency_type": ${Json.stringify(dependency.dependencyType)}');
			lines.push("      {");
			for (fieldIndex in 0...fields.length) {
				final suffix = fieldIndex == fields.length - 1 ? "" : ",";
				lines.push('        ${fields[fieldIndex]}${suffix}');
			}
			final suffix = index == relations.length - 1 ? "" : ",";
			lines.push('      }${suffix}');
		}
		lines.push("    ]");
		return lines.join("\n");
	}

	static function renderIssueComments(comments:Array<IssueComment>):String {
		final lines = ['"comments": ['];
		for (index in 0...comments.length) {
			final comment = comments[index];
			lines.push("      {");
			lines.push('        "id": ${Json.stringify(comment.id)},');
			lines.push('        "issue_id": ${Json.stringify(comment.issueId)},');
			lines.push('        "author": ${Json.stringify(comment.author)},');
			lines.push('        "text": ${Json.stringify(comment.text)},');
			lines.push('        "created_at": ${Json.stringify(comment.createdAt)}');
			final suffix = index == comments.length - 1 ? "" : ",";
			lines.push('      }${suffix}');
		}
		lines.push("    ]");
		return lines.join("\n");
	}

	static function issueTypeWireValue(issueType:IssueType):String {
		return switch issueType {
			case Epic: "epic";
			case Bug: "bug";
			case OtherType(value): value;
		};
	}

	static function hasSelectedDatabase(location:WorkspaceLocation):Bool {
		return !location.databaseMissing || location.databaseName != "";
	}

	static function selectedDatabaseName(invocation:Invocation, location:WorkspaceLocation):String {
		return invocation.databaseName == "" ? location.databaseName : invocation.databaseName;
	}

	function closeIssueQuery(query:IssueQueryPort, operationResult:Int):Int {
		return switch query.close() {
			case Success(_): operationResult;
			case Failure(message):
				if (operationResult == 0) runStoreFailure('closing query session: ${message}'); else {
					output.writeStderr('Error: closing query session: ${message}\n');
					operationResult;
				}
		};
	}

	function renderWhereHuman(location:WorkspaceLocation):String {
		var rendered = location.path + "\n";
		if (location.redirectedFrom != "")
			rendered += '  (via redirect from ${location.redirectedFrom})\n';
		if (location.prefix != "")
			rendered += '  prefix: ${location.prefix}\n';
		if (location.databasePath != "")
			rendered += '  database: ${location.databasePath}\n';
		return rendered;
	}

	function renderWhereJson(location:WorkspaceLocation):String {
		final lines = ["{"];
		if (location.databasePath != "")
			lines.push('  "database_path": ${Json.stringify(location.databasePath)},');
		lines.push('  "path": ${Json.stringify(location.path)},');
		if (location.prefix != "")
			lines.push('  "prefix": ${Json.stringify(location.prefix)},');
		if (location.redirectedFrom != "")
			lines.push('  "redirected_from": ${Json.stringify(location.redirectedFrom)},');
		lines.push('  "schema_version": 1');
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	function runDatabaseNotFound():Int {
		output.writeStderr("Error: no beads database found\n");
		output.writeStderr("Hint: run 'bd where' to inspect the resolved workspace, or 'bd init' to create a new database\n");
		output.writeStderr("      or set BEADS_DIR to point to your .beads directory\n");
		return 1;
	}

	function runStoreFailure(message:String):Int {
		output.writeStderr('Error: ${message}\n');
		return 1;
	}

	function validateDatabaseSelection(invocation:Invocation, location:WorkspaceLocation):DatabaseSelectionValidation {
		var selectedName = location.databaseName;
		if (invocation.databaseName != "") {
			if (selectedName != "" && selectedName != invocation.databaseName)
				return PlainFailure('conflicting database selection: --db="${selectedName}" vs --database="${invocation.databaseName}"');
			selectedName = invocation.databaseName;
		}
		if (selectedName == "")
			return Accepted;
		if (location.proxiedServer)
			return Accepted;
		return ModeAwareFailure("--database (or a --db value naming a database) is only supported in proxied-server mode");
	}

	function runModeAwareFailure(mode:OutputMode, message:String):Int {
		switch mode {
			case Human:
				output.writeStderr('Error: ${message}\n');
			case Json:
				writeJsonStdout('{\n  "error": ${Json.stringify(message)},\n  "schema_version": 1\n}\n');
		}
		return 1;
	}

	function renderInfoHuman(snapshot:InfoSnapshot, includeSchema:Bool):String {
		var rendered = "\nBeads Database Information\n" + "===========================\n" + 'Database: ${snapshot.databasePath}\n'
			+ 'Mode: ${snapshot.mode}\n' + '\nIssue Count: ${snapshot.issueCount}\n';
		if (includeSchema) {
			rendered += "\nSchema Information:\n";
			rendered += "  Tables: [issues dependencies labels config metadata]\n";
			rendered += '  Schema Version: ${snapshot.schemaVersion}\n';
			final detectedPrefix = extractPrefix(snapshot.sampleIssueIds);
			if (detectedPrefix != "")
				rendered += '  Detected Prefix: ${detectedPrefix}\n';
			if (snapshot.sampleIssueIds.length > 0)
				rendered += '  Sample Issues: [${snapshot.sampleIssueIds.join(" ")}]\n';
		}
		return rendered + "\n";
	}

	function renderInfoJson(snapshot:InfoSnapshot, includeSchema:Bool):String {
		final lines = new Array<String>();
		lines.push("{");
		if (snapshot.config.length > 0) {
			lines.push('  "config": {');
			for (index in 0...snapshot.config.length) {
				final entry = snapshot.config[index];
				final suffix = index + 1 == snapshot.config.length ? "" : ",";
				lines.push('    ${Json.stringify(entry.key)}: ${Json.stringify(entry.value)}${suffix}');
			}
			lines.push("  },");
		}
		lines.push('  "database_path": ${Json.stringify(snapshot.databasePath)},');
		lines.push('  "issue_count": ${snapshot.issueCount},');
		lines.push('  "mode": ${Json.stringify(snapshot.mode)},');
		if (includeSchema) {
			lines.push('  "schema": {');
			lines.push('    "config": {');
			if (snapshot.issuePrefix != "")
				lines.push('      "issue_prefix": ${Json.stringify(snapshot.issuePrefix)}');
			lines.push("    },");
			lines.push('    "detected_prefix": ${Json.stringify(extractPrefix(snapshot.sampleIssueIds))},');
			lines.push('    "sample_issue_ids": [');
			for (index in 0...snapshot.sampleIssueIds.length) {
				final suffix = index + 1 == snapshot.sampleIssueIds.length ? "" : ",";
				lines.push('      ${Json.stringify(snapshot.sampleIssueIds[index])}${suffix}');
			}
			lines.push("    ],");
			lines.push('    "schema_version": ${Json.stringify(snapshot.schemaVersion)},');
			lines.push('    "tables": [');
			for (index in 0...schemaTables.length) {
				final suffix = index + 1 == schemaTables.length ? "" : ",";
				lines.push('      ${Json.stringify(schemaTables[index])}${suffix}');
			}
			lines.push("    ]");
			lines.push("  },");
		}
		lines.push('  "schema_version": 1');
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	function extractPrefix(issueIds:Array<String>):String {
		if (issueIds.length == 0)
			return "";
		final issueId = issueIds[0];
		final lastHyphen = issueId.lastIndexOf("-");
		if (lastHyphen <= 0)
			return "";
		final suffix = issueId.substr(lastHyphen + 1);
		final numericPart = suffix.split(".")[0];
		if (Std.parseInt(numericPart) != null)
			return issueId.substr(0, lastHyphen);
		return issueId.split("-")[0];
	}

	static final schemaTables = ["issues", "dependencies", "labels", "config", "metadata"];

	function renderPing(mode:OutputMode, snapshot:PingSnapshot):Void {
		switch mode {
			case Human:
				output.writeStdout('✓ bd ping: ok (${snapshot.totalMs}ms)\n');
			case Json:
				final document:PingDocument = {
					schema_version: 1,
					status: "ok",
					resolve_ms: snapshot.resolveMs,
					store_ms: snapshot.storeMs,
					query_ms: snapshot.queryMs,
					total_ms: snapshot.totalMs
				};
				writeJsonStdout(Json.stringify(document, null, "  ") + "\n");
		}
	}

	function renderStatus(mode:OutputMode, snapshot:StatusSnapshot):Void {
		switch mode {
			case Json:
				if (!snapshot.blockedAvailable) {
					final summary:SkippedStatusSummaryDocument = {
						total_issues: snapshot.totalIssues,
						open_issues: snapshot.openIssues,
						in_progress_issues: snapshot.inProgressIssues,
						closed_issues: snapshot.closedIssues,
						blocked_issues: null,
						deferred_issues: snapshot.deferredIssues,
						ready_issues: null,
						pinned_issues: snapshot.pinnedIssues,
						epics_eligible_for_closure: snapshot.epicsEligibleForClosure,
						average_lead_time_hours: snapshot.averageLeadTime
					};
					final document:SkippedStatusDocument = {
						schema_version: 1,
						summary: summary,
						blocked_count_skipped: true
					};
					writeJsonStdout(Json.stringify(document, null, "  ") + "\n");
				} else {
					final summary:StatusSummaryDocument = {
						total_issues: snapshot.totalIssues,
						open_issues: snapshot.openIssues,
						in_progress_issues: snapshot.inProgressIssues,
						closed_issues: snapshot.closedIssues,
						blocked_issues: snapshot.blockedIssues,
						deferred_issues: snapshot.deferredIssues,
						ready_issues: snapshot.readyIssues,
						pinned_issues: snapshot.pinnedIssues,
						epics_eligible_for_closure: snapshot.epicsEligibleForClosure,
						average_lead_time_hours: snapshot.averageLeadTime
					};
					final document:StatusDocument = {schema_version: 1, summary: summary};
					writeJsonStdout(Json.stringify(document, null, "  ") + "\n");
				}
			case Human:
				output.writeStdout(renderStatusHuman(snapshot));
		}
	}

	function renderStatusHuman(snapshot:StatusSnapshot):String {
		final lines = [
			"",
			"📊 Issue Database Status",
			"",
			"Summary:",
			'  Total Issues:           ${snapshot.totalIssues}',
			'  Open:                   ${snapshot.openIssues}',
			'  In Progress:            ${snapshot.inProgressIssues}',
			'  Blocked:                ${formatCount(snapshot.blockedAvailable, snapshot.blockedIssues)}',
			'  Closed:                 ${snapshot.closedIssues}',
			'  Ready to Work:          ${formatCount(snapshot.readyAvailable, snapshot.readyIssues)}'
		];
		if (snapshot.pinnedIssues > 0 || snapshot.epicsEligibleForClosure > 0 || snapshot.averageLeadTime > 0) {
			lines.push("");
			lines.push("Extended:");
			if (snapshot.pinnedIssues > 0)
				lines.push('  Pinned:                 ${snapshot.pinnedIssues}');
			if (snapshot.epicsEligibleForClosure > 0)
				lines.push('  Epics Ready to Close:   ${snapshot.epicsEligibleForClosure}');
			if (snapshot.averageLeadTime > 0)
				lines.push('  Avg Lead Time:          ${snapshot.averageLeadTime} hours');
		}
		lines.push("");
		lines.push("For more details, use 'bd list' to see individual issues.");
		lines.push("");
		return lines.join("\n") + "\n";
	}

	function formatCount(available:Bool, value:Int):String {
		return available ? Std.string(value) : "(skipped)";
	}

	function rootHelp():String {
		return "Issues chained together like beads. A lightweight issue tracker with first-class dependency support.\n\n"
			+ "Usage:\n  bdhx [flags]\n  bdhx [command]\n\n"
			+ "Read-only commands:\n"
			+ "  children          List child beads of a parent\n"
			+ "  count             Count issues matching filters\n"
			+ "  dep               Inspect dependency edges\n"
			+ "  info              Show database information\n"
			+ "  list              List issues\n"
			+ "  orphans           Identify orphaned issues (referenced in commits but still open)\n"
			+ "  ping              Check database connectivity\n"
			+ "  ready             Show ready work (open, no active blockers)\n"
			+ "  query             Query issues using a simple query language\n"
			+ "  search            Search issues by text query\n"
			+ "  show              Show issue details (compact mode available)\n"
			+ "  stale             Show stale issues (not updated recently)\n"
			+ "  status            Show issue database overview and statistics\n"
			+ "  version           Print version information\n"
			+ "  where             Show active beads location\n\n"
			+ "Flags:\n"
			+ "      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)\n"
			+ "      --cpu-profile               Generate CPU profile for performance analysis\n"
			+
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)\n"
			+
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)\n"
			+ "  -C, --directory string          Change to this directory before running the command (like git -C)\n"
			+
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit\n"
			+ "      --global                    Use the global shared-server database (beads_global)\n"
			+ "  -h, --help                      help for bdhx\n"
			+ "      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)\n"
			+ "      --json                      Output in JSON format\n"
			+ "      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)\n"
			+ "      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)\n"
			+ "  -q, --quiet                     Suppress non-essential output (errors only)\n"
			+ "      --readonly                  Read-only mode: block write operations (for worker sandboxes)\n"
			+ "      --sandbox                   Sandbox mode: disables Dolt auto-push\n"
			+ "  -v, --verbose                   Enable verbose/debug output\n"
			+ "  -V, --version                   Print version information\n";
	}

	function commandHelp(command:Command):String {
		return switch command {
			case RootHelp: rootHelp();
			case Version: basicCommandHelp("Print version information", "version", "");
			case Where:
				basicCommandHelp("Show the active Beads workspace and database paths.", "where", "");
			case Ping:
				basicCommandHelp("Check that BeadsHX can open and query the active database.", "ping", "");
			case Info:
				basicCommandHelp("Show information about the active database.", "info",
					"      --schema      Include schema information in output\n" + "      --whats-new   Show agent-relevant changes from recent versions\n");
			case Status:
				"Show a summary of issue counts and ready work.\n\n"
				+ "Usage:\n  bdhx status [flags]\n\nAliases:\n  status, stats\n\nFlags:\n"
				+ "      --all           Show all issues (default behavior)\n"
				+ "      --assigned      Show issues assigned to the selected actor\n"
				+ "  -h, --help          help for status\n"
				+ "      --no-activity   Skip activity output\n"
				+ "      --no-blocked    Skip blocked and ready counts\n\n"
				+ supportedGlobalFlags();
			case Count: countHelp();
			case Ready: readyHelp();
			case Search: searchHelp();
			case Query: queryHelp();
			case Stale: staleHelp();
			case Orphans: orphansHelp();
			case Children: childrenHelp();
			case DepList: depListHelp();
			case List: listHelp();
			case Show: showHelp();
		};
	}

	function depListHelp():String {
		return "List dependencies for one or more issues.\n\n"
			+ "Usage:\n  bdhx dep list [issue-id...] [flags]\n\n"
			+ "Flags:\n  -h, --help               help for list\n"
			+ "  -t, --type string        Filter by dependency type\n"
			+ "      --direction string   Dependency direction (down only in this read-only slice) (default \"down\")\n\n"
			+ supportedGlobalFlags();
	}

	function childrenHelp():String {
		return [
			"List all beads that are children of the specified parent bead.",
			"",
			"This is a convenience alias for 'bd list --parent <id> --status all'.",
			"Unlike plain 'bd list', children includes closed issues by default,",
			"since the primary use case is inspecting all work under a parent.",
			"",
			"Examples:",
			"  bd children hq-abc123        # List all children of hq-abc123",
			"  bd children hq-abc123 --json # List children in JSON format",
			"  bd children hq-abc123 --pretty # Show children in tree format",
			"",
			"Usage:",
			"  bd children <parent-id> [flags]",
			"",
			"Flags:",
			"  -h, --help     help for children",
			"      --pretty   Show children in tree format",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function orphansHelp():String {
		return [
			"Identify orphaned issues - issues that are referenced in commit messages but remain open or in_progress in the database.",
			"",
			"This helps identify work that has been implemented but not formally closed.",
			"",
			"Examples:",
			"  bd orphans              # Show orphaned issues",
			"  bd orphans --json       # Machine-readable output",
			"  bd orphans --details    # Show full commit information",
			"  bd orphans --fix        # Close orphaned issues with confirmation",
			"  bd orphans --label theme:personal             # Only orphans with this label",
			"  bd orphans --label-any theme:personal,theme:ventures  # Orphans with either label",
			"",
			"Usage:",
			"  bd orphans [flags]",
			"",
			"Flags:",
			"      --details             Show full commit information",
			"  -f, --fix                 Close orphaned issues with confirmation",
			"  -h, --help                help for orphans",
			"  -l, --label strings       Filter by labels (AND: must have ALL). Can combine with --label-any",
			"      --label-any strings   Filter by labels (OR: must have AT LEAST ONE). Can combine with --label",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function staleHelp():String {
		return [
			"Show issues that haven't been updated recently and may need attention.",
			"This helps identify:",
			"- In-progress issues with no recent activity (may be abandoned)",
			"- Open issues that have been forgotten",
			"- Issues that might be outdated or no longer relevant",
			"",
			"Usage:",
			"  bd stale [flags]",
			"",
			"Flags:",
			"  -d, --days int        Issues not updated in this many days (default 30)",
			"  -h, --help            help for stale",
			"  -n, --limit int       Maximum issues to show (default 50)",
			"  -s, --status string   Filter by status (open|in_progress|blocked|deferred)",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function countHelp():String {
		return [
			"Count issues matching the specified filters.",
			"",
			"By default, returns the total count of issues matching the filters.",
			"Use --by-* flags to group counts by different attributes.",
			"",
			"Examples:",
			"  bd count                          # Count all issues",
			"  bd count --status open            # Count open issues",
			"  bd count --by-status              # Group count by status",
			"  bd count --by-priority            # Group count by priority",
			"  bd count --by-type                # Group count by issue type",
			"  bd count --by-assignee            # Group count by assignee",
			"  bd count --by-label               # Group count by label",
			"  bd count --assignee alice --by-status  # Count alice's issues by status",
			"  bd count --include-infra          # Count issues + wisps tier (matches 'bd list --include-infra --all' cardinality)",
			"",
			"",
			"Usage:",
			"  bd count [flags]",
			"",
			"Flags:",
			"  -a, --assignee string         Filter by assignee",
			"      --by-assignee             Group count by assignee",
			"      --by-label                Group count by label",
			"      --by-priority             Group count by priority",
			"      --by-status               Group count by status",
			"      --by-type                 Group count by issue type",
			"      --closed-after string     Filter issues closed after date (YYYY-MM-DD or RFC3339)",
			"      --closed-before string    Filter issues closed before date (YYYY-MM-DD or RFC3339)",
			"      --created-after string    Filter issues created after date (YYYY-MM-DD or RFC3339)",
			"      --created-before string   Filter issues created before date (YYYY-MM-DD or RFC3339)",
			"      --desc-contains string    Filter by description substring",
			"      --empty-description       Filter issues with empty description",
			"  -h, --help                    help for count",
			"      --id string               Filter by specific issue IDs (comma-separated)",
			"      --include-infra           Include infrastructure beads and the wisps tier (matches 'bd list --include-infra --all' cardinality)",
			"  -l, --label strings           Filter by labels (AND: must have ALL)",
			"      --label-any strings       Filter by labels (OR: must have AT LEAST ONE)",
			"      --no-assignee             Filter issues with no assignee",
			"      --no-labels               Filter issues with no labels",
			"      --notes-contains string   Filter by notes substring",
			"  -p, --priority int            Filter by priority (0-4: 0=critical, 1=high, 2=medium, 3=low, 4=backlog)",
			"      --priority-max int        Filter by maximum priority (inclusive)",
			"      --priority-min int        Filter by minimum priority (inclusive)",
			"  -s, --status string           Filter by stored status (open, in_progress, blocked, deferred, closed). Note: dependency-blocked issues use 'bd blocked'",
			"      --title string            Filter by title text (case-insensitive substring match)",
			"      --title-contains string   Filter by title substring",
			"  -t, --type string             Filter by type (bug, feature, task, epic, chore, decision, merge-request, molecule, gate)",
			"      --updated-after string    Filter issues updated after date (YYYY-MM-DD or RFC3339)",
			"      --updated-before string   Filter issues updated before date (YYYY-MM-DD or RFC3339)",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function readyHelp():String {
		return [
			"Show ready work (open issues with no active blockers).",
			"",
			"Excludes in_progress, blocked, deferred, and hooked issues. This uses the",
			"GetReadyWork API which applies blocker-aware semantics to find truly claimable work.",
			"",
			"Note: 'bd list --ready' uses the same blocker-aware ready-work semantics.",
			"",
			"Use --mol to filter to a specific molecule's steps:",
			"  bd ready --mol bd-patrol   # Show ready steps within molecule",
			"",
			"Use --gated to find molecules ready for gate-resume dispatch:",
			"  bd ready --gated           # Find molecules where a gate closed",
			"",
			"Use --claim to atomically claim the first ready issue matching the filters:",
			"  bd ready --claim --json",
			"",
			"This is useful for agents executing molecules to see which steps can run next.",
			"",
			"Usage:",
			"  bd ready [flags]",
			"",
			"Flags:",
			"  -a, --assignee string              Filter by assignee",
			"      --brief                        Omit the free-form text (description, design, acceptance criteria, notes, payload, waiters) from each row. Filters that read those fields still select on them. An omitted field is indistinguishable from an empty one; fetch a whole issue with bd show. Requires --json, and cannot be combined with --claim, --gated, --mol or --explain.",
			"      --claim                        Atomically claim the first ready issue matching the filters",
			"      --exclude-label strings        Exclude issues that have ANY of these labels",
			"      --exclude-type strings         Exclude issue types from results (comma-separated or repeatable, e.g., --exclude-type=convoy,epic)",
			"      --explain                      Show dependency-aware reasoning for why issues are ready or blocked",
			"      --gated                        Find molecules ready for gate-resume dispatch",
			"      --has-metadata-key string      Filter issues that have this metadata key set",
			"  -h, --help                         help for ready",
			"      --include-deferred             Include issues with future defer_until timestamps",
			"      --include-ephemeral            Include ephemeral issues (wisps) in results",
			"  -l, --label strings                Filter by labels (AND: must have ALL). Can combine with --label-any",
			"      --label-any strings            Filter by labels (OR: must have AT LEAST ONE). Can combine with --label",
			"      --label-pattern string         Filter by label glob pattern (e.g., 'tech-*' matches tech-debt, tech-legacy)",
			"      --label-regex string           Filter by label regex pattern (e.g., 'tech-(debt|legacy)')",
			"  -n, --limit int                    Maximum issues to show (use 0 for unlimited) (default 100)",
			"      --max-rows int                 Hard upper bound on rows fetched from storage. Returns a non-zero exit (code 2) and an error to stderr if exceeded. 0 disables (the default). Overrides BEADS_MAX_ROWS for this invocation. Useful in CI/agent rigs that want a circuit breaker against pathological queries. Not supported under --proxied-server: an explicit --max-rows or BEADS_MAX_ROWS cap errors out rather than silently going unenforced.",
			"      --metadata-field stringArray   Filter by metadata field (key=value, repeatable)",
			"      --mol string                   Filter to steps within a specific molecule",
			"      --mol-type string              Filter by molecule type: swarm, patrol, or work",
			"      --offset int                   Skip the first N matching results (0-based). Only supported under --proxied-server.",
			"      --parent string                Filter to descendants of this bead/epic",
			"      --plain                        Display issues as a plain numbered list",
			"      --pretty                       Display issues in a tree format with status/priority symbols (default true)",
			"  -p, --priority int                 Filter by priority",
			"  -s, --sort string                  Sort policy: priority (default), hybrid, oldest (default \"priority\")",
			"  -t, --type string                  Filter by issue type (task, bug, feature, epic, decision, merge-request). Aliases: mr→merge-request, feat→feature, mol→molecule, dec/adr→decision",
			"  -u, --unassigned                   Show only unassigned issues",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output\n"
		].join("\n");
	}

	function queryHelp():String {
		return [
			"Query issues using a simple query language that supports compound filters,",
			"boolean operators, and date-relative expressions.",
			"",
			"The query language enables complex filtering that would otherwise require",
			"multiple flags or piping through jq.",
			"",
			"Syntax:",
			"  field=value       Equality comparison",
			"  field!=value      Inequality comparison",
			"  field>value       Greater than",
			"  field>=value      Greater than or equal",
			"  field<value       Less than",
			"  field<=value      Less than or equal",
			"",
			"Boolean operators (case-insensitive):",
			"  expr AND expr     Both conditions must match",
			"  expr OR expr      Either condition can match",
			"  NOT expr          Negates the condition",
			"  (expr)            Grouping with parentheses",
			"",
			"Supported fields:",
			"  status            Stored status (open, in_progress, blocked, deferred, closed). Note: dependency-blocked issues stay \"open\"; use 'bd blocked' to find them",
			"  priority          Priority level (0-4)",
			"  type              Issue type (bug, feature, task, epic, chore, decision)",
			"  assignee          Assigned user (use \"none\" for unassigned)",
			"  owner             Issue owner",
			"  label             Issue label (use \"none\" for unlabeled)",
			"  title             Search in title (contains)",
			"  description       Search in description (contains, \"none\" for empty)",
			"  notes             Search in notes (contains)",
			"  created           Creation date/time",
			"  updated           Last update date/time",
			"  started           Date/time issue first transitioned to in_progress",
			"  closed            Close date/time",
			"  id                Issue ID (supports wildcards: bd-*)",
			"  spec              Spec ID (supports wildcards)",
			"  pinned            Boolean (true/false)",
			"  ephemeral         Boolean (true/false)",
			"  template          Boolean (true/false)",
			"  parent            Parent issue ID",
			"  mol_type          Molecule type (swarm, patrol, work)",
			"",
			"Date values:",
			"  Relative durations: 7d (7 days ago), 24h (24 hours ago), 2w (2 weeks ago)",
			"  Absolute dates: 2025-01-15, 2025-01-15T10:00:00Z",
			"  Natural language: tomorrow, \"next monday\", \"in 3 days\"",
			"",
			"Examples:",
			"  bd query \"status=open AND priority>1\"",
			"  bd query \"status=open AND priority<=2 AND updated>7d\"",
			"  bd query \"(status=open OR status=blocked) AND priority<2\"",
			"  bd query \"type=bug AND label=urgent\"",
			"  bd query \"NOT status=closed\"",
			"  bd query \"assignee=none AND type=task\"",
			"  bd query \"created>30d AND status!=closed\"",
			"  bd query \"label=frontend OR label=backend\"",
			"  bd query \"title=authentication AND priority=0\"",
			"",
			"Usage:",
			"  bd query [expression] [flags]",
			"",
			"Flags:",
			"  -a, --all           Include closed issues (default: exclude closed)",
			"  -h, --help          help for query",
			"  -n, --limit int     Limit results (default: 50, 0 = unlimited) (default 50)",
			"      --long          Show detailed multi-line output for each issue",
			"      --offset int    Skip the first N matching results (0-based). Only supported under --proxied-server.",
			"      --parse-only    Only parse the query and show the AST (for debugging)",
			"  -r, --reverse       Reverse sort order",
			"      --sort string   Sort by field: priority, created, updated, closed, status, id, title, type, assignee",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function searchHelp():String {
		return [
			"Search issues across title and ID (all statuses, including closed).",
			"",
			"ID-like queries (e.g., \"bd-123\", \"hq-319\") use fast exact/prefix matching.",
			"Text queries search titles. Use --desc-contains for description search.",
			"Use --status open (etc.) to narrow; closed issues are included by default",
			"so \"was this already filed/fixed?\" cannot silently answer no. Matches",
			"beyond --limit are dropped status-blind, so when hunting live work in a",
			"large DB, narrow with --status open or raise --limit.",
			"",
			"Examples:",
			"  bd search \"authentication bug\"",
			"  bd search \"login\" --status open",
			"  bd search \"database\" --label backend --limit 10",
			"  bd search --query \"performance\" --assignee alice",
			"  bd search \"bd-5q\" # Search by partial ID (fast prefix match)",
			"  bd search \"security\" --priority-min 0 --priority-max 2",
			"  bd search \"bug\" --created-after 2025-01-01",
			"  bd search \"refactor\" --status open  # Only open issues",
			"  bd search \"bug\" --sort priority",
			"  bd search \"task\" --sort created --reverse",
			"  bd search \"api\" --desc-contains \"endpoint\"",
			"  bd search \"cleanup\" --no-assignee --no-labels",
			"",
			"Usage:",
			"  bd search [query] [flags]",
			"",
			"Flags:",
			"  -a, --assignee string              Filter by assignee",
			"      --closed-after string          Filter issues closed after date (YYYY-MM-DD or RFC3339)",
			"      --closed-before string         Filter issues closed before date (YYYY-MM-DD or RFC3339)",
			"      --created-after string         Filter issues created after date (YYYY-MM-DD or RFC3339)",
			"      --created-before string        Filter issues created before date (YYYY-MM-DD or RFC3339)",
			"      --desc-contains string         Filter by description substring (case-insensitive)",
			"      --empty-description            Filter issues with empty or missing description",
			"      --external-contains string     Filter by external ref substring (case-insensitive)",
			"      --has-metadata-key string      Filter issues that have this metadata key set",
			"  -h, --help                         help for search",
			"  -l, --label strings                Filter by labels (AND: must have ALL)",
			"      --label-any strings            Filter by labels (OR: must have AT LEAST ONE)",
			"  -n, --limit int                    Limit results (default: 50) (default 50)",
			"      --long                         Show detailed multi-line output for each issue",
			"      --metadata-field stringArray   Filter by metadata field (key=value, repeatable)",
			"      --no-assignee                  Filter issues with no assignee",
			"      --no-labels                    Filter issues with no labels",
			"      --notes-contains string        Filter by notes substring (case-insensitive)",
			"      --priority-max string          Filter by maximum priority (inclusive, 0-4 or P0-P4)",
			"      --priority-min string          Filter by minimum priority (inclusive, 0-4 or P0-P4)",
			"      --query string                 Search query (alternative to positional argument)",
			"  -r, --reverse                      Reverse sort order",
			"      --sort string                  Sort by field: priority, created, updated, closed, status, id, title, type, assignee",
			"  -s, --status string                Filter by stored status (comma-separated for OR; open, in_progress, blocked, deferred, closed, all). Default searches all statuses including closed. Note: dependency-blocked issues use 'bd blocked'",
			"  -t, --type string                  Filter by type (bug, feature, task, epic, chore, decision, merge-request, molecule, gate)",
			"      --updated-after string         Filter issues updated after date (YYYY-MM-DD or RFC3339)",
			"      --updated-before string        Filter issues updated before date (YYYY-MM-DD or RFC3339)",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function showHelp():String {
		return [
			"Show issue details",
			"",
			"Usage:",
			"  bd show [id...] [--id=<id>...] [--current] [flags]",
			"",
			"Aliases:",
			"  show, view",
			"",
			"Flags:",
			"      --as-of string         Show issue as it existed at a specific commit hash or branch (requires Dolt)",
			"      --brief-deps           Reduce each dependency to its identity fields in JSON output (--json only; drops description, design, notes and acceptance criteria)",
			"      --children             Show only the children of this issue",
			"      --current              Show the currently active issue (in-progress, hooked, or last touched)",
			"  -h, --help                 help for show",
			"      --id stringArray       Issue ID (use for IDs that look like flags, e.g., --id=gt--xyz)",
			"      --include-comments     Stream full comment bodies in JSON output (--json only; may be slow on issues with many comments)",
			"      --include-dependents   Stream full dependent issues in JSON output (--json only; may be slow on hub beads)",
			"      --local-time           Show timestamps in local time instead of UTC",
			"      --long                 Show all available fields (extended metadata, agent identity, gate fields, etc.)",
			"      --refs                 Show issues that reference this issue (reverse lookup)",
			"      --short                Show compact one-line output per issue",
			"      --thread               Show full conversation thread (for messages)",
			"  -w, --watch                Watch for changes and auto-refresh display",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function listHelp():String {
		return [
			"List issues",
			"",
			"Usage:",
			"  bd list [flags]",
			"",
			"Flags:",
			"      --all                          Show all issues including closed (overrides default filter)",
			"  -a, --assignee string              Filter by assignee",
			"      --brief                        Omit the free-form text (description, design, acceptance criteria, notes, payload, waiters) from each row. Filters that read those fields, such as --desc-contains, still select on them. An omitted field is indistinguishable from an empty one in --json; fetch a whole issue with bd show.",
			"      --closed-after string          Filter issues closed after date (YYYY-MM-DD or RFC3339)",
			"      --closed-before string         Filter issues closed before date (YYYY-MM-DD or RFC3339)",
			"      --created-after string         Filter issues created after date (YYYY-MM-DD or RFC3339)",
			"      --created-before string        Filter issues created before date (YYYY-MM-DD or RFC3339)",
			"      --defer-after string           Filter issues deferred after date (supports relative: +6h, tomorrow)",
			"      --defer-before string          Filter issues deferred before date (supports relative: +6h, tomorrow)",
			"      --deferred                     Show only issues with defer_until set",
			"      --deps string[=\"scheduling\"]   Annotate tree with dependency edges and order siblings by them: 'scheduling' (bare --deps) or 'all'",
			"      --desc-contains string         Filter by description substring (case-insensitive)",
			"      --due-after string             Filter issues due after date (supports relative: +6h, tomorrow)",
			"      --due-before string            Filter issues due before date (supports relative: +6h, tomorrow)",
			"      --empty-description            Filter issues with empty or missing description",
			"      --exclude-label strings        Exclude issues that have ANY of these labels",
			"      --exclude-type strings         Exclude issue types from results (comma-separated or repeatable, e.g., --exclude-type=convoy,epic)",
			"      --external-contains string     Filter by external ref substring (case-insensitive)",
			"      --external-ref string          Filter by exact external_ref value",
			"      --flat                         Disable tree format and use legacy flat list output",
			"      --format string                Output format: 'digraph' (for golang.org/x/tools/cmd/digraph), 'dot' (Graphviz), or Go template",
			"      --has-metadata-key string      Filter issues that have this metadata key set",
			"  -h, --help                         help for list",
			"      --id string                    Filter by specific issue IDs (comma-separated, e.g., bd-1,bd-5,bd-10)",
			"      --include-gates                Include gate issues in output (normally hidden)",
			"      --include-infra                Include infrastructure beads (agent/role/message) in output",
			"      --include-templates            Include template molecules in output",
			"  -l, --label strings                Filter by labels (AND: must have ALL). Can combine with --label-any",
			"      --label-any strings            Filter by labels (OR: must have AT LEAST ONE). Can combine with --label",
			"      --label-pattern string         Filter by label glob pattern (e.g., 'tech-*' matches tech-debt, tech-legacy)",
			"      --label-regex string           Filter by label regex pattern (e.g., 'tech-(debt|legacy)')",
			"  -n, --limit int                    Limit results (default 50, use 0 for unlimited) (default 50)",
			"      --long                         Show detailed multi-line output for each issue",
			"      --max-rows int                 Hard upper bound on rows returned. Returns a non-zero exit (code 2) and an error to stderr if exceeded. 0 disables (the default). Overrides BEADS_MAX_ROWS for this invocation. Useful in CI/agent rigs that want a circuit breaker against pathological queries. Honored on both the direct and the --proxied-server route.",
			"      --metadata-field stringArray   Filter by metadata field (key=value, repeatable)",
			"      --mol-type string              Filter by molecule type: swarm, patrol, or work",
			"      --no-assignee                  Filter issues with no assignee",
			"      --no-labels                    Filter issues with no labels",
			"      --no-pager                     Disable pager output",
			"      --no-parent                    Exclude child issues (show only top-level issues)",
			"      --no-pinned                    Exclude pinned issues",
			"      --notes-contains string        Filter by notes substring (case-insensitive)",
			"      --offset int                   Skip the first N matching results (0-based). Only supported under --proxied-server.",
			"      --overdue                      Show only issues with due_at in the past (not closed)",
			"      --parent string                Filter by parent issue ID (shows children of specified issue)",
			"      --pinned                       Show only pinned issues",
			"      --pretty                       Display issues in a tree format with status/priority symbols",
			"  -p, --priority string              Priority (0-4 or P0-P4, 0=highest)",
			"      --priority-max string          Filter by maximum priority (inclusive, 0-4 or P0-P4)",
			"      --priority-min string          Filter by minimum priority (inclusive, 0-4 or P0-P4)",
			"      --ready                        Show only ready issues (no active blockers, same semantics as bd ready)",
			"  -r, --reverse                      Reverse sort order",
			"      --skip-labels                  Skip label hydration. The labels field in output will be empty regardless of actual labels. Use only when the caller does not depend on label data. Cannot combine with --label, --label-any, --label-pattern, --label-regex, --exclude-label, or --no-labels.",
			"      --sort string                  Sort by field: priority, created, updated, closed, status, id, title, type, assignee",
			"      --spec string                  Filter by spec_id prefix",
			"  -s, --status string                Filter by stored status (open, in_progress, blocked, deferred, closed). Comma-separated for multiple: --status open,in_progress. Note: repeating -s/--status silently overwrites the previous value — always use the comma-separated form for multi-status filters.",
			"      --title string                 Filter by title text (case-insensitive substring match)",
			"      --title-contains string        Filter by title substring (case-insensitive)",
			"      --tree                         Hierarchical tree format (default: true; use --flat to disable) (default true)",
			"  -t, --type string                  Filter by type (bug, feature, task, epic, chore, decision, merge-request, molecule, gate, convoy). Aliases: mr→merge-request, feat→feature, mol→molecule, dec/adr→decision",
			"      --updated-after string         Filter issues updated after date (YYYY-MM-DD or RFC3339)",
			"      --updated-before string        Filter issues updated before date (YYYY-MM-DD or RFC3339)",
			"  -w, --watch                        Watch for changes and auto-update display (implies --pretty)",
			"      --wisp-type string             Filter by wisp type: heartbeat, ping, patrol, gc_report, recovery, error, escalation",
			"",
			"Global Flags:",
			"      --actor string              Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)",
			"      --cpu-profile               Generate CPU profile for performance analysis",
			"      --database string           Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)",
			"      --db string                 Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)",
			"  -C, --directory string          Change to this directory before running the command (like git -C)",
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit",
			"      --global                    Use the global shared-server database (beads_global)",
			"      --ignore-schema-skew        Proceed despite forward schema drift (some queries may fail)",
			"      --json                      Output in JSON format",
			"      --mem-profile string        Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)",
			"      --no-color                  Disable color output (also: NO_COLOR=1 or CLICOLOR=0)",
			"  -q, --quiet                     Suppress non-essential output (errors only)",
			"      --readonly                  Read-only mode: block write operations (for worker sandboxes)",
			"      --sandbox                   Sandbox mode: disables Dolt auto-push",
			"  -v, --verbose                   Enable verbose/debug output"
		].join("\n") + "\n";
	}

	function basicCommandHelp(description:String, name:String, flags:String):String {
		return '${description}\n\nUsage:\n  bdhx ${name} [flags]\n\nFlags:\n  -h, --help   help for ${name}\n${flags}\n' + supportedGlobalFlags();
	}

	function supportedGlobalFlags():String {
		return "Global Flags:\n"
			+ "      --actor string   Actor name for assigned-work lookup\n"
			+ "  -C, --directory string   Change to this directory before running the command (like git -C)\n"
			+
			"      --database string   Run against a different server database for this invocation, without changing the project's configured database (proxied-server mode only)\n"
			+
			"      --db string         Database path (default: auto-discover .beads/*.db). In proxied-server mode, a value that isn't an existing path is treated as a database name override (see --database)\n"
			+
			"      --dolt-auto-commit string   Dolt auto-commit policy (off|on|batch). 'on': commit after each write. 'batch': defer commits to bd dolt commit; uncommitted changes persist in the working set until then (a live batch-mode bd process also flushes on SIGTERM/SIGHUP). Applies to embedded and direct SQL-server modes; proxied-server routes are unaffected. Default: on. Override via config key dolt.auto-commit\n"
			+ "      --ignore-schema-skew   Proceed despite forward schema drift (some queries may fail)\n"
			+ "      --global          Use the global shared-server database (beads_global)\n"
			+ "      --cpu-profile     Generate CPU profile for performance analysis\n"
			+ "      --mem-profile string   Write heap profile to FILE on exit (also respects BEADS_MEM_PROFILE)\n"
			+ "      --json           Output in JSON format\n"
			+ "      --no-color       Disable color output\n"
			+ "  -q, --quiet          Suppress non-essential output\n"
			+ "      --readonly       Block write operations\n"
			+ "      --sandbox        Disable remote publication\n"
			+ "  -v, --verbose        Enable verbose/debug output\n";
	}
}
