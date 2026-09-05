package main

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type sampleRecord struct {
	SchemaVersion  int                `json:"schemaVersion"`
	RunID          string             `json:"runId"`
	WorkloadID     string             `json:"workloadId"`
	SampleIndex    int                `json:"sampleIndex"`
	FixtureID      *string            `json:"fixtureId"`
	FixtureSHA256  string             `json:"fixtureSha256,omitempty"`
	Measurement    processMeasurement `json:"measurement"`
	Validation     string             `json:"validation"`
	ObservedSHA256 string             `json:"observedSha256"`
	ArtifactSHA256 string             `json:"artifactSha256,omitempty"`
	ArtifactBytes  int64              `json:"artifactBytes,omitempty"`
	Benchmarks     []benchmarkResult  `json:"benchmarks,omitempty"`
}

func runRuntimeWorkloads(evidence preparationEvidence, workspace captureWorkspace, selected policy) error {
	evidenceByFixture := make(map[string]fixtureEvidence, len(evidence.Fixtures))
	for _, fixture := range evidence.Fixtures {
		evidenceByFixture[fixture.ID] = fixture
	}
	resultsRoot := filepath.Join(workspace.Root, "samples")
	if err := os.MkdirAll(resultsRoot, 0o755); err != nil {
		return err
	}
	for _, workload := range selected.Workloads {
		if !isDirectRuntimeWorkload(workload.ID) {
			continue
		}
		if err := runRuntimeWorkload(evidence.RunID, workspace, workload, evidenceByFixture, selected.Sample, resultsRoot); err != nil {
			return err
		}
	}
	return nil
}

func isDirectRuntimeWorkload(id string) bool {
	for _, prefix := range []string{"startup-", "read-", "write-", "large-list-"} {
		if strings.HasPrefix(id, prefix) {
			return true
		}
	}
	return id == "migration-current-noop"
}

