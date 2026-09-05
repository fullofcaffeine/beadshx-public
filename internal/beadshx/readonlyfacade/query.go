package readonlyfacade

import (
	"strconv"
	"time"

	"github.com/steveyegge/beads/internal/types"
	publicops "github.com/steveyegge/beads/issueops"
)

// QueryInstant is a precise, target-neutral time projection for Haxe policy.
type QueryInstant struct {
	canonical    string
	epochSeconds string
	nanosecond   int
	year         int
	month        int
	day          int
}

func newQueryInstant(value time.Time) QueryInstant {
	return QueryInstant{
		canonical:    value.Format(time.RFC3339Nano),
		epochSeconds: strconv.FormatInt(value.Unix(), 10),
		nanosecond:   value.Nanosecond(),
		year:         value.Year(),
		month:        int(value.Month()),
		day:          value.Day(),
	}
}

func (v QueryInstant) Canonical() string    { return v.canonical }
func (v QueryInstant) EpochSeconds() string { return v.epochSeconds }
func (v QueryInstant) Nanosecond() int      { return v.nanosecond }
func (v QueryInstant) Year() int            { return v.year }
func (v QueryInstant) Month() int           { return v.month }
func (v QueryInstant) Day() int             { return v.day }

// QueryRow combines the established list DTO with query-only sidecar facts.
type QueryRow struct {
	item      IssueListItem
	pinned    bool
	ephemeral bool
	template  bool
	created   QueryInstant
	updated   QueryInstant
	started   *QueryInstant
	closed    *QueryInstant
}

func (v QueryRow) Item() *IssueListItem   { return &v.item }
func (v QueryRow) Pinned() bool           { return v.pinned }
func (v QueryRow) Ephemeral() bool        { return v.ephemeral }
func (v QueryRow) Template() bool         { return v.template }
func (v QueryRow) Created() *QueryInstant { return &v.created }
func (v QueryRow) Updated() *QueryInstant { return &v.updated }
func (v QueryRow) HasStarted() bool       { return v.started != nil }
func (v QueryRow) HasClosed() bool        { return v.closed != nil }
func (v QueryRow) Started() *QueryInstant {
	if v.started == nil {
		return &QueryInstant{}
	}
	return v.started
}
func (v QueryRow) Closed() *QueryInstant {
	if v.closed == nil {
		return &QueryInstant{}
	}
	return v.closed
}

// QueryRowsOutcome keeps completeness evidence explicit for predicate reads.
type QueryRowsOutcome struct {
	rows          []QueryRow
	sourceHasMore bool
	complete      bool
	message       string
}

func (v QueryRowsOutcome) Failed() bool        { return v.message != "" }
func (v QueryRowsOutcome) Message() string     { return v.message }
func (v QueryRowsOutcome) Count() int          { return len(v.rows) }
func (v QueryRowsOutcome) SourceHasMore() bool { return v.sourceHasMore }
func (v QueryRowsOutcome) Complete() bool      { return v.complete }
func (v QueryRowsOutcome) Row(index int) *QueryRow {
	if index < 0 || index >= len(v.rows) {
		return &QueryRow{}
	}
	return &v.rows[index]
}

func queryRowsFailure(err error) *QueryRowsOutcome {
	return &QueryRowsOutcome{message: err.Error()}
}

func projectQueryRows(items []*types.IssueWithCounts, sourceHasMore, complete bool) (*QueryRowsOutcome, error) {
	rows := make([]QueryRow, 0, len(items))
	for _, source := range items {
		item, err := projectIssueListItem(source)
		if err != nil {
			return nil, err
		}
		issue := source.Issue
		row := QueryRow{
			item:      item,
			pinned:    issue.Pinned,
			ephemeral: issue.Ephemeral,
			template:  issue.IsTemplate,
			created:   newQueryInstant(issue.CreatedAt),
			updated:   newQueryInstant(issue.UpdatedAt),
		}
		if issue.StartedAt != nil {
			value := newQueryInstant(*issue.StartedAt)
			row.started = &value
		}
		if issue.ClosedAt != nil {
			value := newQueryInstant(*issue.ClosedAt)
			row.closed = &value
		}
		rows = append(rows, row)
	}
	return &QueryRowsOutcome{rows: rows, sourceHasMore: sourceHasMore, complete: complete}, nil
}

// ProjectQueryPage copies fields whose native struct ABI is not yet safely
// expressible by haxe.go. The deterministic goextern audit reports the embedded
// IssueWithCounts.Issue field plus pointer, slice, and map field ABI fallbacks.
// It does not filter, sort, page, or interpret rows; authored Haxe owns those
// product semantics. Remove this copier when that exact exported row graph has
// a fallback-free extern and the direct/proxied query differentials still pass.
func ProjectQueryPage(page publicops.IssuePage) *QueryRowsOutcome {
	outcome, err := projectQueryRows(page.Items, page.HasMore, !page.HasMore)
	if err != nil {
		return queryRowsFailure(err)
	}
	return outcome
}
