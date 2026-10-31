//go:build cgo

package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"sort"
	"testing"
	"time"

	"github.com/steveyegge/beads/internal/configfile"
	"github.com/steveyegge/beads/internal/storage/dbproxy/pidfile"
	"github.com/steveyegge/beads/internal/storage/dbproxy/proxy"
)

// TestBeadsHXProxiedReadonly is the server-backed tracer for the Haxe port.
// Upstream bd owns fixture writes; BeadsHX attaches to the already-running
// external proxy and must produce the same logical reads without persistent
// workspace or database changes.
func TestBeadsHXProxiedReadonly(t *testing.T) {
	candidate := os.Getenv("BEADSHX_CANDIDATE_BIN")
	if candidate == "" {
		t.Skip("set BEADSHX_CANDIDATE_BIN to run the BeadsHX proxied read tracer")
	}
	if _, err := os.Stat(candidate); err != nil {
		t.Fatalf("BEADSHX_CANDIDATE_BIN=%q: %v", candidate, err)
	}

	requireSharedProxiedServer(t)
	upstream := buildEmbeddedBD(t)
	project := newSharedProxiedProject(t, upstream, "bhxp")
	issue := bdProxiedCreate(t, upstream, project.dir, "Proxied Haxe tracer", "--type", "task", "--description", "server-backed details")
	child := bdProxiedCreate(t, upstream, project.dir, "Child Haxe tracer", "--parent", issue.ID)
	commit := exec.Command("git", "commit", "--allow-empty", "-m", "feat: implement ("+issue.ID+")")
	commit.Dir = project.dir
	if output, err := commit.CombinedOutput(); err != nil {
		t.Fatalf("create orphan tracer commit: %v\n%s", err, output)
	}

	cases := []struct {
		name string
		args []string
	}{
		{"where", []string{"where", "--json"}},
		{"info", []string{"info", "--schema", "--json"}},
		{"ping", []string{"ping", "--json"}},
		{"status", []string{"status", "--json"}},
		{"list", []string{"list", "--json", "--all"}},
		{"show", []string{"show", "--json", issue.ID}},
		{"count", []string{"count", "--json"}},
		{"count-by-status", []string{"count", "--by-status", "--json"}},
		{"ready", []string{"ready", "--json", "--limit", "0"}},
		{"search", []string{"search", "--json", "Proxied"}},
		{"query", []string{"query", "status=open", "--json"}},
		{"stale", []string{"stale", "--json", "--days", "1"}},
		{"orphans", []string{"orphans", "--json"}},
		{"children", []string{"children", issue.ID, "--json"}},
		{"dep-list", []string{"dep", "list", child.ID, "--json"}},
	}
	// Run oracle reads before the candidate snapshot: only candidate effects
	// are under qualification, while the oracle owns fixture preparation.
	want := make([]any, len(cases))
	for i, tc := range cases {
		want[i] = runProxiedJSON(t, upstream, project, tc.args...)
		if tc.name == "ping" {
			normalizeProxiedPing(t, want[i])
		}
	}
	before := snapshotBeadsHXProxiedState(t, project)
	for i, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := runProxiedJSON(t, candidate, project, tc.args...)
			if tc.name == "ping" {
				normalizeProxiedPing(t, got)
			}
			if !reflect.DeepEqual(got, want[i]) {
				t.Fatalf("BeadsHX proxied read differs from upstream\nwant: %#v\n got: %#v", want[i], got)
			}
		})
	}

	after := snapshotBeadsHXProxiedState(t, project)
	if !reflect.DeepEqual(after, before) {
		t.Fatalf("BeadsHX proxied reads changed persistent or lifecycle state\nbefore: %#v\n after: %#v", before, after)
	}
}

// Timing values vary between processes. Validate their contract before removing
// only those four fields, using the same normalization as the embedded corpus.
func normalizeProxiedPing(t *testing.T, value any) {
	t.Helper()
	fields, ok := value.(map[string]any)
	if !ok {
		t.Fatalf("ping JSON is not an object: %T", value)
	}
	var sum, total int64
	for _, key := range []string{"query_ms", "resolve_ms", "store_ms", "total_ms"} {
		number, ok := fields[key].(json.Number)
		if !ok {
			t.Fatalf("ping %s is not a number", key)
		}
		n, err := number.Int64()
		if err != nil || n < 0 {
			t.Fatalf("ping %s is not a nonnegative integer: %s", key, number)
		}
		if key == "total_ms" {
			total = n
		} else {
			sum += n
		}
		delete(fields, key)
	}
	if sum != total {
		t.Fatalf("ping total %d differs from component sum %d", total, sum)
	}
}

