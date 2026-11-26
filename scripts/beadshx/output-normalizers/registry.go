package main

import (
	"errors"
	"fmt"
	"slices"
	"strings"
)

// Normalizer is one declared output normalizer: a stable name, the values it
// rewrites, why those values are volatile, the comparisons that may name it,
// and the rewrite itself.
type Normalizer struct {
	Name   string
	Fields string
	Reason string
	Scope  string
	// paths marks the path normalizers, which share one scan: see replacePaths.
	paths bool
	needs func(Options) error
	apply func([]byte, Options) ([]byte, error)
}

// Options holds the side's own values that some normalizers need.
type Options struct {
	// Work, Home and State are the spellings of the side's work directory,
	// HOME directory and state root (the work directory's parent).
	Work, Home, State []string
	// ThanksSource is upstream's cmd/bd/thanks.go, which holds the commit
	// count of each contributor.
	ThanksSource []byte
}

// errRejected marks input that a normalizer refuses, because its declared
// value is not there in the declared form; the comparison then fails.
var errRejected = errors.New("rejected")

func rejectf(format string, arguments ...any) error {
	return fmt.Errorf("%w: "+format, append([]any{errRejected}, arguments...)...)
}

// The markers that replace a declared value.
const (
	workMarker        = "<work>"
	homeMarker        = "<home>"
	stateMarker       = "<state>"
	timeMarker        = "<time>"
	durationMarker    = "<duration>"
	millisMarker      = `"<ms>"`
	buildOutputMarker = "<build output>\n"
	rootUsageMarker   = "<root usage>\n"
)

