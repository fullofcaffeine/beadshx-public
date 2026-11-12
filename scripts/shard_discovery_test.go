package scripts_test

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// Discovery must finish successfully before a shard can publish its manifest.
func TestShardDiscoveryFailureIsNotPartialSuccess(t *testing.T) {
	bash, err := exec.LookPath("bash")
	if err != nil {
		t.Skip("shard helpers require Bash")
	}
	if err := exec.Command(bash, "-c", "type mapfile").Run(); err != nil {
		t.Skip("existing shard helpers require Bash 4 mapfile")
	}
	for _, helper := range []struct{ name, exclusion string }{
		{"go-test-shard-names.sh", "GO_TEST_SHARD_EXCLUDE_TEST_REGEX"},
		{"go-test-shard-packages.sh", "GO_TEST_SHARD_EXCLUDE_REGEX"},
	} {
		t.Run(helper.name, func(t *testing.T) {
			for _, scenario := range []struct {
				name, output, exclude, want string
				status, wantExit            int
			}{
				{"partial discovery failure", "TestBravo\n", "", "", 7, 7},
				{"healthy sorted unique selection", "TestBravo\nTestAlpha\nTestBravo\n", "", "TestAlpha\nTestBravo\n", 0, 0},
				{"healthy exclusion", "TestBravo\nTestAlpha\n", "^TestBravo$", "TestAlpha\n", 0, 0},
				{"empty discovery", "", "", "", 0, 1},
				{"all excluded", "TestBravo\n", ".*", "", 0, 1},
			} {
				t.Run(scenario.name, func(t *testing.T) {
					dir := t.TempDir()
					fake := filepath.Join(dir, "go")
					if err := os.WriteFile(fake, []byte("#!/usr/bin/env bash\nprintf '%s' \"$SHARD_DISCOVERY_OUTPUT\"\nif [[ $SHARD_DISCOVERY_STATUS != 0 ]]; then echo discovery-failed >&2; fi\nexit \"$SHARD_DISCOVERY_STATUS\"\n"), 0o755); err != nil {
						t.Fatal(err)
					}
					env := append(os.Environ(), "SHARD_DISCOVERY_OUTPUT="+scenario.output, "SHARD_DISCOVERY_STATUS="+strconv.Itoa(scenario.status), helper.exclusion+"="+scenario.exclude)
					fakePath := shellPathUnderEnv(t, bash, dir, env)
					script := shellPathUnderEnv(t, bash, filepath.Join(sourceRepoRoot(t), "scripts", "ci", helper.name), env)
					cmd := exec.Command(bash, "--noprofile", "--norc", "-c", `PATH="$1:$PATH"; export PATH; exec "$BASH" "$2" 1 1 ./cmd/bd`, "shard-contract", fakePath, script)
					cmd.Env = env
					var stdout, stderr bytes.Buffer
					cmd.Stdout = &stdout
					cmd.Stderr = &stderr
					err := cmd.Run()
					if got := cmd.ProcessState.ExitCode(); got != scenario.wantExit {
						t.Errorf("exit=%d, want %d: %v: %s", got, scenario.wantExit, err, stderr.String())
					}
					if scenario.status != 0 {
						if err == nil {
							t.Errorf("partial discovery returned success")
						}
						if !strings.Contains(stderr.String(), "discovery-failed") {
							t.Errorf("discovery diagnostic lost: %s", stderr.String())
						}
					} else if scenario.wantExit == 0 && err != nil {
						t.Fatalf("healthy discovery: %v: %s", err, stderr.String())
					}
					if stdout.String() != scenario.want {
						t.Errorf("manifest=%q, want %q", stdout.String(), scenario.want)
					}
				})
			}
		})
	}
}
