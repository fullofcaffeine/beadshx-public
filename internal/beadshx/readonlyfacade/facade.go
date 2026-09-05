// Package readonlyfacade exposes the smallest typed native surface needed by
// the Haxe-authored read-only commands. It owns storage selection and lifetime;
// command policy, JSON, and human output remain in Haxe.
package readonlyfacade

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/steveyegge/beads/internal/config"
	"github.com/steveyegge/beads/internal/configfile"
	"github.com/steveyegge/beads/internal/doltserver"
	"github.com/steveyegge/beads/internal/storage"
	"github.com/steveyegge/beads/internal/storage/dolt"
	storageissueops "github.com/steveyegge/beads/internal/storage/issueops"
	"github.com/steveyegge/beads/internal/timeparsing"
	"github.com/steveyegge/beads/internal/types"
	"github.com/steveyegge/beads/internal/workapi"
	"github.com/steveyegge/beads/issueops"
)

// Info is a concrete database-information snapshot.
type Info struct {
	databasePath  string
	mode          string
	issueCount    int
	config        []configEntry
	schemaVersion string
	issuePrefix   string
	sampleIDs     []string
}

type configEntry struct {
	key   string
	value string
}

type readonlyStore interface {
	Close() error
	SearchIssues(context.Context, string, types.IssueFilter) ([]*types.Issue, error)
	SearchIssueIDs(context.Context, string, types.IssueFilter) ([]string, error)
	SearchIssuesWithCounts(context.Context, string, types.IssueFilter) ([]*types.IssueWithCounts, error)
	GetReadyWorkWithCounts(context.Context, types.WorkFilter) ([]*types.IssueWithCounts, error)
	GetStaleIssues(context.Context, types.StaleFilter) ([]*types.Issue, error)
	GetCustomStatusesDetailed(context.Context) ([]types.CustomStatus, error)
	GetAllConfig(context.Context) (map[string]string, error)
	GetLocalMetadata(context.Context, string) (string, error)
	GetConfig(context.Context, string) (string, error)
	Counter() (issueops.Counter, error)
	ReadyCounter() (issueops.ReadyCounter, error)
	StatsReporter() (issueops.StatsReporter, error)
	IssueReader() (issueops.Reader, error)
	EdgeReader() (issueops.EdgeReader, error)
	BlockingAnnotator() (issueops.BlockingAnnotator, error)
	GetDependentsWithMetadata(context.Context, string) ([]*types.IssueWithDependencyMetadata, error)
}

// IssueIDs is a narrow list projection for Haxe-owned ID resolution.
type IssueIDs struct {
	ids []string
}

func (v IssueIDs) Count() int { return len(v.ids) }

func (v IssueIDs) ID(index int) string {
	if index < 0 || index >= len(v.ids) {
		return ""
	}
	return v.ids[index]
}

func (v Info) DatabasePath() string { return v.databasePath }
func (v Info) Mode() string         { return v.mode }
func (v Info) IssueCount() int      { return v.issueCount }
func (v Info) ConfigCount() int     { return len(v.config) }

func (v Info) ConfigKey(index int) string {
	if index < 0 || index >= len(v.config) {
		return ""
	}
	return v.config[index].key
}

func (v Info) ConfigValue(index int) string {
	if index < 0 || index >= len(v.config) {
		return ""
	}
	return v.config[index].value
}

func (v Info) SchemaVersion() string { return v.schemaVersion }
func (v Info) IssuePrefix() string   { return v.issuePrefix }
func (v Info) SampleCount() int      { return len(v.sampleIDs) }

func (v Info) SampleID(index int) string {
	if index < 0 || index >= len(v.sampleIDs) {
		return ""
	}
	return v.sampleIDs[index]
}

// Ping is a successful connectivity timing snapshot.
type Ping struct {
	resolveMS int
	storeMS   int
	queryMS   int
	totalMS   int
}

func (v Ping) ResolveMS() int { return v.resolveMS }
func (v Ping) StoreMS() int   { return v.storeMS }
func (v Ping) QueryMS() int   { return v.queryMS }
func (v Ping) TotalMS() int   { return v.totalMS }

// Status is a concrete summary with explicit availability for skipped counts.
type Status struct {
	totalIssues             int
	openIssues              int
	inProgressIssues        int
	closedIssues            int
	blockedIssues           int
	blockedAvailable        bool
	deferredIssues          int
	readyIssues             int
	readyAvailable          bool
	pinnedIssues            int
	epicsEligibleForClosure int
	averageLeadTime         float64
}

func (v Status) TotalIssues() int             { return v.totalIssues }
func (v Status) OpenIssues() int              { return v.openIssues }
func (v Status) InProgressIssues() int        { return v.inProgressIssues }
func (v Status) ClosedIssues() int            { return v.closedIssues }
func (v Status) BlockedIssues() int           { return v.blockedIssues }
func (v Status) BlockedAvailable() bool       { return v.blockedAvailable }
func (v Status) DeferredIssues() int          { return v.deferredIssues }
func (v Status) ReadyIssues() int             { return v.readyIssues }
func (v Status) ReadyAvailable() bool         { return v.readyAvailable }
func (v Status) PinnedIssues() int            { return v.pinnedIssues }
func (v Status) EpicsEligibleForClosure() int { return v.epicsEligibleForClosure }
func (v Status) AverageLeadTime() float64     { return v.averageLeadTime }

// IssueSummary is the small typed projection needed by show --short.
type IssueSummary struct {
	id        string
	title     string
	status    string
	priority  int
	issueType string
}

func (v IssueSummary) ID() string        { return v.id }
func (v IssueSummary) Title() string     { return v.title }
func (v IssueSummary) Status() string    { return v.status }
func (v IssueSummary) Priority() int     { return v.priority }
func (v IssueSummary) IssueType() string { return v.issueType }

// IssueLookup keeps a missing issue distinct from a store failure.
type IssueLookup struct {
	found   bool
	summary IssueSummary
}

// IssueListItem is one copied row from the shared issue-reader list role.
type IssueListItem struct {
	IssueRecord
	sender          string
	labels          []string
	dependencies    []IssueListDependency
	dependencyCount int
	dependentCount  int
	commentCount    int
	parent          string
	blockedBy       []string
	blocks          []string
	blockingParent  string
}

