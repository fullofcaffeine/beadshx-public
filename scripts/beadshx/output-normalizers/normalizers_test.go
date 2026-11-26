package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// side is one side's output and the side's own values.
type side struct {
	text    string
	options Options
}

// normalizerTest is the contract of one declared normalizer:
//
//   - same: two outputs that differ only in the declared value; they must
//     normalize to the same text, and want, when set, is that text.
//   - kept: outputs that hold only look-alikes of the declared value; the
//     normalizer must leave them unchanged.
//   - touched: outputs that hold the declared value and look-alikes; want is
//     the output with only the declared value rewritten.
//   - differ: two outputs that differ outside the declared value (and
//     possibly inside it); they must still differ after normalizing.
//   - rejected: outputs without the declared value in its declared form,
//     which the normalizer refuses.
type normalizerTest struct {
	same     []samePair
	kept     []side
	touched  []touchedCase
	differ   [][2]side
	rejected []side
}

type touchedCase struct {
	in   side
	want string
}

type samePair struct {
	left, right side
	want        string
}

const (
	oracleWork        = "/tmp/beadshx-parity-smoke.Ab12Cd/real-database-case/oracle-state/work"
	oracleWorkLogical = "/private/tmp/beadshx-parity-smoke.Ab12Cd/real-database-case/oracle-state/work"
	candidateWork     = "/tmp/beadshx-parity-smoke.Ab12Cd/real-database-case/candidate-state/work"
	oracleHome        = "/tmp/beadshx-parity-smoke.Ab12Cd/real-database-case/oracle-state/user-home"
	candidateHome     = "/tmp/beadshx-parity-smoke.Ab12Cd/real-database-case/candidate-state/user-home"
	candidateState    = "/tmp/beadshx-parity-smoke.Ab12Cd/candidate-only-case/candidate-state"
	candidateOnlyWork = candidateState + "/work"
)

var (
	oracleSide    = Options{Work: []string{oracleWork, oracleWorkLogical}, Home: []string{oracleHome}}
	candidateSide = Options{Work: []string{candidateWork}, Home: []string{candidateHome}}
	stateSide     = Options{Work: []string{candidateOnlyWork}, State: []string{candidateState}}
)

func plain(text string) side { return side{text: text} }

func oracle(text string) side { return side{text: text, options: oracleSide} }

func candidate(text string) side { return side{text: text, options: candidateSide} }

func lines(values ...string) string { return strings.Join(values, "\n") + "\n" }

// thanksPages reads the real upstream thanks pages of testdata/thanks-pages.json:
// two runs of the same page with the tied contributors in other orders, without
// and with colors.
func thanksPages(t *testing.T) map[string]string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("testdata", "thanks-pages.json"))
	if err != nil {
		t.Fatal(err)
	}
	var pages map[string][]string
	if err := json.Unmarshal(data, &pages); err != nil {
		t.Fatal(err)
	}
	joined := make(map[string]string, len(pages))
	for name, pageLines := range pages {
		joined[name] = strings.Join(pageLines, "\n")
	}
	return joined
}

func thanksSource(t *testing.T) []byte {
	t.Helper()
	source, err := os.ReadFile(filepath.Join("..", "..", "..", "cmd", "bd", "thanks.go"))
	if err != nil {
		t.Fatal(err)
	}
	return source
}

const (
	upstreamVersion     = "bd version 1.2.1 (634cbbc4b)\n"
	upstreamVersionJSON = "{\n  \"branch\": \"master\",\n  \"build\": \"634cbbc4b\",\n  \"schema_version\": 1,\n  \"version\": \"1.2.1\"\n}\n"
	beadshxVersion      = "BeadsHX 0.0.0-development (compatible with Beads v1.2.1 at 634cbbc4b)\n"
)

func pingJSON(query, resolve, store, total, status string) string {
	return "{\n  \"query_ms\": " + query + ",\n  \"resolve_ms\": " + resolve + ",\n  \"status\": \"" + status +
		"\",\n  \"store_ms\": " + store + ",\n  \"total_ms\": " + total + "\n}\n"
}

