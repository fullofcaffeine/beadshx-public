package profilefacade

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestProfileLifecycleWritesRequestedArtifacts(t *testing.T) {
	work := t.TempDir()
	t.Chdir(work)
	heapPath := filepath.Join(work, "heap.prof")
	statsPath := filepath.Join(work, "mem.stats")
	t.Setenv("BEADS_MEM_STATS", statsPath)

	StartCPU("info")
	Finish(heapPath)

	profiles, err := filepath.Glob(filepath.Join(work, "bd-profile-info-*.prof"))
	if err != nil || len(profiles) != 1 {
		t.Fatalf("CPU profiles = %v, error = %v, want one", profiles, err)
	}
	traces, err := filepath.Glob(filepath.Join(work, "bd-trace-info-*.out"))
	if err != nil || len(traces) != 1 {
		t.Fatalf("runtime traces = %v, error = %v, want one", traces, err)
	}
	for _, path := range []string{profiles[0], traces[0], heapPath, statsPath} {
		information, statErr := os.Stat(path)
		if statErr != nil {
			t.Fatalf("artifact %q stat: %v", path, statErr)
		}
		if information.Size() == 0 {
			t.Fatalf("artifact %q is empty", path)
		}
	}
	stats, err := os.ReadFile(statsPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(string(stats), "HeapAlloc=") || !strings.Contains(string(stats), " HeapObjects=") {
		t.Fatalf("memory stats = %q, want upstream field summary", stats)
	}
}

func TestEnvironmentHeapProfileIsOptional(t *testing.T) {
	heapPath := filepath.Join(t.TempDir(), "environment.prof")
	t.Setenv("BEADS_MEM_PROFILE", heapPath)

	Finish("")

	information, err := os.Stat(heapPath)
	if err != nil {
		t.Fatalf("environment heap profile stat: %v", err)
	}
	if information.Size() == 0 {
		t.Fatal("environment heap profile is empty")
	}
}
