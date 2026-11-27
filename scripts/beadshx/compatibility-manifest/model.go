package main

// Manifest is the decoded compatibility manifest. JSON Schema validates its
// shape first; these types carry the values that the semantic checks join.
type Manifest struct {
	SchemaVersion     int               `json:"schemaVersion"`
	Identity          Identity          `json:"identity"`
	SourceInventories []SourceInventory `json:"sourceInventories"`
	Profiles          []Profile         `json:"profiles"`
	Capabilities      Registry          `json:"capabilities"`
	Operations        Registry          `json:"operations"`
	Outputs           Registry          `json:"outputs"`
	Errors            Registry          `json:"errors"`
	Data              Registry          `json:"data"`
	Effects           Registry          `json:"effects"`
	NativeBoundaries  Registry          `json:"nativeBoundaries"`
	Performance       Registry          `json:"performance"`
	WorkflowTiers     WorkflowTiers     `json:"workflowTiers"`
	Commands          []Command         `json:"commands"`
	Evidence          []Evidence        `json:"evidence"`
	Differences       []Difference      `json:"differences"`
	Waivers           []Waiver          `json:"waivers"`
}

// Identity pins the compatibility target and points at the locks that own it.
type Identity struct {
	ManifestID   string        `json:"manifestId"`
	Upstream     UpstreamPin   `json:"upstream"`
	SourceLock   LockReference `json:"sourceLock"`
	CompilerLock LockReference `json:"compilerLock"`
}

// UpstreamPin names the pinned upstream release.
type UpstreamPin struct {
	Project string `json:"project"`
	Version string `json:"version"`
	Commit  string `json:"commit"`
}

// LockReference is a JSON pointer into a repository lock file.
type LockReference struct {
	Path    string `json:"path"`
	Pointer string `json:"pointer"`
}

// SourceInventory is one digest-pinned M02 input.
type SourceInventory struct {
	ID            string `json:"id"`
	Task          string `json:"task"`
	Kind          string `json:"kind"`
	Path          string `json:"path"`
	Encoding      string `json:"encoding"`
	SchemaVersion int    `json:"schemaVersion,omitempty"`
	Sha256        string `json:"sha256"`
	CommitPointer string `json:"commitPointer,omitempty"`
}

// Profile is one command profile of the M02-01 inventory.
type Profile struct {
	ID               string   `json:"id"`
	Source           string   `json:"source"`
	GOOS             string   `json:"goos"`
	GOARCH           string   `json:"goarch"`
	CgoEnabled       bool     `json:"cgoEnabled"`
	BuildTags        []string `json:"buildTags"`
	RequirementState string   `json:"requirementState"`
}

// Registry holds records that commands reference by ID.
type Registry struct {
	State           string           `json:"state"`
	Owner           string           `json:"owner,omitempty"`
	CompleteAgainst []string         `json:"completeAgainst,omitempty"`
	Records         []RegistryRecord `json:"records,omitempty"`
}

// RegistryRecord is the union of the registry record shapes; the schema
// restricts which fields each registry may use.
type RegistryRecord struct {
	ID           string   `json:"id"`
	Source       string   `json:"source,omitempty"`
	Commands     []string `json:"commands,omitempty"`
	Capabilities []string `json:"capabilities,omitempty"`
	EffectRecipe string   `json:"effectRecipe,omitempty"`
	Kind         string   `json:"kind,omitempty"`
	Path         string   `json:"path,omitempty"`
}

// WorkflowTiers is the approved M02-09 ranking as a filtered view.
type WorkflowTiers struct {
	State                 string       `json:"state"`
	CompleteAgainst       []string     `json:"completeAgainst"`
	D0IsFullCompatibility bool         `json:"d0IsFullCompatibility"`
	Records               []TierRecord `json:"records"`
}

// TierRecord is one workflow tier.
type TierRecord struct {
	ID         string `json:"id"`
	Source     string `json:"source"`
	Assignment string `json:"assignment"`
}

// Command is the coverage record of one inventory command.
type Command struct {
	ID                  string         `json:"id"`
	Aliases             []string       `json:"aliases"`
	Hidden              bool           `json:"hidden"`
	Runnable            bool           `json:"runnable"`
	Profiles            []string       `json:"profiles"`
	Activations         []string       `json:"activations"`
	Operation           string         `json:"operation"`
	WorkflowTier        string         `json:"workflowTier"`
	RequirementState    string         `json:"requirementState"`
	OwnershipLane       string         `json:"ownershipLane"`
	ImplementationState string         `json:"implementationState"`
	Axes                Axes           `json:"axes"`
	Verification        []Verification `json:"verification"`
}

