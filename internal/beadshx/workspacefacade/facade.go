// Package workspacefacade exposes canonical workspace discovery as one typed
// value. Filesystem routing stays native; command policy and rendering stay in
// Haxe.
package workspacefacade

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/steveyegge/beads/internal/beads"
	"github.com/steveyegge/beads/internal/config"
	"github.com/steveyegge/beads/internal/configfile"
	dbidentifier "github.com/steveyegge/beads/internal/storage/domain/db"
	"github.com/steveyegge/beads/internal/utils"
)

// Location is the active workspace identity used by read-only commands.
type Location struct {
	path            string
	prefix          string
	databasePath    string
	databaseName    string
	databaseMissing bool
	proxiedServer   bool
	listLimitSet    bool
	listLimit       int
}

func (v Location) Path() string              { return v.path }
func (v Location) Prefix() string            { return v.prefix }
func (v Location) DatabasePath() string      { return v.databasePath }
func (v Location) DatabaseName() string      { return v.databaseName }
func (v Location) DatabaseMissing() bool     { return v.databaseMissing }
func (v Location) ProxiedServer() bool       { return v.proxiedServer }
func (v Location) ListLimitConfigured() bool { return v.listLimitSet }
func (v Location) ListLimit() int            { return v.listLimit }

func discoverLocation(path string) *Location {
	// Only the config.yaml prefix: discovery runs before every command and
	// opens no database. Haxe reads the stored issue_prefix when a command
	// needs it.
	prefix := config.GetStringFromDir(path, "issue-prefix")
	if prefix == "" {
		prefix = config.GetStringFromDir(path, "issue_prefix")
	}
	// FindDatabasePath reads metadata with a call that rewrites a legacy
	// config.json as metadata.json. Haxe refuses a legacy-only workspace, so
	// discovery leaves the database path empty there and writes nothing.
	databasePath := ""
	if !hasOnlyLegacyConfig(path) && !hasOnlyLegacyConfig(redirectTarget(path)) {
		databasePath = beads.FindDatabasePath()
	}
	databaseMissing := false
	proxiedServer := false
	fileConfig, configErr := configfile.LoadForDiscovery(path)
	if configErr == nil && fileConfig != nil {
		proxiedServer = fileConfig.IsDoltProxiedServerMode()
	}
	if databasePath == "" {
		databaseMissing = configErr == nil && fileConfig != nil && !fileConfig.IsDoltServerMode() && !proxiedServer
	}
	listLimitSet := config.GetValueSource("list.limit") != config.SourceDefault
	return &Location{
		path:            path,
		prefix:          prefix,
		databasePath:    databasePath,
		databaseMissing: databaseMissing,
		proxiedServer:   proxiedServer,
		listLimitSet:    listLimitSet,
		listLimit:       config.GetInt("list.limit"),
	}
}

// DiscoverFrom resolves explicit -C/--directory and --db selections without
// changing the process working directory. Beads itself represents a selected
// workspace with BEADS_DIR, so this bounded facade does the same while it builds
// the location and restores the caller's environment before returning. The CLI
// calls this synchronously during startup; it must not run concurrently with
// other process-environment mutations.
func DiscoverFrom(directory, database string) (*Location, error) {
	selectedBeadsDir, err := resolveDirectory(directory)
	if err != nil {
		return nil, err
	}
	if database == "" {
		return discoverSelected(selectedBeadsDir), nil
	}

	if _, statErr := os.Stat(database); statErr != nil {
		if !os.IsNotExist(statErr) {
			return nil, fmt.Errorf("--db %q: %w", database, statErr)
		}
		if dbidentifier.ValidateIdentifier(database) == nil {
			location := discoverSelected(selectedBeadsDir)
			location.databaseName = database
			return location, nil
		}
	}

	beadsDir := resolveDatabaseBeadsDir(database, selectedBeadsDir)
	// Else upstream resolveCommandBeadsDir: the first .beads beside the path's directory or an ancestor.
	for dir := filepath.Dir(database); beadsDir == "" && dir != "" && dir != filepath.Dir(dir); dir = filepath.Dir(dir) {
		if information, err := os.Stat(filepath.Join(dir, ".beads")); err == nil && information.IsDir() {
			beadsDir = filepath.Join(dir, ".beads")
		}
	}
	if beadsDir == "" {
		beadsDir = filepath.Dir(database)
	}
	return discoverAt(beadsDir), nil
}

