//go:build cgo

package readonlyfacade

import (
	"context"

	"github.com/steveyegge/beads/internal/storage/embeddeddolt"
)

func openEmbeddedStore(ctx context.Context, beadsDir, database, branch string) (readonlyStore, error) {
	return embeddeddolt.OpenReadOnly(ctx, beadsDir, database, branch)
}
