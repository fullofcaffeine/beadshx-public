package main

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRefusesAWorkspaceWithoutTheDisposableMarker(t *testing.T) {
	workspace := t.TempDir()
	writeMetadata(t, workspace, `{"dolt_mode":"embedded","dolt_database":"test"}`)
	err := run(context.Background(), workspace, strings.NewReader("SELECT 1\n"))
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
	err := run(context.Background(), workspace, strings.NewReader("SELECT 1\n"))
	if err == nil || !strings.Contains(err.Error(), "not an embedded fixture") {
		t.Fatalf("err = %v, want the embedded-only refusal", err)
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
