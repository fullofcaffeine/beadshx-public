package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
)

// jsonNode is one value of a JSON document, by its byte span in the document.
// An object keeps its members' decoded names and values in document order,
// and an array its elements. The JSON normalizers rewrite only the spans of
// their declared values, so every other byte of the document, its key order,
// spacing and string escapes stay as printed.
type jsonNode struct {
	start, end int
	// kind is '{', '[', '"', or 0 for a number, true, false or null.
	kind     byte
	names    []string
	children []*jsonNode
}

// member returns the value of the object member with the given name, or nil
// when the node is not an object or has no such member. A name given twice
// returns its last value, as encoding/json and jq read it.
func (node *jsonNode) member(name string) *jsonNode {
	if node == nil || node.kind != '{' {
		return nil
	}
	var found *jsonNode
	for index, memberName := range node.names {
		if memberName == name {
			found = node.children[index]
		}
	}
	return found
}

func (node *jsonNode) count(name string) int {
	count := 0
	for _, memberName := range node.names {
		if memberName == name {
			count++
		}
	}
	return count
}

// parseJSONSpans parses one JSON document into its value spans.
func parseJSONSpans(data []byte) (*jsonNode, error) {
	if !json.Valid(data) {
		return nil, rejectf("the output is not one JSON document")
	}
	parser := spanParser{data: data}
	parser.space()
	return parser.value(), nil
}

// spanParser walks a document that json.Valid accepted.
type spanParser struct {
	data []byte
	at   int
}

func (parser *spanParser) space() {
	for parser.at < len(parser.data) && bytes.IndexByte([]byte(" \t\r\n"), parser.data[parser.at]) >= 0 {
		parser.at++
	}
}

func (parser *spanParser) value() *jsonNode {
	node := &jsonNode{start: parser.at}
	switch parser.data[parser.at] {
	case '{', '[':
		node.kind = parser.data[parser.at]
		closing := byte('}')
		if node.kind == '[' {
			closing = ']'
		}
		parser.at++
		parser.space()
		for parser.data[parser.at] != closing {
			if node.kind == '{' {
				key := parser.value()
				var name string
				// The key is a valid JSON string, so it decodes.
				_ = json.Unmarshal(parser.data[key.start:key.end], &name)
				node.names = append(node.names, name)
				parser.space()
				parser.at++ // ':'
				parser.space()
			}
			node.children = append(node.children, parser.value())
			parser.space()
			if parser.data[parser.at] == ',' {
				parser.at++
				parser.space()
			}
		}
		parser.at++
	case '"':
		node.kind = '"'
		parser.at++
		for parser.data[parser.at] != '"' {
			if parser.data[parser.at] == '\\' {
				parser.at++
			}
			parser.at++
		}
		parser.at++
	default:
		for parser.at < len(parser.data) && bytes.IndexByte([]byte(" \t\r\n,]}"), parser.data[parser.at]) < 0 {
			parser.at++
		}
	}
	node.end = parser.at
	return node
}

// spanEdit replaces data[start:end] with text.
type spanEdit struct {
	start, end int
	text       []byte
}

func applyEdits(data []byte, edits []spanEdit) []byte {
	sort.Slice(edits, func(left, right int) bool { return edits[left].start < edits[right].start })
	var output bytes.Buffer
	at := 0
	for _, edit := range edits {
		output.Write(data[at:edit.start])
		output.Write(edit.text)
		at = edit.end
	}
	output.Write(data[at:])
	return output.Bytes()
}

// permute returns the edits that place the elements of nodes in the given
// order, each element's exact text in the span of another; the commas and
// spacing between them stay.
func permute(data []byte, nodes, order []*jsonNode) []spanEdit {
	edits := make([]spanEdit, len(nodes))
	for index, node := range nodes {
		edits[index] = spanEdit{start: node.start, end: node.end, text: data[order[index].start:order[index].end]}
	}
	return edits
}

// sortArray returns the edits that sort the elements of an array by their
// exact text.
func sortArray(data []byte, array *jsonNode) []spanEdit {
	order := append([]*jsonNode(nil), array.children...)
	sort.SliceStable(order, func(left, right int) bool {
		return bytes.Compare(data[order[left].start:order[left].end], data[order[right].start:order[right].end]) < 0
	})
	return permute(data, array.children, order)
}

