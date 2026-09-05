package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"go/ast"
	"go/token"
	"go/types"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"

	"golang.org/x/tools/go/packages"
)

type compiledGroup struct {
	policy boundaryGroup
	regex  *regexp.Regexp
}

type compiledDependencyPolicy struct {
	policy dependencyPolicy
	regex  *regexp.Regexp
}

type observedBoundary struct {
	group          boundaryGroup
	callerPackages map[string]bool
	callerSymbols  map[string]bool
	targetPackage  string
	targetSymbol   string
	signature      string
	locators       map[string]bool
	profiles       map[string]bool
	axes           map[string]bool
}

type profileAnalysis struct {
	boundaries         map[string]*observedBoundary
	firstPartyPackages map[string]bool
	boundaryPackages   map[string]bool
	packageModules     map[string]string
}

func analyze(sourceRoot string, selected policy) (inventory, error) {
	groups, err := compileGroups(selected.BoundaryGroups)
	if err != nil {
		return inventory{}, err
	}
	dependencyPolicies, err := compileDependencyPolicies(selected.DependencyPolicies)
	if err != nil {
		return inventory{}, err
	}

	merged := make(map[string]*observedBoundary)
	firstPartyPackages := make(map[string]bool)
	boundaryPackages := make(map[string]bool)
	packageModules := make(map[string]string)
	for _, profile := range selected.Profiles {
		profileResult, err := analyzeProfile(sourceRoot, selected, profile, groups)
		if err != nil {
			return inventory{}, fmt.Errorf("profile %s: %w", profile.ID, err)
		}
		mergeProfile(merged, profileResult.boundaries)
		mergeSet(firstPartyPackages, profileResult.firstPartyPackages)
		mergeSet(boundaryPackages, profileResult.boundaryPackages)
		for packagePath, modulePath := range profileResult.packageModules {
			packageModules[packagePath] = modulePath
		}
	}

	boundaries := materializeBoundaries(merged, selected)
	axisCounts := make(map[string]int, len(selected.PressureAxes))
	for _, axis := range selected.PressureAxes {
		axisCounts[axis] = 0
	}
	for _, boundary := range boundaries {
		for _, axis := range boundary.PressureAxes {
			axisCounts[axis]++
		}
	}
	result := inventory{
		SchemaVersion:    1,
		Source:           selected.Compatibility,
		CompilerEvidence: selected.CompilerEvidence,
		Toolchain: toolchainIdentity{
			Go:       "go" + selected.GoVersion,
			Analyzer: "golang.org/x/tools/go/packages+go/types",
		},
		Profiles:     append([]buildProfile(nil), selected.Profiles...),
		FeatureRanks: buildFeatureRanks(selected.FeatureRanks, axisCounts),
		Dependencies: summarizeDependencies(boundaries, dependencyPolicies, packageModules),
		Boundaries:   boundaries,
		Coverage: coverageSummary{
			ProfileCount:                len(selected.Profiles),
			ReachableFirstPartyPackages: len(firstPartyPackages),
			BoundaryPackageCount:        len(boundaryPackages),
			BoundaryCount:               len(boundaries),
			BoundariesByAxis:            axisCounts,
			UnmappedBoundaryCalls:       0,
			UnmappedEffects:             0,
			UnmappedProfiles:            0,
			UnmappedOperations:          0,
		},
	}
	return result, nil
}

