package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"time"
)

type binaryIdentity struct {
	Version       string `json:"version"`
	Commit        string `json:"commit"`
	Build         string `json:"build"`
	SHA256        string `json:"sha256"`
	SizeBytes     int64  `json:"sizeBytes"`
	DebugSymbols  string `json:"debugSymbols"`
	CodeSignature string `json:"codeSignature"`
}

type fixtureEvidence struct {
	ID                 string `json:"id"`
	LogicalSHA256      string `json:"logicalSha256"`
	LogicalBytes       int    `json:"logicalBytes"`
	PhysicalCopyMethod string `json:"physicalCopyMethod"`
	IssueCount         int    `json:"issueCount"`
	SchemaVersion      int    `json:"schemaVersion"`
}

type doltServerIdentity struct {
	Version   string `json:"version"`
	SHA256    string `json:"sha256"`
	SizeBytes int64  `json:"sizeBytes"`
}

type preparationEvidence struct {
	SchemaVersion int                `json:"schemaVersion"`
	RunID         string             `json:"runId"`
	Source        sourcePolicy       `json:"source"`
	Machine       machineProfile     `json:"machine"`
	Binary        binaryIdentity     `json:"binary"`
	DoltServer    doltServerIdentity `json:"doltServer"`
	Environment   map[string]string  `json:"environment"`
	Fixtures      []fixtureEvidence  `json:"fixtures"`
}

type captureWorkspace struct {
	Repository  string
	Root        string
	Source      string
	Binary      string
	Fixtures    string
	Pristine    string
	Home        string
	Temporary   string
	BuildCache  string
	DoltBinary  string
	Environment []string
}

func prepareCapture(repository, sourceRepository, runID string, selected policy) (preparationEvidence, captureWorkspace, error) {
	if !validRunID(runID) {
		return preparationEvidence{}, captureWorkspace{}, fmt.Errorf("run ID must contain only lowercase letters, digits, and hyphens")
	}
	machine, err := collectMachineProfile()
	if err != nil {
		return preparationEvidence{}, captureWorkspace{}, err
	}
	root := filepath.Join(repository, "build", "evidence", "performance-baseline", "work", runID)
	if _, err := os.Stat(root); err == nil {
		return preparationEvidence{}, captureWorkspace{}, fmt.Errorf("capture workspace already exists: build/evidence/performance-baseline/work/%s", runID)
	} else if !os.IsNotExist(err) {
		return preparationEvidence{}, captureWorkspace{}, err
	}
	workspace := captureWorkspace{
		Repository: repository,
		Root:       root,
		Source:     filepath.Join(root, "source"),
		Binary:     filepath.Join(root, "source", "bd"),
		Fixtures:   filepath.Join(root, "fixtures"),
		Pristine:   filepath.Join(root, "pristine"),
		Home:       filepath.Join(root, "home"),
		Temporary:  filepath.Join(root, "tmp"),
		BuildCache: filepath.Join(root, "go-build-cache"),
		DoltBinary: filepath.Join(repository, filepath.FromSlash(selected.ServerToolchain.RepositoryRelativeBinary)),
	}
	for _, directory := range []string{root, workspace.Fixtures, workspace.Pristine, workspace.Home, workspace.Temporary, workspace.BuildCache} {
		if err := os.MkdirAll(directory, 0o755); err != nil {
			return preparationEvidence{}, captureWorkspace{}, err
		}
	}
	if err := cloneSource(sourceRepository, workspace.Source, selected.Source.Commit); err != nil {
		return preparationEvidence{}, captureWorkspace{}, err
	}
	workspace.Environment, err = captureEnvironment(selected.FixedEnvironment, workspace)
	if err != nil {
		return preparationEvidence{}, captureWorkspace{}, err
	}
	doltServer, err := inspectDoltServer(workspace, selected.ServerToolchain)
	if err != nil {
		return preparationEvidence{}, captureWorkspace{}, err
	}
	if err := buildCandidate(workspace); err != nil {
		return preparationEvidence{}, captureWorkspace{}, err
	}
	binary, err := inspectBinary(workspace)
	if err != nil {
		return preparationEvidence{}, captureWorkspace{}, err
	}
	if binary.Commit != selected.Source.Commit {
		return preparationEvidence{}, captureWorkspace{}, fmt.Errorf("built binary commit = %s; want %s", binary.Commit, selected.Source.Commit)
	}
	if err := generateFixtures(workspace.Fixtures, selected); err != nil {
		return preparationEvidence{}, captureWorkspace{}, err
	}
	fixtureEvidenceRecords := make([]fixtureEvidence, 0, len(selected.Fixtures))
	for _, fixture := range selected.Fixtures {
		evidence, err := initializeFixture(workspace, fixture)
		if err != nil {
			return preparationEvidence{}, captureWorkspace{}, err
		}
		fixtureEvidenceRecords = append(fixtureEvidenceRecords, evidence)
	}
	return preparationEvidence{
		SchemaVersion: 1,
		RunID:         runID,
		Source:        selected.Source,
		Machine:       machine,
		Binary:        binary,
		DoltServer:    doltServer,
		Environment:   selected.FixedEnvironment,
		Fixtures:      fixtureEvidenceRecords,
	}, workspace, nil
}

