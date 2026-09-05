package terminalfacade

import (
	"os"
	"testing"
)

func TestPipeIsNotTerminal(t *testing.T) {
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = reader.Close()
		_ = writer.Close()
	})

	if isTerminal(writer) {
		t.Fatal("pipe reported as a terminal")
	}
}