func analyzeProfile(sourceRoot string, selected policy, profile buildProfile, groups []compiledGroup) (profileAnalysis, error) {
	environment := profileEnvironment(profile, selected.GoVersion)
	discoveryConfig := &packages.Config{
		Mode: packages.NeedName | packages.NeedFiles | packages.NeedCompiledGoFiles |
			packages.NeedImports | packages.NeedDeps | packages.NeedModule,
		Dir: sourceRoot,
		Env: environment,
	}
	roots, err := packages.Load(discoveryConfig, selected.RootPackages...)
	if err != nil {
		return profileAnalysis{}, err
	}
	allowRuntimeCGO := profile.CGOEnabled && (runtime.GOOS != profile.GOOS || runtime.GOARCH != profile.GOARCH)
	if err := packageErrors(roots, selected.FirstPartyPrefix, allowRuntimeCGO); err != nil {
		return profileAnalysis{}, err
	}

	firstParty := make(map[string]bool)
	packageModules := make(map[string]string)
	visitPackages(roots, func(selectedPackage *packages.Package) {
		if strings.HasPrefix(selectedPackage.PkgPath, selected.FirstPartyPrefix) {
			firstParty[selectedPackage.PkgPath] = true
		}
		if selectedPackage.Module != nil {
			packageModules[selectedPackage.PkgPath] = selectedPackage.Module.Path
		}
	})
	patterns := make([]string, 0, len(firstParty))
	for packagePath := range firstParty {
		patterns = append(patterns, packagePath)
	}
	sort.Strings(patterns)
	if len(patterns) == 0 {
		return profileAnalysis{}, errorsForProfile("no reachable first-party packages")
	}

	fileSet := token.NewFileSet()
	typedConfig := &packages.Config{
		Mode: packages.NeedName | packages.NeedFiles | packages.NeedCompiledGoFiles |
			packages.NeedImports | packages.NeedDeps | packages.NeedTypes |
			packages.NeedTypesInfo | packages.NeedTypesSizes | packages.NeedSyntax |
			packages.NeedModule,
		Dir:  sourceRoot,
		Env:  environment,
		Fset: fileSet,
	}
	typedPackages, err := packages.Load(typedConfig, patterns...)
	if err != nil {
		return profileAnalysis{}, err
	}
	if err := packageErrors(typedPackages, selected.FirstPartyPrefix, allowRuntimeCGO); err != nil {
		return profileAnalysis{}, err
	}
	visitPackages(typedPackages, func(selectedPackage *packages.Package) {
		if selectedPackage.Module != nil {
			packageModules[selectedPackage.PkgPath] = selectedPackage.Module.Path
		}
	})

	result := profileAnalysis{
		boundaries:         make(map[string]*observedBoundary),
		firstPartyPackages: firstParty,
		boundaryPackages:   make(map[string]bool),
		packageModules:     packageModules,
	}
	for _, selectedPackage := range typedPackages {
		if !firstParty[selectedPackage.PkgPath] {
			continue
		}
		group, ok := selectGroup(selectedPackage.PkgPath, groups)
		if !ok {
			continue
		}
		result.boundaryPackages[selectedPackage.PkgPath] = true
		collectPackageBoundaries(sourceRoot, profile, selectedPackage, group, groups, result.boundaries)
	}
	return result, nil
}

func collectPackageBoundaries(
	sourceRoot string,
	profile buildProfile,
	selectedPackage *packages.Package,
	group boundaryGroup,
	groups []compiledGroup,
	boundaries map[string]*observedBoundary,
) {
	for _, file := range selectedPackage.Syntax {
		fileHasCgo := importsC(file)
		for _, declaration := range file.Decls {
			switch value := declaration.(type) {
			case *ast.FuncDecl:
				caller := value.Name.Name
				if value.Recv != nil && len(value.Recv.List) > 0 {
					caller = types.ExprString(value.Recv.List[0].Type) + "." + caller
				}
				collectCalls(sourceRoot, profile, selectedPackage, group, groups, caller, value.Body, fileHasCgo, boundaries)
			case *ast.GenDecl:
				for _, spec := range value.Specs {
					valueSpec, ok := spec.(*ast.ValueSpec)
					if !ok {
						continue
					}
					caller := "<package-init>"
					if len(valueSpec.Names) > 0 {
						caller = valueSpec.Names[0].Name
					}
					collectCalls(sourceRoot, profile, selectedPackage, group, groups, caller, valueSpec, fileHasCgo, boundaries)
				}
			}
		}
	}
}

