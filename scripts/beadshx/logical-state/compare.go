package main

import (
	"encoding/json"
	"fmt"
	"io"
	"slices"
	"sort"
	"strconv"
	"strings"
)

// Difference is one way in which two states differ: where (a table, row and
// column, or a revision item) and how.
type Difference struct {
	Path   string
	Detail string
}

func (difference Difference) String() string {
	return difference.Path + ": " + difference.Detail
}

// compare lists every difference between two states of the same view, tables
// first, in the left state's order.
func compare(left, right State) []Difference {
	var differences []Difference
	add := func(path, format string, arguments ...any) {
		differences = append(differences, Difference{Path: path, Detail: fmt.Sprintf(format, arguments...)})
	}
	if left.Database != right.Database {
		add("database", "left %s, right %s", quote(left.Database), quote(right.Database))
	}
	if leftRules, rightRules := ruleNames(left.Rules), ruleNames(right.Rules); leftRules != rightRules {
		add("rules", "left [%s], right [%s]", leftRules, rightRules)
	}
	differences = append(differences, compareTables(left.Tables, right.Tables)...)
	differences = append(differences, compareRevisions(left.Revision, right.Revision)...)
	return differences
}

func ruleNames(rules []RuleNote) string {
	names := make([]string, len(rules))
	for index, rule := range rules {
		names[index] = rule.Name
	}
	return strings.Join(names, ", ")
}

func quote(value string) string {
	return strconv.Quote(value)
}

func quoteCell(cell *string) string {
	if cell == nil {
		return "NULL"
	}
	return quote(*cell)
}

func compareTables(left, right []Table) []Difference {
	var differences []Difference
	compareNamed(left, right, func(table Table) string { return table.Name },
		func(name, side string) {
			differences = append(differences, Difference{Path: "table " + name, Detail: "only in " + side})
		},
		func(_ string, leftTable, rightTable Table) {
			differences = append(differences, compareTable(leftTable, rightTable)...)
		})
	return differences
}

func compareTable(left, right Table) []Difference {
	path := "table " + left.Name
	var differences []Difference
	add := func(path, format string, arguments ...any) {
		differences = append(differences, Difference{Path: path, Detail: fmt.Sprintf(format, arguments...)})
	}
	if left.Create != right.Create {
		add(path, "create statement differs:\n    left:  %s\n    right: %s", quote(left.Create), quote(right.Create))
	}
	if leftColumns, rightColumns := columnList(left.Columns), columnList(right.Columns); leftColumns != rightColumns {
		add(path, "columns: left [%s], right [%s]", leftColumns, rightColumns)
	}
	if !slices.Equal(left.PrimaryKey, right.PrimaryKey) {
		add(path, "primary key: left [%s], right [%s]", strings.Join(left.PrimaryKey, ", "), strings.Join(right.PrimaryKey, ", "))
	}
	// When a rule rewrote a key cell on either side, rows match by content on
	// both. Rows match by key, and their cells by column name, so a column
	// that only one side has is reported once, above.
	byContent := left.KeyedByContent || right.KeyedByContent
	left.KeyedByContent, right.KeyedByContent = byContent, byContent
	rightRows := make(map[string][][]*string, len(right.Rows))
	for _, row := range right.Rows {
		key := rowKey(right, row)
		rightRows[key] = append(rightRows[key], row)
	}
	rightColumn := make(map[string]int, len(right.Columns))
	for index, column := range right.Columns {
		rightColumn[column.Name] = index
	}
	for _, leftRow := range left.Rows {
		key := rowKey(left, leftRow)
		rowPath := path + ": row " + rowLabel(left, leftRow)
		matches := rightRows[key]
		if len(matches) == 0 {
			add(rowPath, "%s", onlyIn("left", rowContent(left, leftRow)))
			continue
		}
		rightRow := matches[0]
		rightRows[key] = matches[1:]
		for index, column := range left.Columns {
			rightIndex, ok := rightColumn[column.Name]
			if ok && !sameCell(leftRow[index], rightRow[rightIndex]) {
				add(rowPath+": column "+column.Name, "left %s, right %s", quoteCell(leftRow[index]), quoteCell(rightRow[rightIndex]))
			}
		}
	}
	for _, rightRow := range right.Rows {
		key := rowKey(right, rightRow)
		if matches := rightRows[key]; len(matches) > 0 {
			rightRows[key] = matches[1:]
			add(path+": row "+rowLabel(right, rightRow), "%s", onlyIn("right", rowContent(right, rightRow)))
		}
	}
	return differences
}

