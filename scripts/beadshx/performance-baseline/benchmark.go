package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

var benchmarkCPUSuffix = regexp.MustCompile(`-[0-9]+$`)

var selectedBenchmarkNames = []string{
	"BenchmarkBootstrapEmbedded",
	"BenchmarkCreateIssue",
	"BenchmarkGetIssue",
	"BenchmarkUpdateIssue",
	"BenchmarkWarmCache",
}

type benchmarkResult struct {
	Name       string             `json:"name"`
	Iterations int64              `json:"iterations"`
	Metrics    map[string]float64 `json:"metrics"`
}

func runSelectedMicrobenchmarks(evidence preparationEvidence, workspace captureWorkspace, selected policy) error {
	var workload *workloadPolicy
	for index := range selected.Workloads {
		if selected.Workloads[index].ID == "microbenchmarks-selected" {
			workload = &selected.Workloads[index]
			break
		}
	}
	if workload == nil {
		return fmt.Errorf("microbenchmarks-selected is missing from the workload registry")
	}
	resultsRoot := filepath.Join(workspace.Root, "samples")
	if err := os.MkdirAll(resultsRoot, 0o755); err != nil {
		return err
	}
	outputPath := filepath.Join(resultsRoot, workload.ID+".jsonl")
	if complete, err := completeSampleFile(outputPath, selected.Sample.MicrobenchmarkCount); err != nil {
		return err
	} else if complete {
		return nil
	}
	output, err := os.OpenFile(outputPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600) // #nosec G304 -- path is rooted in the capture workspace.
	if err != nil {
		return err
	}
	defer output.Close()
	writer := bufio.NewWriter(output)

	port, stopServer, err := startBenchmarkServer(workspace)
	if err != nil {
		return err
	}
	defer func() { _ = stopServer() }()
	environment := append([]string(nil), workspace.Environment...)
	environment = append(environment, fmt.Sprintf("BEADS_BENCH_DOLT_PORT=%d", port))
	pattern := "^(" + strings.Join(selectedBenchmarkNames, "|") + ")$"
	arguments := []string{
		"go", "test", "-tags=bench,gms_pure_go", "-run=^$", "-bench=" + pattern,
		"-benchmem", "-benchtime=" + selected.Sample.MicrobenchmarkBenchtime, "-count=1", "./internal/storage/dolt",
	}
	for index := -selected.Sample.SetupRuns; index < selected.Sample.MicrobenchmarkCount; index++ {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Minute)
		measured, measureErr := measureProcess(ctx, workspace.Source, environment, arguments)
		cancel()
		if measureErr != nil {
			return measureErr
		}
		benchmarks, err := parseBenchmarkResults(measured)
		if err != nil {
			return fmt.Errorf("%s sample %d: %w", workload.ID, index, err)
		}
		if index < 0 {
			continue
		}
		names := make([]string, 0, len(benchmarks))
		for _, benchmark := range benchmarks {
			names = append(names, benchmark.Name)
		}
		observed := digestBytes([]byte(strings.Join(names, "\n") + "\n"))
		record := sampleRecord{
			SchemaVersion: 1, RunID: evidence.RunID, WorkloadID: workload.ID, SampleIndex: index,
			Measurement: measured.Measurement, Validation: "five selected benchmarks reported time, bytes, and allocations per operation",
			ObservedSHA256: observed, Benchmarks: benchmarks,
		}
		if err := json.NewEncoder(writer).Encode(record); err != nil {
			return err
		}
		if err := writer.Flush(); err != nil {
			return err
		}
	}
	if err := writer.Flush(); err != nil {
		return err
	}
	if err := stopServer(); err != nil {
		return err
	}
	return removeSampleWorkspace(workspace.Root, filepath.Join(workspace.Root, "benchmark-server"))
}

