package main

import (
	"errors"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strings"
)

func validateSemanticCatalog(root string, sources []sourceFile, catalog semanticCatalog) error {
	if strings.TrimSpace(catalog.ReviewerRole) == "" ||
		strings.TrimSpace(catalog.SourceClosure) == "" ||
		strings.TrimSpace(catalog.OutputBoundary) == "" ||
		strings.TrimSpace(catalog.ExclusionAuthority) == "" {
		return errors.New("semantic catalog authority fields must be explicit")
	}
	sourceSet := make(map[string]bool, len(sources))
	for _, source := range sources {
		sourceSet[source.Path] = true
	}
	parsedSymbols := make(map[string]map[string]bool)
	ruleIDs := make(map[string]bool, len(catalog.Rules))
	allowedKinds := map[string]bool{"environment": true, "stdin": true, "output": true, "completion": true}
	for _, rule := range catalog.Rules {
		if rule.ID == "" || ruleIDs[rule.ID] {
			return fmt.Errorf("semantic rule has a missing or duplicate ID %q", rule.ID)
		}
		ruleIDs[rule.ID] = true
		if !allowedKinds[rule.Kind] || strings.TrimSpace(rule.Summary) == "" || len(rule.Evidence) == 0 {
			return fmt.Errorf("semantic rule %s is incomplete", rule.ID)
		}
		for _, evidence := range rule.Evidence {
			separator := strings.LastIndex(evidence, ":")
			if separator <= 0 || separator == len(evidence)-1 {
				return fmt.Errorf("semantic rule %s has invalid evidence %q", rule.ID, evidence)
			}
			path := evidence[:separator]
			symbol := evidence[separator+1:]
			if !sourceSet[path] {
				return fmt.Errorf("semantic rule %s references a file outside the source closure: %s", rule.ID, path)
			}
			if parsedSymbols[path] == nil {
				symbols, err := topLevelSymbols(filepath.Join(root, filepath.FromSlash(path)))
				if err != nil {
					return err
				}
				parsedSymbols[path] = symbols
			}
			if !parsedSymbols[path][symbol] {
				return fmt.Errorf("semantic rule %s references unknown symbol %s in %s", rule.ID, symbol, path)
			}
		}
	}
	return nil
}

func topLevelSymbols(path string) (map[string]bool, error) {
	// #nosec G304 -- path comes from the confined, generated source-closure list.
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	parsed, err := parser.ParseFile(token.NewFileSet(), path, content, 0)
	if err != nil {
		return nil, err
	}
	symbols := make(map[string]bool)
	for _, declaration := range parsed.Decls {
		switch value := declaration.(type) {
		case *ast.FuncDecl:
			symbols[value.Name.Name] = true
		case *ast.GenDecl:
			for _, spec := range value.Specs {
				valueSpec, ok := spec.(*ast.ValueSpec)
				if !ok {
					continue
				}
				for _, name := range valueSpec.Names {
					symbols[name.Name] = true
				}
			}
		}
	}
	return symbols, nil
}
