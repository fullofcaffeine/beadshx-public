package main

import (
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// repository reads files below one checkout root. Manifest paths are
// repository-relative, so every read goes through it.
type repository struct {
	root      string
	overrides map[string]string
}

func (r repository) abs(path string) string {
	if override, ok := r.overrides[path]; ok {
		return override
	}
	return filepath.Join(r.root, filepath.FromSlash(path))
}

func (r repository) read(path string) ([]byte, error) {
	return os.ReadFile(filepath.Clean(r.abs(path)))
}

func (r repository) isDir(path string) bool {
	info, err := os.Stat(filepath.Clean(r.abs(path)))
	return err == nil && info.IsDir()
}

func sha256Hex(content []byte) string {
	sum := sha256.Sum256(content)
	return hex.EncodeToString(sum[:])
}

func decodeJSON(content []byte, encoding string) (any, error) {
	if encoding == "gzip-json" {
		reader, err := gzip.NewReader(bytes.NewReader(content))
		if err != nil {
			return nil, err
		}
		inflated, err := io.ReadAll(reader)
		if err != nil {
			return nil, err
		}
		content = inflated
	}
	decoder := json.NewDecoder(bytes.NewReader(content))
	decoder.UseNumber()
	var value any
	if err := decoder.Decode(&value); err != nil {
		return nil, err
	}
	return value, nil
}

// jsonPointer resolves an RFC 6901 pointer.
func jsonPointer(document any, pointer string) (any, bool) {
	if pointer == "" {
		return document, true
	}
	current := document
	for _, raw := range strings.Split(strings.TrimPrefix(pointer, "/"), "/") {
		token := strings.ReplaceAll(strings.ReplaceAll(raw, "~1", "/"), "~0", "~")
		switch node := current.(type) {
		case map[string]any:
			next, ok := node[token]
			if !ok {
				return nil, false
			}
			current = next
		case []any:
			index, err := strconv.Atoi(token)
			if err != nil || index < 0 || index >= len(node) {
				return nil, false
			}
			current = node[index]
		default:
			return nil, false
		}
	}
	return current, true
}

// collectionRecords lists the records of a top-level inventory collection,
// keyed by record ID: array elements by id or profileId, an object that has
// its own id as one record, and any other object by key.
func collectionRecords(document any, collection string) (map[string]any, bool) {
	root, ok := document.(map[string]any)
	if !ok {
		return nil, false
	}
	value, ok := root[collection]
	if !ok {
		return nil, false
	}
	records := map[string]any{}
	switch node := value.(type) {
	case []any:
		for _, element := range node {
			object, ok := element.(map[string]any)
			if !ok {
				continue
			}
			for _, key := range []string{"id", "profileId"} {
				if id, ok := object[key].(string); ok {
					records[id] = object
					break
				}
			}
		}
	case map[string]any:
		if id, ok := node["id"].(string); ok {
			records[id] = node
		} else {
			for key, element := range node {
				records[key] = element
			}
		}
	default:
		return nil, false
	}
	return records, true
}

func splitSourceRef(ref string) (inventory, collection, id string, ok bool) {
	inventory, rest, found := strings.Cut(ref, "#")
	if !found {
		return "", "", "", false
	}
	collection, id, found = strings.Cut(rest, "/")
	if !found {
		return inventory, rest, "", true
	}
	return inventory, collection, id, true
}

// inventoryCommand is the part of an M02-01 command record the gate joins.
type inventoryCommand struct {
	ID       string   `json:"id"`
	Aliases  []string `json:"aliases"`
	Hidden   bool     `json:"hidden"`
	Runnable bool     `json:"runnable"`
}

type commandInventory struct {
	Snapshots []struct {
		Profile    string             `json:"profile"`
		Activation string             `json:"activation"`
		Commands   []inventoryCommand `json:"commands"`
	} `json:"snapshots"`
}

// inventoryView is the command set of the M02-01 inventory.
type inventoryView struct {
	commands  map[string]inventoryCommand
	instances map[string]map[string]bool // command -> "profile/activation"
}

func loadCommandInventory(content []byte) (inventoryView, error) {
	reader, err := gzip.NewReader(bytes.NewReader(content))
	if err != nil {
		return inventoryView{}, err
	}
	inflated, err := io.ReadAll(reader)
	if err != nil {
		return inventoryView{}, err
	}
	var inventory commandInventory
	if err := json.Unmarshal(inflated, &inventory); err != nil {
		return inventoryView{}, err
	}
	view := inventoryView{commands: map[string]inventoryCommand{}, instances: map[string]map[string]bool{}}
	for _, snapshot := range inventory.Snapshots {
		for _, command := range snapshot.Commands {
			if _, ok := view.commands[command.ID]; !ok {
				view.commands[command.ID] = command
				view.instances[command.ID] = map[string]bool{}
			}
			view.instances[command.ID][snapshot.Profile+"/"+snapshot.Activation] = true
		}
	}
	return view, nil
}

// Scenario kinds of a differential suite.
const (
	scenarioDifferential = "differential"
	scenarioRefusal      = "refusal"
)

// suiteIndex holds the literal scenario invocations of a differential suite.
type suiteIndex struct {
	defined   map[string]bool
	scenarios map[string]string // scenario ID -> scenario kind
}

var helperDefinition = regexp.MustCompile(`^([a-z_]+)\(\) \{`)

// indexSuite records family/<first argument> and family/<first>/<second> for
// each literal helper call, and family/<helper> for a call without arguments.
func indexSuite(content []byte, families, refusalFamilies map[string][]string) suiteIndex {
	type helperInfo struct{ family, kind string }
	helpers := map[string]helperInfo{}
	for family, names := range families {
		for _, helper := range names {
			helpers[helper] = helperInfo{family, scenarioDifferential}
		}
	}
	for family, names := range refusalFamilies {
		for _, helper := range names {
			helpers[helper] = helperInfo{family, scenarioRefusal}
		}
	}
	index := suiteIndex{defined: map[string]bool{}, scenarios: map[string]string{}}
	for _, line := range strings.Split(string(content), "\n") {
		if match := helperDefinition.FindStringSubmatch(line); match != nil {
			index.defined[match[1]] = true
			continue
		}
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		info, ok := helpers[fields[0]]
		if !ok {
			continue
		}
		if len(fields) == 1 {
			index.scenarios[info.family+"/"+fields[0]] = info.kind
			continue
		}
		index.scenarios[info.family+"/"+fields[1]] = info.kind
		if len(fields) > 2 {
			index.scenarios[info.family+"/"+fields[1]+"/"+fields[2]] = info.kind
		}
	}
	return index
}

var whitespaceRun = regexp.MustCompile(`\s+`)

func normalizeSpace(text string) string {
	return strings.TrimSpace(whitespaceRun.ReplaceAllString(text, " "))
}

func markdownHeadings(text string) map[string]bool {
	headings := map[string]bool{}
	for _, line := range strings.Split(text, "\n") {
		if strings.HasPrefix(line, "#") {
			headings[strings.TrimSpace(strings.TrimLeft(line, "#"))] = true
		}
	}
	return headings
}

var taskReference = regexp.MustCompile(`beadshx-[a-z0-9]+(?:[.-][a-z0-9]+)*`)

func taskReferences(text string) []string {
	seen := map[string]bool{}
	for _, match := range taskReference.FindAllString(text, -1) {
		seen[strings.TrimRight(match, ".-")] = true
	}
	return sortedKeys(seen)
}

func sortedKeys[V any](values map[string]V) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func stringValue(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	case json.Number:
		return typed.String()
	case bool:
		return strconv.FormatBool(typed)
	case nil:
		return ""
	default:
		return fmt.Sprint(typed)
	}
}

func stringList(value any) []string {
	items, ok := value.([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(items))
	for _, item := range items {
		out = append(out, stringValue(item))
	}
	return out
}
