package main

import (
	"bytes"
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/steveyegge/beads/internal/storage/rowid"
)

func text(value string) *string { return &value }

// baseState is a small state with one issue, one event, one journal entry and a
// linear history of two commits on main.
func baseState() State {
	return State{
		Format:   stateFormat,
		Database: "test",
		Tables: []Table{
			{
				Name:       "bd_events_journal",
				Create:     "CREATE TABLE `bd_events_journal` (...)",
				Columns:    []Column{{Name: "seq", Type: "BIGINT"}, {Name: "op", Type: "VARCHAR"}, {Name: "issue_id", Type: "VARCHAR"}},
				PrimaryKey: []string{"seq"},
				Rows: [][]*string{
					{text("1"), text("create"), text("test-a")},
					{text("2"), text("update"), text("test-a")},
				},
			},
			{
				Name:       "events",
				Create:     "CREATE TABLE `events` (...)",
				Columns:    eventColumns(),
				PrimaryKey: []string{"id"},
				Rows: [][]*string{
					eventRow("events", "test-a", "created", "2026-08-20 10:00:00"),
				},
			},
			{
				Name:       "issues",
				Create:     "CREATE TABLE `issues` (...)",
				Columns:    []Column{{Name: "id", Type: "VARCHAR"}, {Name: "title", Type: "VARCHAR"}, {Name: "updated_at", Type: "DATETIME"}, {Name: "source_system", Type: "VARCHAR"}, {Name: "row_lock", Type: "BIGINT"}},
				PrimaryKey: []string{"id"},
				Rows: [][]*string{
					{text("test-a"), text("First"), text("2026-08-20 10:00:00"), text(""), text("17")},
					{text("test-b"), text("Second"), text("2026-08-20 11:00:00"), text(""), text("23")},
				},
			},
		},
		Revision: Revision{
			ActiveBranch: "main",
			Branches:     []Branch{{Name: "main", Head: "hash2"}},
			Commits: []Commit{
				{Hash: "hash1", Parents: []string{}, Committer: "beads", Email: "beads@local", Date: "2026-08-20 09:00:00", Message: "bd init", Tables: []TableChange{{Name: "config", Data: true}}},
				{Hash: "hash2", Parents: []string{"hash1"}, Committer: "beads", Email: "beads@local", Date: "2026-08-20 10:00:00", Message: "bd: create issue", Tables: []TableChange{{Name: "issues", Data: true}}},
			},
			WorkingSet: WorkingSet{Changes: []StatusChange{}},
		},
	}
}

func eventColumns() []Column {
	return []Column{
		{Name: "issue_id", Type: "VARCHAR"}, {Name: "event_type", Type: "VARCHAR"}, {Name: "actor", Type: "VARCHAR"},
		{Name: "old_value", Type: "LONGTEXT"}, {Name: "new_value", Type: "LONGTEXT"}, {Name: "comment", Type: "TEXT"},
		{Name: "created_at", Type: "DATETIME"}, {Name: "id", Type: "CHAR"},
	}
}

// eventRow builds an events row whose id is upstream's content-derived id.
func eventRow(table, issue, eventType, createdAt string) []*string {
	digest := rowid.Digest([]sql.NullString{
		{String: issue, Valid: true}, {String: eventType, Valid: true}, {String: "fixture", Valid: true},
		{}, {}, {}, {String: createdAt, Valid: true},
	})
	return []*string{text(issue), text(eventType), text("fixture"), nil, nil, nil, text(createdAt), text(rowid.New(table, 0, digest))}
}

func table(state *State, name string) *Table {
	for index := range state.Tables {
		if state.Tables[index].Name == name {
			return &state.Tables[index]
		}
	}
	panic("no table " + name)
}

func differenceText(differences []Difference) string {
	lines := make([]string, len(differences))
	for index, difference := range differences {
		lines[index] = difference.String()
	}
	return strings.Join(lines, "\n")
}

func requireDifference(t *testing.T, differences []Difference, want string) {
	t.Helper()
	if !strings.Contains(differenceText(differences), want) {
		t.Fatalf("differences do not report %q:\n%s", want, differenceText(differences))
	}
}

func mustNormalize(t *testing.T, state State, options Options) State {
	t.Helper()
	normalized, err := normalize(state, options)
	if err != nil {
		t.Fatal(err)
	}
	return normalized
}