func (v *IssueListItem) Record() *IssueRecord { return &v.IssueRecord }
func (v IssueListItem) Sender() string        { return v.sender }
func (v IssueListItem) LabelCount() int       { return len(v.labels) }
func (v IssueListItem) Label(index int) string {
	if index < 0 || index >= len(v.labels) {
		return ""
	}
	return v.labels[index]
}
func (v IssueListItem) DependencyLength() int { return len(v.dependencies) }
func (v IssueListItem) Dependency(index int) *IssueListDependency {
	if index < 0 || index >= len(v.dependencies) {
		return &IssueListDependency{}
	}
	return &v.dependencies[index]
}
func (v IssueListItem) DependencyCount() int { return v.dependencyCount }
func (v IssueListItem) DependentCount() int  { return v.dependentCount }
func (v IssueListItem) CommentCount() int    { return v.commentCount }
func (v IssueListItem) Parent() string       { return v.parent }
func (v IssueListItem) BlockedByCount() int  { return len(v.blockedBy) }
func (v IssueListItem) BlockedBy(index int) string {
	if index < 0 || index >= len(v.blockedBy) {
		return ""
	}
	return v.blockedBy[index]
}
func (v IssueListItem) BlocksCount() int { return len(v.blocks) }
func (v IssueListItem) Blocks(index int) string {
	if index < 0 || index >= len(v.blocks) {
		return ""
	}
	return v.blocks[index]
}
func (v IssueListItem) BlockingParent() string { return v.blockingParent }

// IssueListPage preserves the issue-reader order and truncation decision.
type IssueListPage struct {
	items   []IssueListItem
	hasMore bool
}

// ListTimeParseOutcome returns one validated canonical CLI time expression.
type ListTimeParseOutcome struct {
	value   string
	message string
}

func (v ListTimeParseOutcome) Failed() bool    { return v.message != "" }
func (v ListTimeParseOutcome) Message() string { return v.message }
func (v ListTimeParseOutcome) Value() string   { return v.value }

// ParseListTime applies the pinned CLI's relative and absolute time grammar.
func ParseListTime(value string) *ListTimeParseOutcome {
	parsed, err := timeparsing.ParseRelativeTime(value, time.Now())
	if err != nil {
		return &ListTimeParseOutcome{message: err.Error()}
	}
	return &ListTimeParseOutcome{value: parsed.Format(time.RFC3339Nano)}
}

// IssueListOutcome preserves the max-row circuit breaker as a distinct result.
type IssueListOutcome struct {
	page             *IssueListPage
	message          string
	rowLimitExceeded bool
	found            int
	source           string
	cap              int
}

func (v IssueListOutcome) Failed() bool           { return v.message != "" }
func (v IssueListOutcome) Message() string        { return v.message }
func (v IssueListOutcome) RowLimitExceeded() bool { return v.rowLimitExceeded }
func (v IssueListOutcome) Found() int             { return v.found }
func (v IssueListOutcome) Source() string         { return v.source }
func (v IssueListOutcome) Cap() int               { return v.cap }
func (v IssueListOutcome) Page() *IssueListPage {
	if v.page == nil {
		return &IssueListPage{}
	}
	return v.page
}

func issueListOutcome(page *IssueListPage, err error) *IssueListOutcome {
	if err == nil {
		return &IssueListOutcome{page: page}
	}
	var capErr *storageissueops.ErrTooManyRows
	if errors.As(err, &capErr) {
		return &IssueListOutcome{
			rowLimitExceeded: true,
			found:            capErr.Found,
			source:           capErr.Source,
			cap:              capErr.Cap,
		}
	}
	return &IssueListOutcome{message: err.Error()}
}

// IssueListOptions is the native projection of the Haxe-owned list request.
type IssueListOptions struct {
	request             issueops.ListRequest
	blockingAnnotations bool
	validationErr       error
}

