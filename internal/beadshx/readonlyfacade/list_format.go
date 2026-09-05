package readonlyfacade

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"
	"text/template"

	storageissueops "github.com/steveyegge/beads/internal/storage/issueops"
	"github.com/steveyegge/beads/internal/types"
)

// IssueListFormatOutcome is the typed native result for Go-template and graph
// list formats. Go owns only the target-specific template and quoting mechanics;
// Haxe owns parsing, query policy, routing, and process output.
type IssueListFormatOutcome struct {
	value            string
	message          string
	rowLimitExceeded bool
	found            int
	source           string
	cap              int
}

func (v IssueListFormatOutcome) Failed() bool           { return v.message != "" }
func (v IssueListFormatOutcome) Message() string        { return v.message }
func (v IssueListFormatOutcome) RowLimitExceeded() bool { return v.rowLimitExceeded }
func (v IssueListFormatOutcome) Found() int             { return v.found }
func (v IssueListFormatOutcome) Source() string         { return v.source }
func (v IssueListFormatOutcome) Cap() int               { return v.cap }
func (v IssueListFormatOutcome) Value() string          { return v.value }

// ReadIssueListFormatOutcome reads raw typed rows and renders the requested Go
// format before the native values cross into Haxe. This preserves the complete
// types.Issue template surface without exposing native objects to domain code.
func ReadIssueListFormatOutcome(beadsDir string, options *IssueListOptions, global bool, format string) *IssueListFormatOutcome {
	page, err := readIssueListFormatPage(beadsDir, options, global)
	return issueListFormatOutcome(page, format, err)
}

func issueListFormatOutcome(page []*types.IssueWithCounts, format string, err error) *IssueListFormatOutcome {
	if err != nil {
		var capErr *storageissueops.ErrTooManyRows
		if errors.As(err, &capErr) {
			return &IssueListFormatOutcome{
				rowLimitExceeded: true,
				found:            capErr.Found,
				source:           capErr.Source,
				cap:              capErr.Cap,
			}
		}
		return &IssueListFormatOutcome{message: err.Error()}
	}
	value, err := formatIssueList(page, format)
	if err != nil {
		return &IssueListFormatOutcome{message: err.Error()}
	}
	return &IssueListFormatOutcome{value: value}
}

func readIssueListFormatPage(beadsDir string, options *IssueListOptions, global bool) (items []*types.IssueWithCounts, err error) {
	if options == nil {
		options = NewIssueListOptions()
	}
	if options.validationErr != nil {
		return nil, options.validationErr
	}
	ctx := context.Background()
	store, _, _, err := openStore(ctx, beadsDir, global)
	if err != nil {
		return nil, err
	}
	defer captureClose(store, &err)
	reader, err := store.IssueReader()
	if err != nil {
		return nil, err
	}
	page, err := reader.List(ctx, options.request)
	if err != nil {
		return nil, err
	}
	return page.Items, nil
}

func formatIssueList(items []*types.IssueWithCounts, format string) (string, error) {
	if format == "dot" {
		return formatIssueListDOT(items), nil
	}
	templateSource := format
	if format == "digraph" {
		templateSource = "{{.IssueID}} {{.DependsOnID}}"
	}
	tmpl, err := template.New("format").Parse(templateSource)
	if err != nil {
		return "", fmt.Errorf("invalid format template: %w", err)
	}
	visible := visibleIssueIDs(items)
	var output strings.Builder
	for _, row := range items {
		if row == nil || row.Issue == nil {
			continue
		}
		for _, dependency := range orderedDependencies(row.Dependencies) {
			if dependency == nil || !visible[dependency.DependsOnID] {
				continue
			}
			// text/template requires a heterogeneous named root. Keep that dynamic
			// map inside this native boundary and expose only a concrete string.
			data := map[string]any{
				"IssueID":     row.ID,
				"DependsOnID": dependency.DependsOnID,
				"Type":        dependency.Type,
				"Issue":       row.Issue,
				"Dependency":  dependency,
			}
			var rendered bytes.Buffer
			if err := tmpl.Execute(&rendered, data); err != nil {
				return "", fmt.Errorf("template execution error: %w", err)
			}
			output.WriteString(rendered.String())
			output.WriteByte('\n')
		}
	}
	return output.String(), nil
}

func formatIssueListDOT(items []*types.IssueWithCounts) string {
	visible := visibleIssueIDs(items)
	var output strings.Builder
	output.WriteString("digraph dependencies {\n")
	output.WriteString("  rankdir=TB;\n")
	output.WriteString("  node [shape=box, style=rounded];\n\n")
	for _, row := range items {
		if row == nil || row.Issue == nil {
			continue
		}
		fillColor := "white"
		fontColor := "black"
		switch row.Status {
		case types.StatusClosed:
			fillColor = "lightgray"
			fontColor = "dimgray"
		case types.StatusInProgress:
			fillColor = "lightyellow"
		case types.StatusBlocked:
			fillColor = "lightcoral"
		}
		label := fmt.Sprintf("%s\n[%s P%d]\n%s\n(%s)", row.ID, row.IssueType, row.Priority, row.Title, row.Status)
		fmt.Fprintf(&output, "  %q [label=%q, style=\"rounded,filled\", fillcolor=%q, fontcolor=%q];\n",
			row.ID, label, fillColor, fontColor)
	}
	output.WriteByte('\n')
	for _, row := range items {
		if row == nil || row.Issue == nil {
			continue
		}
		for _, dependency := range orderedDependencies(row.Dependencies) {
			if dependency == nil || !visible[dependency.DependsOnID] {
				continue
			}
			color := "black"
			style := "solid"
			switch dependency.Type {
			case types.DepBlocks:
				color = "red"
				style = "bold"
			case types.DepParentChild:
				color = "blue"
			case types.DepDiscoveredFrom:
				color = "green"
				style = "dashed"
			case types.DepRelated:
				color = "gray"
				style = "dashed"
			}
			fmt.Fprintf(&output, "  %q -> %q [label=%q, color=%s, style=%s];\n",
				row.ID, dependency.DependsOnID, dependency.Type, color, style)
		}
	}
	output.WriteString("}\n")
	return output.String()
}

func visibleIssueIDs(items []*types.IssueWithCounts) map[string]bool {
	visible := make(map[string]bool, len(items))
	for _, row := range items {
		if row != nil && row.Issue != nil {
			visible[row.ID] = true
		}
	}
	return visible
}

func orderedDependencies(items []*types.Dependency) []*types.Dependency {
	ordered := append([]*types.Dependency(nil), items...)
	sort.SliceStable(ordered, func(left, right int) bool {
		if ordered[left] == nil {
			return false
		}
		if ordered[right] == nil {
			return true
		}
		if ordered[left].DependsOnID != ordered[right].DependsOnID {
			return ordered[left].DependsOnID < ordered[right].DependsOnID
		}
		if ordered[left].Type != ordered[right].Type {
			return ordered[left].Type < ordered[right].Type
		}
		return ordered[left].ID < ordered[right].ID
	})
	return ordered
}
