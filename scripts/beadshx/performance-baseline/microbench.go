package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

var benchmarkNamePattern = regexp.MustCompile(`^Benchmark[A-Za-z0-9_]+$`)
var documentedBenchmarkPattern = regexp.MustCompile(`\bBenchmark[A-Z0-9_][A-Za-z0-9_]*\b`)

var benchmarkPackages = []string{
	"./cmd/bd",
	"./internal/types",
	"./internal/storage/embeddeddolt",
	"./internal/storage/dolt",
}

type goTestEvent struct {
	Package string `json:"Package"`
	Output  string `json:"Output"`
}

type benchmarkCatalog struct {
	SchemaVersion     int      `json:"schemaVersion"`
	SourceCommit      string   `json:"sourceCommit"`
	Executable        []string `json:"executable"`
	DocumentationOnly []string `json:"documentationOnly"`
}

func runMicrobenchmarkDiscovery(evidence preparationEvidence, workspace captureWorkspace, selected policy) error {
	var workload *workloadPolicy
	for index := range selected.Workloads {
		if selected.Workloads[index].ID == "microbenchmarks-discovery" {
			workload = &selected.Workloads[index]
			break
		}
	}
	if workload == nil {
		return fmt.Errorf("microbenchmarks-discovery is missing from the workload registry")
	}
	resultsRoot := filepath.Join(workspace.Root, "samples")
	if err := os.MkdirAll(resultsRoot, 0o755); err != nil {
		return err
	}
	outputPath := filepath.Join(resultsRoot, workload.ID+".jsonl")
	if complete, err := completeSampleFile(outputPath, selected.Sample.MeasuredRuns); err != nil {
		return err
	} else if complete {
		return ensureBenchmarkCatalog(evidence, workspace, outputPath)
	}
	output, err := os.OpenFile(outputPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600) // #nosec G304 -- path is rooted in the capture workspace.
	if err != nil {
		return err
	}
	defer output.Close()
	writer := bufio.NewWriter(output)

	arguments := []string{"go", "test", "-json", "-tags=bench,gms_pure_go", "-run=^$", "-list=^Benchmark"}
	arguments = append(arguments, benchmarkPackages...)
	var discovered []string
	for index := -selected.Sample.SetupRuns; index < selected.Sample.MeasuredRuns; index++ {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
		measured, measureErr := measureProcess(ctx, workspace.Source, workspace.Environment, arguments)
		cancel()
		if measureErr != nil {
			return measureErr
		}
		names, err := parseBenchmarkNames(measured)
		if err != nil {
			return fmt.Errorf("%s sample %d: %w", workload.ID, index, err)
		}
		if discovered == nil {
			discovered = names
		} else if strings.Join(discovered, "\n") != strings.Join(names, "\n") {
			return fmt.Errorf("%s sample %d discovered a different benchmark set", workload.ID, index)
		}
		if index < 0 {
			continue
		}
		observed := digestBytes([]byte(strings.Join(names, "\n") + "\n"))
		record := sampleRecord{
			SchemaVersion:  1,
			RunID:          evidence.RunID,
			WorkloadID:     workload.ID,
			SampleIndex:    index,
			Measurement:    measured.Measurement,
			Validation:     fmt.Sprintf("go test listed %d executable benchmarks", len(names)),
			ObservedSHA256: observed,
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
	return writeBenchmarkCatalog(evidence, workspace, discovered)
}

func parseBenchmarkNames(output processOutput) ([]string, error) {
	if output.Measurement.ExitCode != 0 {
		return nil, fmt.Errorf("go test exit %d: %s", output.Measurement.ExitCode, strings.TrimSpace(string(output.Stderr)))
	}
	unique := make(map[string]bool)
	scanner := bufio.NewScanner(strings.NewReader(string(output.Stdout)))
	for scanner.Scan() {
		var event goTestEvent
		if err := json.Unmarshal(scanner.Bytes(), &event); err != nil {
			return nil, fmt.Errorf("decode go test event: %w", err)
		}
		name := strings.TrimSpace(event.Output)
		if event.Package != "" && benchmarkNamePattern.MatchString(name) {
			unique[event.Package+"/"+name] = true
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if len(unique) == 0 {
		return nil, fmt.Errorf("go test listed no executable benchmarks")
	}
	names := make([]string, 0, len(unique))
	for name := range unique {
		names = append(names, name)
	}
	sort.Strings(names)
	return names, nil
}

func ensureBenchmarkCatalog(evidence preparationEvidence, workspace captureWorkspace, samplesPath string) error {
	records, err := readSampleRecords(samplesPath)
	if err != nil {
		return fmt.Errorf("read benchmark discovery samples: %w", err)
	}
	if len(records) == 0 {
		return fmt.Errorf("benchmark discovery samples are empty")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	arguments := []string{"go", "test", "-json", "-tags=bench,gms_pure_go", "-run=^$", "-list=^Benchmark"}
	arguments = append(arguments, benchmarkPackages...)
	output, err := measureProcess(ctx, workspace.Source, workspace.Environment, arguments)
	if err != nil {
		return err
	}
	names, err := parseBenchmarkNames(output)
	if err != nil {
		return err
	}
	return writeBenchmarkCatalog(evidence, workspace, names)
}

func writeBenchmarkCatalog(evidence preparationEvidence, workspace captureWorkspace, executable []string) error {
	documented, err := documentedBenchmarks(workspace.Source)
	if err != nil {
		return err
	}
	executableBare := make(map[string]bool, len(executable))
	for _, qualified := range executable {
		parts := strings.Split(qualified, "/")
		executableBare[parts[len(parts)-1]] = true
	}
	var documentationOnly []string
	for _, name := range documented {
		if !executableBare[name] {
			documentationOnly = append(documentationOnly, name)
		}
	}
	catalog := benchmarkCatalog{
		SchemaVersion:     1,
		SourceCommit:      evidence.Source.Commit,
		Executable:        executable,
		DocumentationOnly: documentationOnly,
	}
	content, err := json.MarshalIndent(catalog, "", "  ")
	if err != nil {
		return err
	}
	return writeFile(filepath.Join(workspace.Root, "benchmark-catalog.json"), append(content, '\n'))
}

func documentedBenchmarks(source string) ([]string, error) {
	unique := make(map[string]bool)
	err := filepath.WalkDir(source, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() {
			if entry.Name() == ".git" {
				return filepath.SkipDir
			}
			return nil
		}
		if filepath.Ext(path) != ".md" {
			return nil
		}
		content, err := os.ReadFile(path) // #nosec G304 -- path is found under the pinned source tree.
		if err != nil {
			return err
		}
		for _, match := range documentedBenchmarkPattern.FindAllString(string(content), -1) {
			unique[match] = true
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	names := make([]string, 0, len(unique))
	for name := range unique {
		names = append(names, name)
	}
	sort.Strings(names)
	return names, nil
}