func openPreparedCapture(repository, runID string, selected policy) (preparationEvidence, captureWorkspace, error) {
	if !validRunID(runID) {
		return preparationEvidence{}, captureWorkspace{}, fmt.Errorf("invalid run ID")
	}
	root := filepath.Join(repository, "build", "evidence", "performance-baseline", "work", runID)
	content, err := os.ReadFile(filepath.Join(root, "preparation.json")) // #nosec G304 -- run ID is validated and rooted in build evidence.
	if err != nil {
		return preparationEvidence{}, captureWorkspace{}, err
	}
	var evidence preparationEvidence
	if err := json.Unmarshal(content, &evidence); err != nil {
		return preparationEvidence{}, captureWorkspace{}, err
	}
	if evidence.RunID != runID || evidence.Source.Commit != selected.Source.Commit {
		return preparationEvidence{}, captureWorkspace{}, fmt.Errorf("prepared capture identity does not match policy")
	}
	workspace := captureWorkspace{
		Repository: repository,
		Root:       root,
		Source:     filepath.Join(root, "source"),
		Binary:     filepath.Join(root, "source", "bd"),
		Fixtures:   filepath.Join(root, "fixtures"),
		Pristine:   filepath.Join(root, "pristine"),
		Home:       filepath.Join(root, "home"),
		Temporary:  filepath.Join(root, "tmp"),
		BuildCache: filepath.Join(root, "go-build-cache"),
		DoltBinary: filepath.Join(repository, filepath.FromSlash(selected.ServerToolchain.RepositoryRelativeBinary)),
	}
	workspace.Environment, err = captureEnvironment(selected.FixedEnvironment, workspace)
	if err != nil {
		return preparationEvidence{}, captureWorkspace{}, err
	}
	digest, _, err := hashFile(workspace.Binary)
	if err != nil || digest != evidence.Binary.SHA256 {
		return preparationEvidence{}, captureWorkspace{}, fmt.Errorf("prepared binary digest drifted")
	}
	doltDigest, _, err := hashFile(workspace.DoltBinary)
	if err != nil || doltDigest != evidence.DoltServer.SHA256 || doltDigest != selected.ServerToolchain.DarwinArm64BinarySHA256 {
		return preparationEvidence{}, captureWorkspace{}, fmt.Errorf("dedicated Dolt server binary digest drifted")
	}
	return evidence, workspace, nil
}

