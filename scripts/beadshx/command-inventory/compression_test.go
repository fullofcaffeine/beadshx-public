package main

import (
	"bytes"
	"compress/gzip"
	"io"
	"testing"
)

func TestCanonicalCompressionIsDeterministicAndReversible(t *testing.T) {
	t.Parallel()
	content := []byte("{\"schemaVersion\":1}\n")
	left, err := compressCanonicalJSON(content)
	if err != nil {
		t.Fatal(err)
	}
	right, err := compressCanonicalJSON(content)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(left, right) {
		t.Fatal("canonical gzip bytes changed between runs")
	}
	reader, err := gzip.NewReader(bytes.NewReader(left))
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := io.ReadAll(reader)
	if err != nil {
		t.Fatal(err)
	}
	if err := reader.Close(); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(decoded, content) {
		t.Fatalf("gzip round trip changed JSON: %q", decoded)
	}
}