func moleculeJSON(group, canParallel, blocks, labels string) string {
	return "{\n  \"molecule_id\": \"test-m\",\n  \"parallel_groups\": {\n    \"group-1\": [" + group + "]\n  },\n" +
		"  \"steps\": [\n    {\n      \"issue\": {\"id\": \"test-m.1\", \"labels\": [" + labels + "]},\n" +
		"      \"parallel_info\": {\n        \"blocked_by\": [],\n        \"blocks\": [" + blocks + "],\n" +
		"        \"can_parallel\": [" + canParallel + "],\n        \"step_id\": \"test-m.1\"\n      }\n    }\n  ]\n}\n"
}

func graphJSON(dependsOn, dependents string) string {
	return "{\n  \"layout\": {\n    \"Layers\": [[\"test-c\"], [\"test-a\", \"test-e\"]],\n    \"Nodes\": {\n" +
		"      \"test-c\": {\n        \"DependsOn\": [" + dependsOn + "],\n        \"Dependents\": [" + dependents + "]\n      },\n" +
		"      \"test-a\": {\n        \"DependsOn\": null\n      }\n    }\n  }\n}\n"
}

const childrenA = "↳ Children of test-a (2):\n  ↳ ○ test-a.1: First P2\n  ↳ ○ test-a.2: Second P2\n\n"

const childrenB = "test-b: No children found\n"

const refsA = "\n📎 References to test-a:\n\n  ↳ CHILDREN (1):\n    test-a.1: Child [P2 - open]\n\n" +
	"  ↔ RELATED (1):\n    test-r: Related [P2 - open]\n\n"

const refsB = "\ntest-b: No references found\n"

func configRows(rows ...string) string { return lines(rows...) }

func configEntries(entries ...string) string {
	return "[\n" + strings.Join(entries, ",\n") + "\n]\n"
}

func entry(key, value, source string) string {
	return "  {\n    \"key\": \"" + key + "\",\n    \"value\": \"" + value + "\",\n    \"source\": \"" + source + "\"\n  }"
}

