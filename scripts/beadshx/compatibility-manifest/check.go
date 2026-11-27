package main

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
)

// Record kinds that references must resolve to.
const (
	kindInventory     = "source inventory"
	kindProfile       = "profile"
	kindCapability    = "capability"
	kindOperation     = "operation"
	kindOutput        = "output"
	kindError         = "error"
	kindData          = "data"
	kindEffect        = "effect"
	kindNative        = "native boundary"
	kindPerformance   = "performance"
	kindTier          = "workflow tier"
	kindCommand       = "command"
	kindEvidence      = "evidence"
	kindDifference    = "difference"
	kindWaiver        = "waiver"
	axisOutputs       = "outputs"
	axisErrors        = "errors"
	axisData          = "data"
	axisEffects       = "effects"
	axisNative        = "nativeBoundaries"
	axisPerformance   = "performance"
	statePending      = "pending"
	stateComplete     = "complete"
	verificationPass  = "pass"
	dispositionWaived = "waived"
	waiverApproved    = "approved"
)

var axisKinds = map[string]string{
	axisOutputs:     kindOutput,
	axisErrors:      kindError,
	axisData:        kindData,
	axisEffects:     kindEffect,
	axisNative:      kindNative,
	axisPerformance: kindPerformance,
}

var nonWaivable = map[string]bool{
	"production-data-safety": true,
	"native-readback":        true,
	"licensing":              true,
	"provenance":             true,
	"recovery":               true,
}

