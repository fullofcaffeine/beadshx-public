// Command output-normalizers rewrites the declared volatile values in one
// side's output of a parity case, for BeadsHX differential tests (BHX-M06-06).
//
// The parity harness compares the stdout and stderr of upstream bd and bdhx
// byte for byte. Some values differ between two correct runs: each side's own
// temporary paths, the wall-clock times that a run prints, the order of
// output that upstream builds from a Go map, and each build's own identity.
// Each normalizer declares the values that it rewrites, why they are
// volatile, and which comparisons may use it, and rewrites nothing else, so a
// difference outside its declared values still fails the comparison.
//
// A comparison names its normalizers with --rules; without --rules the output
// is copied exactly. apply runs the named normalizers in the order of the
// registry, whatever order they are named in. The rules command lists each
// normalizer with its fields, reason and scope. It follows the convention of
// scripts/beadshx/logical-state, whose declared rules normalize the logical
// database state.
//
// Usage:
//
//	output-normalizers apply [OPTION...] FILE > NORMALIZED
//	output-normalizers rules
//
// FILE is one side's stdout or stderr; - reads stdin. Options:
//
//	--rules NAME,...       apply these declared normalizers (none: copy exactly)
//	--work PATH            a spelling of the side's work directory, for work-path (repeatable)
//	--home PATH            a spelling of the side's HOME directory, for home-path (repeatable)
//	--state PATH           a spelling of the side's state root, for state-path (repeatable)
//	--thanks-source FILE   upstream's cmd/bd/thanks.go, for thanks-contributor-order
//
// apply exits 0 after it writes the normalized output, 1 when a normalizer
// rejects the input because its declared value is not there in the declared
// form (the comparison then fails), and 2 on a usage or read error.
package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
)

const usage = `usage: output-normalizers apply [--rules NAME,...] [--work PATH]... [--home PATH]... [--state PATH]...
                          [--thanks-source FILE] FILE
       output-normalizers rules
`

func main() {
	os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
}

// errUsage marks an error for which the usage text helps.
var errUsage = errors.New("usage")

func run(arguments []string, stdin io.Reader, stdout, stderr io.Writer) int {
	if len(arguments) == 0 {
		fmt.Fprint(stderr, usage)
		return 2
	}
	var err error
	switch arguments[0] {
	case "apply":
		err = runApply(arguments[1:], stdin, stdout)
	case "rules":
		err = runRules(arguments[1:], stdout)
	default:
		err = fmt.Errorf("%w: unknown command %q", errUsage, arguments[0])
	}
	if err == nil {
		return 0
	}
	fmt.Fprintf(stderr, "output-normalizers: %v\n", err)
	if errors.Is(err, errUsage) {
		fmt.Fprint(stderr, usage)
	}
	if errors.Is(err, errRejected) {
		return 1
	}
	return 2
}

func runRules(arguments []string, stdout io.Writer) error {
	if len(arguments) != 0 {
		return fmt.Errorf("%w: rules takes no argument", errUsage)
	}
	for _, normalizer := range declaredNormalizers {
		if _, err := fmt.Fprintf(stdout, "%s\n  fields: %s\n  reason: %s\n  scope: %s\n",
			normalizer.Name, normalizer.Fields, normalizer.Reason, normalizer.Scope); err != nil {
			return err
		}
	}
	return nil
}

// repeated collects the values of a flag that may be given more than once.
type repeated []string

func (values *repeated) String() string { return fmt.Sprint(*values) }

func (values *repeated) Set(value string) error {
	*values = append(*values, value)
	return nil
}

func runApply(arguments []string, stdin io.Reader, stdout io.Writer) error {
	flags := flag.NewFlagSet("apply", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	var (
		rules             string
		work, home, state repeated
		thanksSource      string
	)
	flags.StringVar(&rules, "rules", "", "")
	flags.Var(&work, "work", "")
	flags.Var(&home, "home", "")
	flags.Var(&state, "state", "")
	flags.StringVar(&thanksSource, "thanks-source", "", "")
	if err := flags.Parse(arguments); err != nil {
		return fmt.Errorf("%w: %v", errUsage, err)
	}
	if flags.NArg() != 1 {
		return fmt.Errorf("%w: apply takes one file", errUsage)
	}
	names, err := parseRules(rules)
	if err != nil {
		return fmt.Errorf("%w: %v", errUsage, err)
	}
	options := Options{Work: work, Home: home, State: state}
	if thanksSource != "" {
		if options.ThanksSource, err = readFile(thanksSource); err != nil {
			return err
		}
	}
	var input []byte
	if flags.Arg(0) == "-" {
		input, err = io.ReadAll(stdin)
	} else {
		input, err = readFile(flags.Arg(0))
	}
	if err != nil {
		return err
	}
	output, err := normalize(input, names, options)
	if err != nil {
		return err
	}
	_, err = stdout.Write(output)
	return err
}

func readFile(path string) ([]byte, error) {
	//nolint:gosec // G304: the path is an output or source file that the caller names.
	return os.ReadFile(path)
}
