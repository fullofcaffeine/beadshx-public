// Command performance-baseline captures and validates repeated upstream measurements.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	repository := flag.String("repository", ".", "BeadsHX repository root")
	policyPath := flag.String("policy", "compatibility/performance-baseline/policy.json", "policy path relative to the repository")
	fixtureOutput := flag.String("generate-fixtures", "", "write deterministic fixture JSONL and manifests to this repository-relative directory")
	prepareRun := flag.String("prepare-run", "", "prepare a disposable pinned source, binary, and fixtures for a capture run")
	runPrepared := flag.String("run-prepared", "", "run direct command samples in an existing prepared capture workspace")
	summarizeRun := flag.String("summarize-prepared", "", "generate a summary for an existing prepared capture workspace")
	publishRun := flag.String("publish-prepared", "", "publish a sanitized prepared run under the compatibility evidence directory")
	checkPublishedRuns := flag.Bool("check-published", false, "validate published raw evidence and regenerate every summary")
	writeComparison := flag.Bool("write-comparison", false, "write the generated same-machine cross-run comparison")
	sourceRepository := flag.String("source-repository", "../beads", "local Beads Git repository used as the object source")
	flag.Parse()

	absoluteRepository, err := filepath.Abs(*repository)
	if err != nil {
		fail(err)
	}
	absolutePolicy, err := confinedPath(absoluteRepository, *policyPath)
	if err != nil {
		fail(err)
	}
	selected, err := loadPolicy(absolutePolicy)
	if err != nil {
		fail(err)
	}
	if err := validatePolicy(selected); err != nil {
		fail(err)
	}
	if *fixtureOutput != "" {
		outputPath, err := confinedPath(absoluteRepository, *fixtureOutput)
		if err != nil {
			fail(err)
		}
		if err := generateFixtures(outputPath, selected); err != nil {
			fail(err)
		}
	}
	if *prepareRun != "" {
		absoluteSource, err := filepath.Abs(*sourceRepository)
		if err != nil {
			fail(err)
		}
		evidence, workspace, err := prepareCapture(absoluteRepository, absoluteSource, *prepareRun, selected)
		if err != nil {
			fail(err)
		}
		content, err := json.MarshalIndent(evidence, "", "  ")
		if err != nil {
			fail(err)
		}
		content = append(content, '\n')
		if err := writeFile(filepath.Join(workspace.Root, "preparation.json"), content); err != nil {
			fail(err)
		}
		fmt.Printf("performance baseline preparation: PASS (%s; %s; %d fixtures)\n", evidence.RunID, evidence.Binary.SHA256, len(evidence.Fixtures))
	}
	if *runPrepared != "" {
		evidence, workspace, err := openPreparedCapture(absoluteRepository, *runPrepared, selected)
		if err != nil {
			fail(err)
		}
		if err := runRuntimeWorkloads(evidence, workspace, selected); err != nil {
			fail(err)
		}
		if err := runBuildWorkloads(evidence, workspace, selected); err != nil {
			fail(err)
		}
		if err := runMicrobenchmarkDiscovery(evidence, workspace, selected); err != nil {
			fail(err)
		}
		if err := runBackupWorkloads(evidence, workspace, selected); err != nil {
			fail(err)
		}
		if err := runSyncWorkloads(evidence, workspace, selected); err != nil {
			fail(err)
		}
		if err := runSelectedMicrobenchmarks(evidence, workspace, selected); err != nil {
			fail(err)
		}
		fmt.Printf("performance baseline local workloads: PASS (%s)\n", evidence.RunID)
	}
	if *summarizeRun != "" {
		evidence, workspace, err := openPreparedCapture(absoluteRepository, *summarizeRun, selected)
		if err != nil {
			fail(err)
		}
		summary, err := summarizePrepared(evidence, workspace, selected)
		if err != nil {
			fail(err)
		}
		content, err := json.MarshalIndent(summary, "", "  ")
		if err != nil {
			fail(err)
		}
		content = append(content, '\n')
		if err := writeFile(filepath.Join(workspace.Root, "summary.json"), content); err != nil {
			fail(err)
		}
		fmt.Printf("performance baseline summary: PASS (%d measured; %d pending; %d unavailable on this host)\n", summary.Measured, summary.Pending, summary.Unavailable)
	}
	if *publishRun != "" {
		evidence, workspace, err := openPreparedCapture(absoluteRepository, *publishRun, selected)
		if err != nil {
			fail(err)
		}
		if err := publishPrepared(absoluteRepository, evidence, workspace, selected); err != nil {
			fail(err)
		}
		fmt.Printf("performance baseline publish: PASS (%s)\n", evidence.RunID)
	}
	if *checkPublishedRuns {
		if err := checkPublished(absoluteRepository, selected); err != nil {
			fail(err)
		}
		fmt.Println("performance baseline published evidence: PASS")
	}
	if *writeComparison {
		if err := writeComparisonReport(absoluteRepository, selected); err != nil {
			fail(err)
		}
		fmt.Println("performance baseline cross-run comparison: PASS")
	}
	fmt.Printf("performance baseline policy: PASS (%d profiles; %d fixtures; %d workloads)\n", len(selected.Profiles), len(selected.Fixtures), len(selected.Workloads))
}

func confinedPath(repository, input string) (string, error) {
	if filepath.IsAbs(input) {
		return "", fmt.Errorf("path must be relative to the repository")
	}
	absolute := filepath.Join(repository, filepath.Clean(input))
	relative, err := filepath.Rel(repository, absolute)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("path escapes the repository")
	}
	return absolute, nil
}

func fail(err error) {
	fmt.Fprintf(os.Stderr, "performance baseline: %v\n", err)
	os.Exit(1)
}
