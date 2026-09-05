package uow

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/steveyegge/beads/internal/configfile"
)

func TestAttachDoltServerUOWProviderMissingRootCreatesNothing(t *testing.T) {
	root := filepath.Join(t.TempDir(), "missing")

	_, err := AttachDoltServerUOWProvider(context.Background(), root, "beads", "root", "", false, "")
	if err == nil {
		t.Fatal("AttachDoltServerUOWProvider on missing root: got nil, want error")
	}
	if _, statErr := filepath.Glob(filepath.Join(root, "*")); statErr != nil {
		t.Fatalf("glob missing root: %v", statErr)
	}
	if _, statErr := existingServerRoot(root); statErr == nil {
		t.Fatal("missing root was created")
	}
}

func TestAttachExternalDoltServerUOWProviderMissingRootCreatesNothing(t *testing.T) {
	root := filepath.Join(t.TempDir(), "missing")
	external := configfile.ExternalDoltConfig{Host: "127.0.0.1", Port: 3306}

	_, err := AttachExternalDoltServerUOWProvider(context.Background(), root, "beads", external, "root", "", false, "")
	if err == nil {
		t.Fatal("AttachExternalDoltServerUOWProvider on missing root: got nil, want error")
	}
	if _, statErr := existingServerRoot(root); statErr == nil {
		t.Fatal("missing root was created")
	}
}