func runProxiedJSON(t *testing.T, binary string, project proxiedProject, args ...string) any {
	t.Helper()
	cmd := exec.Command(binary, args...)
	cmd.Dir = project.dir
	cmd.Env = bdProxiedEnv(project.dir)
	stdout, stderr, err := runCommandBuffers(t, cmd)
	if err != nil {
		t.Fatalf("%s %v: %v\nstdout:\n%s\nstderr:\n%s", binary, args, err, stdout.String(), stderr.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("%s %v wrote stderr:\n%s", binary, args, stderr.String())
	}
	var value any
	decoder := json.NewDecoder(bytes.NewReader(stdout.Bytes()))
	decoder.UseNumber()
	if err := decoder.Decode(&value); err != nil {
		t.Fatalf("decode %s %v JSON: %v\n%s", binary, args, err, stdout.String())
	}
	return value
}

type beadshxProxiedState struct {
	Head        string
	WorkingHash string
	WorkingSet  []string
	ProxyPID    pidfile.PidFile
	Metadata    string
	ClientInfo  string
	WorkspaceFS []string
}

func snapshotBeadsHXProxiedState(t *testing.T, project proxiedProject) beadshxProxiedState {
	t.Helper()
	db := openProxiedDB(t, project)
	return beadshxProxiedState{
		Head:        proxiedHead(t, db),
		WorkingHash: proxiedWorkingHash(t, db),
		WorkingSet:  proxiedWorkingSet(t, db),
		ProxyPID:    readProxiedPID(t, project.proxyRoot),
		Metadata:    readProxiedFile(t, configfile.ConfigPath(project.beadsDir)),
		ClientInfo:  readProxiedFile(t, configfile.ProxiedServerClientInfoPath(project.beadsDir)),
		WorkspaceFS: proxiedPathSet(t, project.dir),
	}
}

// Include uncommitted row values, not only the names of dirty tables.
func proxiedWorkingHash(t *testing.T, db *sql.DB) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var hash string
	if err := db.QueryRowContext(ctx, "SELECT DOLT_HASHOF_DB()").Scan(&hash); err != nil {
		t.Fatalf("read proxied working database hash: %v", err)
	}
	return hash
}

func proxiedHead(t *testing.T, db *sql.DB) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var head string
	if err := db.QueryRowContext(ctx, "SELECT HASHOF('HEAD')").Scan(&head); err != nil {
		t.Fatalf("read proxied HEAD: %v", err)
	}
	return head
}

func proxiedWorkingSet(t *testing.T, db *sql.DB) []string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	rows, err := db.QueryContext(ctx, "SELECT table_name, staged, status FROM dolt_status ORDER BY table_name, staged, status")
	if err != nil {
		t.Fatalf("read proxied working set: %v", err)
	}
	defer func() { _ = rows.Close() }()
	var values []string
	for rows.Next() {
		var table, status string
		var staged bool
		if err := rows.Scan(&table, &staged, &status); err != nil {
			t.Fatalf("scan proxied working set: %v", err)
		}
		values = append(values, table+"|"+status+"|"+map[bool]string{false: "unstaged", true: "staged"}[staged])
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate proxied working set: %v", err)
	}
	return values
}

func readProxiedPID(t *testing.T, root string) pidfile.PidFile {
	t.Helper()
	value, err := pidfile.Read(root, proxy.PIDFileName)
	if err != nil || value == nil {
		t.Fatalf("read existing proxy PID at %s: value=%v err=%v", root, value, err)
	}
	return *value
}

func readProxiedFile(t *testing.T, path string) string {
	t.Helper()
	value, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(value)
}

func proxiedPathSet(t *testing.T, root string) []string {
	t.Helper()
	var paths []string
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		value := relative + "|" + info.Mode().String()
		if info.Mode().IsRegular() {
			content, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			value += fmt.Sprintf("|%x", sha256.Sum256(content))
		} else if info.Mode()&os.ModeSymlink != 0 {
			target, err := os.Readlink(path)
			if err != nil {
				return err
			}
			value += "|" + target
		}
		paths = append(paths, value)
		return nil
	})
	if err != nil {
		t.Fatalf("snapshot paths under %s: %v", root, err)
	}
	sort.Strings(paths)
	return paths
}

func TestBeadsHXReadonlySnapshotDetectsContentChange(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "config.yaml")
	if err := os.WriteFile(path, []byte("mode: before\n"), 0600); err != nil {
		t.Fatal(err)
	}
	before := proxiedPathSet(t, root)
	if err := os.WriteFile(path, []byte("mode: after!\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if reflect.DeepEqual(before, proxiedPathSet(t, root)) {
		t.Fatal("read-only snapshot missed a same-path, same-size content change")
	}
}
