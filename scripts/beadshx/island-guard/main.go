// Command island-guard keeps the handwritten Go islands under internal/beadshx
// shrink-only.
//
// Why: the islands are frozen, removal-tracked scaffolding (ADR 0008). The
// owner rule of 2026-11-22 says that their non-test lines and their import set
// may only shrink, and that no island may write: no configfile.Load and no
// writable store open. New behavior belongs in authored Haxe.
//
// What: the guard parses every non-test Go file under internal/beadshx. It
// fails when the line count is above the recorded baseline, when the files
// import a package that the baseline does not list, when a file calls
// configfile.Load, or when a file opens a writable store. Growth is refused;
// a deliberate raise needs an owner decision and a hand edit of the baseline.
// A shrink is allowed, but the ratchet is strict: the check also fails while
// the baseline is above the islands, until --update lowers it in the same
// commit. A stale baseline would let later code grow back into deleted lines.
//
// How: lines are newline counts, the same as `wc -l`. Imports are the union
// of the import paths of all non-test files, whatever their build tags. Calls
// are resolved through each file's own import names, so an aliased import is
// still found. A writable store open is any reference to a function named
// Open* or New* in internal/storage/embeddeddolt, except the strict read-only
// openers OpenReadOnly and OpenForPreviewCommand, and any reference to a
// function named Open* or New* in internal/storage/dolt, except a call to New,
// NewFromConfigWithOptions or NewFromConfigWithCLIOptions whose argument list
// has an inline dolt.Config literal that sets ReadOnly: true.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const (
	islandRoot   = "internal/beadshx"
	baselinePath = "compatibility/native-islands/baseline.json"

	configfilePackage   = "github.com/steveyegge/beads/internal/configfile"
	embeddedDoltPackage = "github.com/steveyegge/beads/internal/storage/embeddeddolt"
	doltPackage         = "github.com/steveyegge/beads/internal/storage/dolt"

	updateCommand = "go run ./scripts/beadshx/island-guard --update"
)

// readOnlyEmbeddedOpeners open an embedded store that refuses every write.
var readOnlyEmbeddedOpeners = map[string]bool{
	"OpenReadOnly":          true,
	"OpenForPreviewCommand": true,
}

// configuredDoltOpeners take a *dolt.Config; they open read-only only when
// that config sets ReadOnly: true.
var configuredDoltOpeners = map[string]bool{
	"New":                         true,
	"NewFromConfigWithOptions":    true,
	"NewFromConfigWithCLIOptions": true,
}

type baseline struct {
	SchemaVersion int      `json:"schemaVersion"`
	Root          string   `json:"root"`
	NonTestLines  int      `json:"nonTestLines"`
	Imports       []string `json:"imports"`
}

type measurement struct {
	files      int
	lines      int
	imports    []string
	violations []string
}

func main() {
	repository := flag.String("repository", ".", "BeadsHX repository root")
	update := flag.Bool("update", false, "lower the baseline to the current islands; refuses growth")
	flag.Parse()
	if err := run(*repository, *update, os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "native islands: %v\n", err)
		os.Exit(1)
	}
}