func NewIssueListOptions() *IssueListOptions            { return &IssueListOptions{} }
func (v *IssueListOptions) SetStatus(value string)      { v.request.Status = value }
func (v *IssueListOptions) SetIssueType(value string)   { v.request.IssueType = value }
func (v *IssueListOptions) SetAssignee(value string)    { v.request.Assignee = value }
func (v *IssueListOptions) SetTitleSearch(value string) { v.request.TitleSearch = value }
func (v *IssueListOptions) SetSpecPrefix(value string)  { v.request.SpecPrefix = value }
func (v *IssueListOptions) SetIDFilter(value string)    { v.request.IDFilter = value }
func (v *IssueListOptions) AddLabel(value string)       { v.request.Labels = append(v.request.Labels, value) }
func (v *IssueListOptions) AddLabelAny(value string) {
	v.request.LabelsAny = append(v.request.LabelsAny, value)
}
func (v *IssueListOptions) AddExcludeLabel(value string) {
	v.request.ExcludeLabels = append(v.request.ExcludeLabels, value)
}
func (v *IssueListOptions) SetLabelPattern(value string) { v.request.LabelPattern = value }
func (v *IssueListOptions) SetLabelRegex(value string)   { v.request.LabelRegex = value }
func (v *IssueListOptions) SetTitleContains(value string) {
	v.request.TitleContains = value
}
func (v *IssueListOptions) SetDescriptionContains(value string) {
	v.request.DescContains = value
}
func (v *IssueListOptions) SetNotesContains(value string) {
	v.request.NotesContains = value
}
func (v *IssueListOptions) SetExternalContains(value string) {
	v.request.ExternalContains = value
}
func (v *IssueListOptions) SetExternalRef(value string) { v.request.ExternalRef = value }
func (v *IssueListOptions) setCanonicalTime(value string, target **time.Time) {
	if v.validationErr != nil {
		return
	}
	parsed, err := time.Parse(time.RFC3339Nano, value)
	if err != nil {
		v.validationErr = fmt.Errorf("invalid canonical list timestamp: %w", err)
		return
	}
	*target = &parsed
}
func (v *IssueListOptions) SetCreatedAfter(value string) {
	v.setCanonicalTime(value, &v.request.CreatedAfter)
}
func (v *IssueListOptions) SetCreatedBefore(value string) {
	v.setCanonicalTime(value, &v.request.CreatedBefore)
}
func (v *IssueListOptions) SetUpdatedAfter(value string) {
	v.setCanonicalTime(value, &v.request.UpdatedAfter)
}
func (v *IssueListOptions) SetUpdatedBefore(value string) {
	v.setCanonicalTime(value, &v.request.UpdatedBefore)
}
func (v *IssueListOptions) SetClosedAfter(value string) {
	v.setCanonicalTime(value, &v.request.ClosedAfter)
}
func (v *IssueListOptions) SetClosedBefore(value string) {
	v.setCanonicalTime(value, &v.request.ClosedBefore)
}
func (v *IssueListOptions) SetDeferAfter(value string) {
	v.setCanonicalTime(value, &v.request.DeferAfter)
}
func (v *IssueListOptions) SetDeferBefore(value string) {
	v.setCanonicalTime(value, &v.request.DeferBefore)
}
func (v *IssueListOptions) SetDueAfter(value string) {
	v.setCanonicalTime(value, &v.request.DueAfter)
}
func (v *IssueListOptions) SetDueBefore(value string) {
	v.setCanonicalTime(value, &v.request.DueBefore)
}
func (v *IssueListOptions) SetPriority(value int)    { v.request.Priority = &value }
func (v *IssueListOptions) SetPriorityMin(value int) { v.request.PriorityMin = &value }
func (v *IssueListOptions) SetPriorityMax(value int) { v.request.PriorityMax = &value }
func (v *IssueListOptions) EnableAll()               { v.request.AllFlag = true }
func (v *IssueListOptions) EnableReady()             { v.request.ReadyFlag = true }
func (v *IssueListOptions) EnableNoAssignee()        { v.request.NoAssignee = true }
func (v *IssueListOptions) EnableNoLabels()          { v.request.NoLabels = true }
func (v *IssueListOptions) EnableEmptyDescription()  { v.request.EmptyDesc = true }
func (v *IssueListOptions) EnableSkipLabels()        { v.request.SkipLabels = true }
func (v *IssueListOptions) EnableBrief()             { v.request.Brief = true }
func (v *IssueListOptions) EnablePinned()            { v.request.PinnedFlag = true }
func (v *IssueListOptions) EnableNoPinned()          { v.request.NoPinnedFlag = true }
func (v *IssueListOptions) EnableTemplates()         { v.request.IncludeTemplates = true }
func (v *IssueListOptions) EnableGates()             { v.request.IncludeGates = true }
func (v *IssueListOptions) EnableInfra()             { v.request.IncludeInfra = true }
func (v *IssueListOptions) AddExcludeType(value string) {
	v.request.ExcludeTypes = append(v.request.ExcludeTypes, value)
}
func (v *IssueListOptions) SetParentID(value string) { v.request.ParentID = value }
func (v *IssueListOptions) EnableNoParent()          { v.request.NoParent = true }
func (v *IssueListOptions) SetMoleculeType(value string) {
	moleculeType := types.MolType(value)
	v.request.MolType = &moleculeType
}
func (v *IssueListOptions) SetWispType(value string) {
	wispType := types.WispType(value)
	v.request.WispType = &wispType
}
func (v *IssueListOptions) EnableDeferred() { v.request.DeferredFlag = true }
func (v *IssueListOptions) EnableOverdue()  { v.request.OverdueFlag = true }
func (v *IssueListOptions) AddMetadataField(key, value string) {
	if v.request.MetadataFields == nil {
		v.request.MetadataFields = make(map[string]string)
	}
	v.request.MetadataFields[key] = value
}
func (v *IssueListOptions) SetHasMetadataKey(value string) { v.request.HasMetadataKey = value }
func (v *IssueListOptions) SetSortBy(value string)         { v.request.SortBy = value }
func (v *IssueListOptions) EnableReverse()                 { v.request.Reverse = true }
func (v *IssueListOptions) SetLimit(value int)             { v.request.Limit = &value }
func (v *IssueListOptions) SetOffset(value int)            { v.request.Offset = value }
func (v *IssueListOptions) SetMaxRows(value int, source string) {
	v.request.MaxRows = value
	v.request.MaxRowsSource = source
}
func (v *IssueListOptions) EnableSkipCounts()          { v.request.SkipCounts = true }
func (v *IssueListOptions) EnableBlockingAnnotations() { v.blockingAnnotations = true }

func (v IssueListPage) Count() int    { return len(v.items) }
func (v IssueListPage) HasMore() bool { return v.hasMore }
func (v IssueListPage) Item(index int) *IssueListItem {
	if index < 0 || index >= len(v.items) {
		return &IssueListItem{}
	}
	return &v.items[index]
}

func (v IssueLookup) Found() bool            { return v.found }
func (v IssueLookup) Summary() *IssueSummary { return &v.summary }

// IssueListDependency is one copied raw edge embedded by list --json.
type IssueListDependency struct {
	id             string
	issueID        string
	dependsOnID    string
	dependencyType string
	createdAt      string
	createdBy      string
	metadata       string
	threadID       string
}

func (v IssueListDependency) ID() string             { return v.id }
func (v IssueListDependency) IssueID() string        { return v.issueID }
func (v IssueListDependency) DependsOnID() string    { return v.dependsOnID }
func (v IssueListDependency) DependencyType() string { return v.dependencyType }
func (v IssueListDependency) CreatedAt() string      { return v.createdAt }
func (v IssueListDependency) CreatedBy() string      { return v.createdBy }
func (v IssueListDependency) Metadata() string       { return v.metadata }
func (v IssueListDependency) ThreadID() string       { return v.threadID }

// IssueRecord is the shared typed projection used by top-level details and
// nested dependency rows. It exposes values instead of serialized JSON so the
// Haxe command layer remains the owner of the public output contract.
type IssueRecord struct {
	id                 string
	title              string
	description        string
	design             string
	acceptanceCriteria string
	notes              string
	specID             string
	status             string
	priority           int
	issueType          string
	isBlocked          bool
	assignee           string
	owner              string
	estimatedMinutes   *int
	createdAt          string
	createdBy          string
	updatedAt          string
	updatedAtMillis    float64
	startedAt          string
	closedAt           string
	closeReason        string
	closedBySession    string
	leaseExpiresAt     string
	heartbeatAt        string
	leaseGrantedNode   string
	dueAt              string
	deferUntil         string
	externalRef        string
	sourceSystem       string
	metadata           string
	wispType           string
	moleculeType       string
	compactionLevel    int
	compactedAt        string
	compactedAtCommit  string
	originalSize       int
	sender             string
	ephemeral          bool
	noHistory          bool
	storageClass       string
	pinned             bool
	template           bool
	bondedFrom         []IssueBondReference
	awaitType          string
	awaitID            string
	timeout            string
	timeoutNanos       string
	waiters            []string
	sourceFormula      string
	sourceLocation     string
	workType           string
	eventKind          string
	actor              string
	target             string
	payload            string
}

