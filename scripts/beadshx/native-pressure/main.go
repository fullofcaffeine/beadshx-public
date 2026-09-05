// Command native-pressure generates the pinned Beads native-boundary inventory.
package main

import (
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

func main() {
	repositoryFlag := flag.String("repository", ".", "BeadsHX repository root")
	policyFlag := flag.String("policy", "compatibility/native-pressure/policy.json", "policy path relative to the repository")
	outputFlag := flag.String("output", "compatibility/native-pressure/inventory.json.gz", "inventory path relative to the repository")
	reportFlag := flag.String("report", "compatibility/native-pressure/report.md", "report path relative to the repository")
	checkFlag := flag.Bool("check", false, "compare generated artifacts with committed files")
	flag.Parse()

	if err := run(*repositoryFlag, *policyFlag, *outputFlag, *reportFlag, *checkFlag); err != nil {
		fmt.Fprintf(os.Stderr, "native pressure: %v\n", err)
		os.Exit(1)
	}
}

func run(repositoryInput, policyInput, outputInput, reportInput string, check bool) error {
	repository, err := canonicalDirectory(repositoryInput)
	if err != nil {
		return err
	}
	policyPath, err := confinedPath(repository, policyInput)
	if err != nil {
		return fmt.Errorf("policy: %w", err)
	}
	outputPath, err := confinedPath(repository, outputInput)
	if err != nil {
		return fmt.Errorf("output: %w", err)
	}
	reportPath, err := confinedPath(repository, reportInput)
	if err != nil {
		return fmt.Errorf("report: %w", err)
	}

	selectedPolicy, err := loadJSON[policy](policyPath)
	if err != nil {
		return fmt.Errorf("load policy: %w", err)
	}
	if err := validatePolicy(repository, selectedPolicy); err != nil {
		return err
	}

	scratch, err := os.MkdirTemp("", "beadshx-native-pressure-")
	if err != nil {
		return err
	}
	defer func() { _ = os.RemoveAll(scratch) }()
	sourceRoot := filepath.Join(scratch, "source")
	if err := clonePinnedSource(repository, sourceRoot, selectedPolicy.Compatibility.Commit); err != nil {
		return err
	}

	result, err := analyze(sourceRoot, selectedPolicy)
	if err != nil {
		return err
	}
	content, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return err
	}
	content = append(content, '\n')
	compressed, err := compressCanonical(content)
	if err != nil {
		return err
	}
	report := renderReport(result)

	if check {
		if err := compareFile(outputPath, compressed); err != nil {
			return fmt.Errorf("inventory: %w", err)
		}
		if err := compareFile(reportPath, report); err != nil {
			return fmt.Errorf("report: %w", err)
		}
		return nil
	}
	if err := writeAtomic(outputPath, compressed); err != nil {
		return err
	}
	return writeAtomic(reportPath, report)
}

