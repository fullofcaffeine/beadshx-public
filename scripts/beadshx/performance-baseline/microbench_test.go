package main

import (
	"strings"
	"testing"
)

func TestParseBenchmarkNamesQualifiesAndSortsNames(t *testing.T) {
	stdout := strings.Join([]string{
		`{"Package":"example/b","Output":"BenchmarkSecond\n"}`,
		`{"Package":"example/a","Output":"BenchmarkFirst\n"}`,
		`{"Package":"example/a","Output":"ok example/a 0.1s\n"}`,
	}, "\n")
	output := processOutput{Measurement: processMeasurement{ExitCode: 0}, Stdout: []byte(stdout)}
	names, err := parseBenchmarkNames(output)
	if err != nil {
		t.Fatal(err)
	}
	want := "example/a/BenchmarkFirst\nexample/b/BenchmarkSecond"
	if got := strings.Join(names, "\n"); got != want {
		t.Fatalf("parseBenchmarkNames() = %q; want %q", got, want)
	}
}

func TestParseBenchmarkNamesRejectsEmptyDiscovery(t *testing.T) {
	output := processOutput{Measurement: processMeasurement{ExitCode: 0}, Stdout: []byte(`{"Package":"example/a","Output":"ok example/a\n"}`)}
	if _, err := parseBenchmarkNames(output); err == nil {
		t.Fatal("parseBenchmarkNames() accepted an empty benchmark list")
	}
}