func run(repository string, update bool, stdout io.Writer) error {
	recordedPath := filepath.Join(repository, baselinePath)
	recorded, err := loadBaseline(recordedPath)
	if err != nil {
		return err
	}
	current, err := measure(filepath.Join(repository, islandRoot))
	if err != nil {
		return err
	}

	failures := current.violations
	if current.lines > recorded.NonTestLines {
		failures = append(failures, fmt.Sprintf(
			"non-test Go under %s grew from %d to %d lines", islandRoot, recorded.NonTestLines, current.lines))
	}
	added, removed := difference(recorded.Imports, current.imports)
	for _, path := range added {
		failures = append(failures, fmt.Sprintf("new import %q under %s", path, islandRoot))
	}
	if len(failures) > 0 {
		return fmt.Errorf("%s\nThe islands are shrink-only and may not write (owner rule 2026-11-22, ADR 0008): "+
			"port the behavior to Haxe instead. Raising %s needs an owner decision and a hand edit",
			strings.Join(failures, "\n"), baselinePath)
	}

	shrunk := current.lines < recorded.NonTestLines || len(removed) > 0
	if update && shrunk {
		next := baseline{SchemaVersion: 1, Root: islandRoot, NonTestLines: current.lines, Imports: current.imports}
		if err := writeBaseline(recordedPath, next); err != nil {
			return err
		}
		_, err := fmt.Fprintf(stdout, "native islands: baseline lowered to %d non-test lines and %d imports; commit %s with this change\n",
			current.lines, len(current.imports), baselinePath)
		return err
	}
	if shrunk {
		return fmt.Errorf("the islands shrank (%d of %d baseline lines; %d imports no longer used); "+
			"lower the baseline in this commit: %s",
			current.lines, recorded.NonTestLines, len(removed), updateCommand)
	}
	_, err = fmt.Fprintf(stdout, "native islands: PASS (%d non-test lines in %d files; %d imports; no configfile.Load; no writable store open)\n",
		current.lines, current.files, len(current.imports))
	return err
}

func loadBaseline(path string) (baseline, error) {
	// #nosec G304 -- the path is the fixed baseline inside the repository.
	data, err := os.ReadFile(path)
	if err != nil {
		return baseline{}, fmt.Errorf("read baseline: %w", err)
	}
	var recorded baseline
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&recorded); err != nil {
		return baseline{}, fmt.Errorf("parse %s: %w", baselinePath, err)
	}
	if recorded.SchemaVersion != 1 || recorded.Root != islandRoot || recorded.NonTestLines <= 0 ||
		!sort.StringsAreSorted(recorded.Imports) {
		return baseline{}, fmt.Errorf("%s must have schemaVersion 1, root %q, positive nonTestLines and sorted imports",
			baselinePath, islandRoot)
	}
	return recorded, nil
}

func writeBaseline(path string, next baseline) error {
	data, err := json.MarshalIndent(next, "", "  ")
	if err != nil {
		return err
	}
	// #nosec G306 -- the baseline is a reviewable repository artifact.
	return os.WriteFile(path, append(data, '\n'), 0o644)
}

func measure(root string) (measurement, error) {
	var result measurement
	imports := map[string]bool{}
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() || filepath.Ext(path) != ".go" || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		name := islandRoot + "/" + filepath.ToSlash(relative)
		// #nosec G304 -- the walk stays inside internal/beadshx.
		source, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		fileSet := token.NewFileSet()
		file, err := parser.ParseFile(fileSet, name, source, parser.SkipObjectResolution)
		if err != nil {
			return fmt.Errorf("parse %s: %w", name, err)
		}
		result.files++
		result.lines += bytes.Count(source, []byte("\n"))
		if len(source) > 0 && source[len(source)-1] != '\n' {
			result.lines++
		}
		for _, spec := range file.Imports {
			importPath, err := strconv.Unquote(spec.Path.Value)
			if err != nil {
				return fmt.Errorf("%s: import %s: %w", name, spec.Path.Value, err)
			}
			imports[importPath] = true
		}
		result.violations = append(result.violations, writeViolations(fileSet, file)...)
		return nil
	})
	if err != nil {
		return measurement{}, fmt.Errorf("scan %s: %w", islandRoot, err)
	}
	if result.files == 0 {
		return measurement{}, errors.New("found no non-test Go files under " + islandRoot)
	}
	for importPath := range imports {
		result.imports = append(result.imports, importPath)
	}
	sort.Strings(result.imports)
	return result, nil
}

// importNames maps each local package name in file to its import path, for
// the packages that the write rules watch.
func importNames(file *ast.File) map[string]string {
	watched := map[string]string{
		configfilePackage:   "configfile",
		embeddedDoltPackage: "embeddeddolt",
		doltPackage:         "dolt",
	}
	names := map[string]string{}
	for _, spec := range file.Imports {
		importPath, err := strconv.Unquote(spec.Path.Value)
		if err != nil {
			continue
		}
		local, ok := watched[importPath]
		if !ok {
			continue
		}
		if spec.Name != nil {
			local = spec.Name.Name
		}
		names[local] = importPath
	}
	return names
}

