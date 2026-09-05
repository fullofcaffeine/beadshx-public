package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
)

type artifactIndexEntry struct {
	Path      string `json:"path"`
	SHA256    string `json:"sha256"`
	SizeBytes int64  `json:"sizeBytes"`
}

type artifactIndex struct {
	SchemaVersion int                  `json:"schemaVersion"`
	RunID         string               `json:"runId"`
	Files         []artifactIndexEntry `json:"files"`
}

type comparisonRunIdentity struct {
	RunID        string `json:"runId"`
	BinarySHA256 string `json:"binarySha256"`
}

type comparisonMeasurement struct {
	RunID                string  `json:"runId"`
	SampleCount          int     `json:"sampleCount"`
	MeanNanoseconds      float64 `json:"meanNanoseconds"`
	MedianNanoseconds    float64 `json:"medianNanoseconds"`
	P95Nanoseconds       float64 `json:"p95Nanoseconds"`
	CoefficientVariation float64 `json:"coefficientOfVariation"`
	MeanRelativeToFirst  float64 `json:"meanRelativeToFirst"`
}

type workloadComparison struct {
	ID       string                  `json:"id"`
	Category string                  `json:"category"`
	Runs     []comparisonMeasurement `json:"runs"`
}

type comparisonReport struct {
	SchemaVersion int                     `json:"schemaVersion"`
	Source        sourcePolicy            `json:"source"`
	Machine       machineProfile          `json:"machine"`
	Runs          []comparisonRunIdentity `json:"runs"`
	Workloads     []workloadComparison    `json:"workloads"`
	Unavailable   []workloadSummary       `json:"unavailable"`
}

func publishPrepared(repository string, evidence preparationEvidence, workspace captureWorkspace, selected policy) error {
	summary, err := summarizePrepared(evidence, workspace, selected)
	if err != nil {
		return err
	}
	if summary.Pending != 0 {
		return fmt.Errorf("run %s still has %d pending workloads", evidence.RunID, summary.Pending)
	}
	destination := filepath.Join(repository, "compatibility", "performance-baseline", "runs", evidence.RunID)
	if _, err := os.Stat(destination); err == nil {
		return fmt.Errorf("published run already exists: compatibility/performance-baseline/runs/%s", evidence.RunID)
	} else if !os.IsNotExist(err) {
		return err
	}
	if err := os.MkdirAll(filepath.Join(destination, "fixtures"), 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Join(destination, "samples"), 0o755); err != nil {
		return err
	}
	if err := copyEvidenceFile(filepath.Join(workspace.Root, "preparation.json"), filepath.Join(destination, "manifest.json")); err != nil {
		return err
	}
	if err := copyEvidenceFile(filepath.Join(workspace.Root, "benchmark-catalog.json"), filepath.Join(destination, "benchmark-catalog.json")); err != nil {
		return err
	}
	for _, fixture := range selected.Fixtures {
		name := fixture.ID + ".manifest.json"
		if err := copyEvidenceFile(filepath.Join(workspace.Fixtures, name), filepath.Join(destination, "fixtures", name)); err != nil {
			return err
		}
	}
	for _, workload := range selected.Workloads {
		source := filepath.Join(workspace.Root, "samples", workload.ID+".jsonl")
		if _, err := os.Stat(source); os.IsNotExist(err) && strings.HasPrefix(workload.Admission, "unsupported-") {
			continue
		} else if err != nil {
			return fmt.Errorf("publish %s: %w", workload.ID, err)
		}
		if err := copyEvidenceFile(source, filepath.Join(destination, "samples", workload.ID+".jsonl")); err != nil {
			return err
		}
	}
	summaryContent, err := json.MarshalIndent(summary, "", "  ")
	if err != nil {
		return err
	}
	if err := writeFile(filepath.Join(destination, "summary.json"), append(summaryContent, '\n')); err != nil {
		return err
	}
	index, err := buildArtifactIndex(destination, evidence.RunID)
	if err != nil {
		return err
	}
	indexContent, err := json.MarshalIndent(index, "", "  ")
	if err != nil {
		return err
	}
	if err := writeFile(filepath.Join(destination, "artifact-index.json"), append(indexContent, '\n')); err != nil {
		return err
	}
	_, err = validatePublishedRun(destination, selected)
	return err
}

