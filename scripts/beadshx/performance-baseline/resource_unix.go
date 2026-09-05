//go:build darwin || linux

package main

import (
	"os"
	"runtime"
	"syscall"
)

func maximumResidentBytes(state *os.ProcessState) (int64, bool) {
	usage, ok := state.SysUsage().(*syscall.Rusage)
	if !ok {
		return 0, false
	}
	value := usage.Maxrss
	if runtime.GOOS == "linux" {
		value *= 1024
	}
	return value, true
}