func inspectDoltServer(workspace captureWorkspace, selected serverToolchain) (doltServerIdentity, error) {
	digest, size, err := hashFile(workspace.DoltBinary)
	if err != nil {
		return doltServerIdentity{}, fmt.Errorf("inspect dedicated Dolt server binary: %w", err)
	}
	if digest != selected.DarwinArm64BinarySHA256 {
		return doltServerIdentity{}, fmt.Errorf("dedicated Dolt server binary digest = %s; want %s", digest, selected.DarwinArm64BinarySHA256)
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	output, err := measureProcess(ctx, workspace.Root, workspace.Environment, []string{workspace.DoltBinary, "version"})
	if err != nil {
		return doltServerIdentity{}, fmt.Errorf("inspect dedicated Dolt server version: %w", err)
	}
	if output.Measurement.ExitCode != 0 {
		return doltServerIdentity{}, fmt.Errorf("inspect dedicated Dolt server version: exit %d: %s", output.Measurement.ExitCode, strings.TrimSpace(string(output.Stderr)))
	}
	line := strings.SplitN(strings.TrimSpace(string(output.Stdout)), "\n", 2)[0]
	want := "dolt version " + selected.Version
	if line != want {
		return doltServerIdentity{}, fmt.Errorf("dedicated Dolt server version = %q; want %q", line, want)
	}
	return doltServerIdentity{Version: selected.Version, SHA256: digest, SizeBytes: size}, nil
}

func validRunID(value string) bool {
	if value == "" {
		return false
	}
	for _, character := range value {
		if (character < 'a' || character > 'z') && (character < '0' || character > '9') && character != '-' {
			return false
		}
	}
	return true
}

func cloneSource(sourceRepository, destination, commit string) error {
	clone := exec.Command("git", "clone", "--quiet", "--no-checkout", sourceRepository, destination) // #nosec G204 -- paths are local capture inputs.
	if output, err := clone.CombinedOutput(); err != nil {
		return fmt.Errorf("clone pinned source: %w: %s", err, strings.TrimSpace(string(output)))
	}
	checkout := exec.Command("git", "-C", destination, "checkout", "--quiet", "--detach", commit) // #nosec G204 -- commit is policy-pinned.
	if output, err := checkout.CombinedOutput(); err != nil {
		return fmt.Errorf("checkout pinned source: %w: %s", err, strings.TrimSpace(string(output)))
	}
	return nil
}

func captureEnvironment(fixed map[string]string, workspace captureWorkspace) ([]string, error) {
	moduleCache, err := commandText("go", "env", "GOMODCACHE")
	if err != nil {
		return nil, err
	}
	values := make(map[string]string, len(fixed)+9)
	for name, value := range fixed {
		values[name] = value
	}
	values["PATH"] = filepath.Join(runtime.GOROOT(), "bin") + ":/usr/bin:/bin:/usr/sbin:/sbin"
	values["GOROOT"] = runtime.GOROOT()
	values["GOMODCACHE"] = moduleCache
	values["GOCACHE"] = workspace.BuildCache
	values["HOME"] = workspace.Home
	values["TMPDIR"] = workspace.Temporary
	values["XDG_CONFIG_HOME"] = filepath.Join(workspace.Home, ".config")
	values["XDG_CACHE_HOME"] = filepath.Join(workspace.Home, ".cache")
	keys := make([]string, 0, len(values))
	for name := range values {
		keys = append(keys, name)
	}
	sort.Strings(keys)
	environment := make([]string, 0, len(keys))
	for _, name := range keys {
		environment = append(environment, name+"="+values[name])
	}
	return environment, nil
}

func buildCandidate(workspace captureWorkspace) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	output, err := measureProcess(ctx, workspace.Source, workspace.Environment, []string{"make", "build"})
	if err != nil {
		return err
	}
	if output.Measurement.ExitCode != 0 {
		return fmt.Errorf("pinned build failed: %s", strings.TrimSpace(string(output.Stderr)))
	}
	return nil
}

