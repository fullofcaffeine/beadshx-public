package readonlyfacade

import (
	"context"
	"errors"
	"strconv"
	"time"

	publicops "github.com/steveyegge/beads/issueops"
)

// CountOptions is the typed native boundary for one Haxe-authored count
// request. Times arrive as canonical RFC3339 strings validated by ParseListTime.
type CountOptions struct {
	request       publicops.CountRequest
	validationErr error
}

func NewCountOptions() *CountOptions { return &CountOptions{} }

func (o *CountOptions) SetStatus(value string)        { o.request.Status = value }
func (o *CountOptions) SetIssueType(value string)     { o.request.IssueType = value }
func (o *CountOptions) SetAssignee(value string)      { o.request.Assignee = value }
func (o *CountOptions) SetTitleSearch(value string)   { o.request.TitleSearch = value }
func (o *CountOptions) SetIDFilter(value string)      { o.request.IDFilter = value }
func (o *CountOptions) SetTitleContains(value string) { o.request.TitleContains = value }
func (o *CountOptions) SetDescContains(value string)  { o.request.DescContains = value }
func (o *CountOptions) SetNotesContains(value string) { o.request.NotesContains = value }
func (o *CountOptions) AddLabel(value string)         { o.request.Labels = append(o.request.Labels, value) }
func (o *CountOptions) AddLabelAny(value string) {
	o.request.LabelsAny = append(o.request.LabelsAny, value)
}
func (o *CountOptions) SetEmptyDescription()     { o.request.EmptyDesc = true }
func (o *CountOptions) SetNoAssignee()           { o.request.NoAssignee = true }
func (o *CountOptions) SetNoLabels()             { o.request.NoLabels = true }
func (o *CountOptions) SetIncludeInfra()         { o.request.IncludeInfra = true }
func (o *CountOptions) SetPriority(value int)    { o.request.Priority = &value }
func (o *CountOptions) SetPriorityMin(value int) { o.request.PriorityMin = &value }
func (o *CountOptions) SetPriorityMax(value int) { o.request.PriorityMax = &value }

func (o *CountOptions) setTime(value string, destination **time.Time) {
	if o.validationErr != nil {
		return
	}
	parsed, err := time.Parse(time.RFC3339Nano, value)
	if err != nil {
		o.validationErr = err
		return
	}
	*destination = &parsed
}

func (o *CountOptions) SetCreatedAfter(value string)  { o.setTime(value, &o.request.CreatedAfter) }
func (o *CountOptions) SetCreatedBefore(value string) { o.setTime(value, &o.request.CreatedBefore) }
func (o *CountOptions) SetUpdatedAfter(value string)  { o.setTime(value, &o.request.UpdatedAfter) }
func (o *CountOptions) SetUpdatedBefore(value string) { o.setTime(value, &o.request.UpdatedBefore) }
func (o *CountOptions) SetClosedAfter(value string)   { o.setTime(value, &o.request.ClosedAfter) }
func (o *CountOptions) SetClosedBefore(value string)  { o.setTime(value, &o.request.ClosedBefore) }

// CountGroupRow is one exact group/count pair copied for generated Haxe.
type CountGroupRow struct {
	group string
	count string
}

func (r CountGroupRow) Group() string { return r.group }
func (r CountGroupRow) Count() string { return r.count }

// CountOutcome preserves int64 totals as base-10 text.
type CountOutcome struct {
	total   string
	groups  []CountGroupRow
	message string
}

func (o CountOutcome) Failed() bool           { return o.message != "" }
func (o CountOutcome) Message() string        { return o.message }
func (o CountOutcome) Total() string          { return o.total }
func (o CountOutcome) GroupCount() int        { return len(o.groups) }
func (o CountOutcome) Group(index int) string { return o.groups[index].group }
func (o CountOutcome) Count(index int) string { return o.groups[index].count }

// ReadCountOutcome opens the ordinary direct read-only store and asks its
// existing counter role one cardinality question.
func ReadCountOutcome(beadsDir string, options *CountOptions, group string, global bool) *CountOutcome {
	ctx := context.Background()
	store, _, _, err := openStore(ctx, beadsDir, global)
	if err != nil {
		return countOutcome(publicops.CountResult{}, publicops.CountByGroupResult{}, group, err)
	}
	counter, err := store.Counter()
	if err != nil {
		return countOutcome(publicops.CountResult{}, publicops.CountByGroupResult{}, group, errors.Join(err, store.Close()))
	}
	outcome := readCountOutcome(ctx, counter, options, group)
	if closeErr := store.Close(); closeErr != nil && !outcome.Failed() {
		return countOutcome(publicops.CountResult{}, publicops.CountByGroupResult{}, group, closeErr)
	}
	return outcome
}

func readCountOutcome(ctx context.Context, counter publicops.Counter, options *CountOptions, group string) *CountOutcome {
	if options == nil {
		options = NewCountOptions()
	}
	if options.validationErr != nil {
		return countOutcome(publicops.CountResult{}, publicops.CountByGroupResult{}, group, options.validationErr)
	}
	if group == "" {
		result, err := counter.Count(ctx, options.request)
		return countOutcome(result, publicops.CountByGroupResult{}, group, err)
	}
	result, err := counter.CountByGroup(ctx, publicops.CountByGroupRequest{
		Filter:  options.request,
		GroupBy: publicops.CountGroup(group),
	})
	return countOutcome(publicops.CountResult{}, result, group, err)
}

func countOutcome(scalar publicops.CountResult, grouped publicops.CountByGroupResult, group string, err error) *CountOutcome {
	if err != nil {
		return &CountOutcome{message: err.Error()}
	}
	if group == "" {
		return &CountOutcome{total: strconv.FormatInt(scalar.Total, 10), groups: []CountGroupRow{}}
	}
	rows := make([]CountGroupRow, 0, len(grouped.Groups))
	for key := range grouped.Groups {
		rows = append(rows, CountGroupRow{group: key, count: strconv.Itoa(grouped.Groups[key])})
	}
	return &CountOutcome{total: strconv.FormatInt(grouped.Total, 10), groups: rows}
}
