package main

import (
	"database/sql"
	"errors"
	"fmt"
	"regexp"
	"slices"
	"sort"
	"strings"
	"time"

	"github.com/steveyegge/beads/internal/storage/rowid"
)

// The declared normalization rules. A comparison applies only the rules that
// its caller names, and a normalized view lists each one with its reason.
const (
	ruleCommitHash   = "commit-hash"
	ruleRunTime      = "run-time"
	ruleDerivedRowID = "derived-row-id"
	ruleRandomToken  = "random-token"
	ruleCommitAuthor = "commit-author"

	runTimeToken = "<run-time>"
	derivedToken = "<derived>"
	keptToken    = "<kept>"
	freshToken   = "<fresh>"
)

// declaredRules lists every rule, with the reason that justifies it, in the
// order that a normalized view lists them.
var declaredRules = []RuleNote{
	{
		Name: ruleCommitHash,
		Reason: "Dolt hashes a commit over its time and its parents' hashes, so the same logical commit made at another " +
			"moment gets another hash. Each hash becomes c<N>, the commit's place in the history (root first, by " +
			"generation); parents, branch heads, tags and any cell that holds a commit hash use the same name, so the " +
			"graph shape is still compared.",
	},
	{
		Name: ruleRunTime,
		Reason: "A write stamps the wall clock of its own run, and the two sides run at different moments. Each timestamp " +
			"inside the --since/--until window becomes <run-time>: in cells (Dolt datetimes, and RFC 3339 or Dolt text " +
			"inside text), in commit and tag dates and in commit messages. Timestamps outside the window, such as seed " +
			"rows or a time that a command copies, stay exact.",
	},
	{
		Name: ruleDerivedRowID,
		Reason: "Upstream derives the id of an events, wisp_events, comments, wisp_comments, compaction_snapshots or " +
			"issue_snapshots row from the row's content, created_at included (internal/storage/rowid), so a row written " +
			"at another moment gets another id. An id becomes <derived> only when it equals that derivation from its own " +
			"row's raw content; any other id stays exact. Rows of such a table then match by content.",
	},
	{
		Name: ruleRandomToken,
		Reason: "issues.row_lock and wisps.row_lock are random numbers that every mutating path rewrites (migration " +
			"0054). Creates and dependency writes store fresh random numbers under the local_metadata keys " +
			"issue-create/v1/<shard> and dependency-coordination/v1/<table>/<shard> to make concurrent writes " +
			"conflict (issueops.EnsureIssueIDAvailableInTx and TouchDependencyCoordinationTableInTx). Each such value " +
			"becomes <kept> when it equals the --baseline state's value for the same row, and <fresh> otherwise, so a " +
			"missing or an extra rewrite still shows.",
	},
	{
		Name: ruleCommitAuthor,
		Reason: "Server-mode commits take the committer from the machine's configuration, which differs between machines " +
			"and can hold a personal name. Each committer or tagger name and email pair becomes a<N>, in order of first " +
			"appearance from the root, so which commits share an author is still compared. Embedded fixtures commit as " +
			"fixed identities, so parity cases keep them exact.",
	},
}

// derivedIDColumns lists, for each table whose id upstream derives from the
// row, the frozen digest columns in digest order (auxRekeyTables in
// internal/storage/schema and issueops.InsertDerivedEvent).
var derivedIDColumns = map[string][]string{
	"events":               {"issue_id", "event_type", "actor", "old_value", "new_value", "comment", "created_at"},
	"wisp_events":          {"issue_id", "event_type", "actor", "old_value", "new_value", "comment", "created_at"},
	"comments":             {"issue_id", "author", "text", "created_at"},
	"wisp_comments":        {"issue_id", "author", "text", "created_at"},
	"compaction_snapshots": {"issue_id", "compaction_level", "snapshot_json", "created_at"},
	"issue_snapshots": {
		"issue_id", "snapshot_time", "compaction_level", "original_size", "compressed_size",
		"original_content", "archived_events",
	},
}

// randomTarget is one column of random values. When prefixes are set, only
// rows whose keyColumn starts with one of them hold random values.
type randomTarget struct {
	table, column, keyColumn string
	prefixes                 []string
}

var randomTargets = []randomTarget{
	{table: "issues", column: "row_lock"},
	{table: "wisps", column: "row_lock"},
	{table: "local_metadata", column: "value", keyColumn: "key", prefixes: []string{"issue-create/v1/", "dependency-coordination/v1/"}},
}