func applyPingTimings(input []byte, _ Options) ([]byte, error) {
	root, err := parseJSONSpans(input)
	if err != nil {
		return nil, err
	}
	if root.kind != '{' {
		return nil, rejectf("the output is not a JSON object")
	}
	var edits []spanEdit
	values := map[string]float64{}
	for _, name := range []string{"query_ms", "resolve_ms", "store_ms", "total_ms"} {
		if count := root.count(name); count != 1 {
			return nil, rejectf("the object holds %s %d times, not once", name, count)
		}
		node := root.member(name)
		number, err := strconv.ParseFloat(string(input[node.start:node.end]), 64)
		if node.kind != 0 || err != nil || number < 0 {
			return nil, rejectf("%s is %s, not a number that is not negative", name, input[node.start:node.end])
		}
		values[name] = number
		edits = append(edits, spanEdit{start: node.start, end: node.end, text: []byte(millisMarker)})
	}
	if sum := values["query_ms"] + values["resolve_ms"] + values["store_ms"]; values["total_ms"] != sum {
		return nil, rejectf("total_ms %g is not the sum %g of query_ms, resolve_ms and store_ms", values["total_ms"], sum)
	}
	return applyEdits(input, edits), nil
}

// iterate returns the values of an object or the elements of an array, as jq's
// .[] does, or false for any other value.
func iterate(node *jsonNode) ([]*jsonNode, bool) {
	if node == nil || node.kind != '{' && node.kind != '[' {
		return nil, false
	}
	return node.children, true
}

func applyMoleculeParallelOrder(input []byte, _ Options) ([]byte, error) {
	root, err := parseJSONSpans(input)
	if err != nil {
		return nil, err
	}
	if root.kind != '{' {
		return nil, rejectf("the output is not a JSON object")
	}
	var edits []spanEdit
	if groups := root.member("parallel_groups"); groups != nil {
		members, ok := iterate(groups)
		if !ok {
			return nil, rejectf("parallel_groups is not an object or an array")
		}
		for _, group := range members {
			if group.kind != '[' {
				return nil, rejectf("a parallel group is not an array")
			}
			edits = append(edits, sortArray(input, group)...)
		}
	}
	if steps := root.member("steps"); steps != nil {
		elements, ok := iterate(steps)
		if !ok {
			return nil, rejectf("steps is not an object or an array")
		}
		for _, step := range elements {
			info := step.member("parallel_info")
			for _, name := range []string{"blocked_by", "blocks", "can_parallel"} {
				array := info.member(name)
				if array == nil || array.kind != '[' {
					return nil, rejectf("a step's parallel_info.%s is not an array", name)
				}
				edits = append(edits, sortArray(input, array)...)
			}
		}
	}
	return applyEdits(input, edits), nil
}

func applyGraphDependsOnOrder(input []byte, _ Options) ([]byte, error) {
	root, err := parseJSONSpans(input)
	if err != nil {
		return nil, err
	}
	nodes, ok := iterate(root.member("layout").member("Nodes"))
	if !ok {
		return nil, rejectf("layout.Nodes is not an object or an array")
	}
	var edits []spanEdit
	for _, node := range nodes {
		if node.kind != '{' {
			return nil, rejectf("a node of layout.Nodes is not an object")
		}
		dependsOn := node.member("DependsOn")
		switch {
		case dependsOn == nil || string(input[dependsOn.start:dependsOn.end]) == "null":
		case dependsOn.kind == '[':
			edits = append(edits, sortArray(input, dependsOn)...)
		default:
			return nil, rejectf("a DependsOn is not an array or null")
		}
	}
	return applyEdits(input, edits), nil
}

// stringValue decodes a JSON string node, or returns the node's text for any
// other value, as a sort key.
func stringValue(data []byte, node *jsonNode) string {
	if node == nil {
		return ""
	}
	if node.kind == '"' {
		var value string
		if err := json.Unmarshal(data[node.start:node.end], &value); err == nil {
			return value
		}
	}
	return string(data[node.start:node.end])
}

func applyConfigTieEntries(input []byte, _ Options) ([]byte, error) {
	root, err := parseJSONSpans(input)
	if err != nil {
		return nil, err
	}
	if root.kind != '[' {
		return nil, rejectf("the output is not a JSON array")
	}
	for _, element := range root.children {
		if element.kind != '{' {
			return nil, rejectf("an entry is not a JSON object")
		}
	}
	order := append([]*jsonNode(nil), root.children...)
	key := func(element *jsonNode) (string, bool) {
		member := element.member("key")
		if member == nil || member.kind != '"' {
			return "", false
		}
		return stringValue(input, member), true
	}
	sortRuns(order, key, func(left, right *jsonNode) bool {
		leftSource, rightSource := stringValue(input, left.member("source")), stringValue(input, right.member("source"))
		if leftSource != rightSource {
			return leftSource < rightSource
		}
		return stringValue(input, left.member("value")) < stringValue(input, right.member("value"))
	})
	return applyEdits(input, permute(input, root.children, order)), nil
}

func applyJSONCompact(input []byte, _ Options) ([]byte, error) {
	if !json.Valid(input) {
		return input, nil
	}
	var output bytes.Buffer
	if err := json.Compact(&output, input); err != nil {
		return nil, fmt.Errorf("compact a valid document: %w", err)
	}
	return output.Bytes(), nil
}