func (v IssueRecord) ID() string                 { return v.id }
func (v IssueRecord) Title() string              { return v.title }
func (v IssueRecord) Description() string        { return v.description }
func (v IssueRecord) Design() string             { return v.design }
func (v IssueRecord) AcceptanceCriteria() string { return v.acceptanceCriteria }
func (v IssueRecord) Notes() string              { return v.notes }
func (v IssueRecord) SpecID() string             { return v.specID }
func (v IssueRecord) Status() string             { return v.status }
func (v IssueRecord) Priority() int              { return v.priority }
func (v IssueRecord) IssueType() string          { return v.issueType }
func (v IssueRecord) IsBlocked() bool            { return v.isBlocked }
func (v IssueRecord) Assignee() string           { return v.assignee }
func (v IssueRecord) Owner() string              { return v.owner }
func (v IssueRecord) HasEstimatedMinutes() bool  { return v.estimatedMinutes != nil }
func (v IssueRecord) EstimatedMinutes() int {
	if v.estimatedMinutes == nil {
		return 0
	}
	return *v.estimatedMinutes
}
func (v IssueRecord) CreatedAt() string         { return v.createdAt }
func (v IssueRecord) CreatedBy() string         { return v.createdBy }
func (v IssueRecord) UpdatedAt() string         { return v.updatedAt }
func (v IssueRecord) UpdatedAtMillis() float64  { return v.updatedAtMillis }
func (v IssueRecord) StartedAt() string         { return v.startedAt }
func (v IssueRecord) ClosedAt() string          { return v.closedAt }
func (v IssueRecord) CloseReason() string       { return v.closeReason }
func (v IssueRecord) ClosedBySession() string   { return v.closedBySession }
func (v IssueRecord) LeaseExpiresAt() string    { return v.leaseExpiresAt }
func (v IssueRecord) HeartbeatAt() string       { return v.heartbeatAt }
func (v IssueRecord) LeaseGrantedNode() string  { return v.leaseGrantedNode }
func (v IssueRecord) DueAt() string             { return v.dueAt }
func (v IssueRecord) DeferUntil() string        { return v.deferUntil }
func (v IssueRecord) ExternalRef() string       { return v.externalRef }
func (v IssueRecord) SourceSystem() string      { return v.sourceSystem }
func (v IssueRecord) Metadata() string          { return v.metadata }
func (v IssueRecord) WispType() string          { return v.wispType }
func (v IssueRecord) MoleculeType() string      { return v.moleculeType }
func (v IssueRecord) CompactionLevel() int      { return v.compactionLevel }
func (v IssueRecord) CompactedAt() string       { return v.compactedAt }
func (v IssueRecord) CompactedAtCommit() string { return v.compactedAtCommit }
func (v IssueRecord) OriginalSize() int         { return v.originalSize }
func (v IssueRecord) Sender() string            { return v.sender }
func (v IssueRecord) Ephemeral() bool           { return v.ephemeral }
func (v IssueRecord) NoHistory() bool           { return v.noHistory }
func (v IssueRecord) StorageClass() string      { return v.storageClass }
func (v IssueRecord) Pinned() bool              { return v.pinned }
func (v IssueRecord) Template() bool            { return v.template }
func (v IssueRecord) BondedFromCount() int      { return len(v.bondedFrom) }
func (v IssueRecord) BondedFrom(index int) *IssueBondReference {
	if index < 0 || index >= len(v.bondedFrom) {
		return &IssueBondReference{}
	}
	return &v.bondedFrom[index]
}
func (v IssueRecord) AwaitType() string    { return v.awaitType }
func (v IssueRecord) AwaitID() string      { return v.awaitID }
func (v IssueRecord) Timeout() string      { return v.timeout }
func (v IssueRecord) TimeoutNanos() string { return v.timeoutNanos }
func (v IssueRecord) WaiterCount() int     { return len(v.waiters) }
func (v IssueRecord) Waiter(index int) string {
	if index < 0 || index >= len(v.waiters) {
		return ""
	}
	return v.waiters[index]
}
func (v IssueRecord) SourceFormula() string  { return v.sourceFormula }
func (v IssueRecord) SourceLocation() string { return v.sourceLocation }
func (v IssueRecord) WorkType() string       { return v.workType }
func (v IssueRecord) EventKind() string      { return v.eventKind }
func (v IssueRecord) Actor() string          { return v.actor }
func (v IssueRecord) Target() string         { return v.target }
func (v IssueRecord) Payload() string        { return v.payload }

// IssueBondReference is one copied compound-molecule lineage value.
type IssueBondReference struct {
	sourceID  string
	bondType  string
	bondPoint string
}

func (v IssueBondReference) SourceID() string  { return v.sourceID }
func (v IssueBondReference) BondType() string  { return v.bondType }
func (v IssueBondReference) BondPoint() string { return v.bondPoint }

// IssueDependency is one copied dependency record and its relationship type.
type IssueDependency struct {
	IssueRecord
	dependencyType string
}

func (v IssueDependency) DependencyType() string { return v.dependencyType }

// IssueDependencyRows owns copied full dependent records after the native
// store has closed. Haxe narrows these rows to children or references.
type IssueDependencyRows struct {
	items []IssueDependency
}

func (v IssueDependencyRows) Count() int { return len(v.items) }
func (v IssueDependencyRows) Item(index int) *IssueDependency {
	if index < 0 || index >= len(v.items) {
		return &IssueDependency{}
	}
	return &v.items[index]
}

// IssueComment is a copied comment body for --include-comments.
type IssueComment struct {
	id        string
	issueID   string
	author    string
	text      string
	createdAt string
}

func (v IssueComment) ID() string        { return v.id }
func (v IssueComment) IssueID() string   { return v.issueID }
func (v IssueComment) Author() string    { return v.author }
func (v IssueComment) Text() string      { return v.text }
func (v IssueComment) CreatedAt() string { return v.createdAt }

