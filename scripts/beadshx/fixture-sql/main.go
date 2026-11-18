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
// Usage: fixture-sql WORKSPACE < STATEMENTS (one SQL statement per line)
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/steveyegge/beads/internal/storage/embeddeddolt"
)

const fixtureMarker = ".beadshx-disposable-fixture"

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: fixture-sql WORKSPACE < STATEMENTS")
		os.Exit(2)
	}
	if err := run(context.Background(), os.Args[1], os.Stdin); err != nil {
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

func run(ctx context.Context, workspace string, input io.Reader) (err error) {
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
	if _, commitErr := tx.ExecContext(ctx, "CALL DOLT_COMMIT('-Am', ?)", "beadshx parity fixture"); commitErr != nil {
		return errors.Join(fmt.Errorf("dolt commit: %w", commitErr), tx.Rollback())
	}
	return tx.Commit()
}