func collectCalls(
	sourceRoot string,
	profile buildProfile,
	selectedPackage *packages.Package,
	group boundaryGroup,
	groups []compiledGroup,
	caller string,
	node ast.Node,
	fileHasCgo bool,
	boundaries map[string]*observedBoundary,
) {
	if node == nil {
		return
	}
	ast.Inspect(node, func(candidate ast.Node) bool {
		call, ok := candidate.(*ast.CallExpr)
		if !ok {
			return true
		}
		object, signature, targetSymbol := resolveCall(selectedPackage.TypesInfo, call.Fun)
		if signature == nil {
			return true
		}
		targetPackage := selectedPackage.PkgPath
		if object != nil {
			if object.Pkg() == nil {
				return true
			}
			targetPackage = object.Pkg().Path()
		}
		if targetSymbol == "" {
			targetSymbol = "<callback>"
		}
		if targetPackage == selectedPackage.PkgPath && targetSymbol != "<callback>" {
			return true
		}
		if targetGroup, found := selectGroup(targetPackage, groups); found && targetGroup.ID == group.ID {
			return true
		}

		signatureText := types.TypeString(signature, func(selectedPackage *types.Package) string {
			return selectedPackage.Path()
		})
		key := strings.Join([]string{group.ID, targetPackage, targetSymbol, signatureText}, "\x00")
		boundary := boundaries[key]
		if boundary == nil {
			boundary = &observedBoundary{
				group:          group,
				callerPackages: make(map[string]bool),
				callerSymbols:  make(map[string]bool),
				targetPackage:  targetPackage,
				targetSymbol:   targetSymbol,
				signature:      signatureText,
				locators:       make(map[string]bool),
				profiles:       make(map[string]bool),
				axes:           signatureAxes(signature),
			}
			boundaries[key] = boundary
		}
		boundary.callerPackages[selectedPackage.PkgPath] = true
		boundary.callerSymbols[selectedPackage.PkgPath+":"+caller] = true
		position := selectedPackage.Fset.Position(call.Pos())
		boundary.locators[sourceLocator(sourceRoot, position)] = true
		boundary.profiles[profile.ID] = true
		if fileHasCgo {
			boundary.axes["cgo"] = true
		}
		if platformSpecificFile(position.Filename) {
			boundary.axes["platformSpecific"] = true
		}
		return true
	})
}

func resolveCall(info *types.Info, expression ast.Expr) (types.Object, *types.Signature, string) {
	expression = unwrapCallExpression(expression)
	var object types.Object
	var symbol string
	switch value := expression.(type) {
	case *ast.Ident:
		object = info.ObjectOf(value)
	case *ast.SelectorExpr:
		if selection := info.Selections[value]; selection != nil {
			object = selection.Obj()
			symbol = types.TypeString(selection.Recv(), func(selectedPackage *types.Package) string {
				return selectedPackage.Path()
			}) + "." + object.Name()
		} else {
			object = info.ObjectOf(value.Sel)
		}
	}
	var selectedType types.Type
	if object != nil {
		selectedType = object.Type()
		if symbol == "" {
			symbol = object.Name()
		}
	} else {
		selectedType = info.TypeOf(expression)
	}
	signature, _ := selectedType.Underlying().(*types.Signature)
	return object, signature, symbol
}

func unwrapCallExpression(expression ast.Expr) ast.Expr {
	for {
		switch value := expression.(type) {
		case *ast.ParenExpr:
			expression = value.X
		case *ast.IndexExpr:
			expression = value.X
		case *ast.IndexListExpr:
			expression = value.X
		default:
			return expression
		}
	}
}

func signatureAxes(signature *types.Signature) map[string]bool {
	axes := make(map[string]bool)
	if signature.TypeParams() != nil && signature.TypeParams().Len() > 0 {
		axes["generic"] = true
	}
	if signature.Results() != nil && signature.Results().Len() > 1 {
		axes["multipleReturns"] = true
	}
	visited := make(map[types.Type]bool)
	visitTupleTypes(signature.Params(), axes, visited)
	visitTupleTypes(signature.Results(), axes, visited)
	return axes
}

func visitTupleTypes(tuple *types.Tuple, axes map[string]bool, visited map[types.Type]bool) {
	if tuple == nil {
		return
	}
	for index := 0; index < tuple.Len(); index++ {
		visitType(tuple.At(index).Type(), axes, visited)
	}
}