// IssueDetailsOptions is a semantic builder for optional detail expansions.
type IssueDetailsOptions struct {
	includeDependents bool
	includeComments   bool
	briefDependencies bool
}

func NewIssueDetailsOptions() *IssueDetailsOptions { return &IssueDetailsOptions{} }
func (v *IssueDetailsOptions) EnableDependents()   { v.includeDependents = true }
func (v *IssueDetailsOptions) EnableComments()     { v.includeComments = true }
func (v *IssueDetailsOptions) EnableBriefDeps()    { v.briefDependencies = true }

// IssueDetails adds the detail-only relation and count fields.
type IssueDetails struct {
	IssueRecord
	labels             []string
	dependencies       []IssueDependency
	dependents         []IssueDependency
	comments           []IssueComment
	parent             string
	dependentCount     int64
	dependencyCount    int64
	commentCount       int64
	commentsOmitted    bool
	epicTotalChildren  *int
	epicClosedChildren *int
	epicCloseable      *bool
	revision           string
}

func (v *IssueDetails) Record() *IssueRecord { return &v.IssueRecord }
func (v IssueDetails) LabelCount() int       { return len(v.labels) }
func (v IssueDetails) Label(index int) string {
	if index < 0 || index >= len(v.labels) {
		return ""
	}
	return v.labels[index]
}
func (v IssueDetails) DependencyRowCount() int { return len(v.dependencies) }
func (v IssueDetails) Dependency(index int) *IssueDependency {
	if index < 0 || index >= len(v.dependencies) {
		return &IssueDependency{}
	}
	return &v.dependencies[index]
}
func (v IssueDetails) DependentRowCount() int { return len(v.dependents) }
func (v IssueDetails) Dependent(index int) *IssueDependency {
	if index < 0 || index >= len(v.dependents) {
		return &IssueDependency{}
	}
	return &v.dependents[index]
}
func (v IssueDetails) CommentRowCount() int { return len(v.comments) }
func (v IssueDetails) Comment(index int) *IssueComment {
	if index < 0 || index >= len(v.comments) {
		return &IssueComment{}
	}
	return &v.comments[index]
}
func (v IssueDetails) Parent() string        { return v.parent }
func (v IssueDetails) DependentCount() int   { return int(v.dependentCount) }
func (v IssueDetails) DependencyCount() int  { return int(v.dependencyCount) }
func (v IssueDetails) CommentCount() int     { return int(v.commentCount) }
func (v IssueDetails) CommentsOmitted() bool { return v.commentsOmitted }
func (v IssueDetails) HasEpicProgress() bool {
	return v.epicTotalChildren != nil && v.epicClosedChildren != nil && v.epicCloseable != nil
}
func (v IssueDetails) EpicTotalChildren() int {
	if v.epicTotalChildren == nil {
		return 0
	}
	return *v.epicTotalChildren
}
func (v IssueDetails) EpicClosedChildren() int {
	if v.epicClosedChildren == nil {
		return 0
	}
	return *v.epicClosedChildren
}
func (v IssueDetails) EpicCloseable() bool {
	return v.epicCloseable != nil && *v.epicCloseable
}
func (v IssueDetails) Revision() string { return v.revision }

// IssueDetailsLookup keeps a missing row distinct from an open/read failure.
type IssueDetailsLookup struct {
	found   bool
	details IssueDetails
}

func (v IssueDetailsLookup) Found() bool            { return v.found }
func (v IssueDetailsLookup) Details() *IssueDetails { return &v.details }

func optionalCount(value *int64) int64 {
	if value == nil {
		return 0
	}
	return *value
}

func optionalTime(value *time.Time) string {
	if value == nil {
		return ""
	}
	return value.Format(time.RFC3339Nano)
}

func projectIssueRecord(issue types.Issue) (IssueRecord, error) {
	if len(issue.Metadata) > 0 && !json.Valid(issue.Metadata) {
		return IssueRecord{}, fmt.Errorf("issue %s contains invalid metadata JSON", issue.ID)
	}
	externalRef := ""
	if issue.ExternalRef != nil {
		externalRef = *issue.ExternalRef
	}
	var estimatedMinutes *int
	if issue.EstimatedMinutes != nil {
		value := *issue.EstimatedMinutes
		estimatedMinutes = &value
	}
	compactedAtCommit := ""
	if issue.CompactedAtCommit != nil {
		compactedAtCommit = *issue.CompactedAtCommit
	}
	bondedFrom := make([]IssueBondReference, len(issue.BondedFrom))
	for index, reference := range issue.BondedFrom {
		bondedFrom[index] = IssueBondReference{
			sourceID:  reference.SourceID,
			bondType:  reference.BondType,
			bondPoint: reference.BondPoint,
		}
	}
	timeout := ""
	if issue.Timeout > 0 {
		timeout = issue.Timeout.String()
	}
	return IssueRecord{
		id:                 issue.ID,
		title:              issue.Title,
		description:        issue.Description,
		design:             issue.Design,
		acceptanceCriteria: issue.AcceptanceCriteria,
		notes:              issue.Notes,
		specID:             issue.SpecID,
		status:             string(issue.Status),
		priority:           issue.Priority,
		issueType:          string(issue.IssueType),
		isBlocked:          issue.IsBlocked,
		assignee:           issue.Assignee,
		owner:              issue.Owner,
		estimatedMinutes:   estimatedMinutes,
		createdAt:          issue.CreatedAt.Format(time.RFC3339Nano),
		createdBy:          issue.CreatedBy,
		updatedAt:          issue.UpdatedAt.Format(time.RFC3339Nano),
		updatedAtMillis:    float64(issue.UpdatedAt.UnixMilli()),
		startedAt:          optionalTime(issue.StartedAt),
		closedAt:           optionalTime(issue.ClosedAt),
		closeReason:        issue.CloseReason,
		closedBySession:    issue.ClosedBySession,
		leaseExpiresAt:     optionalTime(issue.LeaseExpiresAt),
		heartbeatAt:        optionalTime(issue.HeartbeatAt),
		leaseGrantedNode:   issue.LeaseGrantedNode,
		dueAt:              optionalTime(issue.DueAt),
		deferUntil:         optionalTime(issue.DeferUntil),
		externalRef:        externalRef,
		sourceSystem:       issue.SourceSystem,
		metadata:           string(issue.Metadata),
		wispType:           string(issue.WispType),
		moleculeType:       string(issue.MolType),
		compactionLevel:    issue.CompactionLevel,
		compactedAt:        optionalTime(issue.CompactedAt),
		compactedAtCommit:  compactedAtCommit,
		originalSize:       issue.OriginalSize,
		sender:             issue.Sender,
		ephemeral:          issue.Ephemeral,
		noHistory:          issue.NoHistory,
		storageClass:       string(issue.StorageClass),
		pinned:             issue.Pinned,
		template:           issue.IsTemplate,
		bondedFrom:         bondedFrom,
		awaitType:          issue.AwaitType,
		awaitID:            issue.AwaitID,
		timeout:            timeout,
		timeoutNanos:       strconv.FormatInt(int64(issue.Timeout), 10),
		waiters:            append([]string(nil), issue.Waiters...),
		sourceFormula:      issue.SourceFormula,
		sourceLocation:     issue.SourceLocation,
		workType:           string(issue.WorkType),
		eventKind:          issue.EventKind,
		actor:              issue.Actor,
		target:             issue.Target,
		payload:            issue.Payload,
	}, nil
}