func (target randomTarget) holds(key *string) bool {
	if target.keyColumn == "" {
		return true
	}
	return key != nil && slices.ContainsFunc(target.prefixes, func(prefix string) bool { return strings.HasPrefix(*key, prefix) })
}

// Window is the span of wall-clock time in which the compared runs wrote.
type Window struct {
	Since time.Time `json:"since"`
	Until time.Time `json:"until"`
}

func (window Window) contains(moment time.Time) bool {
	return !moment.Before(window.Since) && !moment.After(window.Until)
}

// Options selects the rules of a normalized view and gives the inputs that
// some rules need.
type Options struct {
	Rules    []string
	Window   *Window
	Baseline *State
}

// parseRules reads a comma-separated list of rule names.
func parseRules(list string) ([]string, error) {
	var names []string
	for _, name := range strings.Split(list, ",") {
		name = strings.TrimSpace(name)
		if name == "" {
			continue
		}
		if !slices.ContainsFunc(declaredRules, func(rule RuleNote) bool { return rule.Name == name }) {
			return nil, fmt.Errorf("unknown rule %q (see the rules command)", name)
		}
		if slices.Contains(names, name) {
			return nil, fmt.Errorf("rule %q given twice", name)
		}
		names = append(names, name)
	}
	return names, nil
}

// normalize returns the normalized view of a raw state under the named rules.
// Each rule decides from the raw values, so the rules do not depend on one
// another's order. Without rules it returns the raw view unchanged.
func normalize(raw State, options Options) (State, error) {
	if len(raw.Rules) > 0 {
		return State{}, errors.New("normalize takes a raw state, not a normalized view")
	}
	enabled := make(map[string]bool, len(options.Rules))
	for _, name := range options.Rules {
		enabled[name] = true
	}
	if enabled[ruleRunTime] && options.Window == nil {
		return State{}, fmt.Errorf("rule %s needs --since and --until", ruleRunTime)
	}
	if options.Window != nil && options.Window.Since.After(options.Window.Until) {
		return State{}, errors.New("--since is after --until")
	}
	if enabled[ruleRandomToken] && options.Baseline == nil {
		return State{}, fmt.Errorf("rule %s needs --baseline", ruleRandomToken)
	}
	state := cloneState(raw)
	for _, rule := range declaredRules {
		if enabled[rule.Name] {
			state.Rules = append(state.Rules, rule)
		}
	}
	if enabled[ruleRunTime] {
		state.Window = options.Window
	}
	if enabled[ruleRandomToken] {
		applyRandomToken(&state, raw, *options.Baseline)
	}
	if enabled[ruleDerivedRowID] {
		applyDerivedRowID(&state, raw)
	}
	if enabled[ruleRunTime] {
		applyRunTime(&state, *options.Window)
	}
	if enabled[ruleCommitHash] {
		applyCommitHash(&state, raw)
	}
	if enabled[ruleCommitAuthor] {
		applyCommitAuthor(&state)
	}
	for index := range state.Tables {
		table := &state.Tables[index]
		if primaryKeyChanged(*table, raw.Tables[index]) {
			table.KeyedByContent = true
			sortRows(table.Rows)
		}
	}
	return state, nil
}

func cloneState(state State) State {
	clone := state
	clone.Rules = slices.Clone(state.Rules)
	clone.Tables = make([]Table, len(state.Tables))
	for index, table := range state.Tables {
		table.Columns = slices.Clone(table.Columns)
		table.PrimaryKey = slices.Clone(table.PrimaryKey)
		rows := make([][]*string, len(table.Rows))
		for rowIndex, row := range table.Rows {
			rows[rowIndex] = make([]*string, len(row))
			for cellIndex, cell := range row {
				if cell != nil {
					value := *cell
					rows[rowIndex][cellIndex] = &value
				}
			}
		}
		table.Rows = rows
		clone.Tables[index] = table
	}
	revision := state.Revision
	revision.Branches = slices.Clone(revision.Branches)
	revision.Tags = slices.Clone(revision.Tags)
	revision.Remotes = slices.Clone(revision.Remotes)
	revision.Commits = make([]Commit, len(state.Revision.Commits))
	for index, commit := range state.Revision.Commits {
		commit.Parents = slices.Clone(commit.Parents)
		commit.Tables = slices.Clone(commit.Tables)
		revision.Commits[index] = commit
	}
	revision.WorkingSet.Changes = slices.Clone(revision.WorkingSet.Changes)
	clone.Revision = revision
	return clone
}

