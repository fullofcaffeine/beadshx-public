// Command compatibility-manifest validates the BeadsHX compatibility manifest.
//
// It checks the manifest against its JSON Schema (draft 2020-12), then runs
// the semantic rules that a schema cannot express: unique and sorted IDs,
// typed references, exact set equality with the pinned M02-01 command
// inventory, source-inventory digests, evidence freshness, waiver rules, and
// coverage rules. It fails closed and prints every offending ID. Last, it
// renders the Markdown report and compares it byte for byte with the
// committed copy, or rewrites that copy with -write-report.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/santhosh-tekuri/jsonschema/v6"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(arguments []string) int {
	flags := flag.NewFlagSet("compatibility-manifest", flag.ContinueOnError)
	repositoryRoot := flags.String("repository", ".", "repository root")
	manifestPath := flags.String("manifest", "compatibility/manifests/beads-v1.2.1.json", "manifest to check")
	schemaPath := flags.String("schema", "compatibility/schema/manifest.schema.json", "JSON Schema of the manifest")
	reportPath := flags.String("report", "compatibility/generated/beads-v1.2.1.md", "generated report")
	inventoryPath := flags.String("command-inventory", "", "check against this command inventory file instead of the recorded path")
	writeReport := flags.Bool("write-report", false, "rewrite the report from a valid manifest")
	skipReport := flags.Bool("skip-report", false, "do not compare the report (fixture runs)")
	asOf := flags.String("as-of", "", "date (YYYY-MM-DD) for waiver review dates; default: today in UTC")
	if err := flags.Parse(arguments); err != nil {
		return 2
	}
	root, err := filepath.Abs(*repositoryRoot)
	if err != nil {
		fmt.Fprintf(os.Stderr, "compatibility manifest: %v\n", err)
		return 2
	}
	if *asOf == "" {
		*asOf = time.Now().UTC().Format("2006-01-02")
	}
	repo := repository{root: root, overrides: map[string]string{}}
	manifestFile := absolute(root, *manifestPath)
	content, err := os.ReadFile(filepath.Clean(manifestFile))
	if err != nil {
		fmt.Fprintf(os.Stderr, "compatibility manifest: %v\n", err)
		return 1
	}

	var problems []string
	problems = append(problems, validateSchema(absolute(root, *schemaPath), content)...)
	manifest, decodeErr := decodeManifest(content)
	if decodeErr != nil {
		problems = append(problems, "decode: "+decodeErr.Error())
	} else {
		if *inventoryPath != "" {
			for _, inventory := range manifest.SourceInventories {
				if inventory.Kind == "command-inventory" {
					repo.overrides[inventory.Path] = absolute(root, *inventoryPath)
				}
			}
		}
		problems = append(problems, newChecker(manifest, repo, *asOf).run()...)
	}

	if len(problems) == 0 && !*skipReport {
		report := renderReport(manifest, filepath.ToSlash(*manifestPath))
		reportFile := absolute(root, *reportPath)
		if *writeReport {
			// The report is a tracked, world-readable repository file.
			if err := os.WriteFile(filepath.Clean(reportFile), []byte(report), 0o644); err != nil { //nolint:gosec // G306: tracked repository file
				fmt.Fprintf(os.Stderr, "compatibility manifest: %v\n", err)
				return 1
			}
		} else {
			committed, err := os.ReadFile(filepath.Clean(reportFile))
			switch {
			case err != nil:
				problems = append(problems, fmt.Sprintf("generated report is unreadable: %s: %v", *reportPath, errors.Unwrap(err)))
			case !bytes.Equal(committed, []byte(report)):
				problems = append(problems, fmt.Sprintf("generated report differs from the manifest: %s; run scripts/beadshx/check-compatibility-manifest.sh --write-report", *reportPath))
			}
		}
	}

	if len(problems) > 0 {
		fmt.Fprintf(os.Stderr, "compatibility manifest: FAIL (%d problems)\n", len(problems))
		for _, problem := range problems {
			fmt.Fprintf(os.Stderr, "  %s\n", problem)
		}
		return 1
	}
	profiles := 0
	for _, command := range manifest.Commands {
		profiles += len(command.Profiles)
	}
	fmt.Printf("compatibility manifest: PASS (%d commands, %d command profiles, %d differences, %d waivers)\n",
		len(manifest.Commands), profiles, len(manifest.Differences), len(manifest.Waivers))
	return 0
}