func visitType(selectedType types.Type, axes map[string]bool, visited map[types.Type]bool) {
	if selectedType == nil || visited[selectedType] {
		return
	}
	visited[selectedType] = true
	switch value := selectedType.(type) {
	case *types.Pointer:
		axes["pointer"] = true
		visitType(value.Elem(), axes, visited)
	case *types.Chan:
		axes["channel"] = true
		visitType(value.Elem(), axes, visited)
	case *types.Signature:
		axes["callback"] = true
		if value.TypeParams() != nil && value.TypeParams().Len() > 0 {
			axes["generic"] = true
		}
		visitTupleTypes(value.Params(), axes, visited)
		visitTupleTypes(value.Results(), axes, visited)
	case *types.Interface:
		axes["interface"] = true
	case *types.Named:
		if object := value.Obj(); object != nil && object.Pkg() != nil &&
			object.Pkg().Path() == "context" && object.Name() == "Context" {
			axes["context"] = true
		}
		if value.TypeArgs() != nil && value.TypeArgs().Len() > 0 {
			axes["generic"] = true
			for index := 0; index < value.TypeArgs().Len(); index++ {
				visitType(value.TypeArgs().At(index), axes, visited)
			}
		}
		switch value.Underlying().(type) {
		case *types.Interface:
			axes["interface"] = true
		case *types.Chan:
			axes["channel"] = true
		}
	case *types.Slice:
		visitType(value.Elem(), axes, visited)
	case *types.Array:
		visitType(value.Elem(), axes, visited)
	case *types.Map:
		visitType(value.Key(), axes, visited)
		visitType(value.Elem(), axes, visited)
	case *types.Struct:
		for index := 0; index < value.NumFields(); index++ {
			visitType(value.Field(index).Type(), axes, visited)
		}
	case *types.TypeParam:
		axes["generic"] = true
		visitType(value.Constraint(), axes, visited)
	}
}

func materializeBoundaries(observed map[string]*observedBoundary, selected policy) []boundaryRecord {
	profilesByID := make(map[string]buildProfile, len(selected.Profiles))
	for _, profile := range selected.Profiles {
		profilesByID[profile.ID] = profile
	}
	result := make([]boundaryRecord, 0, len(observed))
	for _, boundary := range observed {
		if len(boundary.profiles) != len(selected.Profiles) {
			boundary.axes["platformSpecific"] = true
			allCGO := len(boundary.profiles) > 0
			for profileID := range boundary.profiles {
				if !profilesByID[profileID].CGOEnabled {
					allCGO = false
				}
			}
			if allCGO {
				boundary.axes["cgo"] = true
			}
		}
		axes := boolKeys(boundary.axes)
		linkedGaps := gapsForAxes(selected.CompilerGaps, boundary.axes)
		idInput := strings.Join([]string{
			boundary.group.ID,
			boundary.targetPackage,
			boundary.targetSymbol,
			boundary.signature,
		}, "\x00")
		digest := sha256.Sum256([]byte(idInput))
		result = append(result, boundaryRecord{
			ID:                  "native:" + hex.EncodeToString(digest[:12]),
			SourceLocators:      boolKeys(boundary.locators),
			CallerPackages:      boolKeys(boundary.callerPackages),
			CallerSymbols:       boolKeys(boundary.callerSymbols),
			TargetPackage:       boundary.targetPackage,
			TargetSymbol:        boundary.targetSymbol,
			NormalizedSignature: boundary.signature,
			CommandProfiles:     sortedCopy(boundary.group.CommandProfiles),
			OperationIDs:        sortedCopy(boundary.group.OperationIDs),
			EffectIDs:           sortedCopy(boundary.group.EffectIDs),
			BuildProfiles:       boolKeys(boundary.profiles),
			SemanticRole:        boundary.group.SemanticRole,
			PressureAxes:        axes,
			SelectedOwner:       boundary.group.SelectedOwner,
			FacadeID:            boundary.group.FacadeID,
			HaxeGoEvidence:      sortedCopy(boundary.group.HaxeGoEvidence),
			LinkedGaps:          linkedGaps,
			Severity:            boundary.group.Severity,
			ReducedFixture:      boundary.group.ReducedFixture,
			Waiver:              boundary.group.Waiver,
		})
	}
	sort.Slice(result, func(i, j int) bool { return result[i].ID < result[j].ID })
	return result
}

func buildFeatureRanks(policies []featureRankPolicy, axisCounts map[string]int) []featureRank {
	result := make([]featureRank, 0, len(policies))
	for _, selectedPolicy := range policies {
		counts := make(map[string]int, len(selectedPolicy.Axes))
		total := 0
		for _, axis := range selectedPolicy.Axes {
			counts[axis] = axisCounts[axis]
			total += axisCounts[axis]
		}
		result = append(result, featureRank{
			ID:            selectedPolicy.ID,
			Priority:      selectedPolicy.Priority,
			Axes:          sortedCopy(selectedPolicy.Axes),
			ObservedCount: total,
			AxisCounts:    counts,
			Decision:      selectedPolicy.Decision,
		})
	}
	sort.Slice(result, func(i, j int) bool {
		if result[i].Priority != result[j].Priority {
			return result[i].Priority < result[j].Priority
		}
		if result[i].ObservedCount != result[j].ObservedCount {
			return result[i].ObservedCount > result[j].ObservedCount
		}
		return result[i].ID < result[j].ID
	})
	return result
}