func resolveDirectory(directory string) (string, error) {
	if strings.TrimSpace(directory) == "" {
		return "", nil
	}
	absPath, err := filepath.Abs(directory)
	if err != nil {
		return "", fmt.Errorf("cannot resolve -C directory %q: %w", directory, err)
	}
	information, err := os.Stat(absPath)
	if err != nil {
		return "", fmt.Errorf("cannot use -C directory %q: %w", directory, err)
	}
	if !information.IsDir() {
		return "", fmt.Errorf("cannot use -C directory %q: not a directory", directory)
	}
	beadsDir := beads.FindBeadsDirFrom(absPath)
	if beadsDir == "" {
		return "", fmt.Errorf("cannot use -C directory %q: no beads project found", directory)
	}

	return beadsDir, nil
}

func discoverSelected(beadsDir string) *Location {
	if beadsDir == "" {
		beadsDir = beads.FindBeadsDir()
	}
	if beadsDir == "" {
		return &Location{}
	}
	return discoverAt(beadsDir)
}

func discoverAt(beadsDir string) *Location {
	previous, wasSet := os.LookupEnv("BEADS_DIR")
	_ = os.Setenv("BEADS_DIR", beadsDir)
	defer func() {
		if wasSet {
			_ = os.Setenv("BEADS_DIR", previous)
		} else {
			_ = os.Unsetenv("BEADS_DIR")
		}
	}()
	// Match the native CLI's selected-workspace configuration view. Discovery
	// is best effort, so an unreadable optional config does not hide a workspace.
	_ = config.Initialize()
	return discoverLocation(beadsDir)
}

// resolveDatabaseBeadsDir mirrors the pinned CLI's native path-to-workspace
// mechanics, including custom data directories. Haxe still owns the option
// policy and diagnostics after this boundary returns a concrete location.
func resolveDatabaseBeadsDir(database, selectedBeadsDir string) string {
	actualDatabase := utils.CanonicalizePath(database)
	seen := make(map[string]struct{})
	candidates := make([]string, 0, 16)
	addCandidate := func(candidate string) {
		key := utils.NormalizePathForComparison(candidate)
		if key == "" {
			return
		}
		if _, exists := seen[key]; exists {
			return
		}
		seen[key] = struct{}{}
		candidates = append(candidates, candidate)
	}
	addAncestors := func(start string) {
		for current := start; current != "" && current != filepath.Dir(current); current = filepath.Dir(current) {
			addCandidate(filepath.Join(current, ".beads"))
			if filepath.Base(current) == ".beads" {
				addCandidate(current)
			}
		}
	}

	if information, err := os.Stat(database); err == nil && information.IsDir() {
		addCandidate(database)
	}
	if information, err := os.Stat(actualDatabase); err == nil && information.IsDir() {
		addCandidate(actualDatabase)
	}
	addCandidate(filepath.Dir(database))
	addCandidate(filepath.Dir(actualDatabase))
	addAncestors(filepath.Dir(database))
	addAncestors(filepath.Dir(actualDatabase))
	addCandidate(selectedBeadsDir)
	addCandidate(beads.FindBeadsDir())

	for _, candidate := range candidates {
		fileConfig, err := configfile.LoadForDiscovery(candidate)
		if err != nil || fileConfig == nil {
			continue
		}
		if utils.PathsEqual(candidate, database) || utils.PathsEqual(candidate, actualDatabase) ||
			utils.PathsEqual(filepath.Dir(database), candidate) || utils.PathsEqual(filepath.Dir(actualDatabase), candidate) ||
			utils.PathsEqual(fileConfig.DatabasePath(candidate), database) || utils.PathsEqual(fileConfig.DatabasePath(candidate), actualDatabase) {
			return candidate
		}
	}
	return ""
}

func hasRedirect(beadsDir string) bool {
	_, err := os.Stat(filepath.Join(beadsDir, beads.RedirectFileName))
	return err == nil
}

// redirectTarget is the directory that FindDatabasePath reads for beadsDir,
// or "" when beadsDir has no redirect file.
func redirectTarget(beadsDir string) string {
	if !hasRedirect(beadsDir) {
		return ""
	}
	return beads.FollowRedirect(beadsDir)
}

// hasOnlyLegacyConfig reports a config.json without metadata.json.
func hasOnlyLegacyConfig(beadsDir string) bool {
	if beadsDir == "" {
		return false
	}
	if _, err := os.Stat(configfile.ConfigPath(beadsDir)); !os.IsNotExist(err) {
		return false
	}
	_, err := os.Stat(filepath.Join(beadsDir, "config.json"))
	return err == nil
}