func projectIssueDependencies(items []*types.IssueWithDependencyMetadata) ([]IssueDependency, error) {
	projected := make([]IssueDependency, 0, len(items))
	for _, item := range items {
		record, err := projectIssueRecord(item.Issue)
		if err != nil {
			return nil, err
		}
		projected = append(projected, IssueDependency{
			IssueRecord:    record,
			dependencyType: string(item.DependencyType),
		})
	}
	return projected, nil
}

func projectIssueListItem(item *types.IssueWithCounts) (IssueListItem, error) {
	if item == nil || item.Issue == nil {
		return IssueListItem{}, errors.New("issue list contains an empty row")
	}
	record, err := projectIssueRecord(*item.Issue)
	if err != nil {
		return IssueListItem{}, err
	}
	parent := ""
	if item.Parent != nil {
		parent = *item.Parent
	}
	dependencies := make([]IssueListDependency, 0, len(item.Issue.Dependencies))
	for _, dependency := range item.Issue.Dependencies {
		if dependency == nil {
			return IssueListItem{}, errors.New("issue list contains an empty dependency edge")
		}
		dependencies = append(dependencies, IssueListDependency{
			id:             dependency.ID,
			issueID:        dependency.IssueID,
			dependsOnID:    dependency.DependsOnID,
			dependencyType: string(dependency.Type),
			createdAt:      dependency.CreatedAt.Format(time.RFC3339Nano),
			createdBy:      dependency.CreatedBy,
			metadata:       dependency.Metadata,
			threadID:       dependency.ThreadID,
		})
	}
	return IssueListItem{
		IssueRecord:     record,
		sender:          item.Issue.Sender,
		labels:          append([]string(nil), item.Labels...),
		dependencies:    dependencies,
		dependencyCount: item.DependencyCount,
		dependentCount:  item.DependentCount,
		commentCount:    item.CommentCount,
		parent:          parent,
	}, nil
}

// ReadIssueList reads the pinned default list page without mutating state. The
// shared reader role owns storage filtering and paging; Haxe owns presentation.
func ReadIssueList(beadsDir string, options *IssueListOptions, global bool) (result *IssueListPage, err error) {
	ctx := context.Background()
	if options == nil {
		options = NewIssueListOptions()
	}
	if options.validationErr != nil {
		return nil, options.validationErr
	}
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
	items := make([]IssueListItem, 0, len(page.Items))
	for _, item := range page.Items {
		projected, projectionErr := projectIssueListItem(item)
		if projectionErr != nil {
			return nil, projectionErr
		}
		items = append(items, projected)
	}
	if options.blockingAnnotations {
		annotator, annotationErr := store.BlockingAnnotator()
		if annotationErr == nil {
			ids := make([]string, len(items))
			for index := range items {
				ids[index] = items[index].id
			}
			annotations, annotationErr := annotator.AnnotateBlocking(ctx, issueops.BlockingRequest{IDs: ids})
			if annotationErr == nil {
				byID := make(map[string]int, len(items))
				for index := range items {
					byID[items[index].id] = index
				}
				for _, annotation := range annotations.Items {
					index, found := byID[annotation.ID]
					if !found {
						continue
					}
					items[index].blockedBy = append([]string(nil), annotation.BlockedBy...)
					items[index].blocks = append([]string(nil), annotation.Blocks...)
					items[index].blockingParent = annotation.Parent
				}
			}
		}
	}
	return &IssueListPage{items: items, hasMore: page.HasMore}, nil
}

// ReadIssueListOutcome classifies the defensive cap without string matching.
func ReadIssueListOutcome(beadsDir string, options *IssueListOptions, global bool) *IssueListOutcome {
	page, err := ReadIssueList(beadsDir, options, global)
	return issueListOutcome(page, err)
}

// ReadIssueSummary looks up one exact canonical ID without mutating state.
func ReadIssueSummary(beadsDir, id string, global bool) (lookup *IssueLookup, err error) {
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
	return readIssueSummaryWithReader(ctx, reader, id)
}

func readIssueSummaryWithReader(ctx context.Context, reader issueops.Reader, id string) (*IssueLookup, error) {
	details, err := reader.Get(ctx, issueops.GetRequest{ID: id})
	if errors.Is(err, storage.ErrNotFound) {
		return &IssueLookup{}, nil
	}
	if err != nil {
		return nil, err
	}
	return &IssueLookup{
		found: true,
		summary: IssueSummary{
			id:        details.ID,
			title:     details.Title,
			status:    string(details.Status),
			priority:  details.Priority,
			issueType: string(details.IssueType),
		},
	}, nil
}

// ReadIssueDetails reads one exact canonical ID into a typed projection.
func ReadIssueDetails(beadsDir, id string, options *IssueDetailsOptions, global bool) (lookup *IssueDetailsLookup, err error) {
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
	return readIssueDetailsWithReader(ctx, reader, id, options)
}

