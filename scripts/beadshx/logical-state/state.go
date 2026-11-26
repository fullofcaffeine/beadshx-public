package main

import (
	"encoding/json"
	"fmt"
	"io"
)

// stateFormat names the JSON layout that export writes and compare reads.
const stateFormat = "beadshx-logical-state/1"

// State is the logical state of one embedded Beads database: every table's
// schema and rows, the schema objects, and the Dolt revision state.
//
// The raw view, which export writes, holds each value exactly as Dolt renders
// CAST(value AS CHAR). A normalized view lists the rules that changed it in
// Rules; the raw view has none.
type State struct {
	Format   string     `json:"format"`
	Database string     `json:"database"`
	Rules    []RuleNote `json:"rules"`
	Window   *Window    `json:"window,omitempty"`
	Tables   []Table    `json:"tables"`
	Revision Revision   `json:"revision"`
}

// RuleNote records one normalization rule that a normalized view applied.
type RuleNote struct {
	Name   string `json:"name"`
	Reason string `json:"reason"`
}

// Column is one table column, in the table's column order.
type Column struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

// Table holds one table's schema and its rows. Rows are sorted by the primary
// key (by every column when the table has none), and each row lists its cells
// in Columns order; a nil cell is SQL NULL.
type Table struct {
	Name       string   `json:"name"`
	Create     string   `json:"create"`
	Columns    []Column `json:"columns"`
	PrimaryKey []string `json:"primary_key"`
	// KeyedByContent is set in a normalized view when a rule changed a
	// primary-key cell, so rows match by their whole content instead.
	KeyedByContent bool        `json:"keyed_by_content,omitempty"`
	Rows           [][]*string `json:"rows"`
}

// Revision is the Dolt revision state: branches, tags, remotes, the whole
// commit graph and the working set.
type Revision struct {
	ActiveBranch string     `json:"active_branch"`
	Branches     []Branch   `json:"branches"`
	Tags         []Tag      `json:"tags"`
	Remotes      []Remote   `json:"remotes"`
	Commits      []Commit   `json:"commits"`
	WorkingSet   WorkingSet `json:"working_set"`
}

// Branch is one Dolt branch and the commit at its head.
type Branch struct {
	Name string `json:"name"`
	Head string `json:"head"`
}

// Tag is one Dolt tag.
type Tag struct {
	Name    string `json:"name"`
	Commit  string `json:"commit"`
	Tagger  string `json:"tagger"`
	Email   string `json:"email"`
	Date    string `json:"date"`
	Message string `json:"message"`
}

// Remote is one configured Dolt remote.
type Remote struct {
	Name string `json:"name"`
	URL  string `json:"url"`
}

// Commit is one Dolt commit. Commits are listed root first: by generation
// (the longest parent path from a root), then by hash. Parents keep Dolt's
// parent order, and Tables lists the tables that the commit changed against
// its first parent.
type Commit struct {
	Hash      string        `json:"hash"`
	Parents   []string      `json:"parents"`
	Committer string        `json:"committer"`
	Email     string        `json:"email"`
	Date      string        `json:"date"`
	Message   string        `json:"message"`
	Tables    []TableChange `json:"tables"`
}

// TableChange is one table that a commit changed.
type TableChange struct {
	Name   string `json:"name"`
	Data   bool   `json:"data"`
	Schema bool   `json:"schema"`
}

// WorkingSet is the uncommitted state of the active branch, as dolt_status
// reports it. Tables that dolt_ignore names never make it dirty.
type WorkingSet struct {
	Dirty   bool           `json:"dirty"`
	Changes []StatusChange `json:"changes"`
}

// StatusChange is one dolt_status row.
type StatusChange struct {
	Table  string `json:"table"`
	Staged bool   `json:"staged"`
	Status string `json:"status"`
}

func writeState(output io.Writer, state State) error {
	encoder := json.NewEncoder(output)
	encoder.SetEscapeHTML(false)
	encoder.SetIndent("", " ")
	return encoder.Encode(state)
}

func readState(input io.Reader) (State, error) {
	var state State
	decoder := json.NewDecoder(input)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&state); err != nil {
		return State{}, fmt.Errorf("read state: %w", err)
	}
	if state.Format != stateFormat {
		return State{}, fmt.Errorf("read state: format %q, want %q", state.Format, stateFormat)
	}
	return state, nil
}
