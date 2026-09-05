// Package profilefacade contains the process-wide runtime profiler boundary.
// Profiling artifacts are written only after an explicit flag or environment
// opt-in; task and workspace storage remain untouched.
package profilefacade

import (
	"fmt"
	"os"
	"runtime"
	"runtime/pprof"
	"runtime/trace"
	"time"
)

var cpuFile *os.File
var traceFile *os.File

// StartCPU starts best-effort CPU and runtime tracing with upstream-compatible
// filenames. The Go runtime exposes these profilers process-wide, and BeadsHX
// invokes this boundary once from its synchronous CLI lifecycle.
func StartCPU(command string) {
	timestamp := time.Now().Format("20060102-150405")
	if file, _ := os.Create(fmt.Sprintf("bd-profile-%s-%s.prof", command, timestamp)); file != nil {
		cpuFile = file
		_ = pprof.StartCPUProfile(file)
	}
	if file, _ := os.Create(fmt.Sprintf("bd-trace-%s-%s.out", command, timestamp)); file != nil {
		traceFile = file
		_ = trace.Start(file)
	}
}

// Finish flushes active CPU/trace output and writes optional heap diagnostics.
// Every operation is best effort because profiling must not change command
// success or failure.
func Finish(memProfilePath string) {
	if cpuFile != nil {
		pprof.StopCPUProfile()
		_ = cpuFile.Close()
		cpuFile = nil
	}
	if traceFile != nil {
		trace.Stop()
		_ = traceFile.Close()
		traceFile = nil
	}

	heapDestination := memProfilePath
	if heapDestination == "" {
		heapDestination = os.Getenv("BEADS_MEM_PROFILE")
	}
	if heapDestination != "" {
		if os.Getenv("BEADS_MEM_PROFILE_NOGC") == "" {
			runtime.GC()
		}
		if file, err := os.Create(heapDestination); err == nil { // #nosec G304 -- explicit profiling destination
			_ = pprof.WriteHeapProfile(file)
			_ = file.Close()
		}
	}

	if statsDestination := os.Getenv("BEADS_MEM_STATS"); statsDestination != "" {
		var stats runtime.MemStats
		runtime.ReadMemStats(&stats)
		if file, err := os.Create(statsDestination); err == nil { // #nosec G304 -- explicit profiling destination
			_, _ = fmt.Fprintf(file, "HeapAlloc=%d HeapSys=%d HeapInuse=%d HeapObjects=%d\n",
				stats.HeapAlloc, stats.HeapSys, stats.HeapInuse, stats.HeapObjects)
			_ = file.Close()
		}
	}
}