func parseBenchmarkResults(output processOutput) ([]benchmarkResult, error) {
	if output.Measurement.ExitCode != 0 {
		return nil, fmt.Errorf("go benchmark exit %d: %s", output.Measurement.ExitCode, strings.TrimSpace(string(output.Stderr)))
	}
	var results []benchmarkResult
	scanner := bufio.NewScanner(strings.NewReader(string(output.Stdout)))
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 8 || !strings.HasPrefix(fields[0], "Benchmark") {
			continue
		}
		iterations, err := strconv.ParseInt(fields[1], 10, 64)
		if err != nil || iterations < 1 {
			return nil, fmt.Errorf("invalid iteration count in %q", scanner.Text())
		}
		metrics := make(map[string]float64)
		for index := 2; index+1 < len(fields); index += 2 {
			value, err := strconv.ParseFloat(fields[index], 64)
			if err != nil {
				return nil, fmt.Errorf("invalid metric in %q", scanner.Text())
			}
			metrics[fields[index+1]] = value
		}
		for _, required := range []string{"ns/op", "B/op", "allocs/op"} {
			if _, ok := metrics[required]; !ok {
				return nil, fmt.Errorf("%s is missing %s", fields[0], required)
			}
		}
		results = append(results, benchmarkResult{Name: fields[0], Iterations: iterations, Metrics: metrics})
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	sort.Slice(results, func(left, right int) bool { return results[left].Name < results[right].Name })
	actual := make([]string, 0, len(results))
	for _, result := range results {
		actual = append(actual, benchmarkCPUSuffix.ReplaceAllString(result.Name, ""))
	}
	if !sameStrings(actual, selectedBenchmarkNames) {
		return nil, fmt.Errorf("selected benchmark result set is incomplete")
	}
	return results, nil
}

func startBenchmarkServer(workspace captureWorkspace) (int, func() error, error) {
	serverRoot := filepath.Join(workspace.Root, "benchmark-server")
	for _, directory := range []string{serverRoot, filepath.Join(serverRoot, "data"), filepath.Join(serverRoot, "config"), filepath.Join(serverRoot, "home"), filepath.Join(serverRoot, "tmp")} {
		if err := os.MkdirAll(directory, 0o755); err != nil {
			return 0, nil, err
		}
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		return 0, nil, err
	}
	port := listener.Addr().(*net.TCPAddr).Port
	if err := listener.Close(); err != nil {
		return 0, nil, err
	}
	logFile, err := os.OpenFile(filepath.Join(serverRoot, "server.log"), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600) // #nosec G304 -- path is rooted in the capture workspace.
	if err != nil {
		return 0, nil, err
	}
	arguments := []string{
		"sql-server", "--host", "127.0.0.1", "--port", strconv.Itoa(port),
		"--data-dir", filepath.Join(serverRoot, "data"), "--doltcfg-dir", filepath.Join(serverRoot, "config"), "--loglevel", "error",
	}
	command := exec.Command(workspace.DoltBinary, arguments...) // #nosec G204 -- binary and directories are policy-pinned capture inputs.
	command.Dir = serverRoot
	command.Env = replaceEnvironment(workspace.Environment, "HOME", filepath.Join(serverRoot, "home"))
	command.Env = replaceEnvironment(command.Env, "TMPDIR", filepath.Join(serverRoot, "tmp"))
	command.Stdout = logFile
	command.Stderr = logFile
	if err := command.Start(); err != nil {
		_ = logFile.Close()
		return 0, nil, err
	}
	waited := make(chan error, 1)
	go func() { waited <- command.Wait() }()
	stopped := false
	stop := func() error {
		if stopped {
			return nil
		}
		stopped = true
		defer func() { _ = logFile.Close() }()
		if err := command.Process.Signal(os.Interrupt); err != nil {
			select {
			case waitErr := <-waited:
				return waitErr
			default:
				return err
			}
		}
		select {
		case <-waited:
			return nil
		case <-time.After(10 * time.Second):
			if err := command.Process.Kill(); err != nil {
				return err
			}
			<-waited
			return nil
		}
	}
	deadline := time.Now().Add(30 * time.Second)
	for {
		connection, dialErr := net.DialTimeout("tcp4", fmt.Sprintf("127.0.0.1:%d", port), 250*time.Millisecond)
		if dialErr == nil {
			_ = connection.Close()
			return port, stop, nil
		}
		select {
		case waitErr := <-waited:
			stopped = true
			_ = logFile.Close()
			return 0, nil, fmt.Errorf("dedicated Dolt server exited before readiness: %w", waitErr)
		default:
		}
		if time.Now().After(deadline) {
			_ = stop()
			return 0, nil, fmt.Errorf("dedicated Dolt server did not become ready")
		}
		time.Sleep(100 * time.Millisecond)
	}
}