// primaryKeyChanged reports whether a rule changed a primary-key cell, before
// the rows are sorted again.
func primaryKeyChanged(normalized, raw Table) bool {
	if len(normalized.PrimaryKey) == 0 {
		return false
	}
	indexes := keyColumns(raw)
	for rowIndex, row := range raw.Rows {
		for _, index := range indexes {
			if !sameCell(row[index], normalized.Rows[rowIndex][index]) {
				return true
			}
		}
	}
	return false
}

func findTable(state State, name string) (Table, bool) {
	for _, table := range state.Tables {
		if table.Name == name {
			return table, true
		}
	}
	return Table{}, false
}

func applyRandomToken(state *State, raw, baseline State) {
	for _, target := range randomTargets {
		for index, table := range raw.Tables {
			if table.Name != target.table {
				continue
			}
			column := columnIndex(table, target.column)
			keyColumn := columnIndex(table, target.keyColumn)
			if column < 0 || (target.keyColumn != "" && keyColumn < 0) {
				continue
			}
			before := make(map[string]*string)
			if baselineTable, ok := findTable(baseline, table.Name); ok {
				if baselineColumn := columnIndex(baselineTable, target.column); baselineColumn >= 0 {
					for _, row := range baselineTable.Rows {
						before[rowKey(baselineTable, row)] = row[baselineColumn]
					}
				}
			}
			for rowIndex, row := range table.Rows {
				if row[column] == nil {
					continue
				}
				if keyColumn >= 0 && !target.holds(row[keyColumn]) {
					continue
				}
				token := freshToken
				if previous, ok := before[rowKey(table, row)]; ok && sameCell(previous, row[column]) {
					token = keptToken
				}
				state.Tables[index].Rows[rowIndex][column] = &token
			}
		}
	}
}

func applyDerivedRowID(state *State, raw State) {
	for index, table := range raw.Tables {
		names, ok := derivedIDColumns[table.Name]
		idColumn := columnIndex(table, "id")
		if !ok || idColumn < 0 {
			continue
		}
		digestColumns := make([]int, len(names))
		for position, name := range names {
			if digestColumns[position] = columnIndex(table, name); digestColumns[position] < 0 {
				digestColumns = nil
				break
			}
		}
		if digestColumns == nil {
			continue
		}
		digests := make([]string, len(table.Rows))
		count := make(map[string]int)
		for rowIndex, row := range table.Rows {
			fields := make([]sql.NullString, len(digestColumns))
			for position, column := range digestColumns {
				if row[column] != nil {
					fields[position] = sql.NullString{String: *row[column], Valid: true}
				}
			}
			digests[rowIndex] = rowid.Digest(fields)
			count[digests[rowIndex]]++
		}
		// The n rows that share a digest hold ordinals 0..n-1. An id with a higher
		// ordinal, left by a deleted duplicate, stays exact.
		for rowIndex, row := range table.Rows {
			if row[idColumn] == nil {
				continue
			}
			for ordinal := 0; ordinal < count[digests[rowIndex]]; ordinal++ {
				if rowid.New(table.Name, ordinal, digests[rowIndex]) == *row[idColumn] {
					token := derivedToken
					state.Tables[index].Rows[rowIndex][idColumn] = &token
					break
				}
			}
		}
	}
}

// timestampPattern matches a Dolt datetime ("2006-01-02 15:04:05") or an
// RFC 3339 time, with an optional fraction and zone.
var timestampPattern = regexp.MustCompile(`\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})?`)

// replaceRunTimes replaces each timestamp of text inside the window. A
// timestamp without a zone is UTC, as upstream stores times; a match inside a
// longer run of digits is not a timestamp.
func replaceRunTimes(text string, window Window) string {
	matches := timestampPattern.FindAllStringSubmatchIndex(text, -1)
	if matches == nil {
		return text
	}
	var builder strings.Builder
	last := 0
	for _, match := range matches {
		start, end := match[0], match[1]
		if (start > 0 && isDigit(text[start-1])) || (end < len(text) && isDigit(text[end])) {
			continue
		}
		value := strings.Replace(text[start:end], " ", "T", 1)
		layout := "2006-01-02T15:04:05"
		if match[4] >= 0 {
			layout = time.RFC3339
		}
		moment, err := time.ParseInLocation(layout, value, time.UTC)
		if err != nil || !window.contains(moment) {
			continue
		}
		builder.WriteString(text[last:start])
		builder.WriteString(runTimeToken)
		last = end
	}
	builder.WriteString(text[last:])
	return builder.String()
}

