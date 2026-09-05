package uow

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/steveyegge/beads/internal/configfile"
	"github.com/steveyegge/beads/internal/storage/dbproxy/proxy"
)

// AttachDoltServerUOWProvider opens an existing managed proxy and database for
// inspection. It never creates the root, starts or repairs a proxy, creates a
// database, or runs schema migrations.
func AttachDoltServerUOWProvider(
	ctx context.Context,
	serverRootDir string,
	database string,
	rootUser string,
	rootPassword string,
	teamServer bool,
	expectedProjectID string,
) (UnitOfWorkProvider, error) {
	root, err := existingServerRoot(serverRootDir)
	if err != nil {
		return nil, err
	}
	if database == "" {
		return nil, fmt.Errorf("uow: database name must not be empty (caller should default to %q)", "beads")
	}
	if rootUser == "" {
		return nil, fmt.Errorf("uow: rootUser must not be empty")
	}

	ep, err := proxy.GetExistingDatabaseProxyServerEndpoint(root, proxy.OpenOpts{
		Backend: proxy.BackendLocalServer,
	})
	if err != nil {
		return nil, fmt.Errorf("uow: attach existing proxy endpoint: %w", err)
	}
	return openAndInitSchema(ctx, ep, database, rootUser, rootPassword, "", teamServer, expectedProjectID, providerOptions{preview: true})
}

// AttachExternalDoltServerUOWProvider opens an existing proxy for an external
// Dolt server without creating or repairing any persistent state.
func AttachExternalDoltServerUOWProvider(
	ctx context.Context,
	serverRootDir string,
	database string,
	external configfile.ExternalDoltConfig,
	rootUser string,
	rootPassword string,
	teamServer bool,
	expectedProjectID string,
) (UnitOfWorkProvider, error) {
	root, err := existingServerRoot(serverRootDir)
	if err != nil {
		return nil, err
	}
	if database == "" {
		return nil, fmt.Errorf("uow: database name must not be empty (caller should default to %q)", "beads")
	}
	if rootUser == "" {
		return nil, fmt.Errorf("uow: rootUser must not be empty")
	}
	if err := external.Validate(); err != nil {
		return nil, fmt.Errorf("uow: external: %w", err)
	}

	tlsConfigName, err := registerExternalTLSConfig(external)
	if err != nil {
		return nil, fmt.Errorf("uow: external TLS: %w", err)
	}
	ep, err := proxy.GetExistingDatabaseProxyServerEndpoint(root, proxy.OpenOpts{
		Backend:  proxy.BackendExternal,
		External: external,
	})
	if err != nil {
		return nil, fmt.Errorf("uow: attach existing proxy endpoint: %w", err)
	}
	return openAndInitSchema(ctx, ep, database, rootUser, rootPassword, tlsConfigName, teamServer, expectedProjectID, providerOptions{preview: true})
}

func existingServerRoot(serverRootDir string) (string, error) {
	root, err := filepath.Abs(serverRootDir)
	if err != nil {
		return "", fmt.Errorf("uow: resolving server root dir: %w", err)
	}
	info, err := os.Stat(root)
	if err != nil {
		return "", fmt.Errorf("uow: existing server root directory: %w", err)
	}
	if !info.IsDir() {
		return "", fmt.Errorf("uow: existing server root directory %s: not a directory", root)
	}
	return root, nil
}