func copyEvidenceFile(source, destination string) error {
	input, err := os.Open(source) // #nosec G304 -- source is a known capture artifact.
	if err != nil {
		return err
	}
	defer input.Close()
	temporary, err := os.CreateTemp(filepath.Dir(destination), ".performance-evidence-*")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer func() { _ = os.Remove(temporaryPath) }()
	if _, err := io.Copy(temporary, input); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Chmod(temporaryPath, 0o644); err != nil { // #nosec G302 -- review evidence is intentionally readable.
		return err
	}
	return os.Rename(temporaryPath, destination)
}

func buildArtifactIndex(root, runID string) (artifactIndex, error) {
	var entries []artifactIndexEntry
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() {
			return nil
		}
		if !entry.Type().IsRegular() {
			return fmt.Errorf("published evidence contains a non-regular file")
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		if filepath.ToSlash(relative) == "artifact-index.json" {
			return nil
		}
		digest, size, err := hashFile(path)
		if err != nil {
			return err
		}
		entries = append(entries, artifactIndexEntry{Path: filepath.ToSlash(relative), SHA256: digest, SizeBytes: size})
		return nil
	})
	if err != nil {
		return artifactIndex{}, err
	}
	sort.Slice(entries, func(left, right int) bool { return entries[left].Path < entries[right].Path })
	return artifactIndex{SchemaVersion: 1, RunID: runID, Files: entries}, nil
}

func checkPublished(repository string, selected policy) error {
	root := filepath.Join(repository, "compatibility", "performance-baseline", "runs")
	entries, err := os.ReadDir(root)
	if err != nil {
		return err
	}
	var runDirectories []string
	for _, entry := range entries {
		if entry.IsDir() {
			runDirectories = append(runDirectories, filepath.Join(root, entry.Name()))
		}
	}
	if len(runDirectories) < 2 {
		return fmt.Errorf("published performance evidence has %d runs; want at least 2", len(runDirectories))
	}
	sort.Strings(runDirectories)
	machineIdentity := ""
	for _, directory := range runDirectories {
		evidence, err := validatePublishedRun(directory, selected)
		if err != nil {
			return err
		}
		identity := fmt.Sprintf("%s\x00%s\x00%s\x00%d\x00%s\x00%s", evidence.Machine.MachineModel, evidence.Machine.CPU,
			evidence.Machine.OperatingSystemBuild, evidence.Machine.MemoryBytes, evidence.Machine.GoVersion, evidence.Machine.Filesystem)
		if machineIdentity == "" {
			machineIdentity = identity
		} else if identity != machineIdentity {
			return fmt.Errorf("published runs do not share the same machine identity")
		}
	}
	generated, err := buildComparisonReport(runDirectories, selected)
	if err != nil {
		return err
	}
	content, err := os.ReadFile(filepath.Join(repository, "compatibility", "performance-baseline", "comparison.json")) // #nosec G304 -- fixed repository evidence path.
	if err != nil {
		return err
	}
	var committed comparisonReport
	if err := json.Unmarshal(content, &committed); err != nil {
		return err
	}
	if !reflect.DeepEqual(generated, committed) {
		return fmt.Errorf("published cross-run comparison does not regenerate from run summaries")
	}
	return nil
}

func writeComparisonReport(repository string, selected policy) error {
	root := filepath.Join(repository, "compatibility", "performance-baseline", "runs")
	entries, err := os.ReadDir(root)
	if err != nil {
		return err
	}
	var directories []string
	for _, entry := range entries {
		if entry.IsDir() {
			directories = append(directories, filepath.Join(root, entry.Name()))
		}
	}
	sort.Strings(directories)
	report, err := buildComparisonReport(directories, selected)
	if err != nil {
		return err
	}
	content, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return err
	}
	return writeFile(filepath.Join(repository, "compatibility", "performance-baseline", "comparison.json"), append(content, '\n'))
}

