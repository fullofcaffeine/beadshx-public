package readonlyfacade

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/steveyegge/beads/internal/configfile"
	"github.com/steveyegge/beads/internal/types"
)

func TestIssueRecordCopiesRareLongFields(t *testing.T) {
	compactedAt := time.Date(2026, 8, 21, 14, 0, 0, 0, time.UTC)
	leaseExpiresAt := time.Date(2026, 8, 21, 15, 0, 0, 0, time.UTC)
	heartbeatAt := time.Date(2026, 8, 21, 14, 59, 0, 0, time.UTC)
	compactedCommit := "abc123"
	record, err := projectIssueRecord(types.Issue{
		ID:                "test-rare",
		Metadata:          []byte(`{"valid":true}`),
		IsBlocked:         true,
		LeaseExpiresAt:    &leaseExpiresAt,
		HeartbeatAt:       &heartbeatAt,
		LeaseGrantedNode:  "node-a",
		CompactionLevel:   2,
		CompactedAt:       &compactedAt,
		CompactedAtCommit: &compactedCommit,
		OriginalSize:      100,
		Sender:            "agent-a",
		Ephemeral:         true,
		NoHistory:         true,
		StorageClass:      types.StorageClassUnversioned,
		Pinned:            true,
		IsTemplate:        true,
		BondedFrom: []types.BondRef{{
			SourceID: "proto-a", BondType: "parallel", BondPoint: "root",
		}},
		AwaitType:      "human",
		AwaitID:        "approval",
		Timeout:        time.Minute,
		Waiters:        []string{"alpha", "beta"},
		SourceFormula:  "release",
		SourceLocation: "steps[0]",
		WorkType:       types.WorkType("open_competition"),
		EventKind:      "agent.started",
		Actor:          "agent://a",
		Target:         "bead://b",
		Payload:        `{"k":1}`,
	})
	if err != nil {
		t.Fatal(err)
	}
	if record.compactionLevel != 2 || record.compactedAt != "2026-08-21T14:00:00Z" ||
		record.compactedAtCommit != "abc123" || record.originalSize != 100 {
		t.Fatalf("compaction projection = %+v", record)
	}
	if !record.isBlocked || record.leaseExpiresAt != "2026-08-21T15:00:00Z" ||
		record.heartbeatAt != "2026-08-21T14:59:00Z" || record.leaseGrantedNode != "node-a" {
		t.Fatalf("readiness/lease projection = %+v", record)
	}
	if record.sender != "agent-a" || !record.ephemeral || !record.noHistory ||
		record.storageClass != "unversioned" || !record.pinned || !record.template {
		t.Fatalf("extended flags projection = %+v", record)
	}
	if len(record.bondedFrom) != 1 || record.bondedFrom[0].sourceID != "proto-a" ||
		record.bondedFrom[0].bondType != "parallel" || record.bondedFrom[0].bondPoint != "root" {
		t.Fatalf("bond projection = %+v", record.bondedFrom)
	}
	if record.awaitType != "human" || record.awaitID != "approval" || record.timeout != "1m0s" || record.timeoutNanos != "60000000000" ||
		len(record.waiters) != 2 || record.waiters[1] != "beta" {
		t.Fatalf("gate projection = %+v", record)
	}
	if record.sourceFormula != "release" || record.sourceLocation != "steps[0]" ||
		record.workType != "open_competition" {
		t.Fatalf("source/work projection = %+v", record)
	}
	if record.eventKind != "agent.started" || record.actor != "agent://a" ||
		record.target != "bead://b" || record.payload != `{"k":1}` {
		t.Fatalf("event projection = %+v", record)
	}
}

func TestIssueListOptionsPreserveMaxRowsSource(t *testing.T) {
	options := NewIssueListOptions()
	options.SetMaxRows(7, "BEADS_MAX_ROWS")

	if options.request.MaxRows != 7 {
		t.Fatalf("MaxRows = %d, want 7", options.request.MaxRows)
	}
	if options.request.MaxRowsSource != "BEADS_MAX_ROWS" {
		t.Fatalf("MaxRowsSource = %q, want BEADS_MAX_ROWS", options.request.MaxRowsSource)
	}
}

func TestIssueListOptionsCanSkipUnusedCounts(t *testing.T) {
	options := NewIssueListOptions()
	options.EnableSkipCounts()

	if !options.request.SkipCounts {
		t.Fatal("SkipCounts = false, want true")
	}
}

func TestReadyOptionsPreservePresenceAndLocalCap(t *testing.T) {
	options := NewReadyOptions()
	options.SetPriority(0)
	options.SetLimit(0)
	options.SetOffset(3)
	options.SetMaxRows(7, "BEADS_MAX_ROWS")
	options.AddMetadataField("team", "port")

	if options.request.Priority == nil || *options.request.Priority != 0 {
		t.Fatalf("Priority = %v, want present P0", options.request.Priority)
	}
	if options.request.Limit == nil || *options.request.Limit != 0 {
		t.Fatalf("Limit = %v, want explicitly unlimited", options.request.Limit)
	}
	if options.request.Offset != 3 {
		t.Fatalf("Offset = %d, want 3", options.request.Offset)
	}
	if options.maxRows != 7 || options.maxRowsSource != "BEADS_MAX_ROWS" {
		t.Fatalf("local cap = %d/%q, want 7/BEADS_MAX_ROWS", options.maxRows, options.maxRowsSource)
	}
	if options.request.MetadataFields["team"] != "port" {
		t.Fatalf("MetadataFields = %#v", options.request.MetadataFields)
	}
}