func absolute(root, path string) string {
	if filepath.IsAbs(path) {
		return path
	}
	return filepath.Join(root, filepath.FromSlash(path))
}

func decodeManifest(content []byte) (Manifest, error) {
	decoder := json.NewDecoder(bytes.NewReader(content))
	decoder.DisallowUnknownFields()
	var manifest Manifest
	if err := decoder.Decode(&manifest); err != nil {
		return Manifest{}, err
	}
	if decoder.More() {
		return Manifest{}, errors.New("trailing data after the manifest object")
	}
	return manifest, nil
}

// validateSchema checks the manifest bytes against the schema and names the
// record ID that contains each violation.
func validateSchema(schemaFile string, content []byte) []string {
	schemaContent, err := os.ReadFile(filepath.Clean(schemaFile))
	if err != nil {
		return []string{"schema: " + err.Error()}
	}
	schemaDocument, err := jsonschema.UnmarshalJSON(bytes.NewReader(schemaContent))
	if err != nil {
		return []string{"schema: " + err.Error()}
	}
	compiler := jsonschema.NewCompiler()
	compiler.DefaultDraft(jsonschema.Draft2020)
	const schemaURL = "urn:beadshx:compatibility-manifest:schema:1"
	if err := compiler.AddResource(schemaURL, schemaDocument); err != nil {
		return []string{"schema: " + err.Error()}
	}
	schema, err := compiler.Compile(schemaURL)
	if err != nil {
		return []string{"schema: " + err.Error()}
	}
	instance, err := jsonschema.UnmarshalJSON(bytes.NewReader(content))
	if err != nil {
		return []string{"schema: manifest is not JSON: " + err.Error()}
	}
	err = schema.Validate(instance)
	if err == nil {
		return nil
	}
	var validation *jsonschema.ValidationError
	if !errors.As(err, &validation) {
		return []string{"schema: " + err.Error()}
	}
	seen := map[string]bool{}
	var problems []string
	for _, leaf := range leaves(validation) {
		location := "/" + strings.Join(leaf.InstanceLocation, "/")
		problem := fmt.Sprintf("schema: %s%s: %s", location, recordLabel(instance, leaf.InstanceLocation), leafMessage(leaf))
		if !seen[problem] {
			seen[problem] = true
			problems = append(problems, problem)
		}
	}
	return problems
}

func leaves(err *jsonschema.ValidationError) []*jsonschema.ValidationError {
	if len(err.Causes) == 0 {
		return []*jsonschema.ValidationError{err}
	}
	var out []*jsonschema.ValidationError
	for _, cause := range err.Causes {
		out = append(out, leaves(cause)...)
	}
	return out
}

func leafMessage(err *jsonschema.ValidationError) string {
	message := err.Error()
	if index := strings.LastIndex(message, "\n"); index >= 0 {
		message = message[index+1:]
	}
	return strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(message), "- "))
}

// recordLabel names the innermost record with an id along the location.
func recordLabel(document any, location []string) string {
	label := ""
	current := document
	for _, token := range location {
		switch node := current.(type) {
		case map[string]any:
			current = node[token]
		case []any:
			index, err := strconv.Atoi(token)
			if err != nil || index < 0 || index >= len(node) {
				return label
			}
			current = node[index]
		default:
			return label
		}
		if object, ok := current.(map[string]any); ok {
			if id, ok := object["id"].(string); ok {
				label = " (" + id + ")"
			}
		}
	}
	return label
}