// declaredNormalizers lists every normalizer in the order in which apply runs
// them, whatever order a comparison names them in.
var declaredNormalizers = []Normalizer{
	{
		Name:   "pty-transcript",
		Fields: `the "\r" that the terminal adds before each "\n", and each "^D\b\b" that it echoes for the end of stdin`,
		Reason: "The script(1) runners give the binary a pseudo-terminal, whose driver turns each line feed into CR LF " +
			"and, on macOS, echoes the end of the empty stdin as ^D and two backspaces. The binary writes neither. " +
			"scripts/beadshx/pty_transcript.py undoes the same CR LF translation for the color cases.",
		Scope: "stdout of database cases that run through the script terminal runners (write_terminal_runner), " +
			"and the transcripts of the JSON terminal notice checks",
		apply: applyPtyTranscript,
	},
	{
		Name: "work-path",
		Fields: "each given spelling (--work) of the side's work directory, as a whole path: not after a name " +
			"character or a dot, and not followed by one (a dot ends the path when no name character follows it)",
		Reason: "Each side runs in its own temporary work directory, and upstream prints it in where, info, warnings " +
			"and errors. Go keeps the logical path that the run starts in, so both the physical and the logical " +
			"spelling can appear.",
		Scope: "stdout of exact and exact-home database cases; stderr of database, store-failure and " +
			"candidate-only cases",
		paths: true,
		needs: func(options Options) error { return needPaths("work-path", "--work", options.Work) },
	},
	{
		Name:   "home-path",
		Fields: "each given spelling (--home) of the side's HOME directory, as a whole path, as for work-path",
		Reason: "config get of a user-global key prints the user config.yaml path under each side's own HOME, as Go " +
			"cleans it.",
		Scope: "stdout of exact-home database cases",
		paths: true,
		needs: func(options Options) error { return needPaths("home-path", "--home", options.Home) },
	},
	{
		Name: "state-path",
		Fields: "each given spelling (--state) of the side's state root, the parent of its work directory, as a " +
			"whole path, as for work-path",
		Reason: "For a BEADS_DB path that names no workspace, upstream sets up the parent directory " +
			"(resolveCommandBeadsDir falls back to filepath.Dir) and warns about its permissions.",
		Scope: "stderr of candidate-only cases",
		paths: true,
		needs: func(options Options) error { return needPaths("state-path", "--state", options.State) },
	},
	{
		Name: "log-time",
		Fields: `the RFC 3339 time in a time="..." field that starts a line, followed by a space, as logrus' text ` +
			`formatter writes it`,
		Reason: "Dolt logs warnings such as \"skipping in-progress database directory\" through logrus, which stamps " +
			"the wall clock of each side's own run.",
		Scope: "stderr of database cases",
		apply: applyLogTime,
	},
	{
		Name:   "ping-duration",
		Fields: "the milliseconds N in a line that ends with \"bd ping: ok (Nms)\"",
		Reason: "ping prints the wall time that its own run took (cmd/bd/ping.go:81).",
		Scope:  "stdout of ping-human database cases",
		apply:  applyPingDuration,
	},
	{
		Name: "ping-timings",
		Fields: "the values of the query_ms, resolve_ms, store_ms and total_ms members of the top-level JSON " +
			"object; each must be there once, as a number that is not negative, and total_ms must be the sum " +
			"of the other three",
		Reason: "ping --json prints the wall time of each step of its own run (cmd/bd/ping.go:72-77).",
		Scope:  "stdout of ping-json database cases",
		apply:  applyPingTimings,
	},
	{
		Name:   "build-output",
		Fields: "a whole stdout that is not empty; an empty stdout stays empty",
		Reason: "version, --version and the root help print the build's own name, version, commit and command " +
			"list, so the two builds differ by design. upstream's version --json also names the branch of the " +
			"Git checkout when it resolves the workspace's repository (cmd/bd/version.go:41-63 and 106-130), " +
			"which depends on the workspace. The exit code and stderr are still compared, and a build that " +
			"prints nothing still differs from one that prints its identity.",
		Scope: "stdout of stderr-only database cases; the harness allows that mode only for version, " +
			"version --json, --version, --help and the root command without arguments, after -C and --db " +
			"(is_build_output_command)",
		apply: applyBuildOutput,
	},
	{
		Name:   "root-usage",
		Fields: "the text from a \"Usage:\" line that comes right after the first line to the end",
		Reason: "After a flag error on the root command, cobra prints the root usage last, and it names each build " +
			"and lists that build's own commands. The first line, the error, stays.",
		Scope: "stderr of compare_root_usage_error no-workspace cases",
		apply: applyRootUsage,
	},
	{
		Name: "children-block-order",
		Fields: "the order of the blocks of show --children: a block starts at each line that is not empty and " +
			"does not start with a space; the lines of a block keep their order",
		Reason: "show --children for several issues ranges over a Go map of issue IDs (cmd/bd/show_children.go:67), " +
			"so it prints the issues' blocks in a random order.",
		Scope: "stdout of show-children-multi database cases",
		apply: func(input []byte, _ Options) ([]byte, error) { return sortBlocks(input, childrenBlockStart), nil },
	},
	{
		Name: "refs-block-order",
		Fields: "the order of the blocks of show --refs: a block starts at each empty line that a line follows " +
			"which is not empty and does not start with a space; the lines of a block keep their order",
		Reason: "show --refs for several issues ranges over a Go map of issue IDs (cmd/bd/show_refs.go:54), so it " +
			"prints the issues' blocks in a random order.",
		Scope: "stdout of show-refs-multi database cases",
		apply: func(input []byte, _ Options) ([]byte, error) { return sortBlocks(input, refsBlockStart), nil },
	},
	{
		Name: "routing-mode-order",
		Fields: `the order of the names in "(valid values: ...)" in a line that says "routing.mode: ... is ` +
			`invalid (valid values: ...)"`,
		Reason: "config validate lists the valid routing modes from a Go map (cmd/bd/doctor/config_values.go:19 " +
			"and 210), in a random order.",
		Scope: "stdout of config-validate-routing database cases",
		apply: applyRoutingModeOrder,
	},
	{
		Name: "config-tie-rows",
		Fields: "the order of adjacent config show rows (\"  KEY = VALUE  (SOURCE)\") that have the same key; rows " +
			"with different keys keep their order",
		Reason: "config show sorts its entries by key with sort.Slice, which is not stable, over entries gathered " +
			"from Go maps (cmd/bd/config_show.go:102), so the rows of one key set by two sources print in " +
			"either order.",
		Scope: "stdout of config-show-tied-text database cases",
		apply: applyConfigTieRows,
	},
	{
		Name: "config-tie-entries",
		Fields: "the order of adjacent elements of the top-level JSON array that have the same \"key\" member; " +
			"elements with different keys keep their order",
		Reason: "config show --json prints the same entries as config show, in the same unstable order " +
			"(cmd/bd/config_show.go:102).",
		Scope: "stdout of config-show-tied-json database cases",
		apply: applyConfigTieEntries,
	},
	{
		Name: "molecule-parallel-order",
		Fields: "the order of the elements of each array in the top-level parallel_groups member, and of the " +
			"blocked_by, blocks and can_parallel arrays in the parallel_info of each element of steps",
		Reason: "ready --mol builds its parallel groups from Go maps (cmd/bd/mol_show.go:349-371), so the steps " +
			"of a group and its can_parallel lists come in a random order.",
		Scope: "stdout of molecule-ready-json database cases",
		apply: applyMoleculeParallelOrder,
	},
	{
		Name:   "graph-depends-on-order",
		Fields: "the order of the elements of each DependsOn array in the values of layout.Nodes",
		Reason: "graph --open adds the transitive edges that it joins over left-out issues by ranging over a Go " +
			"map (cmd/bd/graph.go:751), so a node's DependsOn comes in a random order.",
		Scope: "stdout of graph-open-json database cases",
		apply: applyGraphDependsOnOrder,
	},
	{
		Name: "graph-html-node-order",
		Fields: `the order of the node objects on a line that starts with "const nodes = [{"id":" and ends with ` +
			`"}];", split where "},{"id":" occurs, which cannot occur inside a JSON string`,
		Reason: "graph --html builds its nodes by ranging over the layout's Go map of nodes " +
			"(cmd/bd/graph_export.go:205), in a random order.",
		Scope: "stdout of graph-html database cases",
		apply: applyGraphHTMLNodeOrder,
	},
	{
		Name: "thanks-contributor-order",
		Fields: "the order of the contributors that have the same commit count on the thanks page: the rows " +
			"under \"Featured Contributors\" and the wrapped lines under \"Additional Contributors\"; and a " +
			"\"\\r\" right before a \"\\n\", which the former Python check of the page dropped by reading it " +
			"as text (bdhx writes one on a terminal: beadshx-m06.6, after which this part goes)",
		Reason: "The thanks page sorts upstream's contributor map by commit count with an unstable sort " +
			"(cmd/bd/thanks.go:117-122), so contributors with the same count print in a random order. The page " +
			"must name each contributor of --thanks-source once, with the counts never rising, in the rows and " +
			"wrapped lines that upstream's layout gives for that order; the normalizer then lays the names out " +
			"by count, then in the source's order.",
		Scope: "stdout of thanks-page database cases",
		needs: func(options Options) error {
			if len(options.ThanksSource) == 0 {
				return errors.New("thanks-contributor-order needs --thanks-source")
			}
			return nil
		},
		apply: applyThanksContributorOrder,
	},
	{
		Name:   "watch-header-time",
		Fields: "the HH:MM:SS clock time in a line that ends with \"Beads - Open & In Progress (HH:MM:SS)\"",
		Reason: "list --watch prints the wall-clock time of each refresh in its header (cmd/bd/list_tree.go:166).",
		Scope:  "stdout of list watch cases",
		apply:  applyWatchHeaderTime,
	},
	{
		Name: "watch-refresh-noise",
		Fields: "each line \"Error refreshing issues: ...context canceled\", and an \"Error refreshing issues:\" " +
			"line that repeats the line printed right before it",
		Reason: "The watch polls on a timer, so how often a refresh fails before the interrupt is not command " +
			"policy, and a refresh that the final interrupt cancels is shutdown noise. Every other refresh " +
			"error stays once.",
		Scope: "stderr of watch cases",
		apply: applyWatchRefreshNoise,
	},
	{
		Name: "json-compact",
		Fields: "the white space between the tokens of a stdout that is one JSON document; string escapes and " +
			"number spellings stay",
		Reason: "A candidate-only case writes its expected JSON refusal on one line, and bdhx prints it indented " +
			"as upstream does.",
		Scope: "stdout of candidate-only cases that expect a stdout",
		apply: applyJSONCompact,
	},
}

