// Command package-bootstrap creates the development-only BeadsHX bootstrap bundle.
package main

import (
	"archive/zip"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	archivepath "path"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const (
	// The read-only port links the native Dolt and SQL storage stack. The
	// stripped binary is about 117 MiB with the pinned toolchain, so keep a
	// bounded 128 MiB entry ceiling and a separate archive-wide ceiling.
	maxEntryBytes = int64(128 << 20)
	maxTotalBytes = int64(160 << 20)
)

type input struct {
	source string
	name   string
	mode   os.FileMode
	size   int64
	digest [sha256.Size]byte
}

type generatedFixture struct {
	Files []struct {
		Path   string `json:"path"`
		SHA256 string `json:"sha256"`
	} `json:"files"`
}

func main() {
	repositoryFlag := flag.String("repository", "", "repository root")
	outputFlag := flag.String("output", "", "output ZIP path")
	flag.Parse()
	if *repositoryFlag == "" || *outputFlag == "" {
		fatalf("both --repository and --output are required")
	}

	repository, err := filepath.EvalSymlinks(*repositoryFlag)
	if err != nil {
		fatalf("resolve repository: %v", err)
	}
	repository, err = filepath.Abs(repository)
	if err != nil {
		fatalf("resolve repository: %v", err)
	}
	output, err := filepath.Abs(*outputFlag)
	if err != nil {
		fatalf("resolve output: %v", err)
	}
	if err := requireContainedPath(repository, output); err != nil {
		fatalf("validate output: %v", err)
	}
	if err := removePriorOutput(output); err != nil {
		fatalf("remove prior package: %v", err)
	}

	inputs, err := collectInputs(repository)
	if err != nil {
		fatalf("collect package inputs: %v", err)
	}
	candidate, err := writeArchive(output, inputs)
	if err != nil {
		fatalf("write package candidate: %v", err)
	}
	defer func() { _ = os.Remove(candidate) }()

	fixture := filepath.Join(repository, "engdocs/beadshx/generated/bootstrap-fixture.json")
	if err := verifyArchive(candidate, fixture, inputs); err != nil {
		fatalf("verify package candidate: %v", err)
	}
	if err := os.Rename(candidate, output); err != nil {
		fatalf("publish package: %v", err)
	}
}

func collectInputs(repository string) ([]input, error) {
	inputs := []input{
		{source: filepath.Join(repository, "build/bin/bdhx"), name: "bin/bdhx", mode: 0o755},
		{source: filepath.Join(repository, "LICENSE"), name: "LICENSE", mode: 0o644},
		{source: filepath.Join(repository, "THIRD_PARTY_LICENSES"), name: "THIRD_PARTY_LICENSES", mode: 0o644},
		{source: filepath.Join(repository, "engdocs/beadshx/program/source-locks.json"), name: "evidence/source-locks.json", mode: 0o644},
		{source: filepath.Join(repository, "engdocs/beadshx/program/toolchain-locks.json"), name: "evidence/toolchain-locks.json", mode: 0o644},
		{source: filepath.Join(repository, "release/identity-policy.json"), name: "evidence/identity-policy.json", mode: 0o644},
		{source: filepath.Join(repository, "upstream/locks/beads-v1.2.1.json"), name: "evidence/beads-v1.2.1.json", mode: 0o644},
		{source: filepath.Join(repository, "upstream/locks/haxe-go.json"), name: "evidence/haxe-go.json", mode: 0o644},
		{source: filepath.Join(repository, "LICENSES/HAXE-GO-GENERATED-MIT.txt"), name: "generated/LICENSES/HAXE-GO-GENERATED-MIT.txt", mode: 0o644},
		{source: filepath.Join(repository, "LICENSES/HAXE-STDLIB-MIT.txt"), name: "generated/LICENSES/HAXE-STDLIB-MIT.txt", mode: 0o644},
	}

	generated := filepath.Join(repository, "generated/go")
	err := filepath.WalkDir(generated, func(filePath string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("generated input is a symlink: %s", filePath)
		}
		if entry.IsDir() {
			return nil
		}
		if !entry.Type().IsRegular() {
			return fmt.Errorf("generated input is not a regular file: %s", filePath)
		}
		relative, err := filepath.Rel(generated, filePath)
		if err != nil {
			return err
		}
		if filepath.ToSlash(relative) == ".gitignore" {
			return nil
		}
		inputs = append(inputs, input{
			source: filePath,
			name:   "generated/go/" + filepath.ToSlash(relative),
			mode:   0o644,
		})
		return nil
	})
	if err != nil {
		return nil, err
	}

	for index := range inputs {
		prepared, err := prepareInput(repository, inputs[index])
		if err != nil {
			return nil, err
		}
		inputs[index] = prepared
	}
	sort.Slice(inputs, func(i, j int) bool { return inputs[i].name < inputs[j].name })
	return inputs, nil
}

