package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type syncResult struct {
	Status    string   `json:"status"`
	Conflicts []string `json:"conflicts"`
	Pushed    bool     `json:"pushed"`
}

func runSyncWorkloads(evidence preparationEvidence, workspace captureWorkspace, selected policy) error {
	fixtures := make(map[string]fixtureEvidence, len(evidence.Fixtures))
	for _, fixture := range evidence.Fixtures {
		fixtures[fixture.ID] = fixture
	}
	resultsRoot := filepath.Join(workspace.Root, "samples")
	if err := os.MkdirAll(resultsRoot, 0o755); err != nil {
		return err
	}
	for _, workload := range selected.Workloads {
		if !strings.HasPrefix(workload.ID, "sync-") {
			continue
		}
		if workload.Fixture == nil {
			return fmt.Errorf("%s must name a fixture", workload.ID)
		}
		if err := runSyncWorkload(evidence.RunID, workspace, workload, fixtures[*workload.Fixture], selected.Sample, resultsRoot); err != nil {
			return err
		}
	}
	return nil
}

func runSyncWorkload(runID string, workspace captureWorkspace, workload workloadPolicy, fixture fixtureEvidence, samples samplePolicy, resultsRoot string) error {
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
		leftRoot := filepath.Join(sampleRoot, "left")
		rightRoot := filepath.Join(sampleRoot, "right")
		remoteRoot := filepath.Join(sampleRoot, "remote")
		if err := prepareSyncSample(workspace, *workload.Fixture, sampleRoot, leftRoot, rightRoot, remoteRoot); err != nil {
			return err
		}
		remoteBefore, remoteBytesBefore, err := arrangeSyncState(workspace, workload.ID, leftRoot, rightRoot, remoteRoot)
		if err != nil {
			return fmt.Errorf("%s sample %d setup: %w", workload.ID, index, err)
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		measured, measureErr := measureProcess(ctx, leftRoot, workspace.Environment, syncArguments(workspace.Binary))
		cancel()
		if measureErr != nil {
			return measureErr
		}
		observed, artifactDigest, artifactBytes, validation, err := validateSyncResult(workspace, workload.ID, leftRoot, rightRoot, remoteRoot, remoteBefore, remoteBytesBefore, measured)
		if err != nil {
			return fmt.Errorf("%s sample %d: %w", workload.ID, index, err)
		}
		if index >= 0 {
			measured.Measurement.Command[0] = "<pinned-bd>"
			record := sampleRecord{
				SchemaVersion: 1, RunID: runID, WorkloadID: workload.ID, SampleIndex: index,
				FixtureID: workload.Fixture, FixtureSHA256: fixture.LogicalSHA256,
				Measurement: measured.Measurement, Validation: validation, ObservedSHA256: observed,
				ArtifactSHA256: artifactDigest, ArtifactBytes: artifactBytes,
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

func prepareSyncSample(workspace captureWorkspace, fixtureID, sampleRoot, leftRoot, rightRoot, remoteRoot string) error {
	if err := os.MkdirAll(sampleRoot, 0o755); err != nil {
		return err
	}
	for _, destination := range []string{leftRoot, rightRoot} {
		clone := exec.Command("/bin/cp", "-cR", filepath.Join(workspace.Pristine, fixtureID), destination) // #nosec G204 -- paths are confined to the capture workspace.
		if output, err := clone.CombinedOutput(); err != nil {
			return fmt.Errorf("clone sync fixture: %w: %s", err, strings.TrimSpace(string(output)))
		}
	}
	if err := os.Mkdir(remoteRoot, 0o755); err != nil {
		return err
	}
	remoteURL := "file://" + remoteRoot
	for _, replica := range []string{leftRoot, rightRoot} {
		if err := requireSuccessfulCommand(workspace, replica, 2*time.Minute, []string{workspace.Binary, "--actor", "fixture-runner", "--no-color", "dolt", "remote", "add", "baseline", remoteURL}); err != nil {
			return err
		}
	}
	if err := requireSuccessfulCommand(workspace, leftRoot, 5*time.Minute, []string{workspace.Binary, "--actor", "fixture-runner", "--no-color", "dolt", "push", "--remote", "baseline", "--no-adopt"}); err != nil {
		return err
	}
	return requireSuccessfulCommand(workspace, rightRoot, 5*time.Minute, []string{workspace.Binary, "--actor", "fixture-runner", "--no-color", "dolt", "pull", "--remote", "baseline"})
}

func arrangeSyncState(workspace captureWorkspace, workloadID, leftRoot, rightRoot, remoteRoot string) (string, int64, error) {
	create := func(directory, id, title string) error {
		return requireSuccessfulCommand(workspace, directory, 2*time.Minute, []string{workspace.Binary, "--actor", "fixture-runner", "--no-color", "create", "--id", id, "--title", title, "--type", "task", "--priority", "2", "--json"})
	}
	setKV := func(directory, value string) error {
		return requireSuccessfulCommand(workspace, directory, 2*time.Minute, []string{workspace.Binary, "--actor", "fixture-runner", "--no-color", "kv", "set", "baseline-conflict", value, "--json"})
	}
	syncRight := func() error {
		return requireSuccessfulCommand(workspace, rightRoot, 5*time.Minute, syncArguments(workspace.Binary))
	}
	switch workloadID {
	case "sync-no-change":
	case "sync-push-only":
		if err := create(leftRoot, "perf-sync-left", "Left replica mutation"); err != nil {
			return "", 0, err
		}
	case "sync-pull-only":
		if err := create(rightRoot, "perf-sync-right", "Right replica mutation"); err != nil {
			return "", 0, err
		}
		if err := syncRight(); err != nil {
			return "", 0, err
		}
	case "sync-clean-merge":
		if err := create(leftRoot, "perf-sync-left", "Left replica mutation"); err != nil {
			return "", 0, err
		}
		if err := create(rightRoot, "perf-sync-right", "Right replica mutation"); err != nil {
			return "", 0, err
		}
		if err := syncRight(); err != nil {
			return "", 0, err
		}
	case "sync-conflict":
		if err := setKV(leftRoot, "left"); err != nil {
			return "", 0, err
		}
		if err := setKV(rightRoot, "right"); err != nil {
			return "", 0, err
		}
		if err := syncRight(); err != nil {
			return "", 0, err
		}
	default:
		return "", 0, fmt.Errorf("unknown sync workload %s", workloadID)
	}
	return hashDirectory(remoteRoot)
}

func syncArguments(binary string) []string {
	return []string{binary, "--actor", "fixture-runner", "--no-color", "sync", "--remote", "baseline", "--no-adopt", "--json"}
}

func validateSyncResult(workspace captureWorkspace, workloadID, leftRoot, rightRoot, remoteRoot, remoteBefore string, remoteBytesBefore int64, measured processOutput) (string, string, int64, string, error) {
	expectedExit := expectedExitCode(workloadID)
	if measured.Measurement.ExitCode != expectedExit {
		return "", "", 0, "", fmt.Errorf("sync exit %d; want %d: %s", measured.Measurement.ExitCode, expectedExit, strings.TrimSpace(string(measured.Stderr)))
	}
	var result syncResult
	if err := json.Unmarshal(measured.Stdout, &result); err != nil {
		return "", "", 0, "", fmt.Errorf("decode sync result: %w", err)
	}
	remoteAfter, remoteBytesAfter, err := hashDirectory(remoteRoot)
	if err != nil {
		return "", "", 0, "", err
	}
	if workloadID == "sync-conflict" {
		if result.Status != "conflict" || result.Pushed || len(result.Conflicts) == 0 {
			return "", "", 0, "", fmt.Errorf("conflict result did not report a halted unpushed conflict")
		}
		if remoteAfter != remoteBefore || remoteBytesAfter != remoteBytesBefore {
			return "", "", 0, "", fmt.Errorf("conflicted sync changed the remote artifact")
		}
		rightExport, _, err := logicalExport(workspace, rightRoot)
		if err != nil {
			return "", "", 0, "", err
		}
		rightDigest, err := canonicalJSONLDigest(rightExport)
		if err != nil {
			return "", "", 0, "", err
		}
		return rightDigest, remoteAfter, remoteBytesAfter, "exit 2 reported a config conflict and left the remote unchanged", nil
	}
	if result.Status != "ok" {
		return "", "", 0, "", fmt.Errorf("sync status = %q; want ok", result.Status)
	}
	if err := requireSuccessfulCommand(workspace, rightRoot, 5*time.Minute, syncArguments(workspace.Binary)); err != nil {
		return "", "", 0, "", err
	}
	leftExport, _, err := logicalExport(workspace, leftRoot)
	if err != nil {
		return "", "", 0, "", err
	}
	rightExport, _, err := logicalExport(workspace, rightRoot)
	if err != nil {
		return "", "", 0, "", err
	}
	leftDigest, err := canonicalJSONLDigest(leftExport)
	if err != nil {
		return "", "", 0, "", err
	}
	rightDigest, err := canonicalJSONLDigest(rightExport)
	if err != nil {
		return "", "", 0, "", err
	}
	if leftDigest != rightDigest {
		return "", "", 0, "", fmt.Errorf("replica logical export digests differ")
	}
	for _, marker := range syncMarkers(workloadID) {
		if !bytesContain(leftExport, []byte(marker)) || !bytesContain(rightExport, []byte(marker)) {
			return "", "", 0, "", fmt.Errorf("converged exports are missing %s", marker)
		}
	}
	remoteFinal, remoteFinalBytes, err := hashDirectory(remoteRoot)
	if err != nil {
		return "", "", 0, "", err
	}
	return leftDigest, remoteFinal, remoteFinalBytes, "both replicas converged with the expected mutations", nil
}

func syncMarkers(workloadID string) []string {
	switch workloadID {
	case "sync-push-only":
		return []string{"perf-sync-left"}
	case "sync-pull-only":
		return []string{"perf-sync-right"}
	case "sync-clean-merge":
		return []string{"perf-sync-left", "perf-sync-right"}
	default:
		return nil
	}
}