func TestStrictReadOnlyOpenDoesNotProvisionMissingEmbeddedStore(t *testing.T) {
	root := t.TempDir()
	beadsDir := filepath.Join(root, ".beads")
	if err := os.Mkdir(beadsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	cfg := configfile.DefaultConfig()
	cfg.DoltMode = configfile.DoltModeEmbedded
	cfg.DoltDatabase = "readonly_fixture"
	if err := cfg.Save(beadsDir); err != nil {
		t.Fatal(err)
	}

	before, err := os.ReadDir(beadsDir)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, _, err := openStore(context.Background(), beadsDir, false); err == nil {
		t.Fatal("strict read-only open provisioned a missing database")
	}
	after, err := os.ReadDir(beadsDir)
	if err != nil {
		t.Fatal(err)
	}
	if len(after) != len(before) {
		t.Fatalf("strict read-only open changed workspace entry count: before=%d after=%d", len(before), len(after))
	}
	if _, err := os.Stat(filepath.Join(beadsDir, "embeddeddolt")); !os.IsNotExist(err) {
		t.Fatalf("strict read-only open created embedded data: %v", err)
	}
}

func TestGlobalOpenRequiresSharedServerMode(t *testing.T) {
	beadsDir := filepath.Join(t.TempDir(), ".beads")
	if err := os.Mkdir(beadsDir, 0o700); err != nil {
		t.Fatal(err)
	}
	cfg := configfile.DefaultConfig()
	cfg.DoltMode = configfile.DoltModeServer
	if err := cfg.Save(beadsDir); err != nil {
		t.Fatal(err)
	}
	t.Setenv("BEADS_DOLT_SHARED_SERVER", "0")

	_, _, _, err := openStore(context.Background(), beadsDir, true)
	want := "--global requires shared-server mode (set BEADS_DOLT_SHARED_SERVER=1 or dolt.shared-server: true in config.yaml)"
	if err == nil || err.Error() != want {
		t.Fatalf("openStore global error = %v, want %q", err, want)
	}
}

func TestSharedServerOverrideDoesNotFallBackToEmbedded(t *testing.T) {
	beadsDir := filepath.Join(t.TempDir(), ".beads")
	if err := os.Mkdir(beadsDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := configfile.DefaultConfig().Save(beadsDir); err != nil {
		t.Fatal(err)
	}
	t.Setenv("BEADS_DOLT_SHARED_SERVER", "1")
	t.Setenv("BEADS_DOLT_AUTO_START", "0")
	t.Setenv("BEADS_DOLT_PORT", "1")

	_, _, _, err := openStore(context.Background(), beadsDir, true)
	if err == nil {
		t.Fatal("openStore unexpectedly connected to the shared server")
	}
	if strings.Contains(err.Error(), "--global requires shared-server mode") {
		t.Fatalf("shared-server override was rejected: %v", err)
	}
	if !strings.HasPrefix(err.Error(), "failed to open database: Dolt server unreachable") {
		t.Fatalf("shared-server error lost the database-open context: %v", err)
	}
	if _, statErr := os.Stat(filepath.Join(beadsDir, "embeddeddolt")); !os.IsNotExist(statErr) {
		t.Fatalf("shared-server open created embedded data: %v", statErr)
	}
}

func TestSharedServerConfigAllowsGlobalRoutingWithoutEmbeddedFallback(t *testing.T) {
	beadsDir := filepath.Join(t.TempDir(), ".beads")
	if err := os.Mkdir(beadsDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := configfile.DefaultConfig().Save(beadsDir); err != nil {
		t.Fatal(err)
	}
	configYAML := []byte("dolt:\n  shared-server: true\n  auto-start: false\n")
	if err := os.WriteFile(filepath.Join(beadsDir, "config.yaml"), configYAML, 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("BEADS_DOLT_PORT", "1")

	_, _, _, err := openStore(context.Background(), beadsDir, true)
	if err == nil {
		t.Fatal("openStore unexpectedly connected to the configured shared server")
	}
	if strings.Contains(err.Error(), "--global requires shared-server mode") {
		t.Fatalf("config.yaml shared-server mode was rejected: %v", err)
	}
	if !strings.HasPrefix(err.Error(), "failed to open database: Dolt server unreachable") {
		t.Fatalf("configured shared-server error lost the database-open context: %v", err)
	}
	if _, statErr := os.Stat(filepath.Join(beadsDir, "embeddeddolt")); !os.IsNotExist(statErr) {
		t.Fatalf("configured shared-server open created embedded data: %v", statErr)
	}
}
