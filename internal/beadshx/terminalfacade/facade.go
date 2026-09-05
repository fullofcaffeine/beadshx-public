// Package terminalfacade contains the native process-terminal boundary used by
// Haxe-owned output policy. It owns terminal capability and Markdown mechanics,
// but no presentation text, section order, or command behavior.
package terminalfacade

import (
	"os"

	"github.com/steveyegge/beads/internal/uimd"
	"golang.org/x/term"
)

// IsStderrTerminal reports whether the process stderr stream is a terminal.
func IsStderrTerminal() bool {
	return isTerminal(os.Stderr)
}

// IsStdoutTerminal reports whether the process stdout stream is a terminal.
func IsStdoutTerminal() bool {
	return isTerminal(os.Stdout)
}

// RenderMarkdown applies the pinned Beads terminal renderer to stored body
// text. Haxe remains responsible for deciding which sections are rendered.
func RenderMarkdown(value string) string {
	return uimd.RenderMarkdown(value)
}

func isTerminal(file *os.File) bool {
	return term.IsTerminal(int(file.Fd()))
}
