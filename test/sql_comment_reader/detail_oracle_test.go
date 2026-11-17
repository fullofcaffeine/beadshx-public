package commentreader_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"os"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/steveyegge/beads/internal/types"
	"github.com/steveyegge/beads/internal/workapi"
)

// The SQL/int64 contract below is pinned embeddeddolt.CountIssueComments.
// The real direct helper and BuildIssueDetails still own body and omission policy.
// A separate same-workspace facade comparison exercises the actual full store.
type countedCommentSource struct{ commentSource }

func (s countedCommentSource) CountComments(ctx context.Context, id string, _ bool) (int64, error) {
	var n int64
	err := s.transaction.QueryRowContext(ctx, "SELECT count(*) FROM comments WHERE issue_id = ?", id).Scan(&n)
	return n, err
}

type detailObservation struct {
	Name     string    `json:"name"`
	Comments []comment `json:"comments"`
	Count    int64     `json:"count"`
	Omitted  bool      `json:"omitted"`
	Error    string    `json:"error"`
}

func TestPinnedCommentDetailObserver(t *testing.T) {
	path := os.Getenv("BEADSHX_COMMENT_DETAIL_OBSERVATIONS")
	if path == "" {
		t.Skip("set BEADSHX_COMMENT_DETAIL_OBSERVATIONS to capture the pinned detail observer")
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
	for _, name := range []string{"include", "omit", "wisp_include", "wisp_omit", "zero_include", "zero_omit", "missing_count_include", "missing_count_omit", "count_query_include", "count_query_omit", "count_scan_include", "count_rows_include", "count_eof_close_include", "count_deferred_close_include", "null_count_include", "extra_row_omit", "negative_count_omit", "overflow_count_include", "max_count_omit", "min_count_omit", "empty_id_include", "empty_id_omit", "literal_id_include", "body_query_error_after_count", "body_scan_error_after_count"} {
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
			if strings.HasPrefix(name, "empty_id_") {
				id = ""
			}
			if name == "literal_id_include" {
				id = " \t'-- "
			}
			wisp := strings.HasPrefix(name, "wisp_")
			table := "comments"
			if wisp {
				table = "wisp_comments"
			}
			include := name != "omit" && !strings.HasSuffix(name, "_omit")
			expected := mock.ExpectQuery(regexp.QuoteMeta("SELECT count(*) FROM comments WHERE issue_id = ?")).WithArgs(id)
			if strings.HasPrefix(name, "count_query_") {
				expected.WillReturnError(errors.New("count denied"))
			} else {
				rows := sqlmock.NewRows([]string{"count"})
				if !strings.HasPrefix(name, "missing_count_") {
					var count any = int64(2)
					switch name {
					case "zero_include", "zero_omit":
						count = int64(0)
					case "count_scan_include":
						count = "invalid"
					case "null_count_include":
						count = nil
					case "negative_count_omit":
						count = int64(-1)
					case "overflow_count_include":
						count = "9223372036854775808"
					case "max_count_omit":
						count = int64(9223372036854775807)
					case "min_count_omit":
						count = int64(-9223372036854775808)
					}
					rows.AddRow(count)
					if name == "extra_row_omit" {
						rows.AddRow(int64(7))
					}
					if name == "count_rows_include" {
						rows.RowError(0, errors.New("count iteration failed"))
					}
				}
				if name == "count_eof_close_include" || name == "count_deferred_close_include" {
					rows.CloseError(errors.New("count close failed"))
				}
				expected.RowsWillBeClosed()
				if name == "count_deferred_close_include" {
					expected.WillReturnRows(rows, sqlmock.NewRows([]string{"unused"}))
				} else {
					expected.WillReturnRows(rows)
				}
			}
			if include {
				routing := sqlmock.NewRows([]string{"exists"})
				if wisp {
					routing.AddRow(1)
				}
				mock.ExpectQuery(regexp.QuoteMeta("SELECT 1 FROM wisps WHERE id = ? LIMIT 1")).WithArgs(id).RowsWillBeClosed().WillReturnRows(routing)
				bodySQL := "SELECT id, issue_id, author, text, created_at FROM " + table + " WHERE issue_id = ? ORDER BY created_at ASC, id ASC"
				expected := mock.ExpectQuery(regexp.QuoteMeta(bodySQL)).WithArgs(id)
				if name == "body_query_error_after_count" {
					expected.WillReturnError(errors.New("body denied"))
				} else {
					stamp := time.Date(2026, 3, 4, 5, 6, 7, 123456789, time.FixedZone("fixture", 90*60))
					var author any = "writer"
					if name == "body_scan_error_after_count" {
						author = nil
					}
					expected.RowsWillBeClosed().WillReturnRows(sqlmock.NewRows([]string{"id", "issue_id", "author", "text", "created_at"}).AddRow("comment-02", id, author, "body differs from count", stamp))
				}
			}
			mock.ExpectRollback()
			details, readErr := workapi.BuildIssueDetails(context.Background(), countedCommentSource{commentSource{transaction}}, &types.Issue{ID: id}, wisp, workapi.DetailOptions{IncludeComments: include})
			result := detailObservation{Name: name, Comments: []comment{}}
			if readErr != nil {
				result.Error = readErr.Error()
			} else {
				result.Count = *details.CommentCount
				result.Omitted = details.CommentsOmitted != nil && *details.CommentsOmitted
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
