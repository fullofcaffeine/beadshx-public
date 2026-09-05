package main

import (
	"bytes"
	"fmt"
	"sort"
	"strings"
)

type facadeSummary struct {
	ID            string
	Role          string
	Owner         string
	Severity      string
	BoundaryCount int
	Axes          map[string]int
	Targets       map[string]int
}

func renderReport(result inventory) []byte {
	var output bytes.Buffer
	fmt.Fprintln(&output, "# Go dependency and native-boundary pressure")
	fmt.Fprintln(&output)
	fmt.Fprintf(&output, "This report is generated from Beads `%s` with `%s`. ", result.Source.Commit, result.Toolchain.Analyzer)
	fmt.Fprintf(&output, "It ranks pressure against haxe.go `%s` without treating the Go dependency graph as the Haxe product model.\n", result.CompilerEvidence.Commit)
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "The complete machine-readable call inventory is `inventory.json.gz`. The report groups those calls by typed native boundary and dependency policy.")
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "## Coverage")
	fmt.Fprintln(&output)
	fmt.Fprintf(&output, "- %d build profiles\n", result.Coverage.ProfileCount)
	fmt.Fprintf(&output, "- %d reachable first-party packages\n", result.Coverage.ReachableFirstPartyPackages)
	fmt.Fprintf(&output, "- %d packages assigned to a native boundary\n", result.Coverage.BoundaryPackageCount)
	fmt.Fprintf(&output, "- %d deduplicated typed boundary calls\n", result.Coverage.BoundaryCount)
	fmt.Fprintf(&output, "- %d unmapped calls, effects, command profiles, or storage capabilities\n",
		result.Coverage.UnmappedBoundaryCalls+result.Coverage.UnmappedEffects+
			result.Coverage.UnmappedProfiles+result.Coverage.UnmappedOperations)
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "## Ranked haxe.go feature pressure")
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "| Priority | Feature | Observed pressure | Axes | Decision |")
	fmt.Fprintln(&output, "| --- | --- | ---: | --- | --- |")
	for _, feature := range result.FeatureRanks {
		fmt.Fprintf(&output, "| %s | `%s` | %d | %s | %s |\n",
			feature.Priority, feature.ID, feature.ObservedCount,
			markdownCodeList(feature.Axes), escapeTable(feature.Decision))
	}
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "Counts are pressure signals. One call can contribute to more than one axis, so feature totals are not additive.")
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "## Extern-first native boundaries")
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "Haxe owns every first-party Beads implementation. It consumes Go standard-library and independent third-party APIs through precise externs. A handwritten native island is retained only for a third-party or platform boundary that a reduced compiler proof cannot represent safely.")
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "| Priority | Boundary | Boundary calls | Main pressure | Role |")
	fmt.Fprintln(&output, "| --- | --- | ---: | --- | --- |")
	for _, facade := range summarizeFacades(result.Boundaries) {
		fmt.Fprintf(&output, "| %s | `%s` | %d | %s | %s |\n",
			facade.Severity, facade.ID, facade.BoundaryCount,
			formatAxisCounts(facade.Axes, 4), escapeTable(facade.Role))
	}
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "## Dependency ownership")
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "| Priority | Package or module | Boundary calls | Policy | Owner | Main pressure |")
	fmt.Fprintln(&output, "| --- | --- | ---: | --- | --- | --- |")
	for _, dependency := range result.Dependencies {
		fmt.Fprintf(&output, "| %s | `%s` | %d | `%s` | `%s` | %s |\n",
			dependency.Severity, dependency.PackageRoot, dependency.BoundaryCount,
			dependency.PolicyID, dependency.Owner, formatAxisCounts(dependency.AxisCounts, 3))
	}
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "## Highest-pressure APIs")
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "This is a review projection. The compressed inventory retains every source locator, command profile, operation, effect, build profile, and normalized signature.")
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "| Priority | Facade | Target API | Axes | Profiles | First source |")
	fmt.Fprintln(&output, "| --- | --- | --- | --- | --- | --- |")
	for _, boundary := range rankedBoundaries(result.Boundaries, 100) {
		target := boundary.TargetPackage + "." + boundary.TargetSymbol
		fmt.Fprintf(&output, "| %s | `%s` | `%s` | %s | %s | `%s` |\n",
			boundary.Severity, boundary.FacadeID, truncate(target, 90),
			markdownCodeList(boundary.PressureAxes), markdownCodeList(boundary.BuildProfiles),
			boundary.SourceLocators[0])
	}
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "## Compiler disposition")
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "The inventory links interface, context/handle, callback, channel, generic, cross-package, and multiple-return pressure to existing haxe.go gap owners. A handwritten boundary is not justified by preference alone: standard-library and independent third-party exported APIs require extern-first evidence, reusable compiler gaps must land in haxe.go before the BeadsHX lock advances, and first-party Beads code must be ported.")
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "The historically named `test/native-pressure/simple_facade` tracer proves the minimum typed-boundary pipeline: authored Haxe calls one typed native API, generated Go passes native type checking, and runtime output is observed. It does not authorize a Go facade. Each real boundary must first use precise externs or record a reduced, framework-neutral reason that a native island remains necessary.")
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "## Reproduce locally")
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "```sh")
	fmt.Fprintln(&output, "npm run test:native-pressure")
	fmt.Fprintln(&output, "```")
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "The command uses a temporary checkout of the pinned Git commit. It does not require GitHub or Docker and does not modify a live Beads database.")
	return output.Bytes()
}