func readIssueDetailsWithReader(ctx context.Context, reader issueops.Reader, id string, options *IssueDetailsOptions) (*IssueDetailsLookup, error) {
	if options == nil {
		options = NewIssueDetailsOptions()
	}
	details, err := reader.Get(ctx, issueops.GetRequest{
		ID:                id,
		IncludeDependents: options.includeDependents,
		IncludeComments:   options.includeComments,
		BriefDeps:         options.briefDependencies,
	})
	if errors.Is(err, storage.ErrNotFound) {
		return &IssueDetailsLookup{}, nil
	}
	if err != nil {
		return nil, err
	}
	record, err := projectIssueRecord(details.Issue)
	if err != nil {
		return nil, err
	}
	parent := ""
	if details.Parent != nil {
		parent = *details.Parent
	}
	commentsOmitted := details.CommentsOmitted != nil && *details.CommentsOmitted
	dependencies, err := projectIssueDependencies(details.Dependencies)
	if err != nil {
		return nil, err
	}
	dependents, err := projectIssueDependencies(details.Dependents)
	if err != nil {
		return nil, err
	}
	comments := make([]IssueComment, 0, len(details.Comments))
	for _, comment := range details.Comments {
		comments = append(comments, IssueComment{
			id:        comment.ID,
			issueID:   comment.IssueID,
			author:    comment.Author,
			text:      comment.Text,
			createdAt: comment.CreatedAt.Format(time.RFC3339Nano),
		})
	}
	return &IssueDetailsLookup{
		found: true,
		details: IssueDetails{
			IssueRecord:        record,
			labels:             append([]string(nil), details.Labels...),
			dependencies:       dependencies,
			dependents:         dependents,
			comments:           comments,
			parent:             parent,
			dependentCount:     optionalCount(details.DependentCount),
			dependencyCount:    optionalCount(details.DependencyCount),
			commentCount:       optionalCount(details.CommentCount),
			commentsOmitted:    commentsOmitted,
			epicTotalChildren:  details.EpicTotalChildren,
			epicClosedChildren: details.EpicClosedChildren,
			epicCloseable:      details.EpicCloseable,
			revision:           strconv.FormatInt(details.Revision, 10),
		},
	}, nil
}

// ReadIssueDependents copies the store's complete dependent rows. It retains
// native storage mechanics while leaving relationship selection to Haxe.
func ReadIssueDependents(beadsDir, id string, global bool) (rows *IssueDependencyRows, err error) {
	ctx := context.Background()
	store, _, _, err := openStore(ctx, beadsDir, global)
	if err != nil {
		return nil, err
	}
	defer captureClose(store, &err)

	items, err := store.GetDependentsWithMetadata(ctx, id)
	if err != nil {
		return nil, err
	}
	projected, err := projectIssueDependencies(items)
	if err != nil {
		return nil, err
	}
	return &IssueDependencyRows{items: projected}, nil
}

// FindAssignedIssue returns the first store-ordered issue for one actor and status.
func FindAssignedIssue(beadsDir, actor, status string, global bool) (id string, err error) {
	ctx := context.Background()
	store, _, _, err := openStore(ctx, beadsDir, global)
	if err != nil {
		return "", err
	}
	defer captureClose(store, &err)

	issueStatus := types.Status(status)
	issues, err := store.SearchIssues(ctx, "", types.IssueFilter{Status: &issueStatus, Assignee: &actor})
	if err != nil || len(issues) == 0 {
		return "", err
	}
	return issues[0].ID, nil
}