func needPaths(name, flag string, values []string) error {
	if len(values) == 0 {
		return fmt.Errorf("%s needs %s", name, flag)
	}
	for _, value := range values {
		if !strings.HasPrefix(value, "/") || value == "/" || strings.HasSuffix(value, "/") {
			return fmt.Errorf("%s %s takes an absolute path without a trailing slash: %q", name, flag, value)
		}
	}
	return nil
}

func findNormalizer(name string) (Normalizer, bool) {
	index := slices.IndexFunc(declaredNormalizers, func(normalizer Normalizer) bool { return normalizer.Name == name })
	if index < 0 {
		return Normalizer{}, false
	}
	return declaredNormalizers[index], true
}

// parseRules reads a comma-separated list of normalizer names.
func parseRules(list string) ([]string, error) {
	var names []string
	for _, name := range strings.Split(list, ",") {
		name = strings.TrimSpace(name)
		if name == "" {
			continue
		}
		if _, ok := findNormalizer(name); !ok {
			return nil, fmt.Errorf("unknown normalizer %q (see the rules command)", name)
		}
		if slices.Contains(names, name) {
			return nil, fmt.Errorf("normalizer %q given twice", name)
		}
		names = append(names, name)
	}
	return names, nil
}

// normalize applies the named normalizers to one side's output, in the order
// of declaredNormalizers. Without names it returns the input unchanged. An
// error that wraps errRejected means that the input lacks a declared value in
// its declared form; any other error is a usage error.
func normalize(input []byte, names []string, options Options) ([]byte, error) {
	enabled := make(map[string]bool, len(names))
	for _, name := range names {
		normalizer, ok := findNormalizer(name)
		if !ok {
			return nil, fmt.Errorf("unknown normalizer %q", name)
		}
		if normalizer.needs != nil {
			if err := normalizer.needs(options); err != nil {
				return nil, err
			}
		}
		enabled[name] = true
	}
	output := slices.Clone(input)
	pathsDone := false
	for _, normalizer := range declaredNormalizers {
		if !enabled[normalizer.Name] {
			continue
		}
		if normalizer.paths {
			if !pathsDone {
				var err error
				if output, err = replacePaths(output, pathValues(enabled, options)); err != nil {
					return nil, err
				}
				pathsDone = true
			}
			continue
		}
		var err error
		if output, err = normalizer.apply(output, options); err != nil {
			return nil, fmt.Errorf("%s: %w", normalizer.Name, err)
		}
	}
	return output, nil
}
