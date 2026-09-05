package main

import (
	"strings"
	"testing"
)

func TestParseBenchmarkResultsRetainsRequiredMetrics(t *testing.T) {
	var lines []string
	for _, name := range selectedBenchmarkNames {
		lines = append(lines, name+"-12 10 123.5 ns/op 64 B/op 2 allocs/op")
	}
	output := processOutput{Measurement: processMeasurement{ExitCode: 0}, Stdout: []byte(strings.Join(lines, "\n"))}
	results, err := parseBenchmarkResults(output)
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != len(selectedBenchmarkNames) || results[0].Metrics["allocs/op"] != 2 {
		t.Fatalf("unexpected parsed benchmarks: %#v", results)
	}
}

func TestParseBenchmarkResultsRejectsMissingAllocations(t *testing.T) {
	output := processOutput{Measurement: processMeasurement{ExitCode: 0}, Stdout: []byte("BenchmarkCreateIssue-12 10 123.5 ns/op 64 B/op\n")}
	if _, err := parseBenchmarkResults(output); err == nil {
		t.Fatal("parseBenchmarkResults() accepted missing allocations")
	}
}
