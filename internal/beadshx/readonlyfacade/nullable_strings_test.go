package readonlyfacade

import (
	"testing"

	"github.com/steveyegge/beads/internal/types"
)

// The pinned wire model uses pointers: an empty pointee is present data.
// This runtime assertion also keeps the exported native getter ABI precise.
type issuePointerStrings interface {
	ExternalRef() *string
	CompactedAtCommit() *string
}

func TestIssueRecordPreservesNullableStrings(t *testing.T) {
	for _, testCase := range []struct {
		name        string
		externalRef *string
		commit      *string
	}{
		{name: "both NULL"},
		{name: "both empty", externalRef: nullableStringPointer(""), commit: nullableStringPointer("")},
		{name: "distinct text", externalRef: nullableStringPointer("ext-17"), commit: nullableStringPointer("commit-29")},
		{name: "NULL reference and empty commit", commit: nullableStringPointer("")},
		{name: "empty reference and NULL commit", externalRef: nullableStringPointer("")},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			var wantExternal, wantCommit string
			if testCase.externalRef != nil {
				wantExternal = *testCase.externalRef
			}
			if testCase.commit != nil {
				wantCommit = *testCase.commit
			}
			record := projectIssueRecord(types.Issue{ID: "presence-fixture", ExternalRef: testCase.externalRef, CompactedAtCommit: testCase.commit})
			getters, ok := any(record).(issuePointerStrings)
			if !ok {
				t.Fatal("native getters collapse pointer-string presence into plain strings")
			}
			check := func(label string, got *string, source *string, want string) {
				t.Helper()
				if source == nil {
					if got != nil {
						t.Errorf("%s: SQL NULL became present", label)
					}
				} else if got == nil || *got != want {
					t.Errorf("%s: present value was lost or changed", label)
				}
			}
			check("external_ref", getters.ExternalRef(), testCase.externalRef, wantExternal)
			check("compacted_at_commit", getters.CompactedAtCommit(), testCase.commit, wantCommit)
			if testCase.externalRef != nil {
				*testCase.externalRef = "mutated external source"
			}
			if testCase.commit != nil {
				*testCase.commit = "mutated commit source"
			}
			check("detached external_ref", getters.ExternalRef(), testCase.externalRef, wantExternal)
			check("detached compacted_at_commit", getters.CompactedAtCommit(), testCase.commit, wantCommit)
		})
	}
}

func nullableStringPointer(value string) *string { return &value }
