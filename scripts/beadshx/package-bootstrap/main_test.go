package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestPrepareInputRejectsSymlink(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	victimRoot := t.TempDir()
	victim := filepath.Join(victimRoot, "victim")
	if err := os.WriteFile(victim, []byte("private"), 0o600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(root, "candidate")
	if err := os.Symlink(victim, link); err != nil {
		t.Skipf("symlink is unavailable: %v", err)
	}
	_, err := prepareInput(root, input{source: link, name: "bin/bdhx", mode: 0o755})
	if err == nil {
		t.Fatal("prepareInput accepted a symlink")
	}
}

func TestCandidateMustVerifyBeforePublish(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	generated := filepath.Join(root, "generated.go")
	content := []byte("package bootstrap\n")
	if err := os.WriteFile(generated, content, 0o600); err != nil {
		t.Fatal(err)
	}
	prepared, err := prepareInput(root, input{
		source: generated,
		name:   "generated/go/bdhx/haxego_generated_main.go",
		mode:   0o644,
	})
	if err != nil {
		t.Fatal(err)
	}
	outputRoot := filepath.Join(root, "build", "packages")
	if err := os.MkdirAll(outputRoot, 0o700); err != nil {
		t.Fatal(err)
	}
	output := filepath.Join(outputRoot, "candidate.zip")
	if err := os.WriteFile(output, []byte("stale"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := removePriorOutput(output); err != nil {
		t.Fatal(err)
	}
	candidate, err := writeArchive(output, []input{prepared})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Remove(candidate) })

	fixture := filepath.Join(root, "fixture.json")
	wrongHash := fmt.Sprintf("%064d", 0)
	writeFixture(t, fixture, wrongHash)
	if err := verifyArchive(candidate, fixture, []input{prepared}); err == nil {
		t.Fatal("verifyArchive accepted a mismatched generated fixture")
	}
	if _, err := os.Lstat(output); !os.IsNotExist(err) {
		t.Fatalf("failed verification left a final output: %v", err)
	}

	digest := sha256.Sum256(content)
	writeFixture(t, fixture, hex.EncodeToString(digest[:]))
	if err := verifyArchive(candidate, fixture, []input{prepared}); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(candidate, output); err != nil {
		t.Fatal(err)
	}
	if details, err := os.Lstat(output); err != nil || !details.Mode().IsRegular() {
		t.Fatalf("verified package was not published as a regular file: %v", err)
	}
}

func TestRemovePriorOutputRejectsDirectory(t *testing.T) {
	t.Parallel()
	output := filepath.Join(t.TempDir(), "package.zip")
	if err := os.Mkdir(output, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := removePriorOutput(output); err == nil {
		t.Fatal("removePriorOutput accepted a directory")
	}
}

func writeFixture(t *testing.T, path string, digest string) {
	t.Helper()
	content := fmt.Sprintf(
		"{\"files\":[{\"path\":\"bdhx/haxego_generated_main.go\",\"sha256\":%q}]}\n",
		digest,
	)
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}