func prepareInput(repository string, item input) (input, error) {
	if err := requireArchiveName(item.name); err != nil {
		return item, err
	}
	if err := requireContainedPath(repository, item.source); err != nil {
		return item, fmt.Errorf("%s: %w", item.name, err)
	}
	file, details, err := openRegular(item.source)
	if err != nil {
		return item, fmt.Errorf("%s: %w", item.name, err)
	}
	defer file.Close()
	if details.Size() > maxEntryBytes {
		return item, fmt.Errorf("%s exceeds %d bytes", item.name, maxEntryBytes)
	}
	hash := sha256.New()
	written, err := io.Copy(hash, io.LimitReader(file, maxEntryBytes+1))
	if err != nil {
		return item, err
	}
	if written != details.Size() {
		return item, fmt.Errorf("%s changed while it was inspected", item.name)
	}
	item.size = written
	copy(item.digest[:], hash.Sum(nil))
	return item, nil
}

func writeArchive(output string, inputs []input) (candidatePath string, returnErr error) {
	file, err := os.CreateTemp(filepath.Dir(output), ".beadshx-package-*.tmp")
	if err != nil {
		return "", err
	}
	candidatePath = file.Name()
	keep := false
	closed := false
	defer func() {
		if !closed {
			if closeErr := file.Close(); returnErr == nil && closeErr != nil {
				returnErr = closeErr
			}
		}
		if !keep {
			_ = os.Remove(candidatePath)
		}
	}()

	archive := zip.NewWriter(file)
	fixedTime := time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC)
	for _, item := range inputs {
		header := &zip.FileHeader{Name: item.name, Method: zip.Deflate, Modified: fixedTime}
		header.SetMode(item.mode)
		writer, err := archive.CreateHeader(header)
		if err != nil {
			return "", err
		}
		source, details, err := openRegular(item.source)
		if err != nil {
			return "", err
		}
		hash := sha256.New()
		written, copyErr := io.Copy(io.MultiWriter(writer, hash), io.LimitReader(source, maxEntryBytes+1))
		closeErr := source.Close()
		if copyErr != nil {
			return "", copyErr
		}
		if closeErr != nil {
			return "", closeErr
		}
		if written != item.size || written != details.Size() || !equalDigest(hash.Sum(nil), item.digest) {
			return "", fmt.Errorf("package input changed during archive creation: %s", item.name)
		}
	}
	if err := archive.Close(); err != nil {
		return "", err
	}
	if err := file.Sync(); err != nil {
		return "", err
	}
	if err := file.Close(); err != nil {
		return "", err
	}
	closed = true
	keep = true
	return candidatePath, nil
}