func summarizeFacades(boundaries []boundaryRecord) []facadeSummary {
	values := make(map[string]*facadeSummary)
	for _, boundary := range boundaries {
		value := values[boundary.FacadeID]
		if value == nil {
			value = &facadeSummary{
				ID:       boundary.FacadeID,
				Role:     boundary.SemanticRole,
				Owner:    boundary.SelectedOwner,
				Severity: boundary.Severity,
				Axes:     make(map[string]int),
				Targets:  make(map[string]int),
			}
			values[boundary.FacadeID] = value
		}
		value.BoundaryCount++
		for _, axis := range boundary.PressureAxes {
			value.Axes[axis]++
		}
		value.Targets[boundary.TargetPackage+"."+boundary.TargetSymbol]++
	}
	result := make([]facadeSummary, 0, len(values))
	for _, value := range values {
		result = append(result, *value)
	}
	sort.Slice(result, func(i, j int) bool {
		if result[i].Severity != result[j].Severity {
			return result[i].Severity < result[j].Severity
		}
		if result[i].BoundaryCount != result[j].BoundaryCount {
			return result[i].BoundaryCount > result[j].BoundaryCount
		}
		return result[i].ID < result[j].ID
	})
	return result
}

func rankedBoundaries(boundaries []boundaryRecord, limit int) []boundaryRecord {
	result := append([]boundaryRecord(nil), boundaries...)
	sort.Slice(result, func(i, j int) bool {
		if result[i].Severity != result[j].Severity {
			return result[i].Severity < result[j].Severity
		}
		if len(result[i].PressureAxes) != len(result[j].PressureAxes) {
			return len(result[i].PressureAxes) > len(result[j].PressureAxes)
		}
		if result[i].TargetPackage != result[j].TargetPackage {
			return result[i].TargetPackage < result[j].TargetPackage
		}
		if result[i].TargetSymbol != result[j].TargetSymbol {
			return result[i].TargetSymbol < result[j].TargetSymbol
		}
		return result[i].ID < result[j].ID
	})
	if len(result) > limit {
		result = result[:limit]
	}
	return result
}

func formatAxisCounts(counts map[string]int, limit int) string {
	type axisCount struct {
		axis  string
		count int
	}
	values := make([]axisCount, 0, len(counts))
	for axis, count := range counts {
		if count > 0 {
			values = append(values, axisCount{axis: axis, count: count})
		}
	}
	sort.Slice(values, func(i, j int) bool {
		if values[i].count != values[j].count {
			return values[i].count > values[j].count
		}
		return values[i].axis < values[j].axis
	})
	if len(values) > limit {
		values = values[:limit]
	}
	parts := make([]string, 0, len(values))
	for _, value := range values {
		parts = append(parts, fmt.Sprintf("`%s` %d", value.axis, value.count))
	}
	if len(parts) == 0 {
		return "none"
	}
	return strings.Join(parts, ", ")
}

func markdownCodeList(values []string) string {
	if len(values) == 0 {
		return "none"
	}
	parts := make([]string, 0, len(values))
	for _, value := range values {
		parts = append(parts, "`"+value+"`")
	}
	return strings.Join(parts, ", ")
}

func escapeTable(value string) string {
	return strings.ReplaceAll(value, "|", "\\|")
}

func truncate(value string, limit int) string {
	if len(value) <= limit {
		return value
	}
	return value[:limit-1] + "…"
}
