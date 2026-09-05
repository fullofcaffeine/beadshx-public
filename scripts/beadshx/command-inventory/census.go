package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"go/ast"
	"go/parser"
	"go/printer"
	"go/token"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type sourceFile struct {
	Path           string
	ActiveProfiles []string
}

var flagRegistrationMethods = map[string]bool{
	"Bool": true, "BoolP": true, "BoolVar": true, "BoolVarP": true,
	"Duration": true, "DurationP": true, "DurationVar": true, "DurationVarP": true,
	"Float32": true, "Float32P": true, "Float32Var": true, "Float32VarP": true,
	"Float64": true, "Float64P": true, "Float64Var": true, "Float64VarP": true,
	"Int": true, "IntP": true, "IntVar": true, "IntVarP": true,
	"Int32": true, "Int32P": true, "Int32Var": true, "Int32VarP": true,
	"Int64": true, "Int64P": true, "Int64Var": true, "Int64VarP": true,
	"String": true, "StringP": true, "StringVar": true, "StringVarP": true,
	"StringArray": true, "StringArrayP": true, "StringArrayVar": true, "StringArrayVarP": true,
	"StringSlice": true, "StringSliceP": true, "StringSliceVar": true, "StringSliceVarP": true,
	"Uint": true, "UintP": true, "UintVar": true, "UintVarP": true,
	"Uint16": true, "Uint16P": true, "Uint16Var": true, "Uint16VarP": true,
	"Uint32": true, "Uint32P": true, "Uint32Var": true, "Uint32VarP": true,
	"Uint64": true, "Uint64P": true, "Uint64Var": true, "Uint64VarP": true,
	"Var": true, "VarP": true,
}

var metadataMethods = map[string]bool{
	"MarkDeprecated":             true,
	"MarkFlagRequired":           true,
	"MarkFlagsMutuallyExclusive": true,
	"MarkFlagsOneRequired":       true,
	"MarkFlagsRequiredTogether":  true,
	"MarkHidden":                 true,
}

func censusSources(root string, files []sourceFile, policies map[string]string) ([]sourceObligation, error) {
	var obligations []sourceObligation
	for _, source := range files {
		path := filepath.Join(root, filepath.FromSlash(source.Path))
		// #nosec G304 -- source.Path comes from module-owned go-list directories.
		content, err := os.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("read %s: %w", source.Path, err)
		}
		fileSet := token.NewFileSet()
		parsed, err := parser.ParseFile(fileSet, path, content, parser.ParseComments)
		if err != nil {
			return nil, fmt.Errorf("parse %s: %w", source.Path, err)
		}
		if constraint := buildConstraint(parsed); constraint != "" {
			obligations = append(obligations, makeObligation(
				fileSet, source, parsed, "build-constraint", "file", constraint, policies,
			))
		}
		for _, declaration := range parsed.Decls {
			switch value := declaration.(type) {
			case *ast.FuncDecl:
				obligations = append(obligations, scanNode(fileSet, source, value.Name.Name, value.Body, policies)...)
			case *ast.GenDecl:
				for _, spec := range value.Specs {
					valueSpec, ok := spec.(*ast.ValueSpec)
					if !ok {
						continue
					}
					symbol := "file"
					if len(valueSpec.Names) > 0 {
						symbol = valueSpec.Names[0].Name
					}
					obligations = append(obligations, scanNode(fileSet, source, symbol, valueSpec, policies)...)
				}
			}
		}
	}
	sort.Slice(obligations, func(i, j int) bool {
		left, right := obligations[i], obligations[j]
		if left.Path != right.Path {
			return left.Path < right.Path
		}
		if left.Line != right.Line {
			return left.Line < right.Line
		}
		if left.Column != right.Column {
			return left.Column < right.Column
		}
		if left.Kind != right.Kind {
			return left.Kind < right.Kind
		}
		return left.ID < right.ID
	})
	return obligations, nil
}

func scanNode(
	fileSet *token.FileSet,
	source sourceFile,
	symbol string,
	node ast.Node,
	policies map[string]string,
) []sourceObligation {
	if node == nil {
		return nil
	}
	var obligations []sourceObligation
	ast.Inspect(node, func(candidate ast.Node) bool {
		kind, expression := classifyCandidate(candidate)
		if kind == "" {
			return true
		}
		obligations = append(obligations, makeObligation(
			fileSet, source, candidate, kind, symbol, expression, policies,
		))
		return true
	})
	return obligations
}