// ReadLastTouched reads local runtime state without treating absence as failure.
func ReadLastTouched(beadsDir string) string {
	data, err := os.ReadFile(filepath.Join(beadsDir, "last-touched")) // #nosec G304 -- workspace path is already resolved
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

// SearchIssueIDs returns only candidate IDs matching a resolver query.
func SearchIssueIDs(beadsDir, query string, global bool) (result *IssueIDs, err error) {
	ctx := context.Background()
	store, _, _, err := openStore(ctx, beadsDir, global)
	if err != nil {
		return nil, err
	}
	defer captureClose(store, &err)

	ids, err := store.SearchIssueIDs(ctx, query, types.IssueFilter{})
	if err != nil {
		return nil, err
	}
	return &IssueIDs{ids: ids}, nil
}

// ReadLocalPrefix returns the stored issue prefix only when the workspace can
// be opened locally without starting or contacting a server.
func ReadLocalPrefix(beadsDir string) (prefix string, err error) {
	if err := initializeSelectedConfig(beadsDir); err != nil {
		return "", err
	}
	fileConfig, err := configfile.LoadForDiscovery(beadsDir)
	if err != nil {
		return "", err
	}
	if doltserver.IsSharedServerMode() || fileConfig != nil && (fileConfig.IsDoltServerMode() || fileConfig.IsDoltProxiedServerMode()) {
		return "", nil
	}
	ctx := context.Background()
	store, _, _, err := openStore(ctx, beadsDir, false)
	if err != nil {
		return "", err
	}
	defer captureClose(store, &err)
	return store.GetConfig(ctx, "issue_prefix")
}

// ValidateOpen proves that the selected read-only store can be opened without
// running a command query. Static info pages still pass through this lifecycle
// when --global is active, matching the upstream root pre-run contract.
func ValidateOpen(beadsDir string, global bool) (_ bool, err error) {
	store, _, _, err := openStore(context.Background(), beadsDir, global)
	if err != nil {
		return false, err
	}
	defer captureClose(store, &err)
	return true, nil
}

// ReadInfo returns one read-only database-information snapshot.
func ReadInfo(beadsDir string, includeSchema, global bool) (info *Info, err error) {
	ctx := context.Background()
	store, databasePath, mode, err := openStore(ctx, beadsDir, global)
	if err != nil {
		return nil, err
	}
	defer captureClose(store, &err)

	issues, err := store.SearchIssues(ctx, "", types.IssueFilter{})
	if err != nil {
		return nil, err
	}

	allConfig, err := store.GetAllConfig(ctx)
	if err != nil {
		return nil, err
	}
	filtered := workapi.FilterSettingsEnumeration(allConfig)
	keys := make([]string, 0, len(filtered))
	for key := range filtered {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	entries := make([]configEntry, 0, len(keys))
	for _, key := range keys {
		entries = append(entries, configEntry{key: key, value: filtered[key]})
	}

	info = &Info{
		databasePath: databasePath,
		mode:         mode,
		issueCount:   len(issues),
		config:       entries,
	}
	if includeSchema {
		info.schemaVersion, err = store.GetLocalMetadata(ctx, "bd_version")
		if err != nil {
			info.schemaVersion = "unknown"
		}
		info.issuePrefix, _ = store.GetConfig(ctx, "issue_prefix")
		limit := 3
		if len(issues) < limit {
			limit = len(issues)
		}
		info.sampleIDs = make([]string, 0, limit)
		for _, issue := range issues[:limit] {
			info.sampleIDs = append(info.sampleIDs, issue.ID)
		}
	}
	return info, nil
}

// CheckPing opens the store and runs the same count capability used by the
// native health check. Discovery time is measured by the Haxe workspace port,
// so ResolveMS is zero at this boundary.
func CheckPing(beadsDir string, global bool) (ping *Ping, err error) {
	start := time.Now()
	ctx := context.Background()
	store, _, _, err := openStore(ctx, beadsDir, global)
	if err != nil {
		return nil, err
	}
	defer captureClose(store, &err)
	storeMS := elapsedMS(start)

	counter, err := store.Counter()
	if err != nil {
		return nil, err
	}
	if _, err := counter.Count(ctx, issueops.CountRequest{}); err != nil {
		return nil, err
	}
	totalMS := elapsedMS(start)
	return &Ping{
		resolveMS: 0,
		storeMS:   storeMS,
		queryMS:   totalMS - storeMS,
		totalMS:   totalMS,
	}, nil
}

// ReadStatus returns workspace or assignee summary statistics.
func ReadStatus(beadsDir string, skipBlocked bool, assignee string, global bool) (snapshot *Status, err error) {
	ctx := context.Background()
	store, _, _, err := openStore(ctx, beadsDir, global)
	if err != nil {
		return nil, err
	}
	defer captureClose(store, &err)

	reporter, err := store.StatsReporter()
	if err != nil {
		return nil, err
	}
	var result issueops.StatsResult
	if assignee == "" {
		result, err = reporter.Stats(ctx, issueops.StatsRequest{SkipBlocked: skipBlocked})
	} else {
		result, err = reporter.AssigneeStats(ctx, issueops.AssigneeStatsRequest{Assignee: assignee})
	}
	if err != nil {
		return nil, err
	}

	stats := result.Summary
	status := Status{
		totalIssues:             stats.TotalIssues,
		openIssues:              stats.OpenIssues,
		inProgressIssues:        stats.InProgressIssues,
		closedIssues:            stats.ClosedIssues,
		deferredIssues:          stats.DeferredIssues,
		pinnedIssues:            stats.PinnedIssues,
		epicsEligibleForClosure: stats.EpicsEligibleForClosure,
		averageLeadTime:         stats.AverageLeadTime,
	}
	if stats.BlockedIssues != nil {
		status.blockedIssues = *stats.BlockedIssues
		status.blockedAvailable = true
	}
	if stats.ReadyIssues != nil {
		status.readyIssues = *stats.ReadyIssues
		status.readyAvailable = true
	}
	return &status, nil
}

func elapsedMS(start time.Time) int {
	return int(time.Since(start).Milliseconds())
}

func captureClose(store readonlyStore, operationError *error) {
	closeError := store.Close()
	if closeError != nil && *operationError == nil {
		*operationError = closeError
	}
}

func openStore(ctx context.Context, beadsDir string, global bool) (readonlyStore, string, string, error) {
	if err := initializeSelectedConfig(beadsDir); err != nil {
		return nil, "", "", fmt.Errorf("loading config: %w", err)
	}
	fileConfig, err := configfile.Load(beadsDir)
	if err != nil {
		return nil, "", "", fmt.Errorf("loading config: %w", err)
	}
	if fileConfig == nil {
		fileConfig = configfile.DefaultConfig()
	}
	if fileConfig.GetBackend() != configfile.BackendDolt {
		return nil, "", "", fmt.Errorf("configured storage backend %q cannot be opened as Dolt", fileConfig.GetBackend())
	}
	sharedServer := doltserver.IsSharedServerMode()
	if global && !sharedServer {
		return nil, "", "", globalModeError()
	}
	if fileConfig.IsDoltProxiedServerMode() {
		return nil, "", "", fmt.Errorf("strict readonly is unavailable for dolt proxied-server backend")
	}

	if fileConfig.IsDoltServerMode() || sharedServer {
		selected := ""
		if global {
			selected = doltserver.GlobalDatabaseName
		}
		store, err := dolt.NewFromConfigWithOptions(ctx, beadsDir, &dolt.Config{
			Database:         selected,
			ReadOnly:         true,
			DisableAutoStart: true,
		})
		if err != nil {
			return nil, "", "", fmt.Errorf("failed to open database: %w", err)
		}
		path, err := filepath.Abs(filepath.Join(beadsDir, "dolt"))
		if err != nil {
			path = filepath.Join(beadsDir, "dolt")
		}
		return store, path, "direct", nil
	}

	database := fileConfig.GetDoltDatabase()
	if database == "" {
		database = configfile.DefaultDoltDatabase
	}
	store, err := openEmbeddedStore(ctx, beadsDir, database, "main")
	if err != nil {
		return nil, "", "", err
	}
	path, err := filepath.Abs(filepath.Join(beadsDir, "embeddeddolt"))
	if err != nil {
		path = filepath.Join(beadsDir, "embeddeddolt")
	}
	return store, path, "direct", nil
}

func globalModeError() error {
	return fmt.Errorf("--global requires shared-server mode (set BEADS_DOLT_SHARED_SERVER=1 or dolt.shared-server: true in config.yaml)")
}

// initializeSelectedConfig gives config.yaml the same selected-workspace view
// as the native CLI, then restores the caller's environment. The CLI is
// synchronous; callers must not run this beside other environment mutations.
func initializeSelectedConfig(beadsDir string) error {
	previous, wasSet := os.LookupEnv("BEADS_DIR")
	if err := os.Setenv("BEADS_DIR", beadsDir); err != nil {
		return err
	}
	defer func() {
		if wasSet {
			_ = os.Setenv("BEADS_DIR", previous)
		} else {
			_ = os.Unsetenv("BEADS_DIR")
		}
	}()
	return config.Initialize()
}
