package main

type inventory struct {
	SchemaVersion int                `json:"schemaVersion"`
	Source        sourceIdentity     `json:"source"`
	Toolchain     toolchainIdentity  `json:"toolchain"`
	Profiles      []profile          `json:"profiles"`
	Activations   []string           `json:"activations"`
	Snapshots     []runtimeSnapshot  `json:"snapshots"`
	Obligations   []sourceObligation `json:"sourceObligations"`
	Semantics     semanticCatalog    `json:"semantics"`
	Coverage      coverageSummary    `json:"coverage"`
}

type sourceIdentity struct {
	Project string `json:"project"`
	Version string `json:"version"`
	Commit  string `json:"commit"`
}

type toolchainIdentity struct {
	Go    string `json:"go"`
	Cobra string `json:"cobra"`
}

type profile struct {
	ID         string   `json:"id"`
	GOOS       string   `json:"goos"`
	GOARCH     string   `json:"goarch"`
	CGOEnabled bool     `json:"cgoEnabled"`
	BuildTags  []string `json:"buildTags"`
}

type runtimeSnapshot struct {
	Profile     string            `json:"profile"`
	Activation  string            `json:"activation"`
	Commands    []commandRecord   `json:"commands"`
	Flags       []flagDeclaration `json:"flagDeclarations"`
	GlobalFlags []string          `json:"unexpectedGlobalFlags"`
}

type commandRecord struct {
	ID                   string               `json:"id"`
	ParentID             string               `json:"parentId,omitempty"`
	Name                 string               `json:"name"`
	Path                 string               `json:"path"`
	Origin               string               `json:"origin"`
	Aliases              []string             `json:"aliases"`
	SuggestFor           []string             `json:"suggestFor"`
	GroupID              string               `json:"groupId,omitempty"`
	Hidden               bool                 `json:"hidden"`
	Deprecated           string               `json:"deprecated,omitempty"`
	Runnable             bool                 `json:"runnable"`
	HasArgsValidator     bool                 `json:"hasArgsValidator"`
	HasValidArgsFunction bool                 `json:"hasValidArgsFunction"`
	ValidArgs            []string             `json:"validArgs"`
	ArgAliases           []string             `json:"argAliases"`
	LocalFlagRefs        []string             `json:"localFlagRefs"`
	PersistentFlagRefs   []string             `json:"persistentFlagRefs"`
	InheritedFlagRefs    []string             `json:"inheritedFlagRefs"`
	EffectiveFlagRefs    []string             `json:"effectiveFlagRefs"`
	SemanticDispositions semanticDispositions `json:"semanticDispositions"`
}

type semanticDispositions struct {
	Environment string `json:"environment"`
	Stdin       string `json:"stdin"`
	Output      string `json:"output"`
	Completion  string `json:"completion"`
}

type flagDeclaration struct {
	ID                    string           `json:"id"`
	CommandID             string           `json:"commandId"`
	Scope                 string           `json:"scope"`
	Name                  string           `json:"name"`
	Shorthand             string           `json:"shorthand,omitempty"`
	Type                  string           `json:"type"`
	Default               string           `json:"default"`
	NoOptionDefault       string           `json:"noOptionDefault,omitempty"`
	Usage                 string           `json:"usage"`
	Hidden                bool             `json:"hidden"`
	Deprecated            string           `json:"deprecated,omitempty"`
	Annotations           []flagAnnotation `json:"annotations"`
	HasCompletionFunction bool             `json:"hasCompletionFunction"`
}

type flagAnnotation struct {
	Name   string   `json:"name"`
	Values []string `json:"values"`
}

type sourceObligation struct {
	ID             string   `json:"id"`
	Kind           string   `json:"kind"`
	Path           string   `json:"path"`
	Line           int      `json:"line"`
	Column         int      `json:"column"`
	Symbol         string   `json:"symbol"`
	Expression     string   `json:"expression"`
	SnippetSHA256  string   `json:"snippetSha256"`
	ActiveProfiles []string `json:"activeProfiles"`
	Resolution     string   `json:"resolution"`
}

type semanticCatalog struct {
	ReviewerRole       string             `json:"reviewerRole"`
	SourceClosure      string             `json:"sourceClosure"`
	OutputBoundary     string             `json:"outputBoundary"`
	ExclusionAuthority string             `json:"exclusionAuthority"`
	ObligationPolicies []obligationPolicy `json:"obligationPolicies"`
	Rules              []semanticRule     `json:"rules"`
}

type obligationPolicy struct {
	Kind       string `json:"kind"`
	Resolution string `json:"resolution"`
}

type semanticRule struct {
	ID       string   `json:"id"`
	Kind     string   `json:"kind"`
	Summary  string   `json:"summary"`
	Evidence []string `json:"evidence"`
}

type coverageSummary struct {
	SnapshotCount     int            `json:"snapshotCount"`
	CommandInstances  int            `json:"commandInstances"`
	FlagDeclarations  int            `json:"flagDeclarations"`
	ObligationCount   int            `json:"obligationCount"`
	ObligationsByKind map[string]int `json:"obligationsByKind"`
	Unresolved        int            `json:"unresolved"`
	Orphaned          int            `json:"orphaned"`
	Conflicting       int            `json:"conflicting"`
	UnexpectedGlobal  int            `json:"unexpectedGlobalFlags"`
}

type inventoryPolicy struct {
	SchemaVersion int             `json:"schemaVersion"`
	SourceCommit  string          `json:"sourceCommit"`
	GoVersion     string          `json:"goVersion"`
	CobraVersion  string          `json:"cobraVersion"`
	Container     string          `json:"container"`
	Profiles      []profile       `json:"profiles"`
	Activations   []string        `json:"activations"`
	Semantics     semanticCatalog `json:"semantics"`
}
