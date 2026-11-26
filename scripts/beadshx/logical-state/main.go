// Command logical-state exports and compares the logical state of disposable
// embedded Beads fixtures, for BeadsHX differential tests (BHX-M06-07).
//
// Dolt's storage bytes differ between two databases that hold equal rows and
// an equal history, so a byte fingerprint can only say "changed". export reads
// every table, the Dolt system tables that hold schema objects and
// configuration, and the revision state (branches, tags, remotes, the commit
// graph with each commit's changed tables, and the working set) into
// canonical JSON. compare reports the first differences, by table, row and
// column, or by revision item.
//
// A raw comparison is exact. Normalization rules are applied only when named
// with --rules; the rules command lists each rule with its reason, and a
// normalized view records the rules that made it.
//
// Usage:
//
//	logical-state export WORKSPACE > STATE.json
//	logical-state normalize [OPTION...] STATE.json > VIEW.json
//	logical-state compare [OPTION...] LEFT.json RIGHT.json
//	logical-state rules
//
// Options:
//
//	--rules NAME,...  apply these declared rules (none by default: exact)
//	--since TIME      first second of the run window (RFC 3339), for run-time
//	--until TIME      last second of the run window (RFC 3339), for run-time
//	--baseline FILE   the raw state before the runs, for random-token
//	--max N           compare prints at most N differences (0: all; default 40)
//
// The window holds whole seconds: it runs from the start of the --since second
// to the end of the second after --until. Dolt rounds a DATETIME without a
// fraction to the nearest second, so a time stamped in the last half second
// of a run is stored as the next second. `date -u +%Y-%m-%dT%H:%M:%SZ` before
// and after the runs then covers every time that they stamp.
//
// export refuses a workspace without the .beadshx-disposable-fixture marker
// or not in embedded mode. compare exits 0 when the states are equal, 1 when
// they differ, and 2 on a usage or read error; the other commands exit 0 or 2.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"time"
)

const usage = `usage: logical-state export WORKSPACE
       logical-state normalize [--rules NAME,...] [--since TIME --until TIME] [--baseline FILE] STATE
       logical-state compare [--rules NAME,...] [--since TIME --until TIME] [--baseline FILE] [--max N] LEFT RIGHT
       logical-state rules
`

func main() {
	os.Exit(run(context.Background(), os.Args[1:], os.Stdout, os.Stderr))
}

// errUsage marks an error for which the usage text helps.
var errUsage = errors.New("usage")

func run(ctx context.Context, arguments []string, stdout, stderr io.Writer) int {
	if len(arguments) == 0 {
		fmt.Fprint(stderr, usage)
		return 2
	}
	var (
		differ bool
		err    error
	)
	switch arguments[0] {
	case "export":
		err = runExport(ctx, arguments[1:], stdout)
	case "normalize":
		err = runNormalize(arguments[1:], stdout)
	case "compare":
		differ, err = runCompare(arguments[1:], stdout)
	case "rules":
		err = runRules(arguments[1:], stdout)
	default:
		err = fmt.Errorf("%w: unknown command %q", errUsage, arguments[0])
	}
	if err != nil {
		fmt.Fprintf(stderr, "logical-state: %v\n", err)
		if errors.Is(err, errUsage) {
			fmt.Fprint(stderr, usage)
		}
		return 2
	}
	if differ {
		return 1
	}
	return 0
}

func runExport(ctx context.Context, arguments []string, stdout io.Writer) error {
	if len(arguments) != 1 {
		return fmt.Errorf("%w: export takes one workspace", errUsage)
	}
	state, err := export(ctx, arguments[0])
	if err != nil {
		return err
	}
	return writeState(stdout, state)
}

func runRules(arguments []string, stdout io.Writer) error {
	if len(arguments) != 0 {
		return fmt.Errorf("%w: rules takes no argument", errUsage)
	}
	for _, rule := range declaredRules {
		if _, err := fmt.Fprintf(stdout, "%s\n  %s\n", rule.Name, rule.Reason); err != nil {
			return err
		}
	}
	return nil
}

// viewFlags are the options of normalize and compare.
type viewFlags struct {
	set      *flag.FlagSet
	rules    string
	since    string
	until    string
	baseline string
	limit    int
}

func newViewFlags(name string) *viewFlags {
	flags := &viewFlags{set: flag.NewFlagSet(name, flag.ContinueOnError)}
	flags.set.SetOutput(io.Discard)
	flags.set.StringVar(&flags.rules, "rules", "", "")
	flags.set.StringVar(&flags.since, "since", "", "")
	flags.set.StringVar(&flags.until, "until", "", "")
	flags.set.StringVar(&flags.baseline, "baseline", "", "")
	flags.set.IntVar(&flags.limit, "max", 40, "")
	return flags
}

func (flags *viewFlags) parse(arguments []string, positional int) ([]string, Options, error) {
	if err := flags.set.Parse(arguments); err != nil {
		return nil, Options{}, fmt.Errorf("%w: %v", errUsage, err)
	}
	if flags.set.NArg() != positional {
		return nil, Options{}, fmt.Errorf("%w: %s takes %d state files", errUsage, flags.set.Name(), positional)
	}
	var options Options
	var err error
	if options.Rules, err = parseRules(flags.rules); err != nil {
		return nil, Options{}, err
	}
	if flags.since != "" || flags.until != "" {
		since, sinceErr := time.Parse(time.RFC3339, flags.since)
		until, untilErr := time.Parse(time.RFC3339, flags.until)
		if err := errors.Join(sinceErr, untilErr); err != nil {
			return nil, Options{}, fmt.Errorf("--since and --until take RFC 3339 times: %w", err)
		}
		options.Window = &Window{
			Since: since.UTC().Truncate(time.Second),
			Until: until.UTC().Truncate(time.Second).Add(2*time.Second - time.Nanosecond),
		}
	}
	if flags.baseline != "" {
		baseline, err := readStateFile(flags.baseline)
		if err != nil {
			return nil, Options{}, err
		}
		options.Baseline = &baseline
	}
	return flags.set.Args(), options, nil
}

func readStateFile(path string) (State, error) {
	//nolint:gosec // G304: the path is a state file that the caller names.
	file, err := os.Open(path)
	if err != nil {
		return State{}, err
	}
	defer file.Close()
	state, err := readState(file)
	if err != nil {
		return State{}, fmt.Errorf("%s: %w", path, err)
	}
	return state, nil
}

func runNormalize(arguments []string, stdout io.Writer) error {
	paths, options, err := newViewFlags("normalize").parse(arguments, 1)
	if err != nil {
		return err
	}
	state, err := readStateFile(paths[0])
	if err != nil {
		return err
	}
	normalized, err := normalize(state, options)
	if err != nil {
		return err
	}
	return writeState(stdout, normalized)
}

func runCompare(arguments []string, stdout io.Writer) (bool, error) {
	flags := newViewFlags("compare")
	paths, options, err := flags.parse(arguments, 2)
	if err != nil {
		return false, err
	}
	views := make([]State, len(paths))
	for index, path := range paths {
		state, err := readStateFile(path)
		if err != nil {
			return false, err
		}
		if views[index], err = normalize(state, options); err != nil {
			return false, err
		}
	}
	differences := compare(views[0], views[1])
	return len(differences) > 0, writeReport(stdout, differences, views[0].Rules, flags.limit)
}
