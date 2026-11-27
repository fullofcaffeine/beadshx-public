package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/steveyegge/beads/internal/storage/embeddeddolt"
)

const fixtureMarker = ".beadshx-disposable-fixture"

// systemTables lists the Dolt system tables that hold versioned schema or
// configuration, with the columns that identify a row. dolt_schemas holds the
// views, triggers and events.
var systemTables = []struct {
	name string
	key  []string
}{
	{name: "dolt_docs", key: []string{"doc_name"}},
	{name: "dolt_ignore", key: []string{"pattern"}},
	{name: "dolt_nonlocal_tables", key: []string{"table_name"}},
	{name: "dolt_procedures", key: []string{"name"}},
	{name: "dolt_schemas", key: []string{"type", "name"}},
}

// fixtureDatabase returns the embedded database name of a marked disposable
// workspace, or an error that names the missing safety condition.
func fixtureDatabase(workspace string) (string, error) {
	if _, err := os.Stat(filepath.Join(workspace, fixtureMarker)); err != nil {
		return "", fmt.Errorf("refusing %s: no %s marker", workspace, fixtureMarker)
	}
	//nolint:gosec // G304: the path is the caller's own fixture, which passed the marker check above.
	data, err := os.ReadFile(filepath.Join(workspace, ".beads", "metadata.json"))
	if err != nil {
		return "", fmt.Errorf("read fixture metadata: %w", err)
	}
	var metadata struct {
		Mode     string `json:"dolt_mode"`
		Database string `json:"dolt_database"`
	}
	if err := json.Unmarshal(data, &metadata); err != nil {
		return "", fmt.Errorf("parse fixture metadata: %w", err)
	}
	if metadata.Mode != "embedded" || metadata.Database == "" {
		return "", fmt.Errorf("refusing %s: not an embedded fixture", workspace)
	}
	return metadata.Database, nil
}

// export reads the raw logical state of a marked disposable fixture's
// embedded database in one read-only transaction, which it rolls back. Like
// upstream's own read-only stores, it opens the database with
// embeddeddolt.OpenSQL; Dolt may still rewrite derived files such as its
// journal index, but no table, schema or revision changes.
func export(ctx context.Context, workspace string) (state State, err error) {
	database, err := fixtureDatabase(workspace)
	if err != nil {
		return State{}, err
	}
	db, cleanup, err := embeddeddolt.OpenSQL(ctx, filepath.Join(workspace, ".beads", "embeddeddolt"), database, "main")
	if err != nil {
		return State{}, fmt.Errorf("open fixture database: %w", err)
	}
	defer func() { err = errors.Join(err, cleanup()) }()
	tx, err := db.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return State{}, fmt.Errorf("begin: %w", err)
	}
	defer func() { err = errors.Join(err, tx.Rollback()) }()
	reader := stateReader{ctx: ctx, tx: tx}
	state = State{Format: stateFormat, Database: database, Rules: []RuleNote{}}
	if state.Tables, err = reader.tables(); err != nil {
		return State{}, err
	}
	if state.Revision, err = reader.revision(); err != nil {
		return State{}, err
	}
	return state, nil
}

type stateReader struct {
	ctx context.Context
	tx  *sql.Tx
}

// query runs one read and returns its rows as text cells, nil for NULL. It
// refuses a cell that is not UTF-8 text, which JSON could not keep exact.
//
// The statements interpolate only identifiers that the database itself or the
// fixed systemTables list names, each quoted by quoteIdentifier.
func (reader stateReader) query(statement string) ([][]*string, error) {
	rows, err := reader.tx.QueryContext(reader.ctx, statement)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", statement, err)
	}
	defer rows.Close()
	columns, err := rows.Columns()
	if err != nil {
		return nil, fmt.Errorf("%s: %w", statement, err)
	}
	var result [][]*string
	for rows.Next() {
		values := make([]sql.NullString, len(columns))
		destinations := make([]any, len(columns))
		for index := range values {
			destinations[index] = &values[index]
		}
		if err := rows.Scan(destinations...); err != nil {
			return nil, fmt.Errorf("%s: %w", statement, err)
		}
		cells := make([]*string, len(values))
		for index, value := range values {
			if value.Valid {
				if !utf8.ValidString(value.String) {
					return nil, fmt.Errorf("%s: column %s holds bytes that are not UTF-8 text", statement, columns[index])
				}
				text := value.String
				cells[index] = &text
			}
		}
		result = append(result, cells)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("%s: %w", statement, err)
	}
	return result, nil
}