func buildComparisonReport(runDirectories []string, selected policy) (comparisonReport, error) {
	if len(runDirectories) < 2 {
		return comparisonReport{}, fmt.Errorf("cross-run comparison requires at least two runs")
	}
	sort.Strings(runDirectories)
	var summaries []runSummary
	for _, directory := range runDirectories {
		content, err := os.ReadFile(filepath.Join(directory, "summary.json")) // #nosec G304 -- directory is a published run root.
		if err != nil {
			return comparisonReport{}, err
		}
		var summary runSummary
		if err := json.Unmarshal(content, &summary); err != nil {
			return comparisonReport{}, err
		}
		summaries = append(summaries, summary)
	}
	report := comparisonReport{SchemaVersion: 1, Source: selected.Source, Machine: summaries[0].Machine}
	byRun := make([]map[string]workloadSummary, len(summaries))
	for index, summary := range summaries {
		report.Runs = append(report.Runs, comparisonRunIdentity{RunID: summary.RunID, BinarySHA256: summary.Binary.SHA256})
		byRun[index] = make(map[string]workloadSummary, len(summary.Workloads))
		for _, workload := range summary.Workloads {
			byRun[index][workload.ID] = workload
		}
	}
	for _, policyWorkload := range selected.Workloads {
		first := byRun[0][policyWorkload.ID]
		if first.Status != "measured" {
			report.Unavailable = append(report.Unavailable, first)
			continue
		}
		comparison := workloadComparison{ID: policyWorkload.ID, Category: policyWorkload.Category}
		firstMean := first.Metrics.ElapsedNanoseconds.Mean
		for index, summary := range summaries {
			workload := byRun[index][policyWorkload.ID]
			if workload.Status != "measured" || workload.Metrics == nil {
				return comparisonReport{}, fmt.Errorf("workload %s is not measured in run %s", policyWorkload.ID, summary.RunID)
			}
			elapsed := workload.Metrics.ElapsedNanoseconds
			comparison.Runs = append(comparison.Runs, comparisonMeasurement{
				RunID: summary.RunID, SampleCount: workload.SampleCount, MeanNanoseconds: elapsed.Mean,
				MedianNanoseconds: elapsed.Median, P95Nanoseconds: elapsed.P95,
				CoefficientVariation: elapsed.CoefficientOfVariation, MeanRelativeToFirst: elapsed.Mean / firstMean,
			})
		}
		report.Workloads = append(report.Workloads, comparison)
	}
	sort.Slice(report.Unavailable, func(left, right int) bool { return report.Unavailable[left].ID < report.Unavailable[right].ID })
	return report, nil
}

