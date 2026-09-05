package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type metricSummary struct {
	ElapsedNanoseconds   statistics `json:"elapsedNanoseconds"`
	UserNanoseconds      statistics `json:"userNanoseconds"`
	SystemNanoseconds    statistics `json:"systemNanoseconds"`
	MaximumResidentBytes statistics `json:"maximumResidentBytes"`
}

type workloadSummary struct {
	ID                    string         `json:"id"`
	Category              string         `json:"category"`
	Profile               string         `json:"profile"`
	Status                string         `json:"status"`
	SampleCount           int            `json:"sampleCount"`
	Metrics               *metricSummary `json:"metrics,omitempty"`
	UniqueOutputDigests   int            `json:"uniqueOutputDigests,omitempty"`
	UniqueObservedDigests int            `json:"uniqueObservedDigests,omitempty"`
}

type runSummary struct {
	SchemaVersion int                `json:"schemaVersion"`
	RunID         string             `json:"runId"`
	Source        sourcePolicy       `json:"source"`
	Machine       machineProfile     `json:"machine"`
	Binary        binaryIdentity     `json:"binary"`
	DoltServer    doltServerIdentity `json:"doltServer"`
	Measured      int                `json:"measuredWorkloads"`
	Pending       int                `json:"pendingWorkloads"`
	Unavailable   int                `json:"unavailableWorkloads"`
	Workloads     []workloadSummary  `json:"workloads"`
}

func summarizePrepared(evidence preparationEvidence, workspace captureWorkspace, selected policy) (runSummary, error) {
	profiles := make(map[string]profilePolicy, len(selected.Profiles))
	for _, profile := range selected.Profiles {
		profiles[profile.ID] = profile
	}
	result := runSummary{
		SchemaVersion: 1, RunID: evidence.RunID, Source: evidence.Source, Machine: evidence.Machine,
		Binary: evidence.Binary, DoltServer: evidence.DoltServer,
	}
	for _, workload := range selected.Workloads {
		path := filepath.Join(workspace.Root, "samples", workload.ID+".jsonl")
		records, err := readSampleRecords(path)
		if os.IsNotExist(err) {
			status := workload.Admission
			if status == "" && profiles[workload.Profile].Admission != "measured-native" {
				status = profiles[workload.Profile].Admission
			}
			if status == "" {
				status = "pending-capture"
			}
			if strings.HasPrefix(status, "unsupported-") {
				result.Unavailable++
			} else {
				result.Pending++
			}
			result.Workloads = append(result.Workloads, workloadSummary{ID: workload.ID, Category: workload.Category, Profile: workload.Profile, Status: status})
			continue
		}
		if err != nil {
			return runSummary{}, err
		}
		if len(records) != selected.Sample.MeasuredRuns {
			return runSummary{}, fmt.Errorf("%s has %d samples; want %d", workload.ID, len(records), selected.Sample.MeasuredRuns)
		}
		metrics, outputs, observations, err := summarizeRecords(workload.ID, records, selected.Sample.MeasuredRuns)
		if err != nil {
			return runSummary{}, err
		}
		result.Measured++
		result.Workloads = append(result.Workloads, workloadSummary{
			ID: workload.ID, Category: workload.Category, Profile: workload.Profile, Status: "measured",
			SampleCount: len(records), Metrics: &metrics, UniqueOutputDigests: outputs, UniqueObservedDigests: observations,
		})
	}
	sort.Slice(result.Workloads, func(left, right int) bool { return result.Workloads[left].ID < result.Workloads[right].ID })
	return result, nil
}

func readSampleRecords(path string) ([]sampleRecord, error) {
	file, err := os.Open(path) // #nosec G304 -- path is rooted in the capture workspace.
	if err != nil {
		return nil, err
	}
	defer file.Close()
	var records []sampleRecord
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 64*1024), 1024*1024)
	for scanner.Scan() {
		var record sampleRecord
		if err := json.Unmarshal(scanner.Bytes(), &record); err != nil {
			return nil, err
		}
		records = append(records, record)
	}
	return records, scanner.Err()
}

func summarizeRecords(workloadID string, records []sampleRecord, expected int) (metricSummary, int, int, error) {
	elapsed := make([]float64, 0, len(records))
	user := make([]float64, 0, len(records))
	system := make([]float64, 0, len(records))
	memory := make([]float64, 0, len(records))
	outputs := make(map[string]bool)
	observations := make(map[string]bool)
	for index, record := range records {
		if record.WorkloadID != workloadID || record.SampleIndex != index || record.Measurement.ExitCode != expectedExitCode(workloadID) || record.Validation == "" {
			return metricSummary{}, 0, 0, fmt.Errorf("%s sample %d has invalid identity or validation", workloadID, index)
		}
		if !record.Measurement.MemoryObserverAvailable {
			return metricSummary{}, 0, 0, fmt.Errorf("%s sample %d has no memory observer", workloadID, index)
		}
		if workloadID == "microbenchmarks-selected" && len(record.Benchmarks) != len(selectedBenchmarkNames) {
			return metricSummary{}, 0, 0, fmt.Errorf("%s sample %d has incomplete allocation results", workloadID, index)
		}
		elapsed = append(elapsed, float64(record.Measurement.ElapsedNanoseconds))
		user = append(user, float64(record.Measurement.UserNanoseconds))
		system = append(system, float64(record.Measurement.SystemNanoseconds))
		memory = append(memory, float64(record.Measurement.MaximumResidentBytes))
		outputs[record.Measurement.StdoutSHA256] = true
		observations[record.ObservedSHA256] = true
	}
	elapsedStats, err := summarize(elapsed, expected)
	if err != nil {
		return metricSummary{}, 0, 0, err
	}
	userStats, err := summarize(user, expected)
	if err != nil {
		return metricSummary{}, 0, 0, err
	}
	systemStats, err := summarize(system, expected)
	if err != nil {
		return metricSummary{}, 0, 0, err
	}
	memoryStats, err := summarize(memory, expected)
	if err != nil {
		return metricSummary{}, 0, 0, err
	}
	return metricSummary{ElapsedNanoseconds: elapsedStats, UserNanoseconds: userStats, SystemNanoseconds: systemStats, MaximumResidentBytes: memoryStats}, len(outputs), len(observations), nil
}

func expectedExitCode(workloadID string) int {
	if workloadID == "sync-conflict" {
		return 2
	}
	return 0
}
