package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
)

var requiredWorkloadIDs = []string{
	"backup-large", "backup-small", "build-clean", "build-no-change", "build-warm",
	"large-list-json", "large-list-text", "microbenchmarks-discovery", "microbenchmarks-selected",
	"migration-current-noop", "migration-v1.1.2",
	"read-count-large", "read-count-small", "read-dependencies-large", "read-dependencies-small",
	"read-list-large", "read-list-small", "read-ready-large", "read-ready-small",
	"read-search-large", "read-search-small", "read-show-large", "read-show-small",
	"startup-help", "startup-version", "startup-workspace-info",
	"sync-clean-merge", "sync-conflict", "sync-no-change", "sync-pull-only", "sync-push-only",
	"write-close", "write-comment", "write-create", "write-dependency", "write-label", "write-reopen", "write-update",
}

var requiredStatistics = []string{
	"coefficientOfVariation", "count", "maximum", "mean", "median", "minimum", "p90", "p95", "standardDeviation",
}

func loadPolicy(path string) (policy, error) {
	content, err := os.ReadFile(path) // #nosec G304 -- caller confines the path to the repository.
	if err != nil {
		return policy{}, err
	}
	var selected policy
	decoder := json.NewDecoder(strings.NewReader(string(content)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&selected); err != nil {
		return policy{}, err
	}
	return selected, nil
}

func validatePolicy(selected policy) error {
	if selected.SchemaVersion != 1 {
		return fmt.Errorf("schemaVersion = %d; want 1", selected.SchemaVersion)
	}
	if selected.Source.Version != "v1.2.1" || selected.Source.Commit != "634cbbc4bc580fa5124f63fdf65d137a46d5b4ff" {
		return fmt.Errorf("source lock does not match the compatibility target")
	}
	if selected.ServerToolchain.Version != "2.2.0" || selected.ServerToolchain.RepositoryRelativeBinary == "" ||
		len(selected.ServerToolchain.DarwinArm64ArchiveSHA256) != 64 || len(selected.ServerToolchain.DarwinArm64BinarySHA256) != 64 {
		return fmt.Errorf("dedicated server toolchain lock is incomplete")
	}
	if selected.Sample.SetupRuns < 1 || selected.Sample.MeasuredRuns < 10 || selected.Sample.MicrobenchmarkCount < 10 {
		return fmt.Errorf("sample policy requires one setup run and at least ten measured runs")
	}
	if !sameStrings(selected.Sample.RequiredStatistics, requiredStatistics) {
		return fmt.Errorf("required statistics are incomplete")
	}
	for _, name := range []string{"BD_DISABLE_METRICS", "BD_DISABLE_EVENT_FLUSH", "BEADS_NO_REMOTE_ADOPT", "GIT_TERMINAL_PROMPT"} {
		if selected.FixedEnvironment[name] != "1" && selected.FixedEnvironment[name] != "0" {
			return fmt.Errorf("fixed environment %s is missing", name)
		}
	}
	for name, expected := range map[string]string{"GOPROXY": "off", "GOSUMDB": "off", "GOVCS": "*:off", "GOWORK": "off", "GOTOOLCHAIN": "local"} {
		if selected.FixedEnvironment[name] != expected {
			return fmt.Errorf("fixed environment %s = %q; want %q", name, selected.FixedEnvironment[name], expected)
		}
	}

	profiles := make(map[string]profilePolicy, len(selected.Profiles))
	for _, profile := range selected.Profiles {
		if profile.ID == "" || profiles[profile.ID].ID != "" {
			return fmt.Errorf("duplicate or empty profile ID %q", profile.ID)
		}
		profiles[profile.ID] = profile
	}
	fixtures := make(map[string]fixturePolicy, len(selected.Fixtures))
	for _, fixture := range selected.Fixtures {
		if fixture.ID == "" || fixtures[fixture.ID].ID != "" {
			return fmt.Errorf("duplicate or empty fixture ID %q", fixture.ID)
		}
		if profiles[fixture.StorageProfile].ID == "" || fixture.IssueCount < 1 || fixture.GeneratorRevision < 1 {
			return fmt.Errorf("fixture %s has an invalid owner or size", fixture.ID)
		}
		fixtures[fixture.ID] = fixture
	}
	workloads := make(map[string]workloadPolicy, len(selected.Workloads))
	for _, workload := range selected.Workloads {
		if workload.ID == "" || workloads[workload.ID].ID != "" {
			return fmt.Errorf("duplicate or empty workload ID %q", workload.ID)
		}
		if profiles[workload.Profile].ID == "" {
			return fmt.Errorf("workload %s refers to unknown profile %s", workload.ID, workload.Profile)
		}
		if workload.Fixture != nil && fixtures[*workload.Fixture].ID == "" {
			return fmt.Errorf("workload %s refers to unknown fixture %s", workload.ID, *workload.Fixture)
		}
		if workload.Category == "" || workload.CacheState == "" || workload.Observer == "" {
			return fmt.Errorf("workload %s has an incomplete measurement contract", workload.ID)
		}
		workloads[workload.ID] = workload
	}
	actualIDs := make([]string, 0, len(workloads))
	for id := range workloads {
		actualIDs = append(actualIDs, id)
	}
	if !sameStrings(actualIDs, requiredWorkloadIDs) {
		return fmt.Errorf("workload registry does not match the required M02-08 surface")
	}
	return nil
}

func sameStrings(left, right []string) bool {
	leftCopy := append([]string(nil), left...)
	rightCopy := append([]string(nil), right...)
	sort.Strings(leftCopy)
	sort.Strings(rightCopy)
	return strings.Join(leftCopy, "\x00") == strings.Join(rightCopy, "\x00")
}