// utcTime turns a Dolt commit or tag date, which the driver renders as an RFC
// 3339 time in the process's local zone, into the same instant in UTC, the
// zone of upstream's own stored times.
func utcTime(cell *string) (string, error) {
	moment, err := time.Parse(time.RFC3339Nano, cellText(cell))
	if err != nil {
		return "", fmt.Errorf("revision date: %w", err)
	}
	return moment.UTC().Format(time.RFC3339Nano), nil
}

func cellText(cell *string) string {
	if cell == nil {
		return ""
	}
	return *cell
}

func quoteIdentifier(name string) string {
	return "`" + strings.ReplaceAll(name, "`", "``") + "`"
}

// tables reads every base table of the database and the declared system
// tables, sorted by name.
func (reader stateReader) tables() ([]Table, error) {
	names, err := reader.query("SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE' ORDER BY table_name")
	if err != nil {
		return nil, err
	}
	columnRows, err := reader.query("SELECT table_name, column_name, column_type FROM information_schema.columns WHERE table_schema = DATABASE() ORDER BY table_name, ordinal_position")
	if err != nil {
		return nil, err
	}
	keyRows, err := reader.query("SELECT table_name, column_name FROM information_schema.key_column_usage WHERE table_schema = DATABASE() AND constraint_name = 'PRIMARY' ORDER BY table_name, ordinal_position")
	if err != nil {
		return nil, err
	}
	columns := make(map[string][]Column)
	for _, row := range columnRows {
		columns[cellText(row[0])] = append(columns[cellText(row[0])], Column{Name: cellText(row[1]), Type: cellText(row[2])})
	}
	keys := make(map[string][]string)
	for _, row := range keyRows {
		keys[cellText(row[0])] = append(keys[cellText(row[0])], cellText(row[1]))
	}
	tables := make([]Table, 0, len(names)+len(systemTables))
	for _, row := range names {
		name := cellText(row[0])
		create, err := reader.query("SHOW CREATE TABLE " + quoteIdentifier(name))
		if err != nil {
			return nil, err
		}
		if len(create) != 1 || len(create[0]) < 2 {
			return nil, fmt.Errorf("SHOW CREATE TABLE %s: unexpected result", name)
		}
		table := Table{Name: name, Create: cellText(create[0][1]), Columns: columns[name], PrimaryKey: keys[name]}
		if table.PrimaryKey == nil {
			table.PrimaryKey = []string{}
		}
		if table.Rows, err = reader.rows(table); err != nil {
			return nil, err
		}
		tables = append(tables, table)
	}
	for _, system := range systemTables {
		table, err := reader.systemTable(system.name, system.key)
		if err != nil {
			return nil, err
		}
		tables = append(tables, table)
	}
	sort.Slice(tables, func(left, right int) bool { return tables[left].Name < tables[right].Name })
	return tables, nil
}

// rows reads a table's cells as Dolt renders CAST(value AS CHAR), sorted by
// the primary key, or by every column when the table has none.
func (reader stateReader) rows(table Table) ([][]*string, error) {
	cells := make([]string, len(table.Columns))
	for index, column := range table.Columns {
		cells[index] = "CAST(" + quoteIdentifier(column.Name) + " AS CHAR)"
	}
	order := make([]string, 0, len(table.Columns))
	for _, name := range table.PrimaryKey {
		order = append(order, quoteIdentifier(name))
	}
	if len(order) == 0 {
		for index := range table.Columns {
			order = append(order, strconv.Itoa(index+1))
		}
	}
	rows, err := reader.query("SELECT " + strings.Join(cells, ", ") + " FROM " + quoteIdentifier(table.Name) + " ORDER BY " + strings.Join(order, ", "))
	if err != nil {
		return nil, err
	}
	if rows == nil {
		rows = [][]*string{}
	}
	return rows, nil
}

// systemTable reads a Dolt system table, which information_schema does not
// list, with the given identifying columns as its key.
func (reader stateReader) systemTable(name string, key []string) (Table, error) {
	//nolint:gosec // G202: name comes from the fixed systemTables list and is quoted.
	probe, err := reader.tx.QueryContext(reader.ctx, "SELECT * FROM "+quoteIdentifier(name)+" LIMIT 0")
	if err != nil {
		return Table{}, fmt.Errorf("read %s: %w", name, err)
	}
	types, err := probe.ColumnTypes()
	closeErr := probe.Close()
	if err = errors.Join(err, closeErr); err != nil {
		return Table{}, fmt.Errorf("read %s columns: %w", name, err)
	}
	table := Table{Name: name, Columns: make([]Column, len(types)), PrimaryKey: key}
	for index, columnType := range types {
		table.Columns[index] = Column{Name: columnType.Name(), Type: strings.ToLower(columnType.DatabaseTypeName())}
	}
	for _, column := range key {
		if columnIndex(table, column) < 0 {
			return Table{}, fmt.Errorf("read %s: no key column %s", name, column)
		}
	}
	table.Rows, err = reader.rows(table)
	return table, err
}