func runRuntimeWorkload(runID string, workspace captureWorkspace, workload workloadPolicy, fixtures map[string]fixtureEvidence, samples samplePolicy, resultsRoot string) error {
	outputPath := filepath.Join(resultsRoot, workload.ID+".jsonl")
	if complete, err := completeSampleFile(outputPath, samples.MeasuredRuns); err != nil {
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

	for index := -samples.SetupRuns; index < samples.MeasuredRuns; index++ {
		sampleRoot := filepath.Join(workspace.Root, "sample-workspaces", workload.ID, fmt.Sprintf("%02d", index+samples.SetupRuns))
		if err := prepareSampleWorkspace(sampleRoot, workspace, workload); err != nil {
			return err
		}
		arguments, err := runtimeArguments(workspace.Binary, workload)
		if err != nil {
			return err
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		measured, measureErr := measureProcess(ctx, sampleRoot, workspace.Environment, arguments)
		cancel()
		if measureErr != nil {
			return measureErr
		}
		observedDigest, validation, err := validateRuntimeResult(workspace, sampleRoot, workload, measured)
		if err != nil {
			return fmt.Errorf("%s sample %d: %w", workload.ID, index, err)
		}
		if index >= 0 {
			measured.Measurement.Command[0] = "<pinned-bd>"
			fixtureDigest := ""
			if workload.Fixture != nil {
				fixtureDigest = fixtures[*workload.Fixture].LogicalSHA256
			}
			record := sampleRecord{
				SchemaVersion:  1,
				RunID:          runID,
				WorkloadID:     workload.ID,
				SampleIndex:    index,
				FixtureID:      workload.Fixture,
				FixtureSHA256:  fixtureDigest,
				Measurement:    measured.Measurement,
				Validation:     validation,
				ObservedSHA256: observedDigest,
			}
			if err := json.NewEncoder(writer).Encode(record); err != nil {
				return err
			}
			if err := writer.Flush(); err != nil {
				return err
			}
		}
		if err := removeSampleWorkspace(workspace.Root, sampleRoot); err != nil {
			return err
		}
	}
	return writer.Flush()
}

func completeSampleFile(path string, expected int) (bool, error) {
	file, err := os.Open(path) // #nosec G304 -- path is rooted in the capture workspace.
	if os.IsNotExist(err) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	count := 0
	for scanner.Scan() {
		count++
	}
	if err := scanner.Err(); err != nil {
		return false, err
	}
	if count != expected {
		return false, fmt.Errorf("existing sample file %s has %d rows; want %d", filepath.Base(path), count, expected)
	}
	return true, nil
}

func prepareSampleWorkspace(sampleRoot string, workspace captureWorkspace, workload workloadPolicy) error {
	if err := os.MkdirAll(filepath.Dir(sampleRoot), 0o755); err != nil {
		return err
	}
	if workload.Fixture == nil {
		return os.Mkdir(sampleRoot, 0o755)
	}
	source := filepath.Join(workspace.Pristine, *workload.Fixture)
	command := exec.Command("/bin/cp", "-cR", source, sampleRoot) // #nosec G204 -- paths are confined to the capture workspace.
	if output, err := command.CombinedOutput(); err != nil {
		return fmt.Errorf("clone fixture: %w: %s", err, strings.TrimSpace(string(output)))
	}
	return nil
}

func removeSampleWorkspace(captureRoot, sampleRoot string) error {
	relative, err := filepath.Rel(captureRoot, sampleRoot)
	if err != nil || relative == "." || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return fmt.Errorf("refuse to remove sample outside capture workspace")
	}
	return os.RemoveAll(sampleRoot)
}

func runtimeArguments(binary string, workload workloadPolicy) ([]string, error) {
	prefix := "perf-s"
	if workload.Fixture != nil && *workload.Fixture == "large-v1" {
		prefix = "perf-l"
	}
	id := func(number int) string { return fmt.Sprintf("%s-%05d", prefix, number) }
	common := []string{binary, "--actor", "fixture-runner", "--no-color"}
	commands := map[string][]string{
		"startup-version":         {"version", "--json"},
		"startup-help":            {"--help"},
		"startup-workspace-info":  {"info", "--json"},
		"read-show-small":         {"--readonly", "show", id(1), "--json"},
		"read-show-large":         {"--readonly", "show", id(1), "--json"},
		"read-list-small":         {"--readonly", "list", "--all", "--limit", "0", "--json"},
		"read-list-large":         {"--readonly", "list", "--all", "--limit", "0", "--json"},
		"read-ready-small":        {"--readonly", "ready", "--limit", "0", "--json"},
		"read-ready-large":        {"--readonly", "ready", "--limit", "0", "--json"},
		"read-search-small":       {"--readonly", "search", "Performance fixture issue 00001", "--json"},
		"read-search-large":       {"--readonly", "search", "Performance fixture issue 00001", "--json"},
		"read-count-small":        {"--readonly", "count", "--json"},
		"read-count-large":        {"--readonly", "count", "--json"},
		"read-dependencies-small": {"--readonly", "dep", "list", id(5), "--json"},
		"read-dependencies-large": {"--readonly", "dep", "list", id(5), "--json"},
		"write-create":            {"create", "--id", "perf-created", "--title", "Measured create", "--type", "task", "--priority", "2", "--json"},
		"write-update":            {"update", id(1), "--title", "Measured update", "--json"},
		"write-close":             {"close", id(1), "--reason", "Measured close", "--json"},
		"write-reopen":            {"reopen", id(5), "--reason", "Measured reopen", "--json"},
		"write-dependency":        {"dep", "add", id(20), id(2), "--json"},
		"write-label":             {"label", "add", id(20), "measured-label", "--json"},
		"write-comment":           {"comments", "add", id(20), "Measured comment", "--json"},
		"migration-current-noop":  {"migrate", "--yes", "--json"},
		"large-list-json":         {"--readonly", "list", "--all", "--limit", "0", "--json"},
		"large-list-text":         {"--readonly", "list", "--all", "--limit", "0"},
	}
	command, found := commands[workload.ID]
	if !found {
		return nil, fmt.Errorf("unknown direct runtime workload %s", workload.ID)
	}
	return append(common, command...), nil
}

func validateRuntimeResult(workspace captureWorkspace, sampleRoot string, workload workloadPolicy, output processOutput) (string, string, error) {
	if output.Measurement.ExitCode != 0 {
		return "", "", fmt.Errorf("exit %d: %s", output.Measurement.ExitCode, strings.TrimSpace(string(output.Stderr)))
	}
	if workload.ID == "startup-help" {
		if !bytesContain(output.Stdout, []byte("Usage:")) {
			return "", "", fmt.Errorf("root help marker is missing")
		}
		return digestBytes(output.Stdout), "root help marker present", nil
	}
	if workload.ID == "large-list-text" {
		if len(output.Stdout) == 0 {
			return "", "", fmt.Errorf("text list is empty")
		}
		return digestBytes(output.Stdout), "non-empty text list", nil
	}
	if workload.ID == "migration-current-noop" {
		if !bytesContain(output.Stdout, []byte("Version matches")) {
			return "", "", fmt.Errorf("current-schema migration did not report a version match")
		}
		return runtimeReadback(workspace, sampleRoot, workload)
	}
	var decoded any
	if err := json.Unmarshal(output.Stdout, &decoded); err != nil {
		return "", "", fmt.Errorf("JSON output: %w", err)
	}
	if workload.ID == "startup-workspace-info" {
		if object, ok := decoded.(map[string]any); ok {
			delete(object, "database_path")
		}
	}
	observed, err := json.Marshal(decoded)
	if err != nil {
		return "", "", err
	}
	if strings.HasPrefix(workload.ID, "write-") {
		return runtimeReadback(workspace, sampleRoot, workload)
	}
	return digestBytes(observed), "JSON parsed and post-state observer passed", nil
}

func runtimeReadback(workspace captureWorkspace, sampleRoot string, workload workloadPolicy) (string, string, error) {
	argumentsByWorkload := map[string][]string{
		"write-create":           {"show", "perf-created", "--json"},
		"write-update":           {"show", "perf-s-00001", "--json"},
		"write-close":            {"show", "perf-s-00001", "--json"},
		"write-reopen":           {"show", "perf-s-00005", "--json"},
		"write-dependency":       {"dep", "list", "perf-s-00020", "--json"},
		"write-label":            {"show", "perf-s-00020", "--json"},
		"write-comment":          {"comments", "perf-s-00020", "--json"},
		"migration-current-noop": {"count", "--json"},
	}
	expectedMarker := map[string]string{
		"write-create":           "perf-created",
		"write-update":           "Measured update",
		"write-close":            `"status":"closed"`,
		"write-reopen":           `"status":"open"`,
		"write-dependency":       "perf-s-00002",
		"write-label":            "measured-label",
		"write-comment":          "Measured comment",
		"migration-current-noop": `"count":32`,
	}
	arguments := append([]string{workspace.Binary, "--actor", "fixture-validator", "--no-color", "--readonly"}, argumentsByWorkload[workload.ID]...)
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	readback, err := measureProcess(ctx, sampleRoot, workspace.Environment, arguments)
	if err != nil || readback.Measurement.ExitCode != 0 {
		return "", "", fmt.Errorf("post-state readback failed")
	}
	var decoded any
	if err := json.Unmarshal(readback.Stdout, &decoded); err != nil {
		return "", "", fmt.Errorf("post-state JSON: %w", err)
	}
	compact := strings.ReplaceAll(string(readback.Stdout), " ", "")
	compact = strings.ReplaceAll(compact, "\n", "")
	if !strings.Contains(compact, strings.ReplaceAll(expectedMarker[workload.ID], " ", "")) {
		return "", "", fmt.Errorf("post-state marker %q is missing", expectedMarker[workload.ID])
	}
	return digestBytes(readback.Stdout), "typed post-state readback passed", nil
}

func bytesContain(content, selected []byte) bool {
	return strings.Contains(string(content), string(selected))
}

func digestBytes(content []byte) string {
	digest := sha256.Sum256(content)
	return hex.EncodeToString(digest[:])
}
