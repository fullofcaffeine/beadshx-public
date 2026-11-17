package commentreader_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"os"
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/steveyegge/beads/internal/storage"
	"github.com/steveyegge/beads/internal/storage/issueops"
	"github.com/steveyegge/beads/internal/types"
	"github.com/steveyegge/beads/internal/workapi"
)

// This observer invokes the pinned direct SQL helper and detail assembler.
// The other detail facts have no effects, so only the real comment read runs.
type commentSource struct{ transaction *sql.Tx }

func (commentSource) GetIssue(context.Context, string) (*types.Issue, error) {
	panic("unexpected issue read")
}
func (commentSource) GetWisp(context.Context, string) (*types.Issue, error) {
	panic("unexpected wisp read")
}
func (commentSource) Labels(context.Context, string, bool) ([]string, error) { return nil, nil }
func (commentSource) Dependencies(context.Context, string, bool) ([]*types.IssueWithDependencyMetadata, error) {
	return nil, nil
}
func (commentSource) CountDependencies(context.Context, string, bool) (int64, error) { return 0, nil }
func (commentSource) CountDependents(context.Context, string, bool) (int64, error)   { return 0, nil }
func (commentSource) CountComments(context.Context, string, bool) (int64, error)     { return 0, nil }
func (commentSource) IterDependents(context.Context, string, bool) (storage.Iter[types.IssueWithDependencyMetadata], error) {
	panic("unexpected dependents")
}
func (s commentSource) IterComments(ctx context.Context, id string, _ bool) (storage.Iter[types.Comment], error) {
	comments, err := issueops.GetIssueCommentsInTx(ctx, s.transaction, id)
	if err != nil {
		return nil, err
	}
	return storage.NewSliceIter(comments), nil
}

type comment struct {
	ID        string `json:"id"`
	IssueID   string `json:"issueId"`
	Author    string `json:"author"`
	Text      string `json:"text"`
	CreatedAt string `json:"createdAt"`
}
type observation struct {
	Name     string    `json:"name"`
	Comments []comment `json:"comments"`
	Error    string    `json:"error"`
}

func TestPinnedCommentReadObserver(t *testing.T) {
	path := os.Getenv("BEADSHX_COMMENT_OBSERVATIONS")
	if path == "" {
		t.Skip("set BEADSHX_COMMENT_OBSERVATIONS to capture the pinned observer")
	}
	file, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := file.Close(); err != nil {
			t.Error(err)
		}
	}()
	encoder := json.NewEncoder(file)
	for _, name := range []string{"durable", "wisp", "empty", "empty_id", "literal_id", "foreign_row", "query_error", "null_id", "null_issue", "null_author", "null_text", "null_time", "text_time", "row_error", "eof_close", "deferred_close", "scan_close", "routing_query", "routing_scan", "routing_null", "routing_close"} {
		t.Run(name, func(t *testing.T) {
			database, mock, err := sqlmock.New()
			if err != nil {
				t.Fatal(err)
			}
			defer database.Close()
			mock.ExpectBegin()
			transaction, err := database.BeginTx(context.Background(), &sql.TxOptions{})
			if err != nil {
				t.Fatal(err)
			}
			id := "bd-comments"
			if name == "empty_id" {
				id = ""
			}
			if name == "literal_id" {
				id = " \t'-- "
			}
			wisp := name == "wisp"
			table := "comments"
			if wisp {
				table = "wisp_comments"
			}
			route := mock.ExpectQuery(regexp.QuoteMeta("SELECT 1 FROM wisps WHERE id = ? LIMIT 1")).WithArgs(id)
			if name == "routing_query" {
				route.WillReturnError(errors.New("routing denied"))
			} else {
				rows := sqlmock.NewRows([]string{"exists"})
				switch name {
				case "wisp", "routing_close":
					rows.AddRow(1)
				case "routing_scan":
					rows.AddRow("invalid")
				case "routing_null":
					rows.AddRow(nil)
				}
				if name == "routing_close" {
					rows.CloseError(errors.New("routing close failed"))
				}
				route.RowsWillBeClosed().WillReturnRows(rows)
			}
			query := "SELECT id, issue_id, author, text, created_at FROM " + table + " WHERE issue_id = ? ORDER BY created_at ASC, id ASC"
			{
				expect := mock.ExpectQuery(regexp.QuoteMeta(query)).WithArgs(id)
				if name == "query_error" {
					expect.WillReturnError(errors.New("query denied"))
				} else {
					expect.RowsWillBeClosed()
					rows := sqlmock.NewRows([]string{"id", "issue_id", "author", "text", "created_at"})
					stamp := time.Date(2026, 3, 4, 5, 6, 7, 123456789, time.FixedZone("fixture", 90*60))
					values := []any{"comment-02", id, "writer", "first\nline", stamp}
					switch name {
					case "null_id", "scan_close":
						values[0] = nil
					case "null_issue":
						values[1] = nil
					case "null_author":
						values[2] = nil
					case "null_text":
						values[3] = nil
					case "null_time":
						values[4] = nil
					case "text_time":
						values[4] = "2026-03-04"
					}
					if name != "empty" {
						rows.AddRow(values[0], values[1], values[2], values[3], values[4])
					}
					if name == "durable" || name == "wisp" {
						rows.AddRow("comment-10", id, "", "second \"quoted\" λ", stamp)
					}
					if name == "foreign_row" {
						rows.AddRow("foreign", "another-issue", "other", "ignored", stamp)
					}
					if name == "row_error" {
						rows.RowError(0, errors.New("iteration failed"))
					}
					if name == "eof_close" || name == "deferred_close" || name == "scan_close" {
						rows.CloseError(errors.New("close failed"))
					}
					if name == "deferred_close" {
						expect.WillReturnRows(rows, sqlmock.NewRows([]string{"unused"}))
					} else {
						expect.WillReturnRows(rows)
					}
				}
			}
			mock.ExpectRollback()
			details, readErr := workapi.BuildIssueDetails(context.Background(), commentSource{transaction}, &types.Issue{ID: id}, wisp, workapi.DetailOptions{IncludeComments: true})
			result := observation{Name: name, Comments: []comment{}}
			if readErr != nil {
				result.Error = readErr.Error()
			} else {
				for _, item := range details.Comments {
					result.Comments = append(result.Comments, comment{item.ID, item.IssueID, item.Author, item.Text, item.CreatedAt.Format(time.RFC3339Nano)})
				}
			}
			if err := transaction.Rollback(); err != nil {
				t.Fatal(err)
			}
			if err := mock.ExpectationsWereMet(); err != nil {
				t.Fatal(err)
			}
			if err := encoder.Encode(result); err != nil {
				t.Fatal(err)
			}
		})
	}
}