func verifyArchive(packagePath string, fixturePath string, inputs []input) (returnErr error) {
	// #nosec G304 -- collectInputs supplies the fixed, repository-owned fixture path.
	fixtureBytes, err := os.ReadFile(fixturePath)
	if err != nil {
		return err
	}
	var fixture generatedFixture
	if err := json.Unmarshal(fixtureBytes, &fixture); err != nil {
		return err
	}
	if len(fixture.Files) == 0 {
		return fmt.Errorf("generated fixture has no files")
	}

	archive, err := zip.OpenReader(packagePath)
	if err != nil {
		return err
	}
	defer func() {
		if closeErr := archive.Close(); returnErr == nil && closeErr != nil {
			returnErr = closeErr
		}
	}()
	if len(archive.File) != len(inputs) {
		return fmt.Errorf("archive has %d entries; expected %d", len(archive.File), len(inputs))
	}

	expected := make(map[string]input, len(inputs))
	for _, item := range inputs {
		expected[item.name] = item
	}
	entries := make(map[string]*zip.File, len(archive.File))
	var total uint64
	for _, file := range archive.File {
		if err := requireArchiveName(file.Name); err != nil {
			return err
		}
		if entries[file.Name] != nil {
			return fmt.Errorf("archive contains duplicate entry: %s", file.Name)
		}
		item, ok := expected[file.Name]
		if !ok {
			return fmt.Errorf("archive contains unexpected entry: %s", file.Name)
		}
		if !file.Mode().IsRegular() || file.UncompressedSize64 > uint64(maxEntryBytes) {
			return fmt.Errorf("archive entry has unsafe type or size: %s", file.Name)
		}
		total += file.UncompressedSize64
		if total > uint64(maxTotalBytes) {
			return fmt.Errorf("archive exceeds %d uncompressed bytes", maxTotalBytes)
		}
		reader, err := file.Open()
		if err != nil {
			return err
		}
		hash := sha256.New()
		written, copyErr := io.Copy(hash, io.LimitReader(reader, maxEntryBytes+1))
		closeErr := reader.Close()
		if copyErr != nil {
			return copyErr
		}
		if closeErr != nil {
			return closeErr
		}
		if written != item.size || !equalDigest(hash.Sum(nil), item.digest) {
			return fmt.Errorf("archive content differs from input: %s", file.Name)
		}
		entries[file.Name] = file
	}

	if entries["bin/bd"] != nil || entries["bin/beads"] != nil {
		return fmt.Errorf("development archive includes a forbidden upstream binary name")
	}
	for _, generated := range fixture.Files {
		name := "generated/go/" + generated.Path
		item, ok := expected[name]
		if !ok {
			return fmt.Errorf("archive is missing %s", name)
		}
		actual := hex.EncodeToString(item.digest[:])
		if actual != generated.SHA256 {
			return fmt.Errorf("archive hash mismatch for %s: expected %s, got %s", name, generated.SHA256, actual)
		}
	}
	return nil
}

func openRegular(filePath string) (*os.File, os.FileInfo, error) {
	before, err := os.Lstat(filePath)
	if err != nil {
		return nil, nil, err
	}
	if !before.Mode().IsRegular() {
		return nil, nil, fmt.Errorf("input is not a regular file: %s", filePath)
	}
	// #nosec G304 -- callers constrain the path to repository-contained,
	// lstat-checked package inputs before this open.
	file, err := os.Open(filePath)
	if err != nil {
		return nil, nil, err
	}
	after, err := file.Stat()
	if err != nil {
		_ = file.Close()
		return nil, nil, err
	}
	current, err := os.Lstat(filePath)
	if err != nil || !os.SameFile(before, after) || !os.SameFile(after, current) {
		_ = file.Close()
		return nil, nil, fmt.Errorf("input changed while it was opened: %s", filePath)
	}
	return file, after, nil
}

func requireContainedPath(repository string, candidate string) error {
	relative, err := filepath.Rel(repository, candidate)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return fmt.Errorf("path is outside repository: %s", candidate)
	}
	current := repository
	parts := strings.Split(relative, string(filepath.Separator))
	for index, part := range parts[:len(parts)-1] {
		current = filepath.Join(current, part)
		details, statErr := os.Lstat(current)
		if statErr != nil {
			return statErr
		}
		if details.Mode()&os.ModeSymlink != 0 || !details.IsDir() {
			return fmt.Errorf("path component is not a real directory: %s (component %d)", current, index)
		}
	}
	return nil
}

func requireArchiveName(name string) error {
	if name == "" || archivepath.IsAbs(name) || archivepath.Clean(name) != name ||
		strings.HasPrefix(name, "../") || strings.Contains(name, "\\") {
		return fmt.Errorf("unsafe archive name: %q", name)
	}
	return nil
}

func removePriorOutput(output string) error {
	details, err := os.Lstat(output)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if details.IsDir() {
		return fmt.Errorf("output is a directory: %s", output)
	}
	return os.Remove(output)
}

func equalDigest(actual []byte, expected [sha256.Size]byte) bool {
	return subtle.ConstantTimeCompare(actual, expected[:]) == 1
}

func fatalf(format string, values ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", values...)
	os.Exit(1)
}