func TestEqualStatesHaveNoDifferences(t *testing.T) {
	if differences := compare(baseState(), baseState()); len(differences) != 0 {
		t.Fatalf("equal states differ:\n%s", differenceText(differences))
	}
}

func TestReportsAnEventSequenceInAnotherOrder(t *testing.T) {
	right := baseState()
	journal := table(&right, "bd_events_journal")
	journal.Rows[0][1], journal.Rows[1][1] = journal.Rows[1][1], journal.Rows[0][1]
	differences := compare(baseState(), right)
	requireDifference(t, differences, `table bd_events_journal: row seq=1: column op: left "create", right "update"`)
}

func TestReportsAMissingEvent(t *testing.T) {
	right := baseState()
	table(&right, "events").Rows = nil
	differences := compare(baseState(), right)
	requireDifference(t, differences, "table events: row id=")
	requireDifference(t, differences, `only in left: issue_id="test-a" event_type="created"`)
}

func TestReportsAnExtraCommitAndAnotherMessage(t *testing.T) {
	right := baseState()
	right.Revision.Commits = append(right.Revision.Commits, Commit{
		Hash: "hash3", Parents: []string{"hash2"}, Committer: "beads", Email: "beads@local",
		Date: "2026-08-20 10:00:01", Message: "bd: update issue", Tables: []TableChange{{Name: "issues", Data: true}},
	})
	right.Revision.Branches[0].Head = "hash3"
	differences := compare(baseState(), right)
	requireDifference(t, differences, "revision: commits: count: left 2, right 3")
	requireDifference(t, differences, `revision: commit hash3: only in right: "bd: update issue"`)
	requireDifference(t, differences, `revision: branch main: head: left "hash2", right "hash3"`)

	renamed := baseState()
	renamed.Revision.Commits[1].Message = "bd: close issue"
	requireDifference(t, compare(baseState(), renamed), `revision: commit hash2: message: left "bd: create issue", right "bd: close issue"`)
}

func TestReportsAnotherWorkingSetDirtiness(t *testing.T) {
	right := baseState()
	right.Revision.WorkingSet = WorkingSet{Dirty: true, Changes: []StatusChange{{Table: "issues", Status: "modified"}}}
	differences := compare(baseState(), right)
	requireDifference(t, differences, "revision: working set: dirty: left false, right true")
	requireDifference(t, differences, "revision: working set: change only in right: issues (unstaged, modified)")
}

func TestReportsAnotherUpdatedAtAndAHiddenColumn(t *testing.T) {
	right := baseState()
	issues := table(&right, "issues")
	issues.Rows[0][2] = text("2026-08-20 10:00:01")
	issues.Rows[1][3] = text("elsewhere")
	differences := compare(baseState(), right)
	requireDifference(t, differences, `table issues: row id=test-a: column updated_at: left "2026-08-20 10:00:00", right "2026-08-20 10:00:01"`)
	requireDifference(t, differences, `table issues: row id=test-b: column source_system: left "", right "elsewhere"`)
}

func TestReportsSchemaAndTableDifferences(t *testing.T) {
	right := baseState()
	table(&right, "issues").Create = "CREATE TABLE `issues` (changed)"
	right.Tables = right.Tables[1:]
	differences := compare(baseState(), right)
	requireDifference(t, differences, "table bd_events_journal: only in left")
	requireDifference(t, differences, "table issues: create statement differs")
}

func TestUnknownAndIncompleteRulesAreRefused(t *testing.T) {
	if _, err := parseRules("commit-hash,bogus"); err == nil || !strings.Contains(err.Error(), `unknown rule "bogus"`) {
		t.Fatalf("err = %v, want the unknown-rule refusal", err)
	}
	if _, err := normalize(baseState(), Options{Rules: []string{ruleRunTime}}); err == nil || !strings.Contains(err.Error(), "needs --since and --until") {
		t.Fatalf("err = %v, want the missing-window refusal", err)
	}
	if _, err := normalize(baseState(), Options{Rules: []string{ruleRandomToken}}); err == nil || !strings.Contains(err.Error(), "needs --baseline") {
		t.Fatalf("err = %v, want the missing-baseline refusal", err)
	}
}

