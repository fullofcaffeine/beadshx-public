package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os/exec"
	"time"
)

type processMeasurement struct {
	Command                 []string `json:"command"`
	ElapsedNanoseconds      int64    `json:"elapsedNanoseconds"`
	UserNanoseconds         int64    `json:"userNanoseconds"`
	SystemNanoseconds       int64    `json:"systemNanoseconds"`
	MaximumResidentBytes    int64    `json:"maximumResidentBytes"`
	MemoryObserverAvailable bool     `json:"memoryObserverAvailable"`
	ExitCode                int      `json:"exitCode"`
	StdoutBytes             int      `json:"stdoutBytes"`
	StdoutSHA256            string   `json:"stdoutSha256"`
	StderrBytes             int      `json:"stderrBytes"`
	StderrSHA256            string   `json:"stderrSha256"`
}

type processOutput struct {
	Measurement processMeasurement
	Stdout      []byte
	Stderr      []byte
}

func measureProcess(ctx context.Context, directory string, environment, arguments []string) (processOutput, error) {
	if len(arguments) == 0 {
		return processOutput{}, fmt.Errorf("command is empty")
	}
	command := exec.CommandContext(ctx, arguments[0], arguments[1:]...) // #nosec G204 -- arguments come from the reviewed workload registry.
	command.Dir = directory
	command.Env = environment
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	command.Stdout = &stdout
	command.Stderr = &stderr
	started := time.Now()
	err := command.Run()
	elapsed := time.Since(started)
	if ctxErr := ctx.Err(); ctxErr != nil {
		return processOutput{}, fmt.Errorf("command did not finish before its deadline: %w", ctxErr)
	}

	exitCode := 0
	if err != nil {
		var exitError *exec.ExitError
		if !asExitError(err, &exitError) {
			return processOutput{}, err
		}
		exitCode = exitError.ExitCode()
	}
	stdoutDigest := sha256.Sum256(stdout.Bytes())
	stderrDigest := sha256.Sum256(stderr.Bytes())
	maximumResident, memoryAvailable := maximumResidentBytes(command.ProcessState)
	return processOutput{
		Measurement: processMeasurement{
			Command:                 append([]string(nil), arguments...),
			ElapsedNanoseconds:      elapsed.Nanoseconds(),
			UserNanoseconds:         command.ProcessState.UserTime().Nanoseconds(),
			SystemNanoseconds:       command.ProcessState.SystemTime().Nanoseconds(),
			MaximumResidentBytes:    maximumResident,
			MemoryObserverAvailable: memoryAvailable,
			ExitCode:                exitCode,
			StdoutBytes:             stdout.Len(),
			StdoutSHA256:            hex.EncodeToString(stdoutDigest[:]),
			StderrBytes:             stderr.Len(),
			StderrSHA256:            hex.EncodeToString(stderrDigest[:]),
		},
		Stdout: append([]byte(nil), stdout.Bytes()...),
		Stderr: append([]byte(nil), stderr.Bytes()...),
	}, nil
}

func asExitError(err error, target **exec.ExitError) bool {
	return errors.As(err, target)
}
