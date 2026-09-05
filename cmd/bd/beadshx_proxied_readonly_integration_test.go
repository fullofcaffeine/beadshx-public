//go:build cgo

package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
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
	commit := exec.Command("git", "commit", "--allow-empty", "-m", "feat: implement ("+issue.ID+")")
	commit.Dir = project.dir
	if output, err := commit.CombinedOutput(); err != nil {
		t.Fatalf("create orphan tracer commit: %v\n%s", err, output)
	}

	wantList := runProxiedJSON(t, upstream, project, "list", "--json", "--all")
	wantShow := runProxiedJSON(t, upstream, project, "show", "--json", issue.ID)
	wantCount := runProxiedJSON(t, upstream, project, "count", "--json")
	wantCountByStatus := runProxiedJSON(t, upstream, project, "count", "--by-status", "--json")
	wantReady := runProxiedJSON(t, upstream, project, "ready", "--json", "--limit", "0")
	wantSearch := runProxiedJSON(t, upstream, project, "search", "--json", "Proxied")
	wantQuery := runProxiedJSON(t, upstream, project, "query", "status=open", "--json")
	wantStale := runProxiedJSON(t, upstream, project, "stale", "--json", "--days", "1")
	wantOrphans := runProxiedJSON(t, upstream, project, "orphans", "--json")
	before := snapshotBeadsHXProxiedState(t, project)

	gotList := runProxiedJSON(t, candidate, project, "list", "--json", "--all")
	gotShow := runProxiedJSON(t, candidate, project, "show", "--json", issue.ID)
	gotCount := runProxiedJSON(t, candidate, project, "count", "--json")
	gotCountByStatus := runProxiedJSON(t, candidate, project, "count", "--by-status", "--json")
	gotReady := runProxiedJSON(t, candidate, project, "ready", "--json", "--limit", "0")
	gotSearch := runProxiedJSON(t, candidate, project, "search", "--json", "Proxied")
	gotQuery := runProxiedJSON(t, candidate, project, "query", "status=open", "--json")
	gotStale := runProxiedJSON(t, candidate, project, "stale", "--json", "--days", "1")
	gotOrphans := runProxiedJSON(t, candidate, project, "orphans", "--json")
	if !reflect.DeepEqual(gotList, wantList) {
		t.Fatalf("BeadsHX proxied list differs from upstream\nwant: %#v\n got: %#v", wantList, gotList)
	}
	if !reflect.DeepEqual(gotShow, wantShow) {
		t.Fatalf("BeadsHX proxied show differs from upstream\nwant: %#v\n got: %#v", wantShow, gotShow)
	}
	if !reflect.DeepEqual(gotCount, wantCount) {
		t.Fatalf("BeadsHX proxied count differs from upstream\nwant: %#v\n got: %#v", wantCount, gotCount)
	}
	if !reflect.DeepEqual(gotCountByStatus, wantCountByStatus) {
		t.Fatalf("BeadsHX proxied grouped count differs from upstream\nwant: %#v\n got: %#v", wantCountByStatus, gotCountByStatus)
	}
	if !reflect.DeepEqual(gotReady, wantReady) {
		t.Fatalf("BeadsHX proxied ready differs from upstream\nwant: %#v\n got: %#v", wantReady, gotReady)
	}
	if !reflect.DeepEqual(gotSearch, wantSearch) {
		t.Fatalf("BeadsHX proxied search differs from upstream\nwant: %#v\n got: %#v", wantSearch, gotSearch)
	}
	if !reflect.DeepEqual(gotQuery, wantQuery) {
		t.Fatalf("BeadsHX proxied query differs from upstream\nwant: %#v\n got: %#v", wantQuery, gotQuery)
	}
	if !reflect.DeepEqual(gotStale, wantStale) {
		t.Fatalf("BeadsHX proxied stale differs from upstream\nwant: %#v\n got: %#v", wantStale, gotStale)
	}
	if !reflect.DeepEqual(gotOrphans, wantOrphans) {
		t.Fatalf("BeadsHX proxied orphans differ from upstream\nwant: %#v\n got: %#v", wantOrphans, gotOrphans)
	}

	after := snapshotBeadsHXProxiedState(t, project)
	if !reflect.DeepEqual(after, before) {
		t.Fatalf("BeadsHX proxied reads changed persistent or lifecycle state\nbefore: %#v\n after: %#v", before, after)
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
		WorkingSet:  proxiedWorkingSet(t, db),
		ProxyPID:    readProxiedPID(t, project.proxyRoot),
		Metadata:    readProxiedFile(t, configfile.ConfigPath(project.beadsDir)),
		ClientInfo:  readProxiedFile(t, configfile.ProxiedServerClientInfoPath(project.beadsDir)),
		WorkspaceFS: proxiedPathSet(t, project.beadsDir),
	}
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
		paths = append(paths, relative)
		return nil
	})
	if err != nil {
		t.Fatalf("snapshot paths under %s: %v", root, err)
	}
	sort.Strings(paths)
	return paths
}
