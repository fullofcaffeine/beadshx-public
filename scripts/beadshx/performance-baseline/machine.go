package main

import (
	"fmt"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
)

type machineProfile struct {
	GOOS                 string `json:"goos"`
	GOARCH               string `json:"goarch"`
	OperatingSystem      string `json:"operatingSystem"`
	OperatingSystemBuild string `json:"operatingSystemBuild"`
	KernelRelease        string `json:"kernelRelease"`
	MachineModel         string `json:"machineModel"`
	CPU                  string `json:"cpu"`
	LogicalCPUCount      int    `json:"logicalCpuCount"`
	MemoryBytes          int64  `json:"memoryBytes"`
	Filesystem           string `json:"filesystem"`
	StorageMedium        string `json:"storageMedium"`
	PowerSource          string `json:"powerSource"`
	GoVersion            string `json:"goVersion"`
	MemoryObserver       string `json:"memoryObserver"`
	FilesystemCacheNote  string `json:"filesystemCacheNote"`
}

func collectMachineProfile() (machineProfile, error) {
	if runtime.GOOS != "darwin" || runtime.GOARCH != "arm64" {
		return machineProfile{}, fmt.Errorf("capture requires a native darwin/arm64 host; got %s/%s", runtime.GOOS, runtime.GOARCH)
	}
	osVersion, err := commandText("/usr/bin/sw_vers", "-productVersion")
	if err != nil {
		return machineProfile{}, err
	}
	osBuild, err := commandText("/usr/bin/sw_vers", "-buildVersion")
	if err != nil {
		return machineProfile{}, err
	}
	kernel, err := commandText("/usr/bin/uname", "-r")
	if err != nil {
		return machineProfile{}, err
	}
	machineModel, err := commandText("/usr/sbin/sysctl", "-n", "hw.model")
	if err != nil {
		return machineProfile{}, err
	}
	cpu, err := commandText("/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string")
	if err != nil {
		return machineProfile{}, err
	}
	memoryText, err := commandText("/usr/sbin/sysctl", "-n", "hw.memsize")
	if err != nil {
		return machineProfile{}, err
	}
	memoryBytes, err := strconv.ParseInt(memoryText, 10, 64)
	if err != nil {
		return machineProfile{}, fmt.Errorf("parse memory size: %w", err)
	}
	disk, err := commandText("/usr/sbin/diskutil", "info", "/")
	if err != nil {
		return machineProfile{}, err
	}
	filesystem := fieldValue(disk, "File System Personality")
	storageMedium := "rotational-or-unknown"
	if fieldValue(disk, "Solid State") == "Yes" {
		storageMedium = "solid-state"
	}
	power, err := commandText("/usr/bin/pmset", "-g", "batt")
	if err != nil {
		return machineProfile{}, err
	}
	powerSource := "battery"
	if strings.Contains(power, "AC Power") {
		powerSource = "ac"
	}
	return machineProfile{
		GOOS:                 runtime.GOOS,
		GOARCH:               runtime.GOARCH,
		OperatingSystem:      "macOS " + osVersion,
		OperatingSystemBuild: osBuild,
		KernelRelease:        kernel,
		MachineModel:         machineModel,
		CPU:                  cpu,
		LogicalCPUCount:      runtime.NumCPU(),
		MemoryBytes:          memoryBytes,
		Filesystem:           filesystem,
		StorageMedium:        storageMedium,
		PowerSource:          powerSource,
		GoVersion:            runtime.Version(),
		MemoryObserver:       "wait4 rusage.ru_maxrss (Darwin bytes)",
		FilesystemCacheNote:  "host filesystem cache is uncontrolled; fixture copies use APFS clone-on-write outside timed regions",
	}, nil
}

func commandText(name string, arguments ...string) (string, error) {
	output, err := exec.Command(name, arguments...).CombinedOutput() // #nosec G204 -- commands and arguments are fixed by the harness.
	if err != nil {
		return "", fmt.Errorf("%s: %w: %s", name, err, strings.TrimSpace(string(output)))
	}
	return strings.TrimSpace(string(output)), nil
}

func fieldValue(content, name string) string {
	for _, line := range strings.Split(content, "\n") {
		parts := strings.SplitN(line, ":", 2)
		if len(parts) == 2 && strings.TrimSpace(parts[0]) == name {
			return strings.TrimSpace(parts[1])
		}
	}
	return ""
}