func isDigit(character byte) bool {
	return character >= '0' && character <= '9'
}

func applyRunTime(state *State, window Window) {
	for _, table := range state.Tables {
		for _, row := range table.Rows {
			for index, cell := range row {
				if cell != nil {
					replaced := replaceRunTimes(*cell, window)
					row[index] = &replaced
				}
			}
		}
	}
	for index := range state.Revision.Commits {
		commit := &state.Revision.Commits[index]
		commit.Date = replaceRunTimes(commit.Date, window)
		commit.Message = replaceRunTimes(commit.Message, window)
	}
	for index := range state.Revision.Tags {
		tag := &state.Revision.Tags[index]
		tag.Date = replaceRunTimes(tag.Date, window)
		tag.Message = replaceRunTimes(tag.Message, window)
	}
}

// commitGenerations returns each commit's generation: 0 for a root, else one
// more than its highest parent's.
func commitGenerations(commits []Commit) map[string]int {
	parents := make(map[string][]string, len(commits))
	for _, commit := range commits {
		parents[commit.Hash] = commit.Parents
	}
	generation := make(map[string]int, len(commits))
	var visit func(hash string, depth int) int
	visit = func(hash string, depth int) int {
		if value, ok := generation[hash]; ok {
			return value
		}
		value := 0
		// A commit graph has no cycle; the depth bound only stops a malformed file.
		if depth <= len(commits) {
			for _, parent := range parents[hash] {
				value = max(value, visit(parent, depth+1)+1)
			}
		}
		generation[hash] = value
		return value
	}
	for _, commit := range commits {
		visit(commit.Hash, 0)
	}
	return generation
}

func applyCommitHash(state *State, raw State) {
	generation := commitGenerations(raw.Revision.Commits)
	commits := state.Revision.Commits
	order := make([]int, len(commits))
	for index := range order {
		order[index] = index
	}
	// Commits of one generation sort by their normalized content, then by raw
	// hash, so that only a true tie depends on the hash. No other rule changes
	// a hash, so the hashes here are still raw.
	sort.SliceStable(order, func(left, right int) bool {
		a, b := commits[order[left]], commits[order[right]]
		if generation[a.Hash] != generation[b.Hash] {
			return generation[a.Hash] < generation[b.Hash]
		}
		for _, pair := range [][2]string{{a.Message, b.Message}, {a.Committer, b.Committer}, {a.Email, b.Email}, {a.Date, b.Date}} {
			if pair[0] != pair[1] {
				return pair[0] < pair[1]
			}
		}
		return a.Hash < b.Hash
	})
	token := make(map[string]string, len(commits))
	for position, index := range order {
		token[commits[index].Hash] = fmt.Sprintf("c%d", position)
	}
	rename := func(hash string) string {
		if renamed, ok := token[hash]; ok {
			return renamed
		}
		return hash
	}
	sorted := make([]Commit, len(commits))
	for position, index := range order {
		commit := commits[index]
		commit.Hash = rename(commit.Hash)
		for parent := range commit.Parents {
			commit.Parents[parent] = rename(commit.Parents[parent])
		}
		sorted[position] = commit
	}
	state.Revision.Commits = sorted
	for index := range state.Revision.Branches {
		state.Revision.Branches[index].Head = rename(state.Revision.Branches[index].Head)
	}
	for index := range state.Revision.Tags {
		state.Revision.Tags[index].Commit = rename(state.Revision.Tags[index].Commit)
	}
	for _, table := range state.Tables {
		for _, row := range table.Rows {
			for index, cell := range row {
				if cell == nil {
					continue
				}
				if renamed, ok := token[*cell]; ok {
					row[index] = &renamed
				}
			}
		}
	}
}

func applyCommitAuthor(state *State) {
	author := make(map[[2]string]string)
	rename := func(name, email string) string {
		key := [2]string{name, email}
		if _, ok := author[key]; !ok {
			author[key] = fmt.Sprintf("a%d", len(author)+1)
		}
		return author[key]
	}
	for index := range state.Revision.Commits {
		commit := &state.Revision.Commits[index]
		commit.Committer = rename(commit.Committer, commit.Email)
		commit.Email = commit.Committer
	}
	for index := range state.Revision.Tags {
		tag := &state.Revision.Tags[index]
		tag.Tagger = rename(tag.Tagger, tag.Email)
		tag.Email = tag.Tagger
	}
}