func summarizeDependencies(
	boundaries []boundaryRecord,
	policies []compiledDependencyPolicy,
	packageModules map[string]string,
) []dependencySummary {
	type accumulator struct {
		policy dependencyPolicy
		count  int
		axes   map[string]int
	}
	values := make(map[string]*accumulator)
	for _, boundary := range boundaries {
		root := packageModules[boundary.TargetPackage]
		if root == "" {
			root = standardLibraryRoot(boundary.TargetPackage)
		}
		selectedPolicy := selectDependencyPolicy(boundary.TargetPackage, policies)
		key := root + "\x00" + selectedPolicy.ID
		value := values[key]
		if value == nil {
			value = &accumulator{policy: selectedPolicy, axes: make(map[string]int)}
			values[key] = value
		}
		value.count++
		for _, axis := range boundary.PressureAxes {
			value.axes[axis]++
		}
	}
	result := make([]dependencySummary, 0, len(values))
	for key, value := range values {
		root := strings.SplitN(key, "\x00", 2)[0]
		result = append(result, dependencySummary{
			PackageRoot:   root,
			PolicyID:      value.policy.ID,
			Owner:         value.policy.Owner,
			Severity:      value.policy.Severity,
			Decision:      value.policy.Decision,
			BoundaryCount: value.count,
			AxisCounts:    value.axes,
		})
	}
	sort.Slice(result, func(i, j int) bool {
		if result[i].Severity != result[j].Severity {
			return result[i].Severity < result[j].Severity
		}
		if result[i].BoundaryCount != result[j].BoundaryCount {
			return result[i].BoundaryCount > result[j].BoundaryCount
		}
		return result[i].PackageRoot < result[j].PackageRoot
	})
	return result
}

func compileGroups(groups []boundaryGroup) ([]compiledGroup, error) {
	result := make([]compiledGroup, 0, len(groups))
	for _, group := range groups {
		compiled, err := compileRegex(group.CallerPackageRegex)
		if err != nil {
			return nil, err
		}
		result = append(result, compiledGroup{policy: group, regex: compiled})
	}
	return result, nil
}

func compileDependencyPolicies(policies []dependencyPolicy) ([]compiledDependencyPolicy, error) {
	result := make([]compiledDependencyPolicy, 0, len(policies))
	for _, selectedPolicy := range policies {
		compiled, err := compileRegex(selectedPolicy.PackageRegex)
		if err != nil {
			return nil, err
		}
		result = append(result, compiledDependencyPolicy{policy: selectedPolicy, regex: compiled})
	}
	return result, nil
}

func compileRegex(expression string) (*regexp.Regexp, error) {
	compiled, err := regexp.Compile(expression)
	if err != nil {
		return nil, fmt.Errorf("invalid regex %q: %w", expression, err)
	}
	return compiled, nil
}

func selectGroup(packagePath string, groups []compiledGroup) (boundaryGroup, bool) {
	for _, group := range groups {
		if group.regex.MatchString(packagePath) {
			return group.policy, true
		}
	}
	return boundaryGroup{}, false
}

func selectDependencyPolicy(packagePath string, policies []compiledDependencyPolicy) dependencyPolicy {
	for _, selectedPolicy := range policies {
		if selectedPolicy.regex.MatchString(packagePath) {
			return selectedPolicy.policy
		}
	}
	panic("dependency policy has no catch-all")
}

func profileEnvironment(profile buildProfile, goVersion string) []string {
	overrides := map[string]string{
		"GOOS":        profile.GOOS,
		"GOARCH":      profile.GOARCH,
		"CGO_ENABLED": map[bool]string{false: "0", true: "1"}[profile.CGOEnabled],
		"GOWORK":      "off",
		"GOTOOLCHAIN": "go" + goVersion,
		"GOFLAGS":     "-tags=" + strings.Join(profile.BuildTags, ","),
	}
	environment := make([]string, 0, len(os.Environ())+len(overrides))
	for _, entry := range os.Environ() {
		key := strings.SplitN(entry, "=", 2)[0]
		if _, replaced := overrides[key]; !replaced {
			environment = append(environment, entry)
		}
	}
	keys := make([]string, 0, len(overrides))
	for key := range overrides {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		environment = append(environment, key+"="+overrides[key])
	}
	return environment
}

