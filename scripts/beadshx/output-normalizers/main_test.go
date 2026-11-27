package main

import (
	"bytes"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestEveryNormalizerDeclaresItself(t *testing.T) {
	seen := map[string]bool{}
	for _, normalizer := range declaredNormalizers {
		if seen[normalizer.Name] {
			t.Errorf("%s is declared twice", normalizer.Name)
		}
		seen[normalizer.Name] = true
		if normalizer.Name == "" || strings.ContainsAny(normalizer.Name, ", ") {
			t.Errorf("bad normalizer name %q", normalizer.Name)
		}
		if normalizer.Fields == "" || normalizer.Reason == "" || normalizer.Scope == "" {
			t.Errorf("%s must name its fields, reason and scope", normalizer.Name)
		}
		if normalizer.paths == (normalizer.apply != nil) {
			t.Errorf("%s must be a path normalizer or have its own rewrite", normalizer.Name)
		}
	}
}

func TestNoRulesCopiesTheOutputExactly(t *testing.T) {
	input := []byte("time=\"2026-11-26T10:00:00Z\" " + oracleWork + "\r\n")
	output, err := normalize(input, nil, oracleSide)
	if err != nil || !bytes.Equal(output, input) {
		t.Fatalf("got %q, %v", output, err)
	}
}

func TestRulesRunInTheRegistryOrder(t *testing.T) {
	input := []byte("time=\"2026-11-26T10:00:00Z\" level=warning path=" + oracleWork + "/.beads\r\n")
	forward, err := normalize(input, []string{"pty-transcript", "work-path", "log-time"}, oracleSide)
	if err != nil {
		t.Fatal(err)
	}
	backward, err := normalize(input, []string{"log-time", "work-path", "pty-transcript"}, oracleSide)
	if err != nil {
		t.Fatal(err)
	}
	want := "time=\"<time>\" level=warning path=<work>/.beads\n"
	if string(forward) != want || string(backward) != want {
		t.Fatalf("got %q and %q, want %q", forward, backward, want)
	}
}

func TestPathRulesShareOneScanWhereTheLongestPathWins(t *testing.T) {
	input := []byte("Warning: " + candidateState + " has permissions 0755; workspace " + candidateOnlyWork +
		"/.beads; other " + candidateState + "/elsewhere\n")
	for _, names := range [][]string{{"work-path", "state-path"}, {"state-path", "work-path"}} {
		output, err := normalize(input, names, stateSide)
		if err != nil {
			t.Fatal(err)
		}
		want := "Warning: <state> has permissions 0755; workspace <work>/.beads; other <state>/elsewhere\n"
		if string(output) != want {
			t.Fatalf("%v: got %q, want %q", names, output, want)
		}
	}
}

func TestPathRulesUseOnlyTheirOwnValues(t *testing.T) {
	input := []byte(oracleWork + " " + oracleHome + "\n")
	output, err := normalize(input, []string{"work-path"}, oracleSide)
	if err != nil {
		t.Fatal(err)
	}
	if want := "<work> " + oracleHome + "\n"; string(output) != want {
		t.Fatalf("got %q, want %q", output, want)
	}
}

func TestOptionsMustSuitTheirRules(t *testing.T) {
	cases := []struct {
		names   []string
		options Options
	}{
		{[]string{"work-path"}, Options{}},
		{[]string{"work-path"}, Options{Work: []string{"relative/work"}}},
		{[]string{"work-path"}, Options{Work: []string{"/"}}},
		{[]string{"work-path"}, Options{Work: []string{oracleWork + "/"}}},
		{[]string{"home-path"}, Options{Work: []string{oracleWork}}},
		{[]string{"state-path"}, Options{}},
		{[]string{"work-path", "state-path"}, Options{Work: []string{candidateOnlyWork}, State: []string{candidateOnlyWork}}},
		{[]string{"thanks-contributor-order"}, Options{}},
		{[]string{"no-such-rule"}, Options{}},
	}
	for _, test := range cases {
		if _, err := normalize([]byte("x\n"), test.names, test.options); err == nil {
			t.Errorf("%v with %+v: want an error", test.names, test.options)
		}
	}
}

func TestParseRules(t *testing.T) {
	names, err := parseRules(" work-path, ,log-time ")
	if err != nil || !slices.Equal(names, []string{"work-path", "log-time"}) {
		t.Fatalf("got %v, %v", names, err)
	}
	if names, err := parseRules(""); err != nil || len(names) != 0 {
		t.Fatalf("empty list: %v, %v", names, err)
	}
	for _, list := range []string{"work-path,work-path", "workpath", "work-path,bogus"} {
		if _, err := parseRules(list); err == nil {
			t.Errorf("%q: want an error", list)
		}
	}
}

func runCommand(t *testing.T, stdin string, arguments ...string) (int, string, string) {
	t.Helper()
	var stdout, stderr bytes.Buffer
	code := run(arguments, strings.NewReader(stdin), &stdout, &stderr)
	return code, stdout.String(), stderr.String()
}

func TestRulesCommandListsEveryNormalizer(t *testing.T) {
	code, stdout, stderr := runCommand(t, "", "rules")
	if code != 0 || stderr != "" {
		t.Fatalf("exit %d: %s", code, stderr)
	}
	for _, normalizer := range declaredNormalizers {
		for _, want := range []string{
			normalizer.Name + "\n", "  fields: " + normalizer.Fields + "\n", "  reason: " + normalizer.Reason + "\n",
			"  scope: " + normalizer.Scope + "\n",
		} {
			if !strings.Contains(stdout, want) {
				t.Errorf("rules output lacks %q", want)
			}
		}
	}
}

func TestApplyCommand(t *testing.T) {
	directory := t.TempDir()
	input := filepath.Join(directory, "oracle.stderr")
	if err := os.WriteFile(input, []byte("Warning: "+oracleWork+"/.beads\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	code, stdout, stderr := runCommand(t, "", "apply", "--rules", "work-path", "--work", oracleWork, input)
	if code != 0 || stdout != "Warning: <work>/.beads\n" || stderr != "" {
		t.Fatalf("exit %d, stdout %q, stderr %q", code, stdout, stderr)
	}
	code, stdout, _ = runCommand(t, "a\r\nb\r\n", "apply", "--rules", "pty-transcript", "-")
	if code != 0 || stdout != "a\nb\n" {
		t.Fatalf("stdin: exit %d, stdout %q", code, stdout)
	}
	code, stdout, _ = runCommand(t, "", "apply", input)
	if code != 0 || stdout != "Warning: "+oracleWork+"/.beads\n" {
		t.Fatalf("no rules: exit %d, stdout %q", code, stdout)
	}
	code, stdout, _ = runCommand(t, "bd version 1.2.1\n", "apply", "--rules", "build-output", "-")
	if code != 0 || stdout != "<build output>\n" {
		t.Fatalf("build-output: exit %d, stdout %q", code, stdout)
	}
	code, stdout, stderr = runCommand(t, pingJSON("1", "0", "2", "4", "ok"), "apply", "--rules", "ping-timings", "-")
	if code != 1 || stdout != "" || !strings.Contains(stderr, "ping-timings") {
		t.Fatalf("rejected input: exit %d, stdout %q, stderr %q", code, stdout, stderr)
	}
	for _, arguments := range [][]string{
		{"apply"},
		{"apply", "--rules", "bogus", input},
		{"apply", "--rules", "work-path", input},
		{"apply", input, input},
		{"apply", filepath.Join(directory, "missing")},
		{"apply", "--thanks-source", filepath.Join(directory, "missing"), input},
		{"rules", "extra"},
		{"bogus"},
		{},
	} {
		if code, _, _ := runCommand(t, "", arguments...); code != 2 {
			t.Errorf("%v: exit %d, want 2", arguments, code)
		}
	}
}
