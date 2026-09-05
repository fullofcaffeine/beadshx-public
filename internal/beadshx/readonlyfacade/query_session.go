package readonlyfacade

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/steveyegge/beads/internal/proxiedworkspace"
	"github.com/steveyegge/beads/internal/storage/uow"
	"github.com/steveyegge/beads/internal/types"
	publicops "github.com/steveyegge/beads/issueops"
)

// QuerySession is one command-scoped, strict read attachment. It keeps the
// provider private while exposing copied values to generated Haxe code.
type QuerySession struct {
	mu         sync.Mutex
	provider   uow.UnitOfWorkProvider
	reader     publicops.Reader
	edgeReader publicops.EdgeReader
	annotator  publicops.BlockingAnnotator
	route      string
	closeFn    func() error
	closed     bool
}

// OpenDirectQuerySession opens one read-only direct store and exposes its
// exported issue-reader role. Haxe owns requests and query semantics; this
// constructor owns only native storage selection and lifetime.
func OpenDirectQuerySession(beadsDir string, global bool) (*QuerySession, error) {
	store, _, _, err := openStore(context.Background(), beadsDir, global)
	if err != nil {
		return nil, err
	}
	closeOnError := func(openErr error) (*QuerySession, error) {
		return nil, errors.Join(openErr, store.Close())
	}
	reader, err := store.IssueReader()
	if err != nil {
		return closeOnError(err)
	}
	edgeReader, err := store.EdgeReader()
	if err != nil {
		return closeOnError(err)
	}
	annotator, err := store.BlockingAnnotator()
	if err != nil {
		return closeOnError(err)
	}
	return &QuerySession{
		reader:     reader,
		edgeReader: edgeReader,
		annotator:  annotator,
		route:      "direct",
		closeFn:    store.Close,
	}, nil
}

// OpenProxiedQuerySession attaches to an already-running proxied workspace.
// It never starts or repairs a proxy and never enables write-side maintenance.
func OpenProxiedQuerySession(beadsDir, databaseOverride string) (*QuerySession, error) {
	ctx := context.Background()
	provider, err := proxiedworkspace.AttachForInspection(ctx, beadsDir, databaseOverride)
	if err != nil {
		return nil, err
	}
	closeOnError := func(openErr error) (*QuerySession, error) {
		return nil, errors.Join(openErr, provider.Close(context.Background()))
	}

	source, ok := provider.(uow.InspectionIssueReaderSource)
	if !ok {
		return closeOnError(fmt.Errorf("proxied provider %T does not offer the inspection query surface", provider))
	}
	reader, err := source.InspectionIssueReader()
	if err != nil {
		return closeOnError(err)
	}
	edgeSource, ok := provider.(uow.EdgeReaderSource)
	if !ok {
		return closeOnError(fmt.Errorf("proxied provider %T does not offer the edge-reader surface", provider))
	}
	edgeReader, err := edgeSource.EdgeReader()
	if err != nil {
		return closeOnError(err)
	}
	var annotator publicops.BlockingAnnotator
	if source, ok := provider.(uow.BlockingAnnotatorSource); ok {
		annotator, _ = source.BlockingAnnotator()
	}
	return &QuerySession{
		provider:   provider,
		reader:     reader,
		edgeReader: edgeReader,
		annotator:  annotator,
		route:      "proxied",
		closeFn: func() error {
			return provider.Close(context.Background())
		},
	}, nil
}

// Route returns the closed native route used by this session.
func (s *QuerySession) Route() string { return s.route }

// Close releases database resources once. The already-running proxy is not
// owned by this session and remains alive.
func (s *QuerySession) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return nil
	}
	s.closed = true
	if s.closeFn == nil {
		return nil
	}
	return s.closeFn()
}

// Reader returns the exported Beads query role while this session is active.
// Callers use that role directly through precise Haxe externs.
func (s *QuerySession) Reader() (publicops.Reader, error) {
	reader, _, err := s.activeReader()
	return reader, err
}

// EdgeReader returns the exported raw-edge role while this session is active.
// Haxe owns request batching, filters, missing-anchor policy, and rendering.
func (s *QuerySession) EdgeReader() (publicops.EdgeReader, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return nil, errors.New("query session is closed")
	}
	if s.edgeReader == nil {
		return nil, errors.New("query session has no edge reader")
	}
	return s.edgeReader, nil
}

// CloseResult is the value/error shape consumed by the generated Haxe adapter.
func (s *QuerySession) CloseResult() (bool, error) {
	return true, s.Close()
}

func (s *QuerySession) activeReader() (publicops.Reader, publicops.BlockingAnnotator, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return nil, nil, errors.New("query session is closed")
	}
	return s.reader, s.annotator, nil
}

// ReadIssueListOutcome reads one list page through the strict session.
func (s *QuerySession) ReadIssueListOutcome(options *IssueListOptions) *IssueListOutcome {
	reader, annotator, err := s.activeReader()
	if err != nil {
		return issueListOutcome(nil, err)
	}
	page, err := readIssueListWithReader(context.Background(), reader, annotator, options)
	return issueListOutcome(page, err)
}

// ReadIssueListFormatOutcome reads and formats one list page through the
// strict session.
func (s *QuerySession) ReadIssueListFormatOutcome(options *IssueListOptions, format string) *IssueListFormatOutcome {
	reader, _, err := s.activeReader()
	if err != nil {
		return issueListFormatOutcome(nil, format, err)
	}
	if options == nil {
		options = NewIssueListOptions()
	}
	if options.validationErr != nil {
		return issueListFormatOutcome(nil, format, options.validationErr)
	}
	page, err := reader.List(context.Background(), options.request)
	if err != nil {
		return issueListFormatOutcome(nil, format, err)
	}
	return issueListFormatOutcome(page.Items, format, nil)
}

