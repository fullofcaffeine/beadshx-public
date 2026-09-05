// Package gitfacade contains the bounded process mechanics needed by
// Haxe-owned repository-aware commands.
package gitfacade

import (
	"context"
	"fmt"
	"os/exec"
	"time"
)

const gitLogTimeout = 30 * time.Second

// ReadLog returns `git log --oneline --all` output for an existing repository.
// A non-repository directory is an empty history, matching upstream orphan
// detection. Command parsing and issue-reference policy remain in Haxe.
func ReadLog(directory string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), gitLogTimeout)
	defer cancel()

	probe := exec.CommandContext(ctx, "git", "rev-parse", "--git-dir")
	probe.Dir = directory
	if err := probe.Run(); err != nil {
		return "", nil
	}

	command := exec.CommandContext(ctx, "git", "log", "--oneline", "--all")
	command.Dir = directory
	output, err := command.Output()
	if err != nil {
		if ctx.Err() != nil {
			return "", fmt.Errorf("reading git log: %w", ctx.Err())
		}
		return "", fmt.Errorf("reading git log: %w", err)
	}
	return string(output), nil
}