func packageErrors(selectedPackages []*packages.Package, firstPartyPrefix string, allowRuntimeCGO bool) error {
	var messages []string
	visitPackages(selectedPackages, func(selectedPackage *packages.Package) {
		for _, selectedError := range selectedPackage.Errors {
			if !strings.HasPrefix(selectedPackage.PkgPath, firstPartyPrefix) &&
				allowRuntimeCGO &&
				(selectedPackage.PkgPath == "runtime/cgo" || strings.Contains(selectedError.Msg, "could not import C")) {
				continue
			}
			messages = append(messages, selectedPackage.PkgPath+": "+selectedError.Msg)
		}
	})
	if len(messages) == 0 {
		return nil
	}
	sort.Strings(messages)
	if len(messages) > 20 {
		messages = append(messages[:20], "additional package errors omitted")
	}
	return fmt.Errorf("package load failed:\n%s", strings.Join(messages, "\n"))
}

func visitPackages(roots []*packages.Package, visit func(*packages.Package)) {
	seen := make(map[string]bool)
	var walk func(*packages.Package)
	walk = func(selectedPackage *packages.Package) {
		if selectedPackage == nil || seen[selectedPackage.ID] {
			return
		}
		seen[selectedPackage.ID] = true
		visit(selectedPackage)
		keys := make([]string, 0, len(selectedPackage.Imports))
		for key := range selectedPackage.Imports {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			walk(selectedPackage.Imports[key])
		}
	}
	for _, root := range roots {
		walk(root)
	}
}

func sourceLocator(sourceRoot string, position token.Position) string {
	relative, err := filepath.Rel(sourceRoot, position.Filename)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		relative = filepath.Base(position.Filename)
	}
	return filepath.ToSlash(relative) + ":" + strconv.Itoa(position.Line)
}

func importsC(file *ast.File) bool {
	for _, selectedImport := range file.Imports {
		if selectedImport.Path != nil && selectedImport.Path.Value == `"C"` {
			return true
		}
	}
	return false
}

func platformSpecificFile(path string) bool {
	name := filepath.Base(path)
	for _, marker := range []string{"_darwin.go", "_linux.go", "_unix.go", "_windows.go", "_wasm.go", "_nocgo.go", "_cgo.go"} {
		if strings.HasSuffix(name, marker) {
			return true
		}
	}
	return false
}

func gapsForAxes(gaps []compilerGap, axes map[string]bool) []string {
	selected := make(map[string]bool)
	for _, gap := range gaps {
		for _, axis := range gap.Axes {
			if axes[axis] {
				selected[gap.ID] = true
				break
			}
		}
	}
	return boolKeys(selected)
}

func mergeProfile(destination, source map[string]*observedBoundary) {
	for key, value := range source {
		existing := destination[key]
		if existing == nil {
			destination[key] = value
			continue
		}
		mergeSet(existing.locators, value.locators)
		mergeSet(existing.profiles, value.profiles)
		mergeSet(existing.axes, value.axes)
		mergeSet(existing.callerPackages, value.callerPackages)
		mergeSet(existing.callerSymbols, value.callerSymbols)
	}
}

func mergeSet(destination, source map[string]bool) {
	for key := range source {
		destination[key] = true
	}
}

func boolKeys(values map[string]bool) []string {
	result := make([]string, 0, len(values))
	for key, present := range values {
		if present {
			result = append(result, key)
		}
	}
	sort.Strings(result)
	return result
}

func sortedCopy(values []string) []string {
	result := append([]string(nil), values...)
	sort.Strings(result)
	return result
}

func standardLibraryRoot(packagePath string) string {
	if strings.HasPrefix(packagePath, "github.com/steveyegge/beads/") {
		return "github.com/steveyegge/beads"
	}
	parts := strings.Split(packagePath, "/")
	if len(parts) == 0 {
		return packagePath
	}
	if !strings.Contains(parts[0], ".") {
		if len(parts) > 1 && (parts[0] == "database" || parts[0] == "encoding" || parts[0] == "go" || parts[0] == "net") {
			return parts[0] + "/" + parts[1]
		}
		return parts[0]
	}
	return packagePath
}

func errorsForProfile(message string) error {
	return fmt.Errorf("%s", message)
}
