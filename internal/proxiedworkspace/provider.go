// Package proxiedworkspace owns proxied-server workspace resolution and
// provider construction. Command packages select a posture; they do not copy
// topology, database, credential, or project-identity rules.
package proxiedworkspace

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/steveyegge/beads/internal/configfile"
	"github.com/steveyegge/beads/internal/doltserver"
	"github.com/steveyegge/beads/internal/storage/uow"
)

// Topology is the resolved provider input shared by ordinary and strict opens.
type Topology struct {
	Database          string
	TeamServer        bool
	ExpectedProjectID string
	ProxyPort         int
	ProxyIdle         time.Duration
	External          *configfile.ExternalDoltConfig
	RootPassword      string
}

type identityPosture bool

const (
	assertWorkspaceIdentity identityPosture = false
	adoptWorkspaceIdentity  identityPosture = true
)

type configLoader func(string) (*configfile.Config, error)

// Resolve returns the ordinary proxied topology and preserves existing config
// migration behavior for upstream command paths.
func Resolve(beadsDir, databaseOverride string) (Topology, error) {
	return resolve(beadsDir, databaseOverride, assertWorkspaceIdentity, configfile.Load, false)
}

// ResolveAdopting returns ordinary topology without asserting local identity.
// Only explicit initialization and server-wide maintenance may select it.
func ResolveAdopting(beadsDir, databaseOverride string) (Topology, error) {
	return resolve(beadsDir, databaseOverride, adoptWorkspaceIdentity, configfile.Load, false)
}

// ResolveForInspection reads proxied topology without migrating legacy config
// and refuses any workspace that is not explicitly proxied-server mode.
func ResolveForInspection(beadsDir, databaseOverride string) (Topology, error) {
	return resolve(beadsDir, databaseOverride, assertWorkspaceIdentity, configfile.LoadForDiscovery, true)
}

func resolve(beadsDir, databaseOverride string, posture identityPosture, load configLoader, requireProxied bool) (Topology, error) {
	if beadsDir == "" {
		return Topology{}, fmt.Errorf("proxied workspace: beadsDir must be set")
	}
	persisted, err := load(beadsDir)
	if err != nil {
		return Topology{}, fmt.Errorf(
			"corrupt workspace config %s: %w — refusing to fall back to a fresh database; repair or remove the file to proceed",
			configfile.ConfigPath(beadsDir), err)
	}
	if requireProxied && (persisted == nil || !persisted.IsDoltProxiedServerMode()) {
		return Topology{}, fmt.Errorf("strict proxied attach requires a dolt proxied-server workspace")
	}

	topology := Topology{Database: configfile.DefaultDoltDatabase}
	if persisted != nil {
		topology.Database = persisted.GetDoltDatabase()
		topology.TeamServer = persisted.IsTeamServerManaged()
		if posture == assertWorkspaceIdentity {
			topology.ExpectedProjectID = persisted.ProjectID
			if topology.TeamServer && topology.ExpectedProjectID == "" {
				return Topology{}, fmt.Errorf(
					"newProxiedServerUOWProvider: this team-server workspace has no project identity in %s; re-run 'bd init --team-server' to adopt the identity provisioned in the shared database (it never writes to that database)",
					configfile.ConfigFileName)
			}
		}
	}
	if databaseOverride != "" {
		topology.Database = databaseOverride
	}

	info, err := configfile.LoadProxiedServerClientInfo(beadsDir)
	if err != nil {
		return Topology{}, fmt.Errorf(
			"corrupt proxied-server sidecar %s: %w — refusing to fall back to a fresh database; repair or remove the file to proceed",
			configfile.ProxiedServerClientInfoPath(beadsDir), err)
	}
	if info != nil {
		topology.ProxyPort = info.Port
		topology.ProxyIdle = info.IdleTimeout
		if info.External != nil {
			topology.External = info.External
			topology.RootPassword = os.Getenv(configfile.ExternalDoltPasswordEnvVar)
		}
	}
	return topology, nil
}

// AttachForInspection attaches to a verified existing proxy and database. It
// performs no config migration, proxy lifecycle action, schema migration,
// journal activation, or deferred-task wake.
func AttachForInspection(ctx context.Context, beadsDir, databaseOverride string) (uow.UnitOfWorkProvider, error) {
	topology, err := ResolveForInspection(beadsDir, databaseOverride)
	if err != nil {
		return nil, err
	}
	root, err := doltserver.ResolveProxiedServerRootPath(beadsDir)
	if err != nil {
		return nil, fmt.Errorf("strict proxied attach: resolve root path: %w", err)
	}
	if topology.External != nil {
		return uow.AttachExternalDoltServerUOWProvider(
			ctx,
			root,
			topology.Database,
			*topology.External,
			topology.External.ResolvedUser(),
			topology.RootPassword,
			topology.TeamServer,
			topology.ExpectedProjectID,
		)
	}
	return uow.AttachDoltServerUOWProvider(
		ctx,
		root,
		topology.Database,
		"root",
		"",
		topology.TeamServer,
		topology.ExpectedProjectID,
	)
}