// Axes are the per-command reference axes.
type Axes struct {
	Outputs          Axis `json:"outputs"`
	Errors           Axis `json:"errors"`
	Data             Axis `json:"data"`
	Effects          Axis `json:"effects"`
	NativeBoundaries Axis `json:"nativeBoundaries"`
	Performance      Axis `json:"performance"`
}

// Axis is pending, listed, or proved none.
type Axis struct {
	State    string   `json:"state"`
	Owner    string   `json:"owner,omitempty"`
	Known    []string `json:"known,omitempty"`
	IDs      []string `json:"ids,omitempty"`
	Evidence []string `json:"evidence,omitempty"`
}

// Verification is the result of one command profile.
type Verification struct {
	Profile   string   `json:"profile"`
	State     string   `json:"state"`
	Coverage  string   `json:"coverage,omitempty"`
	BlockedBy string   `json:"blockedBy,omitempty"`
	Evidence  []string `json:"evidence,omitempty"`
	Scenarios []string `json:"scenarios,omitempty"`
}

// Evidence is a test, document, suite, or negative proof.
type Evidence struct {
	ID               string              `json:"id"`
	Kind             string              `json:"kind"`
	Path             string              `json:"path"`
	Description      string              `json:"description"`
	Sha256           string              `json:"sha256,omitempty"`
	ListsDifferences bool                `json:"listsDifferences,omitempty"`
	Lane             *Lane               `json:"lane,omitempty"`
	Profile          string              `json:"profile,omitempty"`
	Families         map[string][]string `json:"families,omitempty"`
	RefusalFamilies  map[string][]string `json:"refusalFamilies,omitempty"`
	Covers           []Cover             `json:"covers,omitempty"`
}

// Lane is the CI job that runs a differential suite.
type Lane struct {
	Workflow string `json:"workflow"`
	Job      string `json:"job"`
	Runner   string `json:"runner"`
}

// Cover names one command axis that negative evidence proves empty.
type Cover struct {
	Command string `json:"command"`
	Axis    string `json:"axis"`
}

// Difference is observed BeadsHX behavior that differs from upstream.
type Difference struct {
	ID           string           `json:"id"`
	Summary      string           `json:"summary"`
	Category     string           `json:"category"`
	Disposition  string           `json:"disposition"`
	TrackingTask string           `json:"trackingTask,omitempty"`
	Waiver       string           `json:"waiver,omitempty"`
	Affects      []string         `json:"affects"`
	Profiles     []string         `json:"profiles"`
	Source       DifferenceSource `json:"source"`
}

// DifferenceSource locates the difference in a reviewed document.
type DifferenceSource struct {
	Evidence string `json:"evidence"`
	Section  string `json:"section"`
	Quote    string `json:"quote"`
}

// Waiver is an exact, separately approved exception record.
type Waiver struct {
	ID                   string       `json:"id"`
	Status               string       `json:"status"`
	Differences          []string     `json:"differences"`
	Commands             []string     `json:"commands"`
	Profiles             []string     `json:"profiles"`
	UpstreamBehavior     string       `json:"upstreamBehavior"`
	BeadshxBehavior      string       `json:"beadshxBehavior"`
	UserImpact           string       `json:"userImpact"`
	MigrationImpact      string       `json:"migrationImpact"`
	Scenarios            []string     `json:"scenarios"`
	Tests                []string     `json:"tests"`
	Reason               string       `json:"reason"`
	RequesterDisposition string       `json:"requesterDisposition"`
	DecisionDate         string       `json:"decisionDate,omitempty"`
	OwnerRole            string       `json:"ownerRole"`
	ReviewTrigger        string       `json:"reviewTrigger"`
	ReviewTask           string       `json:"reviewTask,omitempty"`
	ReviewDate           string       `json:"reviewDate,omitempty"`
	RemovalCondition     string       `json:"removalCondition"`
	Rollback             string       `json:"rollback"`
	UpstreamFallback     string       `json:"upstreamFallback"`
	Source               WaiverSource `json:"source"`
}

// WaiverSource locates the approval record.
type WaiverSource struct {
	Evidence string `json:"evidence"`
	Section  string `json:"section"`
}
