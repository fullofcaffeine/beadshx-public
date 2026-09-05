package readonlyfacade

import (
	"context"
	"errors"

	"github.com/steveyegge/beads/internal/storage/uow"
	"github.com/steveyegge/beads/internal/types"
	"github.com/steveyegge/beads/internal/workapi"
)

func searchFilter(options *IssueListOptions, customStatuses []string) (types.IssueFilter, error) {
	if options == nil {
		options = NewIssueListOptions()
	}
	if options.validationErr != nil {
		return types.IssueFilter{}, options.validationErr
	}
	request := options.request
	filter := types.IssueFilter{Limit: 50}
	if request.Limit != nil {
		filter.Limit = *request.Limit
	}
	if request.Status != "" && request.Status != "all" {
		if err := workapi.ApplyStatusFilter(&filter, request.Status, customStatuses); err != nil {
			return types.IssueFilter{}, err
		}
	}
	if request.Assignee != "" {
		filter.Assignee = &request.Assignee
	}
	if request.IssueType != "" {
		issueType := types.IssueType(request.IssueType)
		filter.IssueType = &issueType
	}
	filter.Labels = request.Labels
	filter.LabelsAny = request.LabelsAny
	filter.DescriptionContains = request.DescContains
	filter.NotesContains = request.NotesContains
	filter.ExternalRefContains = request.ExternalContains
	filter.EmptyDescription = request.EmptyDesc
	filter.NoAssignee = request.NoAssignee
	filter.NoLabels = request.NoLabels
	filter.CreatedAfter = request.CreatedAfter
	filter.CreatedBefore = request.CreatedBefore
	filter.UpdatedAfter = request.UpdatedAfter
	filter.UpdatedBefore = request.UpdatedBefore
	filter.ClosedAfter = request.ClosedAfter
	filter.ClosedBefore = request.ClosedBefore
	filter.PriorityMin = request.PriorityMin
	filter.PriorityMax = request.PriorityMax
	filter.MetadataFields = request.MetadataFields
	filter.HasMetadataKey = request.HasMetadataKey
	return filter, nil
}

func projectSearchPage(items []*types.IssueWithCounts) (*IssueListPage, error) {
	projected := make([]IssueListItem, 0, len(items))
	for _, item := range items {
		row, err := projectIssueListItem(item)
		if err != nil {
			return nil, err
		}
		projected = append(projected, row)
	}
	return &IssueListPage{items: projected}, nil
}

func finishSearch(items []*types.IssueWithCounts, options *IssueListOptions) (*IssueListPage, error) {
	if options == nil {
		options = NewIssueListOptions()
	}
	workapi.SortIssuesWithCounts(items, options.request.SortBy, options.request.Reverse)
	return projectSearchPage(items)
}

func searchNeedsCustomStatuses(options *IssueListOptions) bool {
	return options != nil && options.request.Status != "" && options.request.Status != "all"
}

// ReadSearchOutcome runs one direct search through a strict read-only store.
func ReadSearchOutcome(beadsDir, query string, options *IssueListOptions, global bool) *IssueListOutcome {
	ctx := context.Background()
	store, _, _, err := openStore(ctx, beadsDir, global)
	if err != nil {
		return issueListOutcome(nil, err)
	}
	var names []string
	if searchNeedsCustomStatuses(options) {
		statuses, err := store.GetCustomStatusesDetailed(ctx)
		if err != nil {
			return issueListOutcome(nil, errors.Join(err, store.Close()))
		}
		names = make([]string, len(statuses))
		for index, status := range statuses {
			names[index] = status.Name
		}
	}
	filter, err := searchFilter(options, names)
	if err != nil {
		return issueListOutcome(nil, errors.Join(err, store.Close()))
	}
	items, err := store.SearchIssuesWithCounts(ctx, query, filter)
	if err != nil {
		return issueListOutcome(nil, errors.Join(err, store.Close()))
	}
	page, err := finishSearch(items, options)
	if err != nil {
		return issueListOutcome(nil, errors.Join(err, store.Close()))
	}
	if closeErr := store.Close(); closeErr != nil {
		return issueListOutcome(nil, closeErr)
	}
	return issueListOutcome(page, nil)
}

// ReadSearchOutcome runs one proxied search in a fresh read transaction.
func (s *QuerySession) ReadSearchOutcome(query string, options *IssueListOptions) *IssueListOutcome {
	if _, _, err := s.activeReader(); err != nil {
		return issueListOutcome(nil, err)
	}
	page, err := uow.RunTxRead(context.Background(), s.provider, func(ctx context.Context, unit uow.UnitOfWork) (*IssueListPage, error) {
		var customStatuses []string
		if searchNeedsCustomStatuses(options) {
			config, err := workapi.LoadUOWListConfig(ctx, unit)
			if err != nil {
				return nil, err
			}
			customStatuses = config.CustomStatusNames()
		}
		filter, err := searchFilter(options, customStatuses)
		if err != nil {
			return nil, err
		}
		result, err := unit.IssueUseCase().SearchIssuesWithCounts(ctx, query, filter)
		if err != nil {
			return nil, err
		}
		return finishSearch(result.Items, options)
	})
	return issueListOutcome(page, err)
}
