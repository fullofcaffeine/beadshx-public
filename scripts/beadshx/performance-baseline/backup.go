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

func runBackupWorkloads(evidence preparationEvidence, workspace captureWorkspace, selected policy) error {
	fixtures := make(map[string]fixtureEvidence, len(evidence.Fixtures))
	for _, fixture := range evidence.Fixtures {
		fixtures[fixture.ID] = fixture
	}
	resultsRoot := filepath.Join(workspace.Root, "samples")
	if err := os.MkdirAll(resultsRoot, 0o755); err != nil {
		return err
	}
	for _, workload := range selected.Workloads {
		if !strings.HasPrefix(workload.ID, "backup-") {
			continue
		}
		if workload.Fixture == nil {
			return fmt.Errorf("%s must name a fixture", workload.ID)
		}
		if err := runBackupWorkload(evidence.RunID, workspace, workload, fixtures[*workload.Fixture], selected.Sample, resultsRoot); err != nil {
			return err
		}
	}
	return nil
}

func runBackupWorkload(runID string, workspace captureWorkspace, workload workloadPolicy, fixture fixtureEvidence, samples samplePolicy, resultsRoot string) error {
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
		sourceRoot := filepath.Join(sampleRoot, "source")
		backupRoot := filepath.Join(sampleRoot, "backup")
		restoredRoot := filepath.Join(sampleRoot, "restored")
		if err := prepareBackupSample(workspace, *workload.Fixture, sampleRoot, sourceRoot, backupRoot); err != nil {
			return err
		}
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Minute)
		measured, measureErr := measureProcess(ctx, sourceRoot, workspace.Environment, []string{workspace.Binary, "--actor", "fixture-runner", "--no-color", "backup", "sync"})
		cancel()
		if measureErr != nil {
			return measureErr
		}
		artifactDigest, artifactBytes, err := hashDirectory(backupRoot)
		if err != nil {
			return err
		}
		logicalDigest, err := validateBackupRestore(workspace, sourceRoot, backupRoot, restoredRoot, measured)
		if err != nil {
			return fmt.Errorf("%s sample %d: %w", workload.ID, index, err)
		}
		if index >= 0 {
			measured.Measurement.Command[0] = "<pinned-bd>"
			record := sampleRecord{
				SchemaVersion: 1, RunID: runID, WorkloadID: workload.ID, SampleIndex: index,
				FixtureID: workload.Fixture, FixtureSHA256: fixture.LogicalSHA256,
				Measurement: measured.Measurement, Validation: "backup restored to an equal full logical export",
				ObservedSHA256: logicalDigest, ArtifactSHA256: artifactDigest, ArtifactBytes: artifactBytes,
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

func prepareBackupSample(workspace captureWorkspace, fixtureID, sampleRoot, sourceRoot, backupRoot string) error {
	if err := os.MkdirAll(sampleRoot, 0o755); err != nil {
		return err
	}
	clone := exec.Command("/bin/cp", "-cR", filepath.Join(workspace.Pristine, fixtureID), sourceRoot) // #nosec G204 -- paths are confined to the capture workspace.
	if output, err := clone.CombinedOutput(); err != nil {
		return fmt.Errorf("clone backup fixture: %w: %s", err, strings.TrimSpace(string(output)))
	}
	return requireSuccessfulCommand(workspace, sourceRoot, 2*time.Minute, []string{workspace.Binary, "--actor", "fixture-runner", "--no-color", "backup", "init", backupRoot})
}

func validateBackupRestore(workspace captureWorkspace, sourceRoot, backupRoot, restoredRoot string, measured processOutput) (string, error) {
	if measured.Measurement.ExitCode != 0 {
		return "", fmt.Errorf("backup sync exit %d: %s", measured.Measurement.ExitCode, strings.TrimSpace(string(measured.Stderr)))
	}
	if err := os.MkdirAll(restoredRoot, 0o755); err != nil {
		return "", err
	}
	if output, err := exec.Command("git", "-C", restoredRoot, "init", "-q").CombinedOutput(); err != nil {
		return "", fmt.Errorf("initialize restore git repository: %w: %s", err, strings.TrimSpace(string(output)))
	}
	if err := requireSuccessfulCommand(workspace, restoredRoot, 5*time.Minute, []string{workspace.Binary, "--actor", "fixture-runner", "--no-color", "init", "--prefix", "perf", "--skip-hooks", "--skip-agents", "--quiet", "--non-interactive"}); err != nil {
		return "", err
	}
	if err := requireSuccessfulCommand(workspace, restoredRoot, 15*time.Minute, []string{workspace.Binary, "--actor", "fixture-runner", "--no-color", "backup", "restore", backupRoot, "--force"}); err != nil {
		return "", err
	}
	sourceDigest, err := logicalExportDigest(workspace, sourceRoot)
	if err != nil {
		return "", err
	}
	restoredDigest, err := logicalExportDigest(workspace, restoredRoot)
	if err != nil {
		return "", err
	}
	if restoredDigest != sourceDigest {
		return "", fmt.Errorf("restored logical export digest %s differs from source %s", restoredDigest, sourceDigest)
	}
	return restoredDigest, nil
}

func requireSuccessfulCommand(workspace captureWorkspace, directory string, timeout time.Duration, arguments []string) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	output, err := measureProcess(ctx, directory, workspace.Environment, arguments)
	if err != nil {
		return err
	}
	if output.Measurement.ExitCode != 0 {
		return fmt.Errorf("%s exit %d: %s", filepath.Base(arguments[0]), output.Measurement.ExitCode, strings.TrimSpace(string(output.Stderr)))
	}
	return nil
}

func logicalExportDigest(workspace captureWorkspace, directory string) (string, error) {
	_, digest, err := logicalExport(workspace, directory)
	return digest, err
}

func logicalExport(workspace captureWorkspace, directory string) ([]byte, string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	output, err := measureProcess(ctx, directory, workspace.Environment, []string{workspace.Binary, "--actor", "fixture-runner", "--no-color", "--readonly", "export", "--all"})
	if err != nil {
		return nil, "", err
	}
	if output.Measurement.ExitCode != 0 {
		return nil, "", fmt.Errorf("logical export exit %d: %s", output.Measurement.ExitCode, strings.TrimSpace(string(output.Stderr)))
	}
	if len(output.Stdout) == 0 {
		return nil, "", fmt.Errorf("logical export is empty")
	}
	return output.Stdout, digestBytes(output.Stdout), nil
}
