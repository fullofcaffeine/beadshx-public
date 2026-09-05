package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func runBuildWorkloads(evidence preparationEvidence, workspace captureWorkspace, selected policy) error {
	resultsRoot := filepath.Join(workspace.Root, "samples")
	if err := os.MkdirAll(resultsRoot, 0o755); err != nil {
		return err
	}
	for _, workload := range selected.Workloads {
		if workload.Category != "build" {
			continue
		}
		if err := runBuildWorkload(evidence, workspace, workload, selected.Sample, resultsRoot); err != nil {
			return err
		}
	}
	return removeCaptureDirectory(workspace.Root, filepath.Join(workspace.Root, "build-caches"))
}

func runBuildWorkload(evidence preparationEvidence, workspace captureWorkspace, workload workloadPolicy, samples samplePolicy, resultsRoot string) error {
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

	sharedCache := filepath.Join(workspace.Root, "build-caches", workload.ID, "shared")
	if workload.ID != "build-clean" {
		if err := os.MkdirAll(sharedCache, 0o755); err != nil {
			return err
		}
	}
	for index := -samples.SetupRuns; index < samples.MeasuredRuns; index++ {
		cache := sharedCache
		if workload.ID == "build-clean" {
			cache = filepath.Join(workspace.Root, "build-caches", workload.ID, fmt.Sprintf("%02d", index+samples.SetupRuns))
			if err := os.MkdirAll(cache, 0o755); err != nil {
				return err
			}
		}
		environment := replaceEnvironment(workspace.Environment, "GOCACHE", cache)
		if workload.ID != "build-no-change" {
			if err := os.Remove(workspace.Binary); err != nil && !os.IsNotExist(err) {
				return err
			}
		}
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
		measured, measureErr := measureProcess(ctx, workspace.Source, environment, []string{"make", "build"})
		cancel()
		if measureErr != nil {
			return measureErr
		}
		if measured.Measurement.ExitCode != 0 {
			return fmt.Errorf("%s sample %d failed: %s", workload.ID, index, strings.TrimSpace(string(measured.Stderr)))
		}
		binary, err := inspectBinary(captureWorkspace{
			Source:      workspace.Source,
			Binary:      workspace.Binary,
			Environment: environment,
		})
		if err != nil {
			return err
		}
		if binary.Commit != evidence.Source.Commit || binary.SHA256 == "" || binary.SizeBytes == 0 {
			return fmt.Errorf("%s sample %d produced an invalid binary", workload.ID, index)
		}
		if index >= 0 {
			record := sampleRecord{
				SchemaVersion:  1,
				RunID:          evidence.RunID,
				WorkloadID:     workload.ID,
				SampleIndex:    index,
				Measurement:    measured.Measurement,
				Validation:     "pinned commit identity, binary digest, and size passed",
				ObservedSHA256: binary.SHA256,
			}
			if err := json.NewEncoder(writer).Encode(record); err != nil {
				return err
			}
			if err := writer.Flush(); err != nil {
				return err
			}
		}
	}
	return writer.Flush()
}

func removeCaptureDirectory(captureRoot, selectedPath string) error {
	relative, err := filepath.Rel(captureRoot, selectedPath)
	if err != nil || relative == "." || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return fmt.Errorf("refuse to remove path outside capture workspace")
	}
	return os.RemoveAll(selectedPath)
}

func replaceEnvironment(environment []string, name, value string) []string {
	prefix := name + "="
	replaced := false
	result := make([]string, 0, len(environment)+1)
	for _, entry := range environment {
		if strings.HasPrefix(entry, prefix) {
			result = append(result, prefix+value)
			replaced = true
		} else {
			result = append(result, entry)
		}
	}
	if !replaced {
		result = append(result, prefix+value)
	}
	return result
}