func onlyIn(side, content string) string {
	if content == "" {
		return "only in " + side
	}
	return "only in " + side + ": " + content
}

func columnList(columns []Column) string {
	names := make([]string, len(columns))
	for index, column := range columns {
		names[index] = column.Name + " " + column.Type
	}
	return strings.Join(names, ", ")
}

func sameCell(left, right *string) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return *left == *right
}

// keyColumns returns the indexes of the cells that identify a row: the
// primary key, or every column when the table has none or when a rule changed
// a key cell.
func keyColumns(table Table) []int {
	if !table.KeyedByContent && len(table.PrimaryKey) > 0 {
		indexes := make([]int, 0, len(table.PrimaryKey))
		for _, name := range table.PrimaryKey {
			if index := columnIndex(table, name); index >= 0 {
				indexes = append(indexes, index)
			}
		}
		if len(indexes) == len(table.PrimaryKey) {
			return indexes
		}
	}
	indexes := make([]int, len(table.Columns))
	for index := range indexes {
		indexes[index] = index
	}
	return indexes
}

func columnIndex(table Table, name string) int {
	for index, column := range table.Columns {
		if column.Name == name {
			return index
		}
	}
	return -1
}

func keyedByPrimaryKey(table Table) bool {
	return len(keyColumns(table)) == len(table.PrimaryKey) && len(table.PrimaryKey) > 0 && !table.KeyedByContent
}

func rowKey(table Table, row []*string) string {
	indexes := keyColumns(table)
	cells := make([]*string, len(indexes))
	for position, index := range indexes {
		cells[position] = row[index]
	}
	// Marshaling strings and nulls cannot fail.
	key, _ := json.Marshal(cells)
	return string(key)
}

// rowLabel names a row by its primary key as name=value pairs.
func rowLabel(table Table, row []*string) string {
	if !keyedByPrimaryKey(table) {
		return "with this content"
	}
	indexes := keyColumns(table)
	parts := make([]string, len(indexes))
	for position, index := range indexes {
		value := "NULL"
		if row[index] != nil {
			value = *row[index]
		}
		parts[position] = table.Columns[index].Name + "=" + value
	}
	return strings.Join(parts, ", ")
}

// rowContent prints the cells of a row that are neither NULL nor empty, as
// column="value" pairs, leaving out the primary key that its label names.
func rowContent(table Table, row []*string) string {
	label := make(map[int]bool)
	if keyedByPrimaryKey(table) {
		for _, index := range keyColumns(table) {
			label[index] = true
		}
	}
	parts := make([]string, 0, len(row))
	for index, cell := range row {
		if label[index] || cell == nil || *cell == "" {
			continue
		}
		value := *cell
		if len(value) > 120 {
			value = value[:117] + "..."
		}
		parts = append(parts, table.Columns[index].Name+"="+quote(value))
	}
	return strings.Join(parts, " ")
}