func validatePolicy(repository string, selected policy) error {
	if selected.SchemaVersion != 1 || selected.Compatibility.Project != "Beads" ||
		selected.Compatibility.Version != "v1.2.1" || len(selected.Compatibility.Commit) != 40 {
		return errors.New("unexpected compatibility target")
	}
	if selected.CompilerEvidence.Project != "haxe.go" || len(selected.CompilerEvidence.Commit) != 40 {
		return errors.New("invalid compiler evidence")
	}
	if selected.GoVersion != "1.26.5" || selected.FirstPartyPrefix != "github.com/steveyegge/beads/" {
		return errors.New("unexpected toolchain or first-party prefix")
	}
	if len(selected.Profiles) != 2 || len(selected.RootPackages) == 0 || len(selected.BoundaryGroups) == 0 {
		return errors.New("policy is missing profiles, roots, or boundary groups")
	}
	commitType, err := gitOutput(repository, "cat-file", "-t", selected.Compatibility.Commit+"^{commit}")
	if err != nil || strings.TrimSpace(string(commitType)) != "commit" {
		return fmt.Errorf("pinned source commit is unavailable: %w", err)
	}

	toolchainPath := filepath.Join(repository, "engdocs", "beadshx", "program", "toolchain-locks.json")
	var toolchains struct {
		Common struct {
			Go           string `json:"go"`
			HaxeGoCommit string `json:"haxeGoCommit"`
		} `json:"common"`
	}
	if err := decodeJSONLoose(toolchainPath, &toolchains); err != nil {
		return err
	}
	if toolchains.Common.Go != "go"+selected.GoVersion || toolchains.Common.HaxeGoCommit != selected.CompilerEvidence.Commit {
		return errors.New("native-pressure policy drifted from toolchain locks")
	}

	seen := make(map[string]bool)
	for _, profile := range selected.Profiles {
		if profile.ID == "" || seen["profile:"+profile.ID] {
			return fmt.Errorf("invalid or duplicate profile %q", profile.ID)
		}
		seen["profile:"+profile.ID] = true
	}
	axisSet := make(map[string]bool)
	for _, axis := range selected.PressureAxes {
		if axis == "" || axisSet[axis] {
			return fmt.Errorf("invalid or duplicate pressure axis %q", axis)
		}
		axisSet[axis] = true
	}
	for _, feature := range selected.FeatureRanks {
		if feature.ID == "" || seen["feature:"+feature.ID] || feature.Priority == "" || feature.Decision == "" {
			return fmt.Errorf("invalid or duplicate feature rank %q", feature.ID)
		}
		seen["feature:"+feature.ID] = true
		for _, axis := range feature.Axes {
			if !axisSet[axis] {
				return fmt.Errorf("feature %s references unknown axis %s", feature.ID, axis)
			}
		}
	}
	for _, gap := range selected.CompilerGaps {
		if gap.ID == "" || seen["gap:"+gap.ID] || gap.Disposition != "existing-owner" {
			return fmt.Errorf("invalid or duplicate compiler gap %q", gap.ID)
		}
		seen["gap:"+gap.ID] = true
		for _, axis := range gap.Axes {
			if !axisSet[axis] {
				return fmt.Errorf("gap %s references unknown axis %s", gap.ID, axis)
			}
		}
	}
	for _, group := range selected.BoundaryGroups {
		if group.ID == "" || seen["group:"+group.ID] || group.FacadeID == "" ||
			group.SemanticRole == "" || group.SelectedOwner == "" || group.Severity == "" ||
			len(group.CommandProfiles) == 0 || len(group.OperationIDs) == 0 || len(group.EffectIDs) == 0 ||
			len(group.HaxeGoEvidence) == 0 || group.ReducedFixture == "" {
			return fmt.Errorf("invalid or duplicate boundary group %q", group.ID)
		}
		seen["group:"+group.ID] = true
		if _, err := compileRegex(group.CallerPackageRegex); err != nil {
			return fmt.Errorf("group %s: %w", group.ID, err)
		}
	}
	for index, dependency := range selected.DependencyPolicies {
		if dependency.ID == "" || seen["dependency:"+dependency.ID] || dependency.Owner == "" ||
			dependency.Severity == "" || dependency.Decision == "" {
			return fmt.Errorf("invalid or duplicate dependency policy %q", dependency.ID)
		}
		seen["dependency:"+dependency.ID] = true
		if _, err := compileRegex(dependency.PackageRegex); err != nil {
			return fmt.Errorf("dependency policy %s: %w", dependency.ID, err)
		}
		if dependency.PackageRegex == ".*" && index != len(selected.DependencyPolicies)-1 {
			return errors.New("catch-all dependency policy must be last")
		}
	}
	return validateSemanticCoverage(repository, selected)
}

func validateSemanticCoverage(repository string, selected policy) error {
	var storagePlan struct {
		Capabilities    map[string]string `json:"capabilities"`
		CommandProfiles []struct {
			ID string `json:"id"`
		} `json:"commandProfiles"`
	}
	if err := decodeJSONLoose(filepath.Join(repository, "compatibility", "storage-contracts", "plan.json"), &storagePlan); err != nil {
		return err
	}
	var effectPlan struct {
		Effects []struct {
			ID string `json:"id"`
		} `json:"effects"`
	}
	if err := decodeJSONLoose(filepath.Join(repository, "compatibility", "effect-contracts", "plan.json"), &effectPlan); err != nil {
		return err
	}

	profiles := make(map[string]bool)
	operations := make(map[string]bool)
	effects := make(map[string]bool)
	for _, group := range selected.BoundaryGroups {
		for _, id := range group.CommandProfiles {
			profiles[id] = true
		}
		for _, id := range group.OperationIDs {
			operations[id] = true
		}
		for _, id := range group.EffectIDs {
			effects[id] = true
		}
	}
	for _, profile := range storagePlan.CommandProfiles {
		if !profiles[profile.ID] {
			return fmt.Errorf("unmapped command profile: %s", profile.ID)
		}
		delete(profiles, profile.ID)
	}
	for operation := range storagePlan.Capabilities {
		if !operations[operation] {
			return fmt.Errorf("unmapped storage capability: %s", operation)
		}
		delete(operations, operation)
	}
	for _, effect := range effectPlan.Effects {
		if !effects[effect.ID] {
			return fmt.Errorf("unmapped native effect: %s", effect.ID)
		}
		delete(effects, effect.ID)
	}
	if len(profiles) != 0 || len(operations) != 0 || len(effects) != 0 {
		return errors.New("native-pressure policy references unknown semantic IDs")
	}
	return nil
}

