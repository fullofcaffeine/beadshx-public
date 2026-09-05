package main

import (
	"bytes"
	"encoding/json"
	"testing"
)

func TestFixtureGenerationIsDeterministicAndCounted(t *testing.T) {
	selected := fixturePolicy{
		ID:                    "test",
		GeneratorRevision:     1,
		Seed:                  7,
		IssueCount:            8,
		DependencyCount:       4,
		LabelCount:            3,
		CommentCount:          2,
		TextDistributionBytes: []int{8, 16},
	}
	first, firstIDs, err := generateFixture(selected)
	if err != nil {
		t.Fatal(err)
	}
	second, secondIDs, err := generateFixture(selected)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(first, second) || !sameStrings(firstIDs, secondIDs) {
		t.Fatal("fixture generation is not deterministic")
	}

	decoder := json.NewDecoder(bytes.NewReader(first))
	var issues, dependencies, labels, comments int
	for decoder.More() {
		var issue fixtureIssue
		if err := decoder.Decode(&issue); err != nil {
			t.Fatal(err)
		}
		issues++
		dependencies += len(issue.Dependencies)
		labels += len(issue.Labels)
		comments += len(issue.Comments)
	}
	if issues != 8 || dependencies != 4 || labels != 3 || comments != 2 {
		t.Fatalf("counts = %d/%d/%d/%d; want 8/4/3/2", issues, dependencies, labels, comments)
	}
}