func inspectBinary(workspace captureWorkspace) (binaryIdentity, error) {
	digest, size, err := hashFile(workspace.Binary)
	if err != nil {
		return binaryIdentity{}, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	output, err := measureProcess(ctx, workspace.Source, workspace.Environment, []string{workspace.Binary, "version", "--json"})
	if err != nil {
		return binaryIdentity{}, fmt.Errorf("inspect binary identity: %w", err)
	}
	if output.Measurement.ExitCode != 0 {
		return binaryIdentity{}, fmt.Errorf("inspect binary identity: exit %d: %s", output.Measurement.ExitCode, strings.TrimSpace(string(output.Stderr)))
	}
	var identity struct {
		Version string `json:"version"`
		Commit  string `json:"commit"`
		Build   string `json:"build"`
	}
	if err := json.Unmarshal(output.Stdout, &identity); err != nil {
		return binaryIdentity{}, err
	}
	return binaryIdentity{
		Version:       identity.Version,
		Commit:        identity.Commit,
		Build:         identity.Build,
		SHA256:        digest,
		SizeBytes:     size,
		DebugSymbols:  "default go build symbols retained",
		CodeSignature: "ad-hoc codesign from pinned Makefile",
	}, nil
}

func initializeFixture(workspace captureWorkspace, fixture fixturePolicy) (fixtureEvidence, error) {
	fixtureRoot := filepath.Join(workspace.Pristine, fixture.ID)
	if err := os.MkdirAll(fixtureRoot, 0o755); err != nil {
		return fixtureEvidence{}, err
	}
	if output, err := exec.Command("git", "-C", fixtureRoot, "init", "-q").CombinedOutput(); err != nil {
		return fixtureEvidence{}, fmt.Errorf("initialize fixture git repository: %w: %s", err, strings.TrimSpace(string(output)))
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Minute)
	defer cancel()
	initOutput, err := measureProcess(ctx, fixtureRoot, workspace.Environment, []string{workspace.Binary, "init", "--prefix", "perf", "--skip-hooks", "--skip-agents", "--quiet", "--non-interactive"})
	if err != nil {
		return fixtureEvidence{}, fmt.Errorf("initialize fixture %s: %w", fixture.ID, err)
	}
	if initOutput.Measurement.ExitCode != 0 {
		return fixtureEvidence{}, fmt.Errorf("initialize fixture %s: exit %d: %s", fixture.ID, initOutput.Measurement.ExitCode, strings.TrimSpace(string(initOutput.Stderr)))
	}
	contentPath := filepath.Join(workspace.Fixtures, fixture.ID+".jsonl")
	importOutput, err := measureProcess(ctx, fixtureRoot, workspace.Environment, []string{workspace.Binary, "import", contentPath, "--json"})
	if err != nil {
		return fixtureEvidence{}, fmt.Errorf("import fixture %s: %w", fixture.ID, err)
	}
	if importOutput.Measurement.ExitCode != 0 {
		return fixtureEvidence{}, fmt.Errorf("import fixture %s: exit %d: %s", fixture.ID, importOutput.Measurement.ExitCode, strings.TrimSpace(string(importOutput.Stderr)))
	}
	var imported struct {
		Created int `json:"created"`
		Skipped int `json:"skipped"`
	}
	if err := json.Unmarshal(importOutput.Stdout, &imported); err != nil {
		return fixtureEvidence{}, err
	}
	if imported.Created != fixture.IssueCount || imported.Skipped != 0 {
		return fixtureEvidence{}, fmt.Errorf("fixture %s imported %d and skipped %d; want %d/0", fixture.ID, imported.Created, imported.Skipped, fixture.IssueCount)
	}
	digest, size, err := hashFile(contentPath)
	if err != nil {
		return fixtureEvidence{}, err
	}
	return fixtureEvidence{
		ID:                 fixture.ID,
		LogicalSHA256:      digest,
		LogicalBytes:       int(size),
		PhysicalCopyMethod: "APFS clone-on-write via cp -cR outside timed regions",
		IssueCount:         fixture.IssueCount,
		SchemaVersion:      fixture.SchemaVersion,
	}, nil
}
