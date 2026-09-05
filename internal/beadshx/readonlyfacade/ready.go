package readonlyfacade

import (
	"context"
	"errors"
	"strconv"

	storageissueops "github.com/steveyegge/beads/internal/storage/issueops"
	"github.com/steveyegge/beads/internal/types"
	"github.com/steveyegge/beads/internal/workapi"
	publicops "github.com/steveyegge/beads/issueops"
)

// ReadyOptions is the typed native boundary for one Haxe-authored ready query.
type ReadyOptions struct {
	request       publicops.ReadyRequest
	maxRows       int
	maxRowsSource string
}

func NewReadyOptions() *ReadyOptions { return &ReadyOptions{} }

func (o *ReadyOptions) SetIssueType(value string) { o.request.IssueType = value }
func (o *ReadyOptions) SetAssignee(value string)  { o.request.Assignee = value }
func (o *ReadyOptions) EnableUnassigned()         { o.request.Unassigned = true }
func (o *ReadyOptions) AddLabel(value string)     { o.request.Labels = append(o.request.Labels, value) }
func (o *ReadyOptions) AddLabelAny(value string) {
	o.request.LabelsAny = append(o.request.LabelsAny, value)
}
func (o *ReadyOptions) AddExcludeLabel(value string) {
	o.request.ExcludeLabels = append(o.request.ExcludeLabels, value)
}
func (o *ReadyOptions) SetLabelPattern(value string) { o.request.LabelPattern = value }
func (o *ReadyOptions) SetLabelRegex(value string)   { o.request.LabelRegex = value }
func (o *ReadyOptions) SetPriority(value int)        { o.request.Priority = &value }
func (o *ReadyOptions) SetParentID(value string)     { o.request.ParentID = value }
func (o *ReadyOptions) SetMoleculeType(value string) {
	moleculeType := types.MolType(value)
	o.request.MolType = &moleculeType
}
func (o *ReadyOptions) EnableDeferred()  { o.request.IncludeDeferred = true }
func (o *ReadyOptions) EnableEphemeral() { o.request.IncludeEphemeral = true }
func (o *ReadyOptions) AddExcludeType(value string) {
	o.request.ExcludeTypes = append(o.request.ExcludeTypes, value)
}
func (o *ReadyOptions) AddMetadataField(key, value string) {
	if o.request.MetadataFields == nil {
		o.request.MetadataFields = make(map[string]string)
	}
	o.request.MetadataFields[key] = value
}
func (o *ReadyOptions) SetHasMetadataKey(value string) { o.request.HasMetadataKey = value }
func (o *ReadyOptions) SetSort(value string)           { o.request.Sort = value }
func (o *ReadyOptions) SetLimit(value int)             { o.request.Limit = &value }
func (o *ReadyOptions) SetOffset(value int)            { o.request.Offset = value }
func (o *ReadyOptions) EnableBrief()                   { o.request.Brief = true }
func (o *ReadyOptions) SetMaxRows(value int, source string) {
	o.maxRows = value
	o.maxRowsSource = source
}

// ReadyOutcome preserves truncation and cap failures without leaking native errors.
type ReadyOutcome struct {
	page             *IssueListPage
	total            string
	truncated        bool
	hasOpenIssues    bool
	message          string
	rowLimitExceeded bool
	found            int
	source           string
	cap              int
}

func (o ReadyOutcome) Failed() bool           { return o.message != "" }
func (o ReadyOutcome) Message() string        { return o.message }
func (o ReadyOutcome) RowLimitExceeded() bool { return o.rowLimitExceeded }
func (o ReadyOutcome) Found() int             { return o.found }
func (o ReadyOutcome) Source() string         { return o.source }
func (o ReadyOutcome) Cap() int               { return o.cap }
func (o ReadyOutcome) Total() string          { return o.total }
func (o ReadyOutcome) Truncated() bool        { return o.truncated }
func (o ReadyOutcome) HasOpenIssues() bool    { return o.hasOpenIssues }
func (o ReadyOutcome) Page() *IssueListPage {
	if o.page == nil {
		return &IssueListPage{}
	}
	return o.page
}

func readyFailure(err error) *ReadyOutcome {
	var capErr *storageissueops.ErrTooManyRows
	if errors.As(err, &capErr) {
		return &ReadyOutcome{rowLimitExceeded: true, found: capErr.Found, source: capErr.Source, cap: capErr.Cap}
	}
	return &ReadyOutcome{message: err.Error()}
}

func projectReadyPage(items []*types.IssueWithCounts, hasMore bool) (*IssueListPage, error) {
	projected := make([]IssueListItem, 0, len(items))
	for _, item := range items {
		row, err := projectIssueListItem(item)
		if err != nil {
			return nil, err
		}
		projected = append(projected, row)
	}
	return &IssueListPage{items: projected, hasMore: hasMore}, nil
}

func readyRoleCount(ctx context.Context, counter publicops.ReadyCounter, request publicops.ReadyRequest) string {
	request.Limit = nil
	request.Offset = 0
	count, err := counter.CountReady(ctx, request)
	if err != nil {
		return ""
	}
	return strconv.FormatInt(count.Total, 10)
}

func readyHasOpenIssues(ctx context.Context, reporter publicops.StatsReporter) bool {
	stats, err := reporter.Stats(ctx, publicops.StatsRequest{SkipBlocked: true})
	return err == nil && (stats.Summary.OpenIssues > 0 || stats.Summary.InProgressIssues > 0)
}

// ReadReadyOutcome uses the ordinary strict read-only store. Its ready query
// suppresses advisory defer waking because the store was opened read-only.
func ReadReadyOutcome(beadsDir string, options *ReadyOptions, global bool) *ReadyOutcome {
	ctx := context.Background()
	if options == nil {
		options = NewReadyOptions()
	}
	store, _, _, err := openStore(ctx, beadsDir, global)
	if err != nil {
		return readyFailure(err)
	}
	request := options.request
	if request.Offset < 0 {
		request.Offset = 0
	}
	filter, err := workapi.BuildReadyFilter(request)
	if err != nil {
		return readyFailure(errors.Join(err, store.Close()))
	}
	filter.MaxRows = options.maxRows
	filter.MaxRowsSource = options.maxRowsSource
	items, err := store.GetReadyWorkWithCounts(ctx, filter)
	if err != nil {
		return readyFailure(errors.Join(err, store.Close()))
	}

	total := ""
	truncated := false
	if filter.Limit > 0 && len(items) == filter.Limit {
		if counter, countErr := store.ReadyCounter(); countErr == nil {
			total = readyRoleCount(ctx, counter, request)
			if total != "" {
				if parsed, parseErr := strconv.ParseInt(total, 10, 64); parseErr == nil {
					truncated = parsed > int64(len(items))
				}
			}
		}
	}
	page, err := projectReadyPage(items, truncated)
	if err != nil {
		return readyFailure(errors.Join(err, store.Close()))
	}
	hasOpen := false
	if len(items) == 0 {
		if reporter, reporterErr := store.StatsReporter(); reporterErr == nil {
			hasOpen = readyHasOpenIssues(ctx, reporter)
		}
	}
	if closeErr := store.Close(); closeErr != nil {
		return readyFailure(closeErr)
	}
	return &ReadyOutcome{page: page, total: total, truncated: truncated, hasOpenIssues: hasOpen}
}
