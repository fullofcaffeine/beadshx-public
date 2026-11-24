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
		{name: "custom template", format: "{{.IssueID}} -> {{.DependsOnID}} [{{.Type}}]", want: "list-a -> list-b [blocks]\n"},
		// Haxe renders dot and digraph (src/beadshx/cli/ListFormatView.hx); here they are templates.
		{name: "dot is a template here", format: "dot", want: "dot\n"},
		{name: "digraph is a template here", format: "digraph", want: "digraph\n"},
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