func normalizerTests(t *testing.T) map[string]normalizerTest {
	pages := thanksPages(t)
	source := thanksSource(t)
	thanks := func(text string) side { return side{text: text, options: Options{ThanksSource: source}} }
	state := func(text string) side { return side{text: text, options: stateSide} }
	usage := "Usage:\n  bd [flags]\n  bd [command]\n\nUse \"bd [command] --help\" for more information about a command.\n\n"
	return map[string]normalizerTest{
		"pty-transcript": {
			same: []samePair{
				{left: plain("first\r\nsecond\r\n"), right: plain("first\nsecond\n"), want: "first\nsecond\n"},
				{left: plain("^D\b\bfirst\r\n"), right: plain("first\n"), want: "first\n"},
			},
			kept: []side{plain("50%\r100%\n"), plain("^D marks the end\n"), plain("no line feed\r")},
			differ: [][2]side{
				{plain("first\r\nsecond\r\n"), plain("first\r\nthird\r\n")},
				{plain("first\r\r\n"), plain("first\r\n")},
			},
		},
		"work-path": {
			same: []samePair{
				{
					left:  oracle("Warning: " + oracleWork + "/.beads has permissions 0755\n"),
					right: candidate("Warning: " + candidateWork + "/.beads has permissions 0755\n"),
					want:  "Warning: <work>/.beads has permissions 0755\n",
				},
				{
					left:  oracle("in " + oracleWorkLogical + ".\nworkspace: " + oracleWork + "\n"),
					right: candidate("in " + candidateWork + ".\nworkspace: " + candidateWork + "\n"),
					want:  "in <work>.\nworkspace: <work>\n",
				},
				{
					left:  oracle(`{"path":"` + oracleWork + `/.beads","remote":"file://` + oracleWork + `/remote"}`),
					right: candidate(`{"path":"` + candidateWork + `/.beads","remote":"file://` + candidateWork + `/remote"}`),
					want:  `{"path":"<work>/.beads","remote":"file://<work>/remote"}`,
				},
			},
			kept: []side{
				oracle(oracleWork + "2/.beads\n"),
				oracle(oracleWork + "space/.beads\n"),
				oracle(oracleWork + ".bak\n"),
				oracle(oracleWork + "-old\n"),
				oracle("/other" + oracleWork + "/.beads\n"),
				oracle("relative" + oracleWork[len("/tmp"):] + "\n"),
				oracle(strings.TrimSuffix(oracleWork, "/work") + "/user-home\n"),
				oracle(candidateWork + "/.beads\n"),
				oracle(strings.ToUpper(oracleWork) + "\n"),
			},
			differ: [][2]side{
				{oracle(oracleWork + "/.beads: denied\n"), candidate(candidateWork + "/.beads: missing\n")},
				{oracle(oracleWork + "/a\n"), candidate(candidateWork + "/b\n")},
				{oracle(oracleWork + "/a\n"), candidate(strings.ToUpper(candidateWork) + "/a\n")},
				{oracle(oracleWork + "/a\n"), candidate(oracleWork + "/a\n")},
			},
		},
		"home-path": {
			same: []samePair{{
				left:  oracle(oracleHome + "/.config/bd/config.yaml\n"),
				right: candidate(candidateHome + "/.config/bd/config.yaml\n"),
				want:  "<home>/.config/bd/config.yaml\n",
			}},
			kept: []side{oracle(oracleHome + "2/config.yaml\n"), oracle(oracleHome + ".bak\n"), oracle(oracleWork + "\n")},
			differ: [][2]side{
				{oracle(oracleHome + "/.config/bd/config.yaml\n"), candidate(candidateHome + "/.config/bd/config.yml\n")},
			},
		},
		"state-path": {
			same: []samePair{{
				left:  state("Warning: " + candidateState + " has permissions 0755 (recommended: 0700). Run: chmod 700 " + candidateState),
				right: state("Warning: <state> has permissions 0755 (recommended: 0700). Run: chmod 700 <state>"),
				want:  "Warning: <state> has permissions 0755 (recommended: 0700). Run: chmod 700 <state>",
			}},
			kept: []side{state(candidateState + "x\n"), state(candidateState + "-old/work\n"), state(candidateState + ".bak\n")},
			differ: [][2]side{
				{state("Warning: " + candidateState + " has permissions 0755"), state("Warning: " + candidateState + " has permissions 0711")},
			},
		},
		"log-time": {
			same: []samePair{{
				left:  plain(`time="2026-11-26T10:00:00Z" level=warning msg="skipping in-progress database directory" path=x` + "\n"),
				right: plain(`time="2026-11-26T10:00:03+01:00" level=warning msg="skipping in-progress database directory" path=x` + "\n"),
				want:  `time="<time>" level=warning msg="skipping in-progress database directory" path=x` + "\n",
			}},
			kept: []side{
				plain(`time="soon" level=warning msg="x"` + "\n"),
				plain(` time="2026-11-26T10:00:00Z" level=warning msg="x"` + "\n"),
				plain(`msg="x" time="2026-11-26T10:00:00Z" level=warning` + "\n"),
				plain(`time="2026-11-26 10:00:00" level=warning msg="x"` + "\n"),
				plain(`time="2026-11-26T10:00:00Z"level=warning` + "\n"),
			},
			differ: [][2]side{
				{plain(`time="2026-11-26T10:00:00Z" level=warning msg="a"` + "\n"), plain(`time="2026-11-26T10:00:01Z" level=error msg="a"` + "\n")},
				{plain(`time="2026-11-26T10:00:00Z" level=warning msg="a"` + "\n"), plain(`time="2026-11-26T10:00:00Z" level=warning msg="b"` + "\n")},
			},
		},
		"ping-duration": {
			same: []samePair{
				{left: plain("✓ bd ping: ok (12ms)\n"), right: plain("✓ bd ping: ok (3ms)\n"), want: "✓ bd ping: ok (<duration>)\n"},
				{left: plain("\x1b[32m✓\x1b[0m bd ping: ok (0ms)\n"), right: plain("\x1b[32m✓\x1b[0m bd ping: ok (250ms)\n")},
			},
			kept: []side{
				plain("query took 12ms\n"),
				plain("✓ bd ping: ok (12s)\n"),
				plain("Error: bd ping: store not initialized (5ms)\n"),
				plain("✓ bd ping: ok (12ms) later\n"),
			},
			differ: [][2]side{
				{plain("✓ bd ping: ok (12ms)\n"), plain("✓ bd ping: ok (12ms)\nextra\n")},
				{plain("✓ bd ping: ok (1ms)\n"), plain("✗ bd ping: ok (1ms)\n")},
			},
		},
		"ping-timings": {
			same: []samePair{{
				left:  plain(pingJSON("1", "0", "2", "3", "ok")),
				right: plain(pingJSON("10", "4", "25", "39", "ok")),
				want:  pingJSON(`"<ms>"`, `"<ms>"`, `"<ms>"`, `"<ms>"`, "ok"),
			}},
			touched: []touchedCase{{
				in: plain("{\"detail\": {\"total_ms\": 9}, \"latency_ms\": 4, \"query_ms\": 1, \"resolve_ms\": 0, " +
					"\"store_ms\": 2, \"total_ms\": 3}\n"),
				want: "{\"detail\": {\"total_ms\": 9}, \"latency_ms\": 4, \"query_ms\": \"<ms>\", \"resolve_ms\": \"<ms>\", " +
					"\"store_ms\": \"<ms>\", \"total_ms\": \"<ms>\"}\n",
			}},
			differ: [][2]side{
				{plain(pingJSON("1", "0", "2", "3", "ok")), plain(pingJSON("1", "0", "2", "3", "okay"))},
				{plain(pingJSON("1", "0", "2", "3", "ok")), plain(`{"query_ms": 1, "resolve_ms": 0, "status": "ok", "store_ms": 2, "total_ms": 3}` + "\n")},
				{plain(pingJSON("1", "0", "2", "3", "<ok>")), plain(pingJSON("1", "0", "2", "3", `\u003cok\u003e`))},
				{
					plain(pingJSON("1", "0", "2", "3", "ok")),
					plain("{\n  \"resolve_ms\": 0,\n  \"query_ms\": 1,\n  \"status\": \"ok\",\n  \"store_ms\": 2,\n  \"total_ms\": 3\n}\n"),
				},
			},
			rejected: []side{
				plain(pingJSON("1", "0", "2", "4", "ok")),
				plain(pingJSON("-1", "0", "2", "1", "ok")),
				plain(pingJSON(`"1"`, "0", "2", "3", "ok")),
				plain("{\n  \"query_ms\": 1,\n  \"status\": \"ok\",\n  \"store_ms\": 2,\n  \"total_ms\": 3\n}\n"),
				plain("{\"query_ms\": 1, \"query_ms\": 1, \"resolve_ms\": 0, \"store_ms\": 2, \"total_ms\": 3}\n"),
				plain("[1, 0, 2, 3]\n"),
				plain("not json\n"),
			},
		},
		"build-output": {
			same: []samePair{
				{left: plain(upstreamVersion), right: plain(beadshxVersion), want: "<build output>\n"},
				{left: plain(upstreamVersionJSON), right: plain(beadshxVersion)},
			},
			kept:   []side{plain("")},
			differ: [][2]side{{plain(upstreamVersion), plain("")}},
		},
		"root-usage": {
			same: []samePair{{
				left:  plain("Error: unknown flag: --frobnicate\n" + usage),
				right: plain("Error: unknown flag: --frobnicate\nUsage:\n  bdhx [flags]\n\nFlags:\n  -h, --help   help for bdhx\n\n"),
				want:  "Error: unknown flag: --frobnicate\n<root usage>\n",
			}},
			kept: []side{
				plain("Error: unknown flag: --frobnicate\nhint\n" + usage),
				plain("Error: unknown flag: --frobnicate\n"),
				plain("Error: unknown flag: --frobnicate\n  Usage:\n"),
				plain("Usage:\n  bd [flags]\n"),
			},
			differ: [][2]side{
				{plain("Error: unknown flag: --frobnicate\n" + usage), plain("Error: unknown flag: --bogus\n" + usage)},
				{plain("Error: unknown flag: --frobnicate\n" + usage), plain("Error: unknown flag: --frobnicate\n")},
				{plain("Error: unknown flag: --frobnicate\n" + usage), plain("Error: unknown flag: --frobnicate\nhint\n" + usage)},
			},
		},
		"children-block-order": {
			same: []samePair{{left: plain(childrenA + childrenB), right: plain(childrenB + childrenA)}},
			kept: []side{
				plain(childrenA),
				plain("↳ Children of test-a (2):\n  ↳ ○ test-a.2: Second P2\n  ↳ ○ test-a.1: First P2\n\n"),
			},
			differ: [][2]side{
				{
					plain(childrenA + childrenB),
					plain("↳ Children of test-a (2):\n  ↳ ○ test-a.2: Second P2\n  ↳ ○ test-a.1: First P2\n\n" + childrenB),
				},
				{plain(childrenA + childrenB), plain(childrenA + "\n" + childrenB)},
				{plain(childrenA + childrenB), plain(childrenA)},
			},
		},
		"refs-block-order": {
			same: []samePair{{left: plain(refsA + refsB), right: plain(refsB + refsA)}},
			kept: []side{
				plain(refsA),
				plain("\n📎 References to test-a:\n\n  ↔ RELATED (1):\n    test-r: Related [P2 - open]\n\n" +
					"  ↳ CHILDREN (1):\n    test-a.1: Child [P2 - open]\n\n"),
			},
			differ: [][2]side{
				{
					plain(refsA + refsB),
					plain("\n📎 References to test-a:\n\n  ↔ RELATED (1):\n    test-r: Related [P2 - open]\n\n" +
						"  ↳ CHILDREN (1):\n    test-a.1: Child [P2 - open]\n\n" + refsB),
				},
				{plain(refsA + refsB), plain(refsA + "\n" + refsB)},
				{plain(refsA + refsB), plain(refsB)},
			},
		},
		"routing-mode-order": {
			same: []samePair{
				{
					left:  plain("  ✖ routing.mode: \"Maintainer\" is invalid (valid values: contributor, explicit, auto, maintainer)\n"),
					right: plain("  ✖ routing.mode: \"Maintainer\" is invalid (valid values: auto, maintainer, contributor, explicit)\n"),
					want:  "  ✖ routing.mode: \"Maintainer\" is invalid (valid values: auto, contributor, explicit, maintainer)\n",
				},
				{
					left:  plain(`    "routing.mode: \"bogus\" is invalid (valid values: explicit, auto, maintainer, contributor)",` + "\n"),
					right: plain(`    "routing.mode: \"bogus\" is invalid (valid values: maintainer, contributor, explicit, auto)",` + "\n"),
				},
			},
			kept: []side{
				plain("federation.sovereignty: \"x\" is invalid (valid values: T4, T1, or empty for no restriction)\n"),
				plain("routing.mode: \"x\" is invalid\n"),
				plain("sync.mode: \"x\" is invalid (valid values: dolt-native, belt-and-suspenders)\n"),
			},
			differ: [][2]side{
				{
					plain("routing.mode: \"Maintainer\" is invalid (valid values: auto, maintainer)\n"),
					plain("routing.mode: \"maintainer\" is invalid (valid values: auto, maintainer)\n"),
				},
				{
					plain("routing.mode: \"x\" is invalid (valid values: auto, contributor, explicit, maintainer)\n"),
					plain("routing.mode: \"x\" is invalid (valid values: auto, contributor, maintainer)\n"),
				},
			},
		},
		"config-tie-rows": {
			same: []samePair{{
				left: plain(configRows(
					"  beads.role    = maintainer  (git)",
					"  beads.role    = yaml-role   (config.yaml)",
					"  issue_prefix  = test        (database)",
				)),
				right: plain(configRows(
					"  beads.role    = yaml-role   (config.yaml)",
					"  beads.role    = maintainer  (git)",
					"  issue_prefix  = test        (database)",
				)),
			}},
			kept: []side{
				plain(configRows("  issue_prefix  = test        (database)", "  beads.role    = maintainer  (git)")),
				plain(configRows("No configuration found")),
			},
			differ: [][2]side{
				{
					plain(configRows("  beads.role    = maintainer  (git)", "  issue_prefix  = test        (database)")),
					plain(configRows("  issue_prefix  = test        (database)", "  beads.role    = maintainer  (git)")),
				},
				{
					plain(configRows("  beads.role    = maintainer  (git)", "  beads.role    = yaml-role   (config.yaml)")),
					plain(configRows("  beads.role    = maintainer  (git)", "  beads.role    = yaml-role   (env)")),
				},
			},
		},
		"config-tie-entries": {
			same: []samePair{{
				left: plain(configEntries(
					entry("beads.role", "maintainer", "git"), entry("beads.role", "yaml-role", "config.yaml"),
					entry("issue_prefix", "test", "database"),
				)),
				right: plain(configEntries(
					entry("beads.role", "yaml-role", "config.yaml"), entry("beads.role", "maintainer", "git"),
					entry("issue_prefix", "test", "database"),
				)),
			}},
			kept: []side{
				plain(configEntries(entry("issue_prefix", "test", "database"), entry("beads.role", "maintainer", "git"))),
			},
			differ: [][2]side{
				{
					plain(configEntries(entry("beads.role", "maintainer", "git"), entry("issue_prefix", "test", "database"))),
					plain(configEntries(entry("issue_prefix", "test", "database"), entry("beads.role", "maintainer", "git"))),
				},
				{
					plain(configEntries(entry("beads.role", "a<b", "git"), entry("beads.role", "c", "config.yaml"))),
					plain(configEntries(entry("beads.role", `a\u003cb`, "git"), entry("beads.role", "c", "config.yaml"))),
				},
			},
			rejected: []side{plain("{\"key\": \"beads.role\"}\n"), plain("[\"beads.role\"]\n"), plain("No configuration found\n")},
		},
		"molecule-parallel-order": {
			same: []samePair{{
				left:  plain(moleculeJSON(`"test-m.99", "test-m", "test-m.1"`, `"test-m.99", "test-m"`, `"test-m.2"`, `"b", "a"`)),
				right: plain(moleculeJSON(`"test-m", "test-m.1", "test-m.99"`, `"test-m", "test-m.99"`, `"test-m.2"`, `"b", "a"`)),
			}},
			kept: []side{plain(moleculeJSON(`"test-m"`, `"test-m.99"`, ``, `"b", "a"`))},
			rejected: []side{
				plain("[]\n"),
				plain("{\"parallel_groups\": {\"group-1\": \"test-m\"}}\n"),
				plain("{\"steps\": [{\"parallel_info\": {\"blocked_by\": null, \"blocks\": [], \"can_parallel\": []}}]}\n"),
				plain("{\"steps\": [{\"issue\": {}}]}\n"),
				plain("Error: no molecule\n"),
			},
			differ: [][2]side{
				{
					plain(moleculeJSON(`"test-m", "test-m.1"`, `"test-m"`, ``, `"b", "a"`)),
					plain(moleculeJSON(`"test-m", "test-m.1"`, `"test-m"`, ``, `"a", "b"`)),
				},
				{
					plain(moleculeJSON(`"test-m", "test-m.1"`, `"test-m"`, ``, `"a"`)),
					plain(moleculeJSON(`"test-m"`, `"test-m"`, ``, `"a"`)),
				},
			},
		},
		"graph-depends-on-order": {
			same: []samePair{{
				left:  plain(graphJSON(`"test-e", "test-a"`, `"test-z", "test-y"`)),
				right: plain(graphJSON(`"test-a", "test-e"`, `"test-z", "test-y"`)),
			}},
			kept: []side{plain(graphJSON(`"test-a", "test-e"`, `"test-z", "test-y"`))},
			rejected: []side{
				plain("{\"layout\": {\"Nodes\": {\"test-a\": {\"DependsOn\": \"test-b\"}}}}\n"),
				plain("{\"layout\": {}}\n"),
				plain("{\"layout\": {\"Nodes\": [1]}}\n"),
				plain("Error: not json\n"),
			},
			differ: [][2]side{
				{plain(graphJSON(`"test-e", "test-a"`, `"test-z", "test-y"`)), plain(graphJSON(`"test-e", "test-a"`, `"test-y", "test-z"`))},
				{plain(graphJSON(`"test-e", "test-a"`, ``)), plain(graphJSON(`"test-e"`, ``))},
			},
		},
		"graph-html-node-order": {
			same: []samePair{{
				left:  plain(lines("<script>", `const nodes = [{"id":"test-b","layer":1},{"id":"test-a","layer":0}];`, `const edges = [{"source":"test-a"}];`)),
				right: plain(lines("<script>", `const nodes = [{"id":"test-a","layer":0},{"id":"test-b","layer":1}];`, `const edges = [{"source":"test-a"}];`)),
				want:  lines("<script>", `const nodes = [{"id":"test-a","layer":0},{"id":"test-b","layer":1}];`, `const edges = [{"source":"test-a"}];`),
			}},
			kept: []side{
				plain(lines(`const edges = [{"id":"test-b"},{"id":"test-a"}];`)),
				plain(lines(`  const nodes = [{"id":"test-b"},{"id":"test-a"}];`)),
				plain(lines(`const nodes = [{"id":"test-b"},{"id":"test-a"}]`)),
			},
			differ: [][2]side{
				{
					plain(lines(`const nodes = [{"id":"test-b","layer":1},{"id":"test-a","layer":0}];`, `const edges = [{"source":"test-a"}];`)),
					plain(lines(`const nodes = [{"id":"test-b","layer":1},{"id":"test-a","layer":0}];`, `const edges = [{"source":"test-b"}];`)),
				},
				{
					plain(lines(`const nodes = [{"id":"test-b","layer":1},{"id":"test-a","layer":0}];`)),
					plain(lines(`const nodes = [{"id":"test-b","layer":2},{"id":"test-a","layer":0}];`)),
				},
			},
		},
		"thanks-contributor-order": {
			same: []samePair{
				{left: thanks(pages["plain-a"]), right: thanks(pages["plain-b"])},
				{left: thanks(pages["color-a"]), right: thanks(pages["color-b"])},
				// bdhx writes a stray carriage return on line 7 on a terminal (beadshx-m06.6).
				{left: thanks(pages["color-a"]), right: thanks(withCarriageReturn(pages["color-b"], 6))},
			},
			kept: []side{thanks(mustNormalize(t, pages["plain-a"], "thanks-contributor-order", Options{ThanksSource: source}))},
			differ: [][2]side{
				{thanks(pages["plain-a"]), thanks(strings.Replace(pages["plain-b"], "THANK YOU!", "THANK YOU?", 1))},
				{thanks(pages["plain-a"]), thanks(pages["color-b"])},
				{thanks(pages["plain-a"]), thanks(strings.Replace(pages["plain-b"], "THANK YOU!", "THANK\rYOU!", 1))},
			},
			rejected: []side{
				thanks(strings.Replace(pages["plain-a"], "Steve Yegge  ", "Someone Else ", 1)),
				thanks(swapNames(pages["plain-a"], "Steve Yegge", "Zoe Gagnon ")),
				thanks(strings.Replace(pages["plain-a"], ", Nikolai Prokoschenko", "", 1)),
				thanks(strings.Replace(pages["plain-a"], "  Featured Contributors", "  Contributors", 1)),
				thanks(strings.Replace(pages["plain-a"], "Steve Yegge           ", "Steve Yegge          ", 1)),
			},
		},
		"watch-header-time": {
			same: []samePair{{
				left:  plain("Beads - Open & In Progress (10:00:00)\n○ test-a\n"),
				right: plain("Beads - Open & In Progress (23:59:59)\n○ test-a\n"),
				want:  "Beads - Open & In Progress (<time>)\n○ test-a\n",
			}},
			kept: []side{plain("Beads - Open & In Progress (10:00)\n"), plain("Updated at (10:00:00)\n"), plain("Beads - Open & In Progress (10:00:00) now\n")},
			differ: [][2]side{
				{plain("Beads - Open & In Progress (10:00:00)\n○ test-a\n"), plain("Beads - Open & In Progress (10:00:01)\n○ test-b\n")},
				{plain("Beads - Open & In Progress (10:00:00)\n"), plain("Beads - Open (10:00:00)\n")},
			},
		},
		"watch-refresh-noise": {
			same: []samePair{
				{
					left:  plain("Watching for changes\nError refreshing issues: list: context canceled\n"),
					right: plain("Watching for changes\n"),
					want:  "Watching for changes\n",
				},
				{
					left:  plain("Error refreshing issues: search returned 2 rows\nError refreshing issues: search returned 2 rows\n"),
					right: plain("Error refreshing issues: search returned 2 rows\n"),
				},
			},
			kept: []side{
				plain("Error refreshing issues: search returned 2 rows\nWatching for changes\nError refreshing issues: search returned 2 rows\n"),
				plain("Error refreshing issues: context canceled by the user\n"),
				plain("Watching for changes\nWatching for changes\n"),
			},
			differ: [][2]side{
				{plain("Error refreshing issues: a\n"), plain("Error refreshing issues: b\n")},
				{plain("Watching for changes\nError refreshing issues: a\n"), plain("Watching for changes\n")},
			},
		},
		"json-compact": {
			same: []samePair{{
				left:  plain("{\n  \"error\": \"list is not available yet\",\n  \"schema_version\": 1\n}\n"),
				right: plain(`{"error":"list is not available yet","schema_version":1}`),
				want:  `{"error":"list is not available yet","schema_version":1}`,
			}},
			kept: []side{plain("Error: not json\n"), plain(`{"a":"\u003c","n":1.0}`), plain("{\"a\":1}\n{\"b\":2}\n")},
			differ: [][2]side{
				{plain(`{"a": "\u003c"}`), plain(`{"a": "<"}`)},
				{plain(`{"a": 1.0}`), plain(`{"a": 1}`)},
				{plain(`{"a": 1, "b": 2}`), plain(`{"b": 2, "a": 1}`)},
			},
		},
	}
}

