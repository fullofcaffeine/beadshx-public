package readonlyfacade

import (
	"context"
	"errors"
	"fmt"

	"github.com/steveyegge/beads/internal/storage/uow"
	"github.com/steveyegge/beads/internal/types"
)

// OrphanCandidate is the compact storage projection needed by Haxe-owned
// commit-reference detection.
type OrphanCandidate struct {
	id     string
	title  string
	status string
}

func (v OrphanCandidate) ID() string     { return v.id }
func (v OrphanCandidate) Title() string  { return v.title }
func (v OrphanCandidate) Status() string { return v.status }

// OrphanCandidates carries all still-active candidates and the stored prefix
// fallback without exposing a storage or transaction object.
type OrphanCandidates struct {
	prefix string
	items  []OrphanCandidate
}

func (v OrphanCandidates) Prefix() string { return v.prefix }
func (v OrphanCandidates) Count() int     { return len(v.items) }

func (v OrphanCandidates) Item(index int) *OrphanCandidate {
	if index < 0 || index >= len(v.items) {
		return &OrphanCandidate{}
	}
	return &v.items[index]
}

func orphanLabels(options *IssueListOptions) ([]string, []string, error) {
	if options == nil {
		return nil, nil, nil
	}
	if options.validationErr != nil {
		return nil, nil, options.validationErr
	}
	return append([]string(nil), options.request.Labels...), append([]string(nil), options.request.LabelsAny...), nil
}

func projectOrphanCandidates(openIssues, inProgressIssues []*types.Issue, prefix string) (*OrphanCandidates, error) {
	items := make([]OrphanCandidate, 0, len(openIssues)+len(inProgressIssues))
	for _, issue := range append(openIssues, inProgressIssues...) {
		if issue == nil {
			return nil, errors.New("orphan candidate query returned a nil issue")
		}
		items = append(items, OrphanCandidate{id: issue.ID, title: issue.Title, status: string(issue.Status)})
	}
	return &OrphanCandidates{prefix: prefix, items: items}, nil
}

// ReadOrphanCandidates copies the direct store facts needed for Haxe-owned
// orphan detection. Git history is deliberately outside this storage boundary.
func ReadOrphanCandidates(beadsDir string, options *IssueListOptions, global bool) (result *OrphanCandidates, err error) {
	labels, labelsAny, err := orphanLabels(options)
	if err != nil {
		return nil, err
	}
	ctx := context.Background()
	store, _, _, err := openStore(ctx, beadsDir, global)
	if err != nil {
		return nil, err
	}
	defer captureClose(store, &err)

	openStatus := types.StatusOpen
	openIssues, err := store.SearchIssues(ctx, "", types.IssueFilter{Status: &openStatus, Labels: labels, LabelsAny: labelsAny})
	if err != nil {
		return nil, fmt.Errorf("getting open issues: %w", err)
	}
	inProgressStatus := types.StatusInProgress
	inProgressIssues, err := store.SearchIssues(ctx, "", types.IssueFilter{Status: &inProgressStatus, Labels: labels, LabelsAny: labelsAny})
	if err != nil {
		return nil, fmt.Errorf("getting open issues: %w", err)
	}
	prefix, _ := store.GetConfig(ctx, "issue_prefix")
	return projectOrphanCandidates(openIssues, inProgressIssues, prefix)
}

// ReadOrphanCandidates copies the same facts through one fresh proxied read
// transaction without provisioning, lifecycle changes, or persistent writes.
func (s *QuerySession) ReadOrphanCandidates(options *IssueListOptions) (*OrphanCandidates, error) {
	if _, _, err := s.activeReader(); err != nil {
		return nil, err
	}
	labels, labelsAny, err := orphanLabels(options)
	if err != nil {
		return nil, err
	}
	return uow.RunTxRead(context.Background(), s.provider, func(ctx context.Context, unit uow.UnitOfWork) (*OrphanCandidates, error) {
		openStatus := types.StatusOpen
		openPage, err := unit.IssueUseCase().SearchIssues(ctx, "", types.IssueFilter{Status: &openStatus, Labels: labels, LabelsAny: labelsAny})
		if err != nil {
			return nil, fmt.Errorf("getting open issues: %w", err)
		}
		inProgressStatus := types.StatusInProgress
		inProgressPage, err := unit.IssueUseCase().SearchIssues(ctx, "", types.IssueFilter{
			Status: &inProgressStatus, Labels: labels, LabelsAny: labelsAny,
		})
		if err != nil {
			return nil, fmt.Errorf("getting open issues: %w", err)
		}
		prefix, _ := unit.ConfigUseCase().GetConfig(ctx, "issue_prefix")
		return projectOrphanCandidates(openPage.Items, inProgressPage.Items, prefix)
	})
}