// ReadIssueSummary reads one exact issue through the command-scoped reader.
func (s *QuerySession) ReadIssueSummary(id string) (*IssueLookup, error) {
	reader, _, err := s.activeReader()
	if err != nil {
		return nil, err
	}
	return readIssueSummaryWithReader(context.Background(), reader, id)
}

// ReadIssueDetails reads one exact detail view through the command-scoped reader.
func (s *QuerySession) ReadIssueDetails(id string, options *IssueDetailsOptions) (*IssueDetailsLookup, error) {
	reader, _, err := s.activeReader()
	if err != nil {
		return nil, err
	}
	return readIssueDetailsWithReader(context.Background(), reader, id, options)
}

// ReadIssueDependents returns copied incoming edges through the shared detail role.
func (s *QuerySession) ReadIssueDependents(id string) (*IssueDependencyRows, error) {
	reader, _, err := s.activeReader()
	if err != nil {
		return nil, err
	}
	details, err := reader.Get(context.Background(), publicops.GetRequest{ID: id, IncludeDependents: true})
	if err != nil {
		return nil, err
	}
	projected, err := projectIssueDependencies(details.Dependents)
	if err != nil {
		return nil, err
	}
	return &IssueDependencyRows{items: projected}, nil
}

// FindAssignedIssue returns the first store-ordered issue for an actor and status.
func (s *QuerySession) FindAssignedIssue(actor, status string) (string, error) {
	if _, _, err := s.activeReader(); err != nil {
		return "", err
	}
	issueStatus := types.Status(status)
	return uow.RunTxRead(context.Background(), s.provider, func(ctx context.Context, uw uow.UnitOfWork) (string, error) {
		page, err := uw.IssueUseCase().SearchIssues(ctx, "", types.IssueFilter{Status: &issueStatus, Assignee: &actor})
		if err != nil || len(page.Items) == 0 {
			return "", err
		}
		return page.Items[0].ID, nil
	})
}

// SearchIssueIDs returns resolver candidates through one fresh read transaction.
func (s *QuerySession) SearchIssueIDs(query string) (*IssueIDs, error) {
	if _, _, err := s.activeReader(); err != nil {
		return nil, err
	}
	ids, err := uow.RunTxRead(context.Background(), s.provider, func(ctx context.Context, uw uow.UnitOfWork) ([]string, error) {
		return uw.IssueUseCase().SearchIssueIDs(ctx, query, types.IssueFilter{})
	})
	if err != nil {
		return nil, err
	}
	return &IssueIDs{ids: ids}, nil
}

// ReadCountOutcome asks the provider's existing counter role without opening
// another provider or exposing storage objects to Haxe.
func (s *QuerySession) ReadCountOutcome(options *CountOptions, group string) *CountOutcome {
	if _, _, err := s.activeReader(); err != nil {
		return countOutcome(publicops.CountResult{}, publicops.CountByGroupResult{}, group, err)
	}
	source, ok := s.provider.(uow.CounterSource)
	if !ok {
		return countOutcome(publicops.CountResult{}, publicops.CountByGroupResult{}, group,
			fmt.Errorf("proxied provider %T does not offer the count role", s.provider))
	}
	counter, err := source.Counter()
	if err != nil {
		return countOutcome(publicops.CountResult{}, publicops.CountByGroupResult{}, group, err)
	}
	return readCountOutcome(context.Background(), counter, options, group)
}

// ReadReadyOutcome asks the inspection reader for one page, then uses the
// provider's ready-counter and stats roles only when presentation needs them.
func (s *QuerySession) ReadReadyOutcome(options *ReadyOptions) *ReadyOutcome {
	reader, _, err := s.activeReader()
	if err != nil {
		return readyFailure(err)
	}
	if options == nil {
		options = NewReadyOptions()
	}
	if options.maxRows > 0 {
		return readyFailure(fmt.Errorf("--max-rows is not supported under --proxied-server"))
	}
	if options.request.Offset < 0 {
		return readyFailure(errors.New("--offset must be >= 0"))
	}
	page, err := reader.Ready(context.Background(), options.request)
	if err != nil {
		return readyFailure(err)
	}
	projected, err := projectReadyPage(page.Items, page.HasMore)
	if err != nil {
		return readyFailure(err)
	}
	total := ""
	if page.HasMore {
		if source, ok := s.provider.(uow.ReadyCounterSource); ok {
			if counter, counterErr := source.ReadyCounter(); counterErr == nil {
				total = readyRoleCount(context.Background(), counter, options.request)
			}
		}
	}
	hasOpen := false
	if len(page.Items) == 0 {
		if source, ok := s.provider.(uow.StatsReporterSource); ok {
			if reporter, reporterErr := source.StatsReporter(); reporterErr == nil {
				hasOpen = readyHasOpenIssues(context.Background(), reporter)
			}
		}
	}
	return &ReadyOutcome{page: projected, total: total, truncated: page.HasMore, hasOpenIssues: hasOpen}
}

func readIssueListWithReader(ctx context.Context, reader publicops.Reader, annotator publicops.BlockingAnnotator, options *IssueListOptions) (*IssueListPage, error) {
	if options == nil {
		options = NewIssueListOptions()
	}
	if options.validationErr != nil {
		return nil, options.validationErr
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
	if options.blockingAnnotations && annotator != nil {
		ids := make([]string, len(items))
		for index := range items {
			ids[index] = items[index].id
		}
		annotations, annotationErr := annotator.AnnotateBlocking(ctx, publicops.BlockingRequest{IDs: ids})
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
	return &IssueListPage{items: items, hasMore: page.HasMore}, nil
}