// writeViolations lists each configfile.Load reference and each writable store
// open in file. A dolt opener is admitted only at a call with a read-only
// config; inspection reaches the call before its function selector.
func writeViolations(fileSet *token.FileSet, file *ast.File) []string {
	names := importNames(file)
	if len(names) == 0 {
		return nil
	}
	admitted := map[*ast.SelectorExpr]bool{}
	var violations []string
	ast.Inspect(file, func(node ast.Node) bool {
		if call, ok := node.(*ast.CallExpr); ok {
			selector, importPath := watchedSelector(call.Fun, names)
			if importPath == doltPackage && configuredDoltOpeners[selector.Sel.Name] && hasReadOnlyConfig(call.Args, names) {
				admitted[selector] = true
			}
			return true
		}
		selector, importPath := watchedSelector(node, names)
		if selector == nil || admitted[selector] {
			return true
		}
		function := selector.Sel.Name
		position := fileSet.Position(selector.Pos())
		location := fmt.Sprintf("%s:%d", position.Filename, position.Line)
		switch {
		case importPath == configfilePackage && function == "Load":
			violations = append(violations, location+
				" calls configfile.Load, which rewrites a legacy config.json; use configfile.LoadForDiscovery")
		case importPath == embeddedDoltPackage && isOpener(function) && !readOnlyEmbeddedOpeners[function]:
			violations = append(violations, fmt.Sprintf(
				"%s uses embeddeddolt.%s, which can open a writable store; use embeddeddolt.OpenReadOnly", location, function))
		case importPath == doltPackage && isOpener(function):
			violations = append(violations, fmt.Sprintf(
				"%s uses dolt.%s without an inline &dolt.Config{ReadOnly: true} argument", location, function))
		}
		return true
	})
	return violations
}

func isOpener(function string) bool {
	return strings.HasPrefix(function, "Open") || strings.HasPrefix(function, "New")
}

// watchedSelector returns node as pkg.Name when pkg names a watched import.
func watchedSelector(node ast.Node, names map[string]string) (*ast.SelectorExpr, string) {
	selector, ok := node.(*ast.SelectorExpr)
	if !ok {
		return nil, ""
	}
	pkg, ok := selector.X.(*ast.Ident)
	if !ok {
		return nil, ""
	}
	importPath, ok := names[pkg.Name]
	if !ok {
		return nil, ""
	}
	return selector, importPath
}

// hasReadOnlyConfig reports whether args has an inline dolt.Config literal,
// optionally behind &, that sets ReadOnly: true.
func hasReadOnlyConfig(args []ast.Expr, names map[string]string) bool {
	for _, arg := range args {
		if unary, ok := arg.(*ast.UnaryExpr); ok && unary.Op == token.AND {
			arg = unary.X
		}
		literal, ok := arg.(*ast.CompositeLit)
		if !ok {
			continue
		}
		selector, importPath := watchedSelector(literal.Type, names)
		if importPath != doltPackage || selector.Sel.Name != "Config" {
			continue
		}
		for _, element := range literal.Elts {
			field, ok := element.(*ast.KeyValueExpr)
			if !ok {
				continue
			}
			key, keyOK := field.Key.(*ast.Ident)
			value, valueOK := field.Value.(*ast.Ident)
			if keyOK && valueOK && key.Name == "ReadOnly" && value.Name == "true" {
				return true
			}
		}
	}
	return false
}

// difference returns the sorted entries only in current (added) and only in
// recorded (removed).
func difference(recorded, current []string) (added, removed []string) {
	inRecorded := map[string]bool{}
	for _, importPath := range recorded {
		inRecorded[importPath] = true
	}
	inCurrent := map[string]bool{}
	for _, importPath := range current {
		inCurrent[importPath] = true
		if !inRecorded[importPath] {
			added = append(added, importPath)
		}
	}
	for _, importPath := range recorded {
		if !inCurrent[importPath] {
			removed = append(removed, importPath)
		}
	}
	return added, removed
}
