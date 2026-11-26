package main

import (
	"context"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRefusesAWorkspaceWithoutTheDisposableMarker(t *testing.T) {
	workspace := t.TempDir()
	writeMetadata(t, workspace, `{"dolt_mode":"embedded","dolt_database":"test"}`)
	err := run(context.Background(), workspace, strings.NewReader("SELECT 1\n"), defaultMessage)
	if err == nil || !strings.Contains(err.Error(), "no .beadshx-disposable-fixture marker") {
		t.Fatalf("err = %v, want the missing-marker refusal", err)
	}
}

func TestRefusesAServerModeWorkspace(t *testing.T) {
	workspace := t.TempDir()
	writeMetadata(t, workspace, `{"dolt_mode":"server","dolt_database":"test"}`)
	if err := os.WriteFile(filepath.Join(workspace, fixtureMarker), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	err := run(context.Background(), workspace, strings.NewReader("SELECT 1\n"), defaultMessage)
	if err == nil || !strings.Contains(err.Error(), "not an embedded fixture") {
		t.Fatalf("err = %v, want the embedded-only refusal", err)
	}
}

func TestQueryRefusesAWorkspaceWithoutTheDisposableMarker(t *testing.T) {
	workspace := t.TempDir()
	writeMetadata(t, workspace, `{"dolt_mode":"embedded","dolt_database":"test"}`)
	err := query(context.Background(), workspace, strings.NewReader("SELECT 1\n"), io.Discard)
	if err == nil || !strings.Contains(err.Error(), "no .beadshx-disposable-fixture marker") {
		t.Fatalf("err = %v, want the missing-marker refusal", err)
	}
}

func TestQueryTakesOneStatement(t *testing.T) {
	workspace := t.TempDir()
	writeMetadata(t, workspace, `{"dolt_mode":"embedded","dolt_database":"test"}`)
	if err := os.WriteFile(filepath.Join(workspace, fixtureMarker), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	err := query(context.Background(), workspace, strings.NewReader("SELECT 1\nSELECT 2\n"), io.Discard)
	if err == nil || !strings.Contains(err.Error(), "--query takes one statement, got 2") {
		t.Fatalf("err = %v, want the one-statement refusal", err)
	}
}

func TestParsesTheCommitOptions(t *testing.T) {
	for _, test := range []struct {
		arguments []string
		want      invocation
	}{
		{[]string{"ws"}, invocation{workspace: "ws", message: defaultMessage}},
		{[]string{"--message", "bd: update issue", "ws"}, invocation{workspace: "ws", message: "bd: update issue"}},
		{[]string{"--no-commit", "ws"}, invocation{workspace: "ws"}},
		{[]string{"--query", "ws"}, invocation{workspace: "ws", query: true}},
	} {
		got, err := parseArguments(test.arguments)
		if err != nil || got != test.want {
			t.Fatalf("parseArguments(%q) = %+v, %v; want %+v", test.arguments, got, err, test.want)
		}
	}
	for _, arguments := range [][]string{
		{}, {"--message"}, {"--message", "", "ws"}, {"--no-commit", "--message", "m", "ws"},
		{"--query", "--no-commit", "ws"}, {"--bogus", "ws"}, {"one", "two"},
	} {
		if _, err := parseArguments(arguments); err == nil {
			t.Fatalf("parseArguments(%q) was accepted", arguments)
		}
	}
}

func TestRefusesEmptyInput(t *testing.T) {
	if _, err := readStatements(strings.NewReader("\n  \n")); err == nil {
		t.Fatal("empty input was accepted")
	}
}

func writeMetadata(t *testing.T, workspace, metadata string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(workspace, ".beads"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(workspace, ".beads", "metadata.json"), []byte(metadata), 0o600); err != nil {
		t.Fatal(err)
	}
}
