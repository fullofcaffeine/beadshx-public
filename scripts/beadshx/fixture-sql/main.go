// Command fixture-sql writes rows that ordinary bd commands refuse to create,
// such as a dependency cycle, into a disposable embedded Beads fixture.
//
// Upstream bd refuses every cycle-closing edge (dep add, --no-cycle-check and
// import), but cycles still reach real databases through merges. Parity tests
// need such data, so this tool applies SQL statements directly, in one
// transaction, followed by the same DOLT_COMMIT('-Am') that bd writes use.
//
// It refuses any workspace without the .beadshx-disposable-fixture marker and
// any workspace that is not in embedded mode. Never point it at real data.
//
// --message sets the commit message. --no-commit commits the SQL transaction
// but makes no Dolt commit, so the change stays in the working set (dirty,
// unless it only touches tables that dolt_ignore names). The logical state
// tests use both to build revision states.
//
// With --query it instead runs one read query in a transaction that it rolls
// back, and prints each row as tab-separated values (NULL as "NULL"). Tests use
// it to read values, such as Dolt revision hashes, that bd prints nowhere.
//
// Usage: fixture-sql [--message TEXT | --no-commit] WORKSPACE < STATEMENTS
// (one SQL statement per line)
//
//	fixture-sql --query WORKSPACE < QUERY
package main

import (
	"bufio"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/steveyegge/beads/internal/storage/embeddeddolt"
)

const (
	fixtureMarker = ".beadshx-disposable-fixture"
	// defaultMessage is the Dolt commit message without --message.
	defaultMessage = "beadshx parity fixture"
)

// invocation is one parsed command line.
type invocation struct {
	query     bool
	workspace string
	// message is the Dolt commit message; empty with --no-commit or --query.
	message string
}

func parseArguments(arguments []string) (invocation, error) {
	result := invocation{message: defaultMessage}
	noCommit, messageSet := false, false
	for len(arguments) > 1 {
		switch arguments[0] {
		case "--query":
			result.query = true
			arguments = arguments[1:]
		case "--no-commit":
			noCommit = true
			arguments = arguments[1:]
		case "--message":
			if len(arguments) < 3 || arguments[1] == "" {
				return invocation{}, errors.New("--message takes a non-empty message")
			}
			result.message, messageSet = arguments[1], true
			arguments = arguments[2:]
		default:
			return invocation{}, fmt.Errorf("unknown option %q", arguments[0])
		}
	}
	if len(arguments) != 1 || arguments[0] == "" || strings.HasPrefix(arguments[0], "--") {
		return invocation{}, errors.New("missing workspace")
	}
	if (result.query && (noCommit || messageSet)) || (noCommit && messageSet) {
		return invocation{}, errors.New("--query, --message and --no-commit do not combine")
	}
	result.workspace = arguments[0]
	if noCommit || result.query {
		result.message = ""
	}
	return result, nil
}

func main() {
	command, err := parseArguments(os.Args[1:])
	if err != nil {
		fmt.Fprintf(os.Stderr, "fixture-sql: %v\n", err)
		fmt.Fprintln(os.Stderr, "usage: fixture-sql [--message TEXT | --no-commit] WORKSPACE < STATEMENTS")
		fmt.Fprintln(os.Stderr, "       fixture-sql --query WORKSPACE < QUERY")
		os.Exit(2)
	}
	if command.query {
		err = query(context.Background(), command.workspace, os.Stdin, os.Stdout)
	} else {
		err = run(context.Background(), command.workspace, os.Stdin, command.message)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "fixture-sql: %v\n", err)
		os.Exit(1)
	}
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

func readStatements(input io.Reader) ([]string, error) {
	var statements []string
	scanner := bufio.NewScanner(input)
	for scanner.Scan() {
		if statement := strings.TrimSpace(scanner.Text()); statement != "" {
			statements = append(statements, statement)
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("read statements: %w", err)
	}
	if len(statements) == 0 {
		return nil, errors.New("no statements on stdin")
	}
	return statements, nil
}

// query runs the one statement on input in a read transaction, rolls the
// transaction back and writes each row as tab-separated values.
func query(ctx context.Context, workspace string, input io.Reader, output io.Writer) (err error) {
	database, err := fixtureDatabase(workspace)
	if err != nil {
		return err
	}
	statements, err := readStatements(input)
	if err != nil {
		return err
	}
	if len(statements) != 1 {
		return fmt.Errorf("--query takes one statement, got %d", len(statements))
	}
	dataDir := filepath.Join(workspace, ".beads", "embeddeddolt")
	db, cleanup, err := embeddeddolt.OpenSQL(ctx, dataDir, database, "main")
	if err != nil {
		return fmt.Errorf("open fixture database: %w", err)
	}
	defer func() { err = errors.Join(err, cleanup()) }()
	tx, err := db.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return fmt.Errorf("begin: %w", err)
	}
	defer func() { err = errors.Join(err, tx.Rollback()) }()
	rows, err := tx.QueryContext(ctx, statements[0])
	if err != nil {
		return fmt.Errorf("%s: %w", statements[0], err)
	}
	defer func() { err = errors.Join(err, rows.Close()) }()
	columns, err := rows.Columns()
	if err != nil {
		return fmt.Errorf("columns: %w", err)
	}
	for rows.Next() {
		values := make([]sql.NullString, len(columns))
		destinations := make([]any, len(columns))
		for index := range values {
			destinations[index] = &values[index]
		}
		if err := rows.Scan(destinations...); err != nil {
			return fmt.Errorf("scan: %w", err)
		}
		cells := make([]string, len(values))
		for index, value := range values {
			cells[index] = "NULL"
			if value.Valid {
				cells[index] = value.String
			}
		}
		if _, err := fmt.Fprintln(output, strings.Join(cells, "\t")); err != nil {
			return err
		}
	}
	return rows.Err()
}

// run applies the statements in one transaction and, unless message is empty,
// makes a Dolt commit with that message.
func run(ctx context.Context, workspace string, input io.Reader, message string) (err error) {
	database, err := fixtureDatabase(workspace)
	if err != nil {
		return err
	}
	statements, err := readStatements(input)
	if err != nil {
		return err
	}
	dataDir := filepath.Join(workspace, ".beads", "embeddeddolt")
	db, cleanup, err := embeddeddolt.OpenSQL(ctx, dataDir, database, "main")
	if err != nil {
		return fmt.Errorf("open fixture database: %w", err)
	}
	defer func() { err = errors.Join(err, cleanup()) }()
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin: %w", err)
	}
	for _, statement := range statements {
		if _, execErr := tx.ExecContext(ctx, statement); execErr != nil {
			return errors.Join(fmt.Errorf("%s: %w", statement, execErr), tx.Rollback())
		}
	}
	if message != "" {
		if _, commitErr := tx.ExecContext(ctx, "CALL DOLT_COMMIT('-Am', ?)", message); commitErr != nil {
			return errors.Join(fmt.Errorf("dolt commit: %w", commitErr), tx.Rollback())
		}
	}
	return tx.Commit()
}
