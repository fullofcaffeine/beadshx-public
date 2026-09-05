package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestHashDirectoryUsesRelativePathsAndContent(t *testing.T) {
	left := filepath.Join(t.TempDir(), "left")
	right := filepath.Join(t.TempDir(), "right")
	for _, root := range []string{left, right} {
		if err := os.MkdirAll(filepath.Join(root, "nested"), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(root, "nested", "value"), []byte("same"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	leftDigest, leftBytes, err := hashDirectory(left)
	if err != nil {
		t.Fatal(err)
	}
	rightDigest, rightBytes, err := hashDirectory(right)
	if err != nil {
		t.Fatal(err)
	}
	if leftDigest != rightDigest || leftBytes != 4 || rightBytes != 4 {
		t.Fatalf("equal directory trees differ: %s/%d != %s/%d", leftDigest, leftBytes, rightDigest, rightBytes)
	}
	if err := os.WriteFile(filepath.Join(right, "nested", "value"), []byte("changed"), 0o644); err != nil {
		t.Fatal(err)
	}
	changed, _, err := hashDirectory(right)
	if err != nil {
		t.Fatal(err)
	}
	if changed == leftDigest {
		t.Fatal("content change did not change directory digest")
	}
}

func TestCanonicalJSONLDigestIgnoresOrderAndTimes(t *testing.T) {
	left := []byte("{\"id\":\"one\",\"created_at\":\"first\"}\n{\"id\":\"two\",\"comments\":[{\"timestamp\":\"first\",\"text\":\"same\"}]}\n")
	right := []byte("{\"comments\":[{\"text\":\"same\",\"timestamp\":\"second\"}],\"id\":\"two\"}\n{\"created_at\":\"second\",\"id\":\"one\"}\n")
	leftDigest, err := canonicalJSONLDigest(left)
	if err != nil {
		t.Fatal(err)
	}
	rightDigest, err := canonicalJSONLDigest(right)
	if err != nil {
		t.Fatal(err)
	}
	if leftDigest != rightDigest {
		t.Fatalf("equivalent logical exports differ: %s != %s", leftDigest, rightDigest)
	}
}
