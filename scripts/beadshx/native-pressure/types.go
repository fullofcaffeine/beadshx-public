package main

type policy struct {
	SchemaVersion      int                 `json:"schemaVersion"`
	Compatibility      sourceIdentity      `json:"compatibilityTarget"`
	CompilerEvidence   compilerEvidence    `json:"compilerEvidence"`
	GoVersion          string              `json:"goVersion"`
	FirstPartyPrefix   string              `json:"firstPartyPrefix"`
	RootPackages       []string            `json:"rootPackages"`
	Profiles           []buildProfile      `json:"profiles"`
	PressureAxes       []string            `json:"pressureAxes"`
	FeatureRanks       []featureRankPolicy `json:"featureRanks"`
	CompilerGaps       []compilerGap       `json:"compilerGaps"`
	BoundaryGroups     []boundaryGroup     `json:"boundaryGroups"`
	DependencyPolicies []dependencyPolicy  `json:"dependencyPolicies"`
}

type sourceIdentity struct {
	Project string `json:"project"`
	Version string `json:"version"`
	Commit  string `json:"commit"`
}

type compilerEvidence struct {
	Project string `json:"project"`
	Commit  string `json:"commit"`
	Policy  string `json:"policy"`
}

type buildProfile struct {
	ID         string   `json:"id"`
	GOOS       string   `json:"goos"`
	GOARCH     string   `json:"goarch"`
	CGOEnabled bool     `json:"cgoEnabled"`
	BuildTags  []string `json:"buildTags"`
}

type featureRankPolicy struct {
	ID       string   `json:"id"`
	Priority string   `json:"priority"`
	Axes     []string `json:"axes"`
	Decision string   `json:"decision"`
}

type compilerGap struct {
	ID          string   `json:"id"`
	Axes        []string `json:"axes"`
	Disposition string   `json:"disposition"`
	Need        string   `json:"need"`
}

type boundaryGroup struct {
	ID                 string   `json:"id"`
	CallerPackageRegex string   `json:"callerPackageRegex"`
	SemanticRole       string   `json:"semanticRole"`
	SelectedOwner      string   `json:"selectedOwner"`
	FacadeID           string   `json:"facadeId"`
	Severity           string   `json:"severity"`
	CommandProfiles    []string `json:"commandProfiles"`
	OperationIDs       []string `json:"operationIds"`
	EffectIDs          []string `json:"effectIds"`
	HaxeGoEvidence     []string `json:"haxeGoEvidence"`
	ReducedFixture     string   `json:"reducedFixture"`
	Waiver             *string  `json:"waiver"`
}

type dependencyPolicy struct {
	ID           string `json:"id"`
	PackageRegex string `json:"packageRegex"`
	Owner        string `json:"owner"`
	Severity     string `json:"severity"`
	Decision     string `json:"decision"`
}

type inventory struct {
	SchemaVersion    int                 `json:"schemaVersion"`
	Source           sourceIdentity      `json:"source"`
	CompilerEvidence compilerEvidence    `json:"compilerEvidence"`
	Toolchain        toolchainIdentity   `json:"toolchain"`
	Profiles         []buildProfile      `json:"profiles"`
	FeatureRanks     []featureRank       `json:"featureRanks"`
	Dependencies     []dependencySummary `json:"dependencies"`
	Boundaries       []boundaryRecord    `json:"boundaries"`
	Coverage         coverageSummary     `json:"coverage"`
}

type toolchainIdentity struct {
	Go       string `json:"go"`
	Analyzer string `json:"analyzer"`
}

type featureRank struct {
	ID            string         `json:"id"`
	Priority      string         `json:"priority"`
	Axes          []string       `json:"axes"`
	ObservedCount int            `json:"observedCount"`
	AxisCounts    map[string]int `json:"axisCounts"`
	Decision      string         `json:"decision"`
}

type dependencySummary struct {
	PackageRoot   string         `json:"packageRoot"`
	PolicyID      string         `json:"policyId"`
	Owner         string         `json:"owner"`
	Severity      string         `json:"severity"`
	Decision      string         `json:"decision"`
	BoundaryCount int            `json:"boundaryCount"`
	AxisCounts    map[string]int `json:"axisCounts"`
}

type boundaryRecord struct {
	ID                  string   `json:"id"`
	SourceLocators      []string `json:"sourceLocators"`
	CallerPackages      []string `json:"callerPackages"`
	CallerSymbols       []string `json:"callerSymbols"`
	TargetPackage       string   `json:"targetPackage"`
	TargetSymbol        string   `json:"targetSymbol"`
	NormalizedSignature string   `json:"normalizedSignature"`
	CommandProfiles     []string `json:"commandProfiles"`
	OperationIDs        []string `json:"operationIds"`
	EffectIDs           []string `json:"effectIds"`
	BuildProfiles       []string `json:"buildProfiles"`
	SemanticRole        string   `json:"semanticRole"`
	PressureAxes        []string `json:"pressureAxes"`
	SelectedOwner       string   `json:"selectedOwner"`
	FacadeID            string   `json:"facadeId"`
	HaxeGoEvidence      []string `json:"haxeGoEvidence"`
	LinkedGaps          []string `json:"linkedGaps"`
	Severity            string   `json:"severity"`
	ReducedFixture      string   `json:"reducedFixture"`
	Waiver              *string  `json:"waiver"`
}

type coverageSummary struct {
	ProfileCount                int            `json:"profileCount"`
	ReachableFirstPartyPackages int            `json:"reachableFirstPartyPackages"`
	BoundaryPackageCount        int            `json:"boundaryPackageCount"`
	BoundaryCount               int            `json:"boundaryCount"`
	BoundariesByAxis            map[string]int `json:"boundariesByAxis"`
	UnmappedBoundaryCalls       int            `json:"unmappedBoundaryCalls"`
	UnmappedEffects             int            `json:"unmappedEffects"`
	UnmappedProfiles            int            `json:"unmappedProfiles"`
	UnmappedOperations          int            `json:"unmappedOperations"`
}