func classifyCandidate(node ast.Node) (string, string) {
	switch value := node.(type) {
	case *ast.CallExpr:
		selector, ok := value.Fun.(*ast.SelectorExpr)
		if !ok {
			return "", ""
		}
		method := selector.Sel.Name
		if method == "AddCommand" || method == "AddGroup" {
			return "command-registration", renderNode(value)
		}
		if flagRegistrationMethods[method] {
			return "flag-registration", renderNode(value)
		}
		if metadataMethods[method] {
			return "flag-or-command-metadata", renderNode(value)
		}
		if method == "RegisterFlagCompletionFunc" {
			return "completion-registration", renderNode(value)
		}
		if method == "InOrStdin" {
			return "stdin-input", renderNode(value)
		}
		if method == "OutOrStdout" || method == "ErrOrStderr" || method == "SetOut" || method == "SetErr" {
			return "output-channel", renderNode(value)
		}
		if method == "BindEnv" || method == "AutomaticEnv" {
			return "environment-input", renderNode(value)
		}
		if packageName, ok := selector.X.(*ast.Ident); ok && packageName.Name == "os" &&
			(method == "Getenv" || method == "LookupEnv" || method == "Environ" || method == "ExpandEnv") {
			return "environment-input", renderNode(value)
		}
	case *ast.AssignStmt:
		for _, left := range value.Lhs {
			selector, ok := left.(*ast.SelectorExpr)
			if !ok {
				continue
			}
			switch selector.Sel.Name {
			case "Aliases", "Hidden", "Deprecated":
				return "command-metadata", renderNode(value)
			case "ValidArgs", "ValidArgsFunction":
				return "completion-registration", renderNode(value)
			}
		}
	case *ast.SelectorExpr:
		packageName, ok := value.X.(*ast.Ident)
		if !ok || packageName.Name != "os" {
			return "", ""
		}
		switch value.Sel.Name {
		case "Stdin":
			return "stdin-input", renderNode(value)
		case "Stdout", "Stderr":
			return "output-channel", renderNode(value)
		}
	case *ast.KeyValueExpr:
		key, ok := value.Key.(*ast.Ident)
		if !ok {
			return "", ""
		}
		switch key.Name {
		case "Aliases", "Hidden", "Deprecated":
			return "command-metadata", renderNode(value)
		case "ValidArgs", "ValidArgsFunction":
			return "completion-registration", renderNode(value)
		}
	}
	return "", ""
}

func makeObligation(
	fileSet *token.FileSet,
	source sourceFile,
	node ast.Node,
	kind string,
	symbol string,
	expression string,
	policies map[string]string,
) sourceObligation {
	position := fileSet.Position(node.Pos())
	digest := sha256.Sum256([]byte(expression))
	digestText := hex.EncodeToString(digest[:])
	idInput := fmt.Sprintf("%s\x00%s\x00%d\x00%d\x00%s\x00%s", kind, source.Path, position.Line, position.Column, symbol, digestText)
	idDigest := sha256.Sum256([]byte(idInput))
	profiles := append([]string(nil), source.ActiveProfiles...)
	sort.Strings(profiles)
	return sourceObligation{
		ID:             "obl:" + hex.EncodeToString(idDigest[:12]),
		Kind:           kind,
		Path:           source.Path,
		Line:           position.Line,
		Column:         position.Column,
		Symbol:         symbol,
		Expression:     expression,
		SnippetSHA256:  digestText,
		ActiveProfiles: profiles,
		Resolution:     policies[kind],
	}
}

func renderNode(node ast.Node) string {
	var buffer bytes.Buffer
	if err := printer.Fprint(&buffer, token.NewFileSet(), node); err != nil {
		return "<unprintable>"
	}
	return strings.Join(strings.Fields(buffer.String()), " ")
}

func buildConstraint(file *ast.File) string {
	for _, group := range file.Comments {
		for _, comment := range group.List {
			if strings.HasPrefix(comment.Text, "//go:build ") {
				return strings.TrimSpace(strings.TrimPrefix(comment.Text, "//go:build "))
			}
		}
	}
	return ""
}
