package readonlyfacade

import (
	"testing"

	"github.com/steveyegge/beads/internal/types"
)

func listFormatFixture() []*types.IssueWithCounts {
	first := &types.Issue{
		ID:        "list-a",
		Title:     "Alpha",
		Status:    types.StatusOpen,
		Priority:  1,
		IssueType: types.TypeBug,
	}
	second := &types.Issue{
		ID:        "list-b",
		Title:     "Beta",
		Status:    types.StatusClosed,
		Priority:  2,
		IssueType: types.TypeTask,
	}
	first.Dependencies = []*types.Dependency{{
		IssueID:     first.ID,
		DependsOnID: second.ID,
		Type:        types.DepBlocks,
	}}
	return []*types.IssueWithCounts{{Issue: first}, {Issue: second}}
}

func TestFormatIssueListExactBytes(t *testing.T) {
	t.Parallel()
	items := listFormatFixture()
	tests := []struct {
		name   string
		format string
		want   string
	}{
		{name: "digraph preset", format: "digraph", want: "list-a list-b\n"},
		{name: "custom template", format: "{{.IssueID}} -> {{.DependsOnID}} [{{.Type}}]", want: "list-a -> list-b [blocks]\n"},
		{name: "dot", format: "dot", want: "digraph dependencies {\n" +
			"  rankdir=TB;\n" +
			"  node [shape=box, style=rounded];\n\n" +
			"  \"list-a\" [label=\"list-a\\n[bug P1]\\nAlpha\\n(open)\", style=\"rounded,filled\", fillcolor=\"white\", fontcolor=\"black\"];\n" +
			"  \"list-b\" [label=\"list-b\\n[task P2]\\nBeta\\n(closed)\", style=\"rounded,filled\", fillcolor=\"lightgray\", fontcolor=\"dimgray\"];\n\n" +
			"  \"list-a\" -> \"list-b\" [label=\"blocks\", color=red, style=bold];\n" +
			"}\n"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			got, err := formatIssueList(items, test.format)
			if err != nil {
				t.Fatalf("formatIssueList: %v", err)
			}
			if got != test.want {
				t.Fatalf("formatted bytes differ: got %q, want %q", got, test.want)
			}
		})
	}
}

func TestFormatIssueListRejectsInvalidTemplate(t *testing.T) {
	t.Parallel()
	if _, err := formatIssueList(listFormatFixture(), "{{.IssueID"); err == nil {
		t.Fatal("formatIssueList accepted an invalid template")
	}
}
