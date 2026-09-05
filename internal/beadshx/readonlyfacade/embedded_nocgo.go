//go:build !cgo

package readonlyfacade

import (
	"context"
	"errors"
)

func openEmbeddedStore(_ context.Context, _, _, _ string) (readonlyStore, error) {
	return nil, errors.New("embedded strict read-only storage requires CGO")
}