func TestNoRuleKeepsTheRawView(t *testing.T) {
	normalized := mustNormalize(t, baseState(), Options{})
	if len(normalized.Rules) != 0 {
		t.Fatalf("rules = %v, want none", normalized.Rules)
	}
	if differences := compare(baseState(), normalized); len(differences) != 0 {
		t.Fatalf("raw view changed:\n%s", differenceText(differences))
	}
}

func TestNormalizedViewDeclaresEachRuleWithItsReason(t *testing.T) {
	normalized := mustNormalize(t, baseState(), Options{Rules: []string{ruleCommitHash, ruleDerivedRowID}})
	if len(normalized.Rules) != 2 || normalized.Rules[0].Name != ruleCommitHash || normalized.Rules[1].Name != ruleDerivedRowID {
		t.Fatalf("rules = %+v, want commit-hash and derived-row-id in that order", normalized.Rules)
	}
	for _, rule := range normalized.Rules {
		if strings.TrimSpace(rule.Reason) == "" {
			t.Fatalf("rule %s has no reason", rule.Name)
		}
	}
}

func window(t *testing.T) *Window {
	t.Helper()
	since, err := time.Parse(time.RFC3339, "2026-11-26T15:00:00Z")
	if err != nil {
		t.Fatal(err)
	}
	return &Window{Since: since, Until: since.Add(10 * time.Second)}
}

func TestRunTimeReplacesOnlyTimestampsInsideTheWindow(t *testing.T) {
	state := baseState()
	issues := table(&state, "issues")
	issues.Rows[0][2] = text("2026-11-26 15:00:05")
	issues.Rows[1][1] = text(`{"at":"2026-11-26T09:00:03-06:00","seed":"2026-08-20T10:00:00Z"}`)
	state.Revision.Commits[1].Date = "2026-11-26 15:00:09.123"
	normalized := mustNormalize(t, state, Options{Rules: []string{ruleRunTime}, Window: window(t)})
	got := table(&normalized, "issues")
	if *got.Rows[0][2] != runTimeToken {
		t.Fatalf("in-window datetime = %q, want %s", *got.Rows[0][2], runTimeToken)
	}
	if want := `{"at":"<run-time>","seed":"2026-08-20T10:00:00Z"}`; *got.Rows[1][1] != want {
		t.Fatalf("text = %q, want %q", *got.Rows[1][1], want)
	}
	if *got.Rows[1][2] != "2026-08-20 11:00:00" {
		t.Fatalf("seed datetime changed to %q", *got.Rows[1][2])
	}
	if normalized.Revision.Commits[1].Date != runTimeToken || normalized.Revision.Commits[0].Date != "2026-08-20 09:00:00" {
		t.Fatalf("commit dates = %q, %q", normalized.Revision.Commits[0].Date, normalized.Revision.Commits[1].Date)
	}
}

func TestCommitHashKeepsTheGraphShape(t *testing.T) {
	left := baseState()
	right := baseState()
	for index := range right.Revision.Commits {
		right.Revision.Commits[index].Hash = "other" + right.Revision.Commits[index].Hash
	}
	right.Revision.Commits[1].Parents = []string{"otherhash1"}
	right.Revision.Branches[0].Head = "otherhash2"
	table(&right, "issues").Rows[0][1] = text("otherhash2")
	table(&left, "issues").Rows[0][1] = text("hash2")
	options := Options{Rules: []string{ruleCommitHash}}
	if differences := compare(left, right); len(differences) == 0 {
		t.Fatal("raw states with other hashes compare equal")
	}
	normalizedLeft, normalizedRight := mustNormalize(t, left, options), mustNormalize(t, right, options)
	if differences := compare(normalizedLeft, normalizedRight); len(differences) != 0 {
		t.Fatalf("normalized states differ:\n%s", differenceText(differences))
	}
	if normalizedLeft.Revision.Branches[0].Head != "c1" || normalizedLeft.Revision.Commits[1].Parents[0] != "c0" {
		t.Fatalf("revision = %+v", normalizedLeft.Revision)
	}

	// A merge commit is another shape, even with the same messages.
	merged := baseState()
	merged.Revision.Commits = append([]Commit{{Hash: "side", Parents: []string{}, Message: "side root"}}, merged.Revision.Commits...)
	merged.Revision.Commits[2].Parents = []string{"hash1", "side"}
	single := baseState()
	single.Revision.Commits = append([]Commit{{Hash: "side", Parents: []string{}, Message: "side root"}}, single.Revision.Commits...)
	requireDifference(t, compare(mustNormalize(t, single, options), mustNormalize(t, merged, options)), "parents")
}