func validatePublishedRun(root string, selected policy) (preparationEvidence, error) {
	manifestContent, err := os.ReadFile(filepath.Join(root, "manifest.json")) // #nosec G304 -- root is a published run directory.
	if err != nil {
		return preparationEvidence{}, err
	}
	var evidence preparationEvidence
	if err := json.Unmarshal(manifestContent, &evidence); err != nil {
		return preparationEvidence{}, err
	}
	if evidence.RunID != filepath.Base(root) || evidence.Source != selected.Source ||
		evidence.Binary.Commit != selected.Source.Commit || evidence.DoltServer.Version != selected.ServerToolchain.Version ||
		evidence.DoltServer.SHA256 != selected.ServerToolchain.DarwinArm64BinarySHA256 {
		return preparationEvidence{}, fmt.Errorf("published run %s has a mismatched identity", filepath.Base(root))
	}
	workspace := captureWorkspace{Root: root}
	generated, err := summarizePrepared(evidence, workspace, selected)
	if err != nil {
		return preparationEvidence{}, err
	}
	if generated.Pending != 0 || generated.Measured != len(selected.Workloads)-generated.Unavailable {
		return preparationEvidence{}, fmt.Errorf("published run %s is incomplete", evidence.RunID)
	}
	committedContent, err := os.ReadFile(filepath.Join(root, "summary.json")) // #nosec G304 -- root is a published run directory.
	if err != nil {
		return preparationEvidence{}, err
	}
	var committed runSummary
	if err := json.Unmarshal(committedContent, &committed); err != nil {
		return preparationEvidence{}, err
	}
	if !reflect.DeepEqual(generated, committed) {
		return preparationEvidence{}, fmt.Errorf("published run %s summary does not regenerate from raw samples", evidence.RunID)
	}
	if err := validatePublishedFixtures(root, evidence, selected); err != nil {
		return preparationEvidence{}, err
	}
	if err := validatePublishedBenchmarkCatalog(root, selected); err != nil {
		return preparationEvidence{}, err
	}
	if err := validateArtifactIndex(root, evidence.RunID); err != nil {
		return preparationEvidence{}, err
	}
	if err := validateEvidencePrivacy(root); err != nil {
		return preparationEvidence{}, err
	}
	return evidence, nil
}

func validatePublishedFixtures(root string, evidence preparationEvidence, selected policy) error {
	byID := make(map[string]fixtureEvidence, len(evidence.Fixtures))
	for _, fixture := range evidence.Fixtures {
		byID[fixture.ID] = fixture
	}
	for _, fixture := range selected.Fixtures {
		content, err := os.ReadFile(filepath.Join(root, "fixtures", fixture.ID+".manifest.json")) // #nosec G304 -- fixture ID is policy-owned.
		if err != nil {
			return err
		}
		var manifest fixtureManifest
		if err := json.Unmarshal(content, &manifest); err != nil {
			return err
		}
		if !reflect.DeepEqual(manifest.Fixture, fixture) || manifest.ContentSHA256 != byID[fixture.ID].LogicalSHA256 || manifest.ContentBytes != byID[fixture.ID].LogicalBytes {
			return fmt.Errorf("published fixture %s does not match its run manifest", fixture.ID)
		}
	}
	return nil
}

func validatePublishedBenchmarkCatalog(root string, selected policy) error {
	content, err := os.ReadFile(filepath.Join(root, "benchmark-catalog.json")) // #nosec G304 -- root is a published run directory.
	if err != nil {
		return err
	}
	var catalog benchmarkCatalog
	if err := json.Unmarshal(content, &catalog); err != nil {
		return err
	}
	if catalog.SourceCommit != selected.Source.Commit || len(catalog.Executable) == 0 || len(catalog.DocumentationOnly) == 0 {
		return fmt.Errorf("published benchmark catalog is incomplete")
	}
	return nil
}

func validateArtifactIndex(root, runID string) error {
	content, err := os.ReadFile(filepath.Join(root, "artifact-index.json")) // #nosec G304 -- root is a published run directory.
	if err != nil {
		return err
	}
	var committed artifactIndex
	if err := json.Unmarshal(content, &committed); err != nil {
		return err
	}
	generated, err := buildArtifactIndex(root, runID)
	if err != nil {
		return err
	}
	if !reflect.DeepEqual(committed, generated) {
		return fmt.Errorf("published run %s artifact index does not match its files", runID)
	}
	return nil
}

func validateEvidencePrivacy(root string) error {
	privateMarkers := []string{"/Users/", "/home/", `C:` + `\\Users\\`, "file:///"}
	return filepath.WalkDir(root, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() {
			return nil
		}
		content, err := os.ReadFile(path) // #nosec G304 -- path is under the published evidence root.
		if err != nil {
			return err
		}
		for _, marker := range privateMarkers {
			if strings.Contains(string(content), marker) {
				return fmt.Errorf("published evidence %s contains a private path marker", filepath.Base(path))
			}
		}
		return nil
	})
}
