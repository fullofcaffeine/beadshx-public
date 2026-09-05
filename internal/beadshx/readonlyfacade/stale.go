package readonlyfacade

import (
	"context"
	"errors"

	"github.com/steveyegge/beads/internal/storage/uow"
	"github.com/steveyegge/beads/internal/types"
)

func staleFilter(days int, status string, limit int) types.StaleFilter {
	return types.StaleFilter{Days: days, Status: status, Limit: limit}
}

func projectStalePage(items []*types.Issue) (*IssueListPage, error) {
	projected := make([]IssueListItem, 0, len(items))
	for _, item := range items {
		if item == nil {
			return nil, errors.New("stale query returned a nil issue")
		}
		record, err := projectIssueRecord(*item)
		if err != nil {
			return nil, err
		}
		projected = append(projected, IssueListItem{IssueRecord: record})
	}
	return &IssueListPage{items: projected}, nil
}

// ReadStaleOutcome runs one direct stale query through a strict read-only store.
func ReadStaleOutcome(beadsDir string, days int, status string, limit int, global bool) *IssueListOutcome {
	ctx := context.Background()
	store, _, _, err := openStore(ctx, beadsDir, global)
	if err != nil {
		return issueListOutcome(nil, err)
	}
	items, err := store.GetStaleIssues(ctx, staleFilter(days, status, limit))
	if err != nil {
		return issueListOutcome(nil, errors.Join(err, store.Close()))
	}
	page, err := projectStalePage(items)
	if err != nil {
		return issueListOutcome(nil, errors.Join(err, store.Close()))
	}
	if closeErr := store.Close(); closeErr != nil {
		return issueListOutcome(nil, closeErr)
	}
	return issueListOutcome(page, nil)
}

// ReadStaleOutcome runs one proxied stale query in a fresh read transaction.
func (s *QuerySession) ReadStaleOutcome(days int, status string, limit int) *IssueListOutcome {
	if _, _, err := s.activeReader(); err != nil {
		return issueListOutcome(nil, err)
	}
	page, err := uow.RunTxRead(context.Background(), s.provider, func(ctx context.Context, unit uow.UnitOfWork) (*IssueListPage, error) {
		items, err := unit.IssueUseCase().GetStaleIssues(ctx, staleFilter(days, status, limit))
		if err != nil {
			return nil, err
		}
		return projectStalePage(items)
	})
	return issueListOutcome(page, err)
}
