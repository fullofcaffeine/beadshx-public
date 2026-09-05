package main

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"
)

func TestMeasureProcessCapturesOutputAndExit(t *testing.T) {
	if os.Getenv("BEADSHX_PERFORMANCE_HELPER") == "1" {
		fmt.Fprint(os.Stdout, "measured stdout\n")
		fmt.Fprint(os.Stderr, "measured stderr\n")
		os.Exit(7)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	output, err := measureProcess(ctx, t.TempDir(), append(os.Environ(), "BEADSHX_PERFORMANCE_HELPER=1"), []string{os.Args[0], "-test.run=TestMeasureProcessCapturesOutputAndExit"})
	if err != nil {
		t.Fatal(err)
	}
	if output.Measurement.ExitCode != 7 || string(output.Stdout) != "measured stdout\n" || string(output.Stderr) != "measured stderr\n" {
		t.Fatalf("unexpected measurement: %#v stdout=%q stderr=%q", output.Measurement, output.Stdout, output.Stderr)
	}
	if output.Measurement.ElapsedNanoseconds <= 0 || output.Measurement.StdoutSHA256 == "" || output.Measurement.StderrSHA256 == "" {
		t.Fatalf("incomplete measurement: %#v", output.Measurement)
	}
}
