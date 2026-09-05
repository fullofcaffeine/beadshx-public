//go:build !darwin && !linux

package main

import "os"

func maximumResidentBytes(_ *os.ProcessState) (int64, bool) {
	return 0, false
}