func canonicalDirectory(input string) (string, error) {
	absolute, err := filepath.Abs(input)
	if err != nil {
		return "", err
	}
	resolved, err := filepath.EvalSymlinks(absolute)
	if err != nil {
		return "", err
	}
	info, err := os.Stat(resolved)
	if err != nil {
		return "", err
	}
	if !info.IsDir() {
		return "", fmt.Errorf("not a directory: %s", resolved)
	}
	return resolved, nil
}

func confinedPath(root, input string) (string, error) {
	path := input
	if !filepath.IsAbs(path) {
		path = filepath.Join(root, path)
	}
	path = filepath.Clean(path)
	relative, err := filepath.Rel(root, path)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("path escapes repository: %s", input)
	}
	return path, nil
}

func loadJSON[T any](path string) (T, error) {
	var value T
	err := decodeJSON(path, &value)
	return value, err
}

func decodeJSON(path string, target any) error {
	// #nosec G304 -- callers pass repository-confined policy paths.
	content, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	decoder := json.NewDecoder(bytes.NewReader(content))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return fmt.Errorf("decode %s: %w", path, err)
	}
	return nil
}

func decodeJSONLoose(path string, target any) error {
	// #nosec G304 -- callers pass fixed repository-owned authority paths.
	content, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(content, target); err != nil {
		return fmt.Errorf("decode %s: %w", path, err)
	}
	return nil
}

func clonePinnedSource(repository, destination, commit string) error {
	if _, err := gitOutput("", "clone", "--shared", "--no-checkout", "--quiet", repository, destination); err != nil {
		return fmt.Errorf("clone pinned source: %w", err)
	}
	if _, err := gitOutput(destination, "checkout", "--detach", "--quiet", commit); err != nil {
		return fmt.Errorf("checkout pinned source: %w", err)
	}
	actual, err := gitOutput(destination, "rev-parse", "HEAD")
	if err != nil || strings.TrimSpace(string(actual)) != commit {
		return errors.New("scratch checkout does not match the pinned commit")
	}
	return nil
}

func gitOutput(directory string, arguments ...string) ([]byte, error) {
	command := exec.Command("git", arguments...)
	command.Dir = directory
	output, err := command.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("git %s: %w: %s", strings.Join(arguments, " "), err, strings.TrimSpace(string(output)))
	}
	return output, nil
}

func compressCanonical(content []byte) ([]byte, error) {
	var output bytes.Buffer
	writer, err := gzip.NewWriterLevel(&output, gzip.BestCompression)
	if err != nil {
		return nil, err
	}
	writer.Header.ModTime = time.Unix(0, 0).UTC()
	writer.Header.OS = 255
	if _, err := writer.Write(content); err != nil {
		_ = writer.Close()
		return nil, err
	}
	if err := writer.Close(); err != nil {
		return nil, err
	}
	return output.Bytes(), nil
}

func compareFile(path string, expected []byte) error {
	// #nosec G304 -- path is confined to the repository.
	actual, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if bytes.Equal(actual, expected) {
		return nil
	}
	want := sha256.Sum256(actual)
	got := sha256.Sum256(expected)
	return fmt.Errorf("generated bytes differ: committed=%s generated=%s", hex.EncodeToString(want[:]), hex.EncodeToString(got[:]))
}

func writeAtomic(path string, content []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".native-pressure-*")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer func() { _ = os.Remove(temporaryPath) }()
	if _, err := temporary.Write(content); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	// #nosec G302 -- generated repository artifacts must be reviewable by all users.
	if err := os.Chmod(temporaryPath, 0o644); err != nil {
		return err
	}
	return os.Rename(temporaryPath, path)
}

func sortedKeys(values map[string]int) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
