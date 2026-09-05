package main

import "testing"

func TestPolicyRejectsAOneOffMeasurement(t *testing.T) {
	selected := validTestPolicy()
	selected.Sample.MeasuredRuns = 1
	if err := validatePolicy(selected); err == nil {
		t.Fatal("validatePolicy() accepted a one-off measurement")
	}
}

func TestPolicyRejectsAWorkloadGap(t *testing.T) {
	selected := validTestPolicy()
	selected.Workloads = selected.Workloads[1:]
	if err := validatePolicy(selected); err == nil {
		t.Fatal("validatePolicy() accepted an incomplete workload registry")
	}
}

func validTestPolicy() policy {
	profiles := []profilePolicy{{ID: "profile"}}
	fixtureID := "fixture"
	fixtures := []fixturePolicy{{ID: fixtureID, GeneratorRevision: 1, IssueCount: 1, StorageProfile: "profile"}}
	workloads := make([]workloadPolicy, 0, len(requiredWorkloadIDs))
	for _, id := range requiredWorkloadIDs {
		workloads = append(workloads, workloadPolicy{ID: id, Category: "test", Profile: "profile", Fixture: &fixtureID, CacheState: "fixed", Observer: "validated"})
	}
	return policy{
		SchemaVersion: 1,
		Source:        sourcePolicy{Version: "v1.2.1", Commit: "634cbbc4bc580fa5124f63fdf65d137a46d5b4ff"},
		Sample:        samplePolicy{SetupRuns: 1, MeasuredRuns: 10, MicrobenchmarkCount: 10, RequiredStatistics: requiredStatistics},
		FixedEnvironment: map[string]string{
			"BD_DISABLE_METRICS": "1", "BD_DISABLE_EVENT_FLUSH": "1", "BEADS_NO_REMOTE_ADOPT": "1", "GIT_TERMINAL_PROMPT": "0",
			"GOPROXY": "off", "GOSUMDB": "off", "GOVCS": "*:off", "GOWORK": "off", "GOTOOLCHAIN": "local",
		},
		Profiles:  profiles,
		Fixtures:  fixtures,
		Workloads: workloads,
	}
}