func TestDerivedRowIDReplacesOnlyAVerifiedID(t *testing.T) {
	left := baseState()
	right := baseState()
	table(&left, "events").Rows = [][]*string{eventRow("events", "test-a", "updated", "2026-11-26 15:00:02")}
	table(&right, "events").Rows = [][]*string{eventRow("events", "test-a", "updated", "2026-11-26 15:00:07")}
	options := Options{Rules: []string{ruleRunTime, ruleDerivedRowID}, Window: window(t)}
	if differences := compare(mustNormalize(t, left, options), mustNormalize(t, right, options)); len(differences) != 0 {
		t.Fatalf("events written at other moments differ:\n%s", differenceText(differences))
	}
	// An id that is not the derivation of its row stays exact.
	forged := baseState()
	table(&forged, "events").Rows[0][7] = text("00000000-0000-5000-8000-000000000000")
	normalized := mustNormalize(t, forged, Options{Rules: []string{ruleDerivedRowID}})
	if got := *table(&normalized, "events").Rows[0][7]; got != "00000000-0000-5000-8000-000000000000" {
		t.Fatalf("forged id = %q, want it kept", got)
	}
	requireDifference(t, compare(mustNormalize(t, baseState(), Options{Rules: []string{ruleDerivedRowID}}), normalized), "table events")

	// A side without derived rows still compares its rows by content.
	empty := baseState()
	table(&empty, "events").Rows = nil
	differences := compare(mustNormalize(t, baseState(), Options{Rules: []string{ruleDerivedRowID}}), mustNormalize(t, empty, Options{Rules: []string{ruleDerivedRowID}}))
	requireDifference(t, differences, `table events: row with this content: only in left: issue_id="test-a" event_type="created"`)
}

func TestRandomTokenComparesWithTheBaseline(t *testing.T) {
	baseline := baseState()
	left := baseState()
	right := baseState()
	table(&left, "issues").Rows[0][4] = text("99")
	table(&right, "issues").Rows[0][4] = text("98")
	options := Options{Rules: []string{ruleRandomToken}, Baseline: &baseline}
	normalizedLeft := mustNormalize(t, left, options)
	if got := table(&normalizedLeft, "issues").Rows; *got[0][4] != freshToken || *got[1][4] != keptToken {
		t.Fatalf("row_lock = %q, %q", *got[0][4], *got[1][4])
	}
	if differences := compare(normalizedLeft, mustNormalize(t, right, options)); len(differences) != 0 {
		t.Fatalf("two fresh row locks differ:\n%s", differenceText(differences))
	}
	// A write that forgets to rewrite the lock still shows.
	requireDifference(t, compare(normalizedLeft, mustNormalize(t, baseState(), options)), `column row_lock: left "<fresh>", right "<kept>"`)
}

func TestRandomTokenCoversOnlyTheCoordinationKeys(t *testing.T) {
	withMetadata := func(create, dependency, version string) State {
		state := baseState()
		state.Tables = append(state.Tables, Table{
			Name:       "local_metadata",
			Columns:    []Column{{Name: "key", Type: "VARCHAR"}, {Name: "value", Type: "TEXT"}},
			PrimaryKey: []string{"key"},
			Rows: [][]*string{
				{text("bd_version"), text(version)},
				{text("dependency-coordination/v1/dependencies/65e"), text(dependency)},
				{text("issue-create/v1/360"), text(create)},
			},
		})
		return state
	}
	baseline := withMetadata("1", "2", "1.2.1")
	options := Options{Rules: []string{ruleRandomToken}, Baseline: &baseline}
	left := mustNormalize(t, withMetadata("1", "5", "1.2.1"), options)
	if differences := compare(left, mustNormalize(t, withMetadata("1", "6", "1.2.1"), options)); len(differences) != 0 {
		t.Fatalf("two fresh coordination values differ:\n%s", differenceText(differences))
	}
	rows := table(&left, "local_metadata").Rows
	if *rows[0][1] != "1.2.1" || *rows[1][1] != freshToken || *rows[2][1] != keptToken {
		t.Fatalf("local_metadata values = %q, %q, %q", *rows[0][1], *rows[1][1], *rows[2][1])
	}
	requireDifference(t, compare(left, mustNormalize(t, withMetadata("1", "5", "1.3.0"), options)), `row key=bd_version: column value: left "1.2.1", right "1.3.0"`)
}