func compareRevisions(left, right Revision) []Difference {
	var differences []Difference
	add := func(path, format string, arguments ...any) {
		differences = append(differences, Difference{Path: "revision: " + path, Detail: fmt.Sprintf(format, arguments...)})
	}
	if left.ActiveBranch != right.ActiveBranch {
		add("active branch", "left %s, right %s", quote(left.ActiveBranch), quote(right.ActiveBranch))
	}
	compareNamed(left.Branches, right.Branches, func(branch Branch) string { return branch.Name },
		func(name, side string) { add("branch "+name, "only in %s", side) },
		func(name string, leftBranch, rightBranch Branch) {
			if leftBranch.Head != rightBranch.Head {
				add("branch "+name, "head: left %s, right %s", quote(leftBranch.Head), quote(rightBranch.Head))
			}
		})
	compareNamed(left.Tags, right.Tags, func(tag Tag) string { return tag.Name },
		func(name, side string) { add("tag "+name, "only in %s", side) },
		func(name string, leftTag, rightTag Tag) {
			if leftTag != rightTag {
				add("tag "+name, "left %+v, right %+v", leftTag, rightTag)
			}
		})
	compareNamed(left.Remotes, right.Remotes, func(remote Remote) string { return remote.Name },
		func(name, side string) { add("remote "+name, "only in %s", side) },
		func(name string, leftRemote, rightRemote Remote) {
			if leftRemote.URL != rightRemote.URL {
				add("remote "+name, "url: left %s, right %s", quote(leftRemote.URL), quote(rightRemote.URL))
			}
		})
	if len(left.Commits) != len(right.Commits) {
		add("commits", "count: left %d, right %d", len(left.Commits), len(right.Commits))
	}
	message := make(map[string]string, len(left.Commits)+len(right.Commits))
	for _, commit := range append(slices.Clone(left.Commits), right.Commits...) {
		message[commit.Hash] = commit.Message
	}
	compareNamed(left.Commits, right.Commits, func(commit Commit) string { return commit.Hash },
		func(hash, side string) { add("commit "+hash, "only in %s: %s", side, quote(message[hash])) },
		func(hash string, leftCommit, rightCommit Commit) {
			path := "commit " + hash
			if !slices.Equal(leftCommit.Parents, rightCommit.Parents) {
				add(path, "parents: left [%s], right [%s]", strings.Join(leftCommit.Parents, ", "), strings.Join(rightCommit.Parents, ", "))
			}
			for _, field := range []struct{ name, left, right string }{
				{"committer", leftCommit.Committer, rightCommit.Committer},
				{"email", leftCommit.Email, rightCommit.Email},
				{"date", leftCommit.Date, rightCommit.Date},
				{"message", leftCommit.Message, rightCommit.Message},
			} {
				if field.left != field.right {
					add(path, "%s: left %s, right %s", field.name, quote(field.left), quote(field.right))
				}
			}
			if leftTables, rightTables := changeList(leftCommit.Tables), changeList(rightCommit.Tables); leftTables != rightTables {
				add(path, "changed tables: left [%s], right [%s]", leftTables, rightTables)
			}
		})
	if left.WorkingSet.Dirty != right.WorkingSet.Dirty {
		add("working set", "dirty: left %t, right %t", left.WorkingSet.Dirty, right.WorkingSet.Dirty)
	}
	statusKey := func(change StatusChange) string {
		staged := "unstaged"
		if change.Staged {
			staged = "staged"
		}
		return change.Table + " (" + staged + ", " + change.Status + ")"
	}
	compareNamed(left.WorkingSet.Changes, right.WorkingSet.Changes, statusKey,
		func(key, side string) { add("working set", "change only in %s: %s", side, key) },
		func(string, StatusChange, StatusChange) {})
	return differences
}

func changeList(changes []TableChange) string {
	parts := make([]string, len(changes))
	for index, change := range changes {
		kind := make([]string, 0, 2)
		if change.Data {
			kind = append(kind, "data")
		}
		if change.Schema {
			kind = append(kind, "schema")
		}
		parts[index] = change.Name + " (" + strings.Join(kind, ", ") + ")"
	}
	return strings.Join(parts, ", ")
}

// compareNamed matches two lists by name. It calls only for each name that
// one list lacks, left names first and each list in its own order, and both
// for each name that the lists share.
func compareNamed[T any](left, right []T, name func(T) string, only func(name, side string), both func(name string, left, right T)) {
	rightItems := make(map[string]T, len(right))
	for _, item := range right {
		rightItems[name(item)] = item
	}
	leftNames := make(map[string]bool, len(left))
	for _, item := range left {
		key := name(item)
		leftNames[key] = true
		if rightItem, ok := rightItems[key]; ok {
			both(key, item, rightItem)
		} else {
			only(key, "left")
		}
	}
	for _, item := range right {
		if key := name(item); !leftNames[key] {
			only(key, "right")
		}
	}
}

// writeReport prints a summary line and at most limit differences (all of
// them when limit is 0). It prints nothing for equal states.
func writeReport(output io.Writer, differences []Difference, rules []RuleNote, limit int) error {
	if len(differences) == 0 {
		return nil
	}
	applied := "none"
	if len(rules) > 0 {
		applied = ruleNames(rules)
	}
	noun := "differences"
	if len(differences) == 1 {
		noun = "difference"
	}
	if _, err := fmt.Fprintf(output, "logical state differs: %d %s (rules: %s)\n", len(differences), noun, applied); err != nil {
		return err
	}
	shown := differences
	if limit > 0 && len(shown) > limit {
		shown = shown[:limit]
	}
	for _, difference := range shown {
		if _, err := fmt.Fprintf(output, "  %s\n", difference); err != nil {
			return err
		}
	}
	if hidden := len(differences) - len(shown); hidden > 0 {
		if _, err := fmt.Fprintf(output, "  ... %d more\n", hidden); err != nil {
			return err
		}
	}
	return nil
}

// sortRows sorts rows by every cell, NULL first.
func sortRows(rows [][]*string) {
	sort.SliceStable(rows, func(left, right int) bool {
		for index := range rows[left] {
			a, b := rows[left][index], rows[right][index]
			switch {
			case a == nil && b == nil:
				continue
			case a == nil:
				return true
			case b == nil:
				return false
			case *a != *b:
				return *a < *b
			}
		}
		return false
	})
}