func mustNormalize(t *testing.T, text, name string, options Options) string {
	t.Helper()
	output, err := normalize([]byte(text), []string{name}, options)
	if err != nil {
		t.Fatalf("%s: %v", name, err)
	}
	return string(output)
}

// withCarriageReturn puts a carriage return before the line feed that ends
// the line at the given index.
func withCarriageReturn(page string, index int) string {
	pageLines := strings.Split(page, "\n")
	pageLines[index] += "\r"
	return strings.Join(pageLines, "\n")
}

// swapNames swaps two cells of the same width on the thanks page.
func swapNames(page, first, second string) string {
	page = strings.Replace(page, first, "\x00", 1)
	page = strings.Replace(page, second, first, 1)
	return strings.Replace(page, "\x00", second, 1)
}

func TestEveryNormalizerHasItsContract(t *testing.T) {
	tests := normalizerTests(t)
	for _, normalizer := range declaredNormalizers {
		test, ok := tests[normalizer.Name]
		if !ok {
			t.Errorf("%s has no tests", normalizer.Name)
			continue
		}
		if len(test.same) == 0 || len(test.kept)+len(test.touched) == 0 || len(test.differ) == 0 {
			t.Errorf("%s needs same, kept or touched, and differ cases", normalizer.Name)
		}
	}
	for name := range tests {
		if _, ok := findNormalizer(name); !ok {
			t.Errorf("tests name an undeclared normalizer %s", name)
		}
	}
}