var isoDate = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}$`)

// checker runs the semantic rules that JSON Schema cannot express.
type checker struct {
	manifest    Manifest
	repo        repository
	asOf        string
	errors      []string
	kinds       map[string]string
	inventories map[string]any
	byKind      map[string]string // inventory kind -> inventory ID
	commandView inventoryView
	haveView    bool
	suites      map[string]suiteIndex
	documents   map[string]string
	evidence    map[string]Evidence
	differences map[string]Difference
	waivers     map[string]Waiver
	commands    map[string]Command
	profiles    map[string]Profile
}

func (c *checker) fail(format string, args ...any) {
	c.errors = append(c.errors, fmt.Sprintf(format, args...))
}

func newChecker(manifest Manifest, repo repository, asOf string) *checker {
	return &checker{
		manifest:    manifest,
		repo:        repo,
		asOf:        asOf,
		kinds:       map[string]string{},
		inventories: map[string]any{},
		byKind:      map[string]string{},
		suites:      map[string]suiteIndex{},
		documents:   map[string]string{},
		evidence:    map[string]Evidence{},
		differences: map[string]Difference{},
		waivers:     map[string]Waiver{},
		commands:    map[string]Command{},
		profiles:    map[string]Profile{},
	}
}

func (c *checker) run() []string {
	c.indexIDs()
	c.checkIdentity()
	c.checkSourceInventories()
	c.checkProfiles()
	c.checkRegistries()
	c.checkWorkflowTiers()
	c.checkEvidence()
	c.checkCommands()
	c.checkDifferences()
	c.checkWaivers()
	return c.errors
}

// register records a unique ID of one kind.
func (c *checker) register(id, kind string) {
	if previous, ok := c.kinds[id]; ok {
		c.fail("duplicate ID: %s is recorded as %s and again as %s", id, previous, kind)
		return
	}
	c.kinds[id] = kind
}

// requireSorted reports a list whose IDs are not unique and in byte order.
func (c *checker) requireSorted(where string, ids []string) {
	for index := 1; index < len(ids); index++ {
		if ids[index-1] == ids[index] {
			c.fail("duplicate ID in %s: %s", where, ids[index])
		} else if ids[index-1] > ids[index] {
			c.fail("unsorted IDs in %s: %s must come before %s", where, ids[index], ids[index-1])
		}
	}
}

// resolve reports a dangling reference or one to the wrong record kind.
func (c *checker) resolve(owner, field, ref string, want ...string) bool {
	kind, ok := c.kinds[ref]
	if !ok {
		c.fail("dangling reference: %s %s -> %s", owner, field, ref)
		return false
	}
	for _, allowed := range want {
		if kind == allowed {
			return true
		}
	}
	c.fail("wrong record kind: %s %s -> %s has kind %s, want %s", owner, field, ref, kind, strings.Join(want, " or "))
	return false
}

func registryKinds() []struct {
	name string
	kind string
	get  func(Manifest) Registry
} {
	return []struct {
		name string
		kind string
		get  func(Manifest) Registry
	}{
		{"capabilities", kindCapability, func(m Manifest) Registry { return m.Capabilities }},
		{"operations", kindOperation, func(m Manifest) Registry { return m.Operations }},
		{"outputs", kindOutput, func(m Manifest) Registry { return m.Outputs }},
		{"errors", kindError, func(m Manifest) Registry { return m.Errors }},
		{"data", kindData, func(m Manifest) Registry { return m.Data }},
		{"effects", kindEffect, func(m Manifest) Registry { return m.Effects }},
		{"nativeBoundaries", kindNative, func(m Manifest) Registry { return m.NativeBoundaries }},
		{"performance", kindPerformance, func(m Manifest) Registry { return m.Performance }},
	}
}

func (c *checker) indexIDs() {
	m := c.manifest
	ids := func(n int, at func(int) string) []string {
		out := make([]string, n)
		for i := range out {
			out[i] = at(i)
		}
		return out
	}
	c.requireSorted("sourceInventories", ids(len(m.SourceInventories), func(i int) string { return m.SourceInventories[i].ID }))
	for _, inventory := range m.SourceInventories {
		c.register(inventory.ID, kindInventory)
	}
	c.requireSorted("profiles", ids(len(m.Profiles), func(i int) string { return m.Profiles[i].ID }))
	for _, profile := range m.Profiles {
		c.register(profile.ID, kindProfile)
		c.profiles[profile.ID] = profile
	}
	for _, registry := range registryKinds() {
		records := registry.get(m).Records
		c.requireSorted(registry.name, ids(len(records), func(i int) string { return records[i].ID }))
		for _, record := range records {
			c.register(record.ID, registry.kind)
		}
	}
	tiers := m.WorkflowTiers.Records
	c.requireSorted("workflowTiers", ids(len(tiers), func(i int) string { return tiers[i].ID }))
	for _, tier := range tiers {
		c.register(tier.ID, kindTier)
	}
	c.requireSorted("commands", ids(len(m.Commands), func(i int) string { return m.Commands[i].ID }))
	for _, command := range m.Commands {
		c.register(command.ID, kindCommand)
		c.commands[command.ID] = command
	}
	c.requireSorted("evidence", ids(len(m.Evidence), func(i int) string { return m.Evidence[i].ID }))
	for _, evidence := range m.Evidence {
		c.register(evidence.ID, kindEvidence)
		c.evidence[evidence.ID] = evidence
	}
	c.requireSorted("differences", ids(len(m.Differences), func(i int) string { return m.Differences[i].ID }))
	for _, difference := range m.Differences {
		c.register(difference.ID, kindDifference)
		c.differences[difference.ID] = difference
	}
	c.requireSorted("waivers", ids(len(m.Waivers), func(i int) string { return m.Waivers[i].ID }))
	for _, waiver := range m.Waivers {
		c.register(waiver.ID, kindWaiver)
		c.waivers[waiver.ID] = waiver
	}
}

func (c *checker) loadJSONFile(path, encoding string) (any, []byte, bool) {
	content, err := c.repo.read(path)
	if err != nil {
		c.fail("unreadable file: %s: %v", path, err)
		return nil, nil, false
	}
	document, err := decodeJSON(content, encoding)
	if err != nil {
		c.fail("undecodable file: %s: %v", path, err)
		return nil, content, false
	}
	return document, content, true
}

func (c *checker) checkIdentity() {
	identity := c.manifest.Identity
	if identity.ManifestID != "beads-"+identity.Upstream.Version {
		c.fail("identity: manifestId %s does not name upstream version %s", identity.ManifestID, identity.Upstream.Version)
	}
	lock, _, ok := c.loadJSONFile(identity.SourceLock.Path, "json")
	if ok {
		target, found := jsonPointer(lock, identity.SourceLock.Pointer)
		object, isObject := target.(map[string]any)
		switch {
		case !found || !isObject:
			c.fail("identity: source lock pointer %s%s does not resolve to an object", identity.SourceLock.Path, identity.SourceLock.Pointer)
		default:
			for field, want := range map[string]string{
				"project": identity.Upstream.Project,
				"version": identity.Upstream.Version,
				"commit":  identity.Upstream.Commit,
			} {
				if got := stringValue(object[field]); got != want {
					c.fail("identity: upstream %s %q does not match source lock %q", field, want, got)
				}
			}
		}
	}
	compiler, _, ok := c.loadJSONFile(identity.CompilerLock.Path, "json")
	if ok {
		value, found := jsonPointer(compiler, identity.CompilerLock.Pointer)
		if revision := stringValue(value); !found || !regexp.MustCompile(`^[0-9a-f]{40}$`).MatchString(revision) {
			c.fail("identity: compiler lock pointer %s%s does not resolve to a commit", identity.CompilerLock.Path, identity.CompilerLock.Pointer)
		}
	}
}

func (c *checker) checkSourceInventories() {
	for _, inventory := range c.manifest.SourceInventories {
		if previous, ok := c.byKind[inventory.Kind]; ok {
			c.fail("source inventory kind %s is recorded twice: %s and %s", inventory.Kind, previous, inventory.ID)
		}
		c.byKind[inventory.Kind] = inventory.ID
		document, content, ok := c.loadJSONFile(inventory.Path, inventory.Encoding)
		if content != nil {
			if digest := sha256Hex(content); digest != inventory.Sha256 {
				c.fail("stale source inventory: %s %s has sha256 %s, manifest records %s", inventory.ID, inventory.Path, digest, inventory.Sha256)
			}
		}
		if !ok {
			continue
		}
		c.inventories[inventory.ID] = document
		if inventory.SchemaVersion != 0 {
			if got, _ := jsonPointer(document, "/schemaVersion"); stringValue(got) != fmt.Sprint(inventory.SchemaVersion) {
				c.fail("source inventory %s schemaVersion is %s, manifest records %d", inventory.ID, stringValue(got), inventory.SchemaVersion)
			}
		}
		if inventory.CommitPointer != "" {
			value, found := jsonPointer(document, inventory.CommitPointer)
			if got := stringValue(value); !found || got != c.manifest.Identity.Upstream.Commit {
				c.fail("source inventory %s commit %s%s is %q, not the pinned upstream commit", inventory.ID, inventory.Path, inventory.CommitPointer, got)
			}
		}
		if inventory.Kind == "command-inventory" {
			view, err := loadCommandInventory(content)
			if err != nil {
				c.fail("undecodable command inventory %s: %v", inventory.Path, err)
				continue
			}
			c.commandView = view
			c.haveView = true
		}
	}
	for _, kind := range []string{"command-inventory", "command-policy", "storage-contracts", "effect-contracts", "daily-workflow"} {
		if _, ok := c.byKind[kind]; !ok {
			c.fail("source inventory of kind %s is missing", kind)
		}
	}
}

// sourceRecord resolves <inventory>#<collection>/<id>.
func (c *checker) sourceRecord(owner, ref string) (map[string]any, bool) {
	inventory, collection, id, ok := splitSourceRef(ref)
	if !ok || id == "" {
		c.fail("malformed source reference: %s -> %s", owner, ref)
		return nil, false
	}
	if !c.resolve(owner, "source", inventory, kindInventory) {
		return nil, false
	}
	document, ok := c.inventories[inventory]
	if !ok {
		return nil, false
	}
	records, ok := collectionRecords(document, collection)
	if !ok {
		c.fail("dangling source reference: %s -> %s: %s has no collection %s", owner, ref, inventory, collection)
		return nil, false
	}
	record, ok := records[id]
	if !ok {
		c.fail("dangling source reference: %s -> %s: %s#%s has no record %s", owner, ref, inventory, collection, id)
		return nil, false
	}
	object, _ := record.(map[string]any)
	return object, true
}

func (c *checker) checkProfiles() {
	if id, ok := c.byKind["command-policy"]; ok {
		resolved := map[string]bool{}
		for _, profile := range c.manifest.Profiles {
			resolved[profile.Source] = true
		}
		c.checkComplete("profiles", []string{id + "#profiles"}, resolved)
	}
	for _, profile := range c.manifest.Profiles {
		if profile.RequirementState != "required" {
			c.fail("profile requirement dropped: %s is %s; every M02-01 profile is required", profile.ID, profile.RequirementState)
		}
		source, ok := c.sourceRecord(profile.ID, profile.Source)
		if !ok || source == nil {
			continue
		}
		if stringValue(source["goos"]) != profile.GOOS || stringValue(source["goarch"]) != profile.GOARCH ||
			stringValue(source["cgoEnabled"]) != fmt.Sprint(profile.CgoEnabled) ||
			strings.Join(stringList(source["buildTags"]), ",") != strings.Join(profile.BuildTags, ",") {
			c.fail("profile %s differs from its source %s", profile.ID, profile.Source)
		}
		if _, _, id, _ := splitSourceRef(profile.Source); "prof:"+id != profile.ID {
			c.fail("profile %s does not carry the inventory profile ID of %s", profile.ID, profile.Source)
		}
	}
}

func (c *checker) checkRegistries() {
	for _, registry := range registryKinds() {
		value := registry.get(c.manifest)
		resolved := map[string]bool{}
		for _, record := range value.Records {
			owner := registry.name + " " + record.ID
			if record.Source != "" {
				if _, ok := c.sourceRecord(owner, record.Source); ok {
					resolved[record.Source] = true
				}
			}
			c.requireSorted(owner+" commands", record.Commands)
			for _, command := range record.Commands {
				c.resolve(owner, "commands", command, kindCommand)
			}
			c.requireSorted(owner+" capabilities", record.Capabilities)
			for _, capability := range record.Capabilities {
				c.resolve(owner, "capabilities", capability, kindCapability)
			}
			if record.EffectRecipe != "" {
				c.sourceRecord(owner+" effectRecipe", record.EffectRecipe)
			}
			if record.Kind == "go_facade" && !c.repo.isDir(record.Path) {
				c.fail("stale native boundary: %s path %s is not a directory", record.ID, record.Path)
			}
			c.checkRecordEcho(registry.name, record)
		}
		if value.State == stateComplete {
			c.checkComplete(registry.name, value.CompleteAgainst, resolved)
		}
	}
}

// checkRecordEcho compares copied facts with their source record.
func (c *checker) checkRecordEcho(registry string, record RegistryRecord) {
	if record.Source == "" {
		return
	}
	inventory, _, _, _ := splitSourceRef(record.Source)
	document := c.inventories[inventory]
	source, ok := c.quietSourceRecord(record.Source, document)
	if !ok {
		return
	}
	switch registry {
	case "operations":
		var want []string
		for _, capability := range stringList(source["capabilities"]) {
			want = append(want, "cap:"+capability)
		}
		sort.Strings(want)
		if strings.Join(want, ",") != strings.Join(record.Capabilities, ",") {
			c.fail("operation %s capabilities %v differ from %s %v", record.ID, record.Capabilities, record.Source, want)
		}
	case "outputs", "errors":
		if command := stringValue(source["commandId"]); command != "" {
			if len(record.Commands) != 1 || record.Commands[0] != command {
				c.fail("%s record %s commands %v differ from its source command %s", registry, record.ID, record.Commands, command)
			}
		}
	}
}

func (c *checker) quietSourceRecord(ref string, document any) (map[string]any, bool) {
	_, collection, id, ok := splitSourceRef(ref)
	if !ok || document == nil {
		return nil, false
	}
	records, ok := collectionRecords(document, collection)
	if !ok {
		return nil, false
	}
	object, ok := records[id].(map[string]any)
	return object, ok
}

// checkComplete proves that a complete registry lists every source record.
func (c *checker) checkComplete(name string, collections []string, resolved map[string]bool) {
	want := map[string]bool{}
	for _, ref := range collections {
		inventory, collection, _, ok := splitSourceRef(ref)
		if !ok || !c.resolve(name, "completeAgainst", inventory, kindInventory) {
			continue
		}
		records, ok := collectionRecords(c.inventories[inventory], collection)
		if !ok {
			c.fail("dangling source reference: %s completeAgainst -> %s", name, ref)
			continue
		}
		for id := range records {
			want[inventory+"#"+collection+"/"+id] = true
		}
	}
	for _, ref := range sortedKeys(want) {
		if !resolved[ref] {
			c.fail("incomplete registry: %s is complete but has no record for %s", name, ref)
		}
	}
	for _, ref := range sortedKeys(resolved) {
		if !want[ref] {
			c.fail("incomplete registry: %s is complete but %s is outside its completeAgainst collections", name, ref)
		}
	}
}

func (c *checker) checkWorkflowTiers() {
	tiers := c.manifest.WorkflowTiers
	resolved := map[string]bool{}
	for _, tier := range tiers.Records {
		if _, ok := c.sourceRecord(tier.ID, tier.Source); ok {
			resolved[tier.Source] = true
		}
		if _, _, id, _ := splitSourceRef(tier.Source); "tier:"+id != tier.ID {
			c.fail("workflow tier %s does not carry the tier ID of %s", tier.ID, tier.Source)
		}
	}
	c.checkComplete("workflowTiers", tiers.CompleteAgainst, resolved)
	if tiers.D0IsFullCompatibility {
		c.fail("D0 counted as full coverage: workflowTiers.d0IsFullCompatibility is true; a workflow tier is a filtered view and never the full-compatibility denominator")
	}
	if id, ok := c.byKind["daily-workflow"]; ok {
		if value, found := jsonPointer(c.inventories[id], "/scope/d0IsFullCompatibility"); !found || stringValue(value) != fmt.Sprint(tiers.D0IsFullCompatibility) {
			c.fail("workflowTiers.d0IsFullCompatibility does not match %s /scope/d0IsFullCompatibility", id)
		}
	}
}

// expectedTiers maps each command to the tier M02-09 assigns.
func (c *checker) expectedTiers() map[string]string {
	assigned := map[string]string{}
	remaining := ""
	for _, tier := range c.manifest.WorkflowTiers.Records {
		if tier.Assignment == "remaining-commands" {
			remaining = tier.ID
			continue
		}
		inventory, _, _, _ := splitSourceRef(tier.Source)
		source, ok := c.quietSourceRecord(tier.Source, c.inventories[inventory])
		if !ok {
			continue
		}
		for _, command := range stringList(source["commands"]) {
			assigned[command] = tier.ID
		}
	}
	for id := range c.commands {
		if _, ok := assigned[id]; !ok {
			assigned[id] = remaining
		}
	}
	return assigned
}

func (c *checker) checkEvidence() {
	for _, evidence := range c.manifest.Evidence {
		content, err := c.repo.read(evidence.Path)
		if err != nil {
			c.fail("stale evidence: %s path %s is unreadable: %v", evidence.ID, evidence.Path, err)
			continue
		}
		if evidence.Sha256 != "" {
			if digest := sha256Hex(content); digest != evidence.Sha256 {
				c.fail("stale evidence: %s %s has sha256 %s, manifest records %s", evidence.ID, evidence.Path, digest, evidence.Sha256)
			}
		}
		switch evidence.Kind {
		case "document":
			c.documents[evidence.ID] = string(content)
		case "differential-suite":
			c.checkSuite(evidence, content)
		case "negative":
			for _, cover := range evidence.Covers {
				c.resolve(evidence.ID, "covers", cover.Command, kindCommand)
			}
		}
	}
}

func (c *checker) checkSuite(evidence Evidence, content []byte) {
	index := indexSuite(content, evidence.Families, evidence.RefusalFamilies)
	c.suites[evidence.ID] = index
	for _, families := range []map[string][]string{evidence.Families, evidence.RefusalFamilies} {
		for _, family := range sortedKeys(families) {
			for _, helper := range families[family] {
				if !index.defined[helper] {
					c.fail("stale evidence: %s family %s names helper %s, which %s does not define", evidence.ID, family, helper, evidence.Path)
				}
			}
		}
	}
	c.resolve(evidence.ID, "profile", evidence.Profile, kindProfile)
	lane := evidence.Lane
	workflow, err := c.repo.read(lane.Workflow)
	if err != nil || !strings.Contains(string(workflow), "\n  "+lane.Job+":\n") {
		c.fail("stale evidence: %s lane job %s is not a job of %s", evidence.ID, lane.Job, lane.Workflow)
	}
	runner, err := c.repo.read(lane.Runner)
	if err != nil || !strings.Contains(string(runner), evidence.Path[strings.LastIndex(evidence.Path, "/")+1:]) {
		c.fail("stale evidence: %s lane runner %s does not run %s", evidence.ID, lane.Runner, evidence.Path)
	}
}

// operationRoots maps an M02-04 command root to its storage profile.
func (c *checker) operationRoots() map[string][]string {
	roots := map[string][]string{}
	id, ok := c.byKind["storage-contracts"]
	if !ok {
		return roots
	}
	profiles, ok := collectionRecords(c.inventories[id], "commandProfiles")
	if !ok {
		return roots
	}
	for _, name := range sortedKeys(profiles) {
		object, _ := profiles[name].(map[string]any)
		for _, root := range stringList(object["roots"]) {
			roots[root] = append(roots[root], "op:"+name)
		}
	}
	return roots
}

func commandRoot(id string) string {
	path := strings.TrimPrefix(id, "cmd:bd")
	if path == "" {
		return "<root>"
	}
	root, _, _ := strings.Cut(strings.TrimPrefix(path, "/"), "/")
	return root
}

func (c *checker) checkCommands() {
	if c.haveView {
		for _, id := range sortedKeys(c.commandView.commands) {
			if _, ok := c.commands[id]; !ok {
				c.fail("inventory command missing from manifest: %s", id)
			}
		}
	}
	roots := c.operationRoots()
	tiers := c.expectedTiers()
	for _, command := range c.manifest.Commands {
		c.checkInventoryEcho(command)
		c.requireSorted(command.ID+" profiles", command.Profiles)
		c.requireSorted(command.ID+" activations", command.Activations)
		for _, profile := range command.Profiles {
			c.resolve(command.ID, "profiles", profile, kindProfile)
		}
		if c.resolve(command.ID, "operation", command.Operation, kindOperation) {
			if want := roots[commandRoot(command.ID)]; len(want) != 1 || want[0] != command.Operation {
				c.fail("operation differs from M02-04: %s is %s, the storage contracts map root %s to %v", command.ID, command.Operation, commandRoot(command.ID), want)
			}
		}
		if c.resolve(command.ID, "workflowTier", command.WorkflowTier, kindTier) && tiers[command.ID] != command.WorkflowTier {
			c.fail("workflow tier differs from M02-09: %s is %s, the approved profile assigns %s", command.ID, command.WorkflowTier, tiers[command.ID])
		}
		c.checkAxes(command)
		c.checkVerification(command)
		c.checkStates(command)
	}
}

func (c *checker) checkInventoryEcho(command Command) {
	if !c.haveView {
		return
	}
	source, ok := c.commandView.commands[command.ID]
	if !ok {
		c.fail("manifest-only command not in inventory: %s", command.ID)
		return
	}
	aliases := append([]string(nil), source.Aliases...)
	sort.Strings(aliases)
	if strings.Join(aliases, ",") != strings.Join(command.Aliases, ",") {
		c.fail("inventory echo differs: %s aliases %v, inventory %v", command.ID, command.Aliases, aliases)
	}
	if source.Hidden != command.Hidden {
		c.fail("inventory echo differs: %s hidden %t, inventory %t", command.ID, command.Hidden, source.Hidden)
	}
	if source.Runnable != command.Runnable {
		c.fail("inventory echo differs: %s runnable %t, inventory %t", command.ID, command.Runnable, source.Runnable)
	}
	declared := map[string]bool{}
	for _, profile := range command.Profiles {
		for _, activation := range command.Activations {
			declared[strings.TrimPrefix(profile, "prof:")+"/"+activation] = true
		}
	}
	for _, instance := range sortedKeys(c.commandView.instances[command.ID]) {
		if !declared[instance] {
			c.fail("command-profile set differs: %s@%s is in the inventory but not the manifest", command.ID, instance)
		}
	}
	for _, instance := range sortedKeys(declared) {
		if !c.commandView.instances[command.ID][instance] {
			c.fail("command-profile set differs: %s@%s is in the manifest but not the inventory", command.ID, instance)
		}
	}
}

func (c *checker) checkAxes(command Command) {
	operationSteps := c.alwaysEffects(command.Operation)
	for _, entry := range []struct {
		name string
		axis Axis
	}{
		{axisOutputs, command.Axes.Outputs},
		{axisErrors, command.Axes.Errors},
		{axisData, command.Axes.Data},
		{axisEffects, command.Axes.Effects},
		{axisNative, command.Axes.NativeBoundaries},
		{axisPerformance, command.Axes.Performance},
	} {
		owner := command.ID + " " + entry.name
		want := axisKinds[entry.name]
		c.requireSorted(owner+" known", entry.axis.Known)
		c.requireSorted(owner+" ids", entry.axis.IDs)
		c.requireSorted(owner+" evidence", entry.axis.Evidence)
		for _, id := range append(append([]string(nil), entry.axis.Known...), entry.axis.IDs...) {
			c.resolve(owner, "record", id, want)
		}
		for _, ref := range entry.axis.Evidence {
			c.resolve(owner, "evidence", ref, kindEvidence, kindInventory)
		}
		if entry.axis.State != "none" {
			continue
		}
		for _, ref := range entry.axis.Evidence {
			evidence, ok := c.evidence[ref]
			covered := false
			for _, cover := range evidence.Covers {
				covered = covered || (cover.Command == command.ID && cover.Axis == entry.name)
			}
			if !ok || evidence.Kind != "negative" || !covered {
				c.fail("false none claim: %s %s cites %s, which is not negative evidence covering it", command.ID, entry.name, ref)
			}
		}
		if entry.name == axisEffects && len(operationSteps) > 0 {
			c.fail("false none claim: %s effects is none, but its operation %s always runs %s", command.ID, command.Operation, strings.Join(operationSteps, ", "))
		}
	}
}

// alwaysEffects lists the unconditional effect steps of an operation's recipe.
func (c *checker) alwaysEffects(operation string) []string {
	for _, record := range c.manifest.Operations.Records {
		if record.ID != operation || record.EffectRecipe == "" {
			continue
		}
		inventory, _, _, _ := splitSourceRef(record.EffectRecipe)
		recipe, ok := c.quietSourceRecord(record.EffectRecipe, c.inventories[inventory])
		if !ok {
			return nil
		}
		var effects []string
		steps, _ := recipe["steps"].([]any)
		for _, step := range steps {
			object, _ := step.(map[string]any)
			if stringValue(object["condition"]) == "always" {
				effects = append(effects, stringValue(object["effectId"]))
			}
		}
		return effects
	}
	return nil
}

func (c *checker) checkVerification(command Command) {
	seen := map[string]bool{}
	allowed := map[string]bool{}
	for _, profile := range command.Profiles {
		allowed[profile] = true
	}
	for _, result := range command.Verification {
		owner := command.ID + "@" + strings.TrimPrefix(result.Profile, "prof:")
		if seen[result.Profile] {
			c.fail("duplicate verification: %s", owner)
		}
		seen[result.Profile] = true
		if !allowed[result.Profile] {
			c.fail("verification for a profile the command lacks: %s", owner)
		}
		c.requireSorted(owner+" evidence", result.Evidence)
		c.requireSorted(owner+" scenarios", result.Scenarios)
		var suites []string
		for _, ref := range result.Evidence {
			if !c.resolve(owner, "evidence", ref, kindEvidence, kindInventory) {
				continue
			}
			evidence := c.evidence[ref]
			if evidence.Kind == "dogfood" && result.State == verificationPass {
				c.fail("D0 counted as full coverage: %s passes on dogfood evidence %s", owner, ref)
			}
			if evidence.Kind == "differential-suite" {
				suites = append(suites, ref)
				if evidence.Profile != result.Profile {
					c.fail("evidence profile mismatch: %s cites %s, which verifies %s", owner, ref, evidence.Profile)
				}
			}
		}
		for _, scenario := range result.Scenarios {
			kind := ""
			for _, suite := range suites {
				if found := c.suites[suite].scenarios[scenario]; found != "" {
					kind = found
				}
			}
			switch kind {
			case "":
				c.fail("stale evidence: %s cites scenario %s, which no cited differential suite defines", owner, scenario)
			case scenarioRefusal:
				c.fail("refusal scenario counted as parity: %s cites %s, which checks BeadsHX-only behavior", owner, scenario)
			}
		}
		if result.State == verificationPass {
			if len(suites) == 0 {
				c.fail("pass without differential evidence: %s", owner)
			}
			if result.Coverage == stateComplete && (command.Axes.Outputs.State != "listed" || command.Axes.Errors.State != "listed") {
				c.fail("complete coverage without scenario denominators: %s needs listed outputs and errors axes", owner)
			}
		}
	}
	for _, profile := range command.Profiles {
		if !seen[profile] {
			c.fail("missing verification: %s@%s", command.ID, strings.TrimPrefix(profile, "prof:"))
		}
	}
}

func (c *checker) affecting(command string) []Difference {
	var out []Difference
	for _, difference := range c.manifest.Differences {
		for _, affected := range difference.Affects {
			if affected == command {
				out = append(out, difference)
				break
			}
		}
	}
	return out
}

func (c *checker) checkStates(command Command) {
	if command.RequirementState != "required" && !c.approvedWaiverCovers(command.ID) {
		c.fail("requirement dropped without an approved waiver: %s is %s", command.ID, command.RequirementState)
	}
	if command.OwnershipLane == "development_fallback" && command.ImplementationState == "implemented" {
		c.fail("development fallback counted as implemented: %s", command.ID)
	}
	if command.ImplementationState == "not_started" {
		for _, result := range command.Verification {
			if result.State == verificationPass || result.State == "fail" {
				c.fail("contradictory states: %s is not_started but %s verification is %s", command.ID, result.Profile, result.State)
			}
		}
	}
	if command.ImplementationState == "implemented" {
		for _, difference := range c.affecting(command.ID) {
			if difference.Disposition != dispositionWaived {
				c.fail("contradictory states: %s is implemented but difference %s is %s", command.ID, difference.ID, difference.Disposition)
			}
		}
	}
}

// approvedWaiverCovers reports whether an approved waiver names the command.
func (c *checker) approvedWaiverCovers(command string) bool {
	for _, waiver := range c.manifest.Waivers {
		if waiver.Status != waiverApproved {
			continue
		}
		for _, id := range waiver.Commands {
			if id == command {
				return true
			}
		}
	}
	return false
}

func (c *checker) checkDifferences() {
	tracked := map[string]map[string]bool{}
	for _, difference := range c.manifest.Differences {
		c.requireSorted(difference.ID+" affects", difference.Affects)
		c.requireSorted(difference.ID+" profiles", difference.Profiles)
		profiles := map[string]bool{}
		for _, command := range difference.Affects {
			if c.resolve(difference.ID, "affects", command, kindCommand) {
				for _, profile := range c.commands[command].Profiles {
					profiles[profile] = true
				}
			}
		}
		for _, profile := range difference.Profiles {
			if c.resolve(difference.ID, "profiles", profile, kindProfile) && !profiles[profile] {
				c.fail("difference %s names profile %s, which none of its commands has", difference.ID, profile)
			}
		}
		source := difference.Source
		if c.resolve(difference.ID, "source", source.Evidence, kindEvidence) {
			text, ok := c.documents[source.Evidence]
			switch {
			case !ok:
				c.fail("wrong record kind: %s source -> %s is not document evidence", difference.ID, source.Evidence)
			case !markdownHeadings(text)[source.Section]:
				c.fail("stale difference source: %s section %q is not a heading of %s", difference.ID, source.Section, c.evidence[source.Evidence].Path)
			case !strings.Contains(normalizeSpace(text), normalizeSpace(source.Quote)):
				c.fail("stale difference source: %s quote is not in %s: %q", difference.ID, c.evidence[source.Evidence].Path, source.Quote)
			}
			if difference.TrackingTask != "" {
				if tracked[source.Evidence] == nil {
					tracked[source.Evidence] = map[string]bool{}
				}
				tracked[source.Evidence][difference.TrackingTask] = true
			}
		}
		if difference.Disposition == dispositionWaived {
			c.checkWaivedDifference(difference)
		}
	}
	for _, evidence := range c.manifest.Evidence {
		if !evidence.ListsDifferences {
			continue
		}
		for _, task := range taskReferences(c.documents[evidence.ID]) {
			if !tracked[evidence.ID][task] {
				c.fail("untracked difference: %s names %s, but no difference from it tracks that task", evidence.Path, task)
			}
		}
	}
}

func (c *checker) checkWaivedDifference(difference Difference) {
	if !c.resolve(difference.ID, "waiver", difference.Waiver, kindWaiver) {
		return
	}
	waiver := c.waivers[difference.Waiver]
	if waiver.Status != waiverApproved {
		c.fail("pending waiver counted as green: %s is waived by %s, whose status is %s", difference.ID, waiver.ID, waiver.Status)
	}
	named := false
	for _, id := range waiver.Differences {
		named = named || id == difference.ID
	}
	if !named {
		c.fail("difference %s is waived by %s, which does not name it", difference.ID, waiver.ID)
	}
	if nonWaivable[difference.Category] {
		c.fail("non-waivable difference waived: %s is %s", difference.ID, difference.Category)
	}
}

func isWildcard(id string) bool {
	return strings.ContainsAny(id, "*?[") || strings.HasSuffix(id, "/all") || strings.HasSuffix(id, ":all") || strings.HasSuffix(id, ":any")
}

func (c *checker) checkWaivers() {
	for _, waiver := range c.manifest.Waivers {
		for _, id := range append(append([]string(nil), waiver.Commands...), waiver.Profiles...) {
			if isWildcard(id) {
				c.fail("wildcard waiver: %s names %s; a waiver must name exact commands and profiles", waiver.ID, id)
			}
		}
		c.requireSorted(waiver.ID+" differences", waiver.Differences)
		c.requireSorted(waiver.ID+" commands", waiver.Commands)
		c.requireSorted(waiver.ID+" profiles", waiver.Profiles)
		affects := map[string]bool{}
		profiles := map[string]bool{}
		active := 0
		for _, id := range waiver.Differences {
			if !c.resolve(waiver.ID, "differences", id, kindDifference) {
				continue
			}
			active++
			difference := c.differences[id]
			for _, command := range difference.Affects {
				affects[command] = true
			}
			for _, profile := range difference.Profiles {
				profiles[profile] = true
			}
			if nonWaivable[difference.Category] {
				c.fail("waiver covers a non-waivable requirement: %s names %s (%s)", waiver.ID, id, difference.Category)
			}
			if waiver.Status == waiverApproved && (difference.Disposition != dispositionWaived || difference.Waiver != waiver.ID) {
				c.fail("approved waiver not applied: %s names %s, whose disposition is %s", waiver.ID, id, difference.Disposition)
			}
		}
		if active == 0 {
			c.fail("waiver names no active difference: %s", waiver.ID)
		}
		for _, command := range waiver.Commands {
			if c.resolve(waiver.ID, "commands", command, kindCommand) && !affects[command] {
				c.fail("waiver %s covers %s, which none of its differences affects", waiver.ID, command)
			}
		}
		for _, profile := range waiver.Profiles {
			if c.resolve(waiver.ID, "profiles", profile, kindProfile) && !profiles[profile] {
				c.fail("waiver %s covers profile %s, which none of its differences names", waiver.ID, profile)
			}
		}
		for _, ref := range waiver.Tests {
			c.resolve(waiver.ID, "tests", ref, kindEvidence, kindInventory)
		}
		for _, scenario := range waiver.Scenarios {
			found := false
			for _, suite := range c.suites {
				found = found || suite.scenarios[scenario] != ""
			}
			if !found {
				c.fail("stale evidence: %s cites scenario %s, which no differential suite defines", waiver.ID, scenario)
			}
		}
		if waiver.ReviewDate != "" && isoDate.MatchString(c.asOf) && waiver.ReviewDate < c.asOf {
			c.fail("waiver outlives its review condition: %s review date %s is before %s", waiver.ID, waiver.ReviewDate, c.asOf)
		}
		if c.resolve(waiver.ID, "source", waiver.Source.Evidence, kindEvidence) {
			text, ok := c.documents[waiver.Source.Evidence]
			if !ok || !markdownHeadings(text)[waiver.Source.Section] {
				c.fail("stale waiver source: %s section %q is not a heading of %s", waiver.ID, waiver.Source.Section, waiver.Source.Evidence)
			}
		}
	}
}