func TestStateRoundTripsThroughJSON(t *testing.T) {
	var buffer bytes.Buffer
	if err := writeState(&buffer, baseState()); err != nil {
		t.Fatal(err)
	}
	read, err := readState(&buffer)
	if err != nil {
		t.Fatal(err)
	}
	if differences := compare(baseState(), read); len(differences) != 0 {
		t.Fatalf("round trip changed the state:\n%s", differenceText(differences))
	}
}

func writeStateFile(t *testing.T, state State) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "state.json")
	var buffer bytes.Buffer
	if err := writeState(&buffer, state); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, buffer.Bytes(), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestCompareCommandExitsByResult(t *testing.T) {
	left := writeStateFile(t, baseState())
	renamed := baseState()
	renamed.Revision.Commits[1].Date = "2026-11-26T15:00:05.9Z"
	right := writeStateFile(t, renamed)
	for _, test := range []struct {
		arguments []string
		status    int
		output    string
	}{
		{[]string{"compare", left, left}, 0, ""},
		{[]string{"compare", left, right}, 1, "logical state differs: 1 difference (rules: none)"},
		{[]string{"compare", "--rules", "bogus", left, right}, 2, `unknown rule "bogus"`},
		{[]string{"compare", left}, 2, "compare takes 2 state files"},
		{[]string{"rules"}, 0, "derived-row-id\n  Upstream derives"},
	} {
		var stdout, stderr bytes.Buffer
		if status := run(context.Background(), test.arguments, &stdout, &stderr); status != test.status ||
			!strings.Contains(stdout.String()+stderr.String(), test.output) {
			t.Fatalf("run(%q) = %d\n%s%s\nwant %d and %q", test.arguments, status, stdout.String(), stderr.String(), test.status, test.output)
		}
	}
}

func TestRunWindowHoldsWholeSecondsAndTheRoundedNextSecond(t *testing.T) {
	state := baseState()
	state.Revision.Commits[1].Date = "2026-11-26T15:00:05.9Z"
	issues := table(&state, "issues")
	// Dolt stores a time stamped at 15:00:05.6 as 15:00:06.
	issues.Rows[0][2] = text("2026-11-26 15:00:06")
	issues.Rows[1][2] = text("2026-11-26 15:00:07")
	path := writeStateFile(t, state)
	var stdout, stderr bytes.Buffer
	arguments := []string{"normalize", "--rules", "run-time", "--since", "2026-11-26T15:00:01Z", "--until", "2026-11-26T15:00:05Z", path}
	if status := run(context.Background(), arguments, &stdout, &stderr); status != 0 {
		t.Fatalf("normalize exited %d: %s", status, stderr.String())
	}
	normalized, err := readState(&stdout)
	if err != nil {
		t.Fatal(err)
	}
	if got := normalized.Revision.Commits[1].Date; got != runTimeToken {
		t.Fatalf("a date in the --until second = %q, want %s", got, runTimeToken)
	}
	rows := table(&normalized, "issues").Rows
	if *rows[0][2] != runTimeToken || *rows[1][2] != "2026-11-26 15:00:07" {
		t.Fatalf("rounded datetimes = %q, %q; want %s and the later one kept", *rows[0][2], *rows[1][2], runTimeToken)
	}
}

func TestExportRefusesAWorkspaceWithoutTheDisposableMarker(t *testing.T) {
	workspace := t.TempDir()
	if err := os.MkdirAll(filepath.Join(workspace, ".beads"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(workspace, ".beads", "metadata.json"), []byte(`{"dolt_mode":"embedded","dolt_database":"test"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := export(context.Background(), workspace); err == nil || !strings.Contains(err.Error(), "no .beadshx-disposable-fixture marker") {
		t.Fatalf("err = %v, want the missing-marker refusal", err)
	}
}