func TestNormalizerContracts(t *testing.T) {
	for name, test := range normalizerTests(t) {
		t.Run(name, func(t *testing.T) {
			run := func(input side) string {
				t.Helper()
				output, err := normalize([]byte(input.text), []string{name}, input.options)
				if err != nil {
					t.Fatalf("normalize %q: %v", input.text, err)
				}
				return string(output)
			}
			for _, pair := range test.same {
				left, right := run(pair.left), run(pair.right)
				if left != right {
					t.Errorf("declared values still differ:\n left: %q\nright: %q", left, right)
				}
				if pair.want != "" && left != pair.want {
					t.Errorf("normalized %q\n  got: %q\n want: %q", pair.left.text, left, pair.want)
				}
			}
			for _, input := range test.kept {
				if output := run(input); output != input.text {
					t.Errorf("changed a value that it does not declare:\n   in: %q\n  out: %q", input.text, output)
				}
			}
			for _, touched := range test.touched {
				if output := run(touched.in); output != touched.want {
					t.Errorf("rewrote more or less than its declared value:\n   in: %q\n  got: %q\n want: %q",
						touched.in.text, output, touched.want)
				}
			}
			for _, pair := range test.differ {
				if left, right := run(pair[0]), run(pair[1]); left == right {
					t.Errorf("hid a difference outside its declared value: both normalize to %q", left)
				}
			}
			for _, input := range test.rejected {
				_, err := normalize([]byte(input.text), []string{name}, input.options)
				if !errors.Is(err, errRejected) {
					t.Errorf("accepted %q: %v", input.text, err)
				}
			}
		})
	}
}