// revision reads the branches, tags, remotes, every commit with its parents
// and changed tables, and the working set.
func (reader stateReader) revision() (Revision, error) {
	var revision Revision
	active, err := reader.query("SELECT active_branch()")
	if err != nil {
		return Revision{}, err
	}
	if len(active) == 1 {
		revision.ActiveBranch = cellText(active[0][0])
	}
	branches, err := reader.query("SELECT name, hash FROM dolt_branches ORDER BY name")
	if err != nil {
		return Revision{}, err
	}
	revision.Branches = make([]Branch, len(branches))
	for index, row := range branches {
		revision.Branches[index] = Branch{Name: cellText(row[0]), Head: cellText(row[1])}
	}
	tags, err := reader.query("SELECT tag_name, tag_hash, tagger, email, date, message FROM dolt_tags ORDER BY tag_name")
	if err != nil {
		return Revision{}, err
	}
	revision.Tags = make([]Tag, len(tags))
	for index, row := range tags {
		date, err := utcTime(row[4])
		if err != nil {
			return Revision{}, err
		}
		revision.Tags[index] = Tag{Name: cellText(row[0]), Commit: cellText(row[1]), Tagger: cellText(row[2]), Email: cellText(row[3]), Date: date, Message: cellText(row[5])}
	}
	remotes, err := reader.query("SELECT name, url FROM dolt_remotes ORDER BY name")
	if err != nil {
		return Revision{}, err
	}
	revision.Remotes = make([]Remote, len(remotes))
	for index, row := range remotes {
		revision.Remotes[index] = Remote{Name: cellText(row[0]), URL: cellText(row[1])}
	}
	if revision.Commits, err = reader.commits(); err != nil {
		return Revision{}, err
	}
	status, err := reader.query("SELECT table_name, CAST(staged AS CHAR), status FROM dolt_status ORDER BY table_name, staged, status")
	if err != nil {
		return Revision{}, err
	}
	revision.WorkingSet = WorkingSet{Dirty: len(status) > 0, Changes: make([]StatusChange, len(status))}
	for index, row := range status {
		staged, err := strconv.ParseBool(cellText(row[1]))
		if err != nil {
			return Revision{}, fmt.Errorf("dolt_status staged %q: %w", cellText(row[1]), err)
		}
		revision.WorkingSet.Changes[index] = StatusChange{Table: cellText(row[0]), Staged: staged, Status: cellText(row[2])}
	}
	return revision, nil
}

func (reader stateReader) commits() ([]Commit, error) {
	rows, err := reader.query("SELECT commit_hash, committer, email, date, message FROM dolt_commits")
	if err != nil {
		return nil, err
	}
	commits := make([]Commit, len(rows))
	index := make(map[string]int, len(rows))
	for position, row := range rows {
		date, err := utcTime(row[3])
		if err != nil {
			return nil, err
		}
		commits[position] = Commit{
			Hash: cellText(row[0]), Parents: []string{}, Committer: cellText(row[1]), Email: cellText(row[2]),
			Date: date, Message: cellText(row[4]), Tables: []TableChange{},
		}
		index[commits[position].Hash] = position
	}
	parents, err := reader.query("SELECT commit_hash, parent_hash FROM dolt_commit_ancestors ORDER BY commit_hash, parent_index")
	if err != nil {
		return nil, err
	}
	for _, row := range parents {
		if position, ok := index[cellText(row[0])]; ok {
			commits[position].Parents = append(commits[position].Parents, cellText(row[1]))
		}
	}
	changes, err := reader.query("SELECT commit_hash, table_name, CAST(data_change AS CHAR), CAST(schema_change AS CHAR) FROM dolt_diff ORDER BY commit_hash, table_name")
	if err != nil {
		return nil, err
	}
	for _, row := range changes {
		position, ok := index[cellText(row[0])]
		if !ok {
			continue
		}
		data, dataErr := strconv.ParseBool(cellText(row[2]))
		schema, schemaErr := strconv.ParseBool(cellText(row[3]))
		if err := errors.Join(dataErr, schemaErr); err != nil {
			return nil, fmt.Errorf("dolt_diff change flags: %w", err)
		}
		commits[position].Tables = append(commits[position].Tables, TableChange{Name: cellText(row[1]), Data: data, Schema: schema})
	}
	generation := commitGenerations(commits)
	sort.Slice(commits, func(left, right int) bool {
		if generation[commits[left].Hash] != generation[commits[right].Hash] {
			return generation[commits[left].Hash] < generation[commits[right].Hash]
		}
		return commits[left].Hash < commits[right].Hash
	})
	return commits, nil
}
