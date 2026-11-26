package main

import (
	"bytes"
	"regexp"
	"sort"
	"strings"
)

// splitLines splits text into lines that each keep their "\n". A last line
// without "\n" is the last element.
func splitLines(text []byte) []string {
	var result []string
	for len(text) > 0 {
		end := bytes.IndexByte(text, '\n')
		if end < 0 {
			result = append(result, string(text))
			break
		}
		result = append(result, string(text[:end+1]))
		text = text[end+1:]
	}
	return result
}

// lineContent drops the "\n" at the end of a line, if any.
func lineContent(line string) string { return strings.TrimSuffix(line, "\n") }

// rewriteLines replaces the content of each line with rewrite(content) and
// keeps each line's "\n".
func rewriteLines(input []byte, rewrite func(string) string) []byte {
	var output strings.Builder
	output.Grow(len(input))
	for _, line := range splitLines(input) {
		content := lineContent(line)
		output.WriteString(rewrite(content))
		output.WriteString(line[len(content):])
	}
	return []byte(output.String())
}

func applyPtyTranscript(input []byte, _ Options) ([]byte, error) {
	output := bytes.ReplaceAll(input, []byte("^D\b\b"), nil)
	return bytes.ReplaceAll(output, []byte("\r\n"), []byte("\n")), nil
}

var logTime = regexp.MustCompile(`(?m)^time="\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})" `)

func applyLogTime(input []byte, _ Options) ([]byte, error) {
	return logTime.ReplaceAll(input, []byte(`time="`+timeMarker+`" `)), nil
}

var pingDuration = regexp.MustCompile(`(?m)(bd ping: ok \()[0-9]+ms\)$`)

func applyPingDuration(input []byte, _ Options) ([]byte, error) {
	return pingDuration.ReplaceAll(input, []byte("${1}"+durationMarker+")")), nil
}

func applyBuildOutput(input []byte, _ Options) ([]byte, error) {
	if len(input) == 0 {
		return input, nil
	}
	return []byte(buildOutputMarker), nil
}

// applyRootUsage keeps the first line and, when the second line is exactly
// "Usage:", replaces it and every line after it with one marker line.
func applyRootUsage(input []byte, _ Options) ([]byte, error) {
	lines := splitLines(input)
	if len(lines) < 2 || lines[1] != "Usage:\n" && lines[1] != "Usage:" {
		return input, nil
	}
	return []byte(lines[0] + rootUsageMarker), nil
}

// blockStart reports whether lines[at] starts a block.
type blockStart func(lines []string, at int) bool

func startsUnindented(line string) bool {
	content := lineContent(line)
	return content != "" && content[0] != ' ' && content[0] != '\t'
}

// childrenBlockStart: show --children prints, for each issue, a header line
// and its indented children followed by an empty line, or one line "ID: No
// children found" (cmd/bd/show_children.go:67-83).
func childrenBlockStart(lines []string, at int) bool { return startsUnindented(lines[at]) }

// refsBlockStart: show --refs prints, for each issue, an empty line and a
// header line, then indented groups (each after an empty line) and a last
// empty line; or an empty line and "ID: No references found"
// (cmd/bd/show_refs.go:54-70).
func refsBlockStart(lines []string, at int) bool {
	return lineContent(lines[at]) == "" && at+1 < len(lines) && startsUnindented(lines[at+1])
}

// sortBlocks splits the text into blocks at each line where start holds and
// sorts the blocks by their exact text. Lines before the first block stay
// first, and the lines of a block keep their order. A last line without
// "\n" stays last.
func sortBlocks(input []byte, start blockStart) []byte {
	lines := splitLines(input)
	tail := ""
	if len(lines) > 0 && !strings.HasSuffix(lines[len(lines)-1], "\n") {
		tail = lines[len(lines)-1]
		lines = lines[:len(lines)-1]
	}
	var prefix strings.Builder
	var blocks []string
	for at, line := range lines {
		switch {
		case start(lines, at):
			blocks = append(blocks, line)
		case len(blocks) == 0:
			prefix.WriteString(line)
		default:
			blocks[len(blocks)-1] += line
		}
	}
	sort.Strings(blocks)
	return []byte(prefix.String() + strings.Join(blocks, "") + tail)
}

var (
	routingInvalid    = regexp.MustCompile(`routing\.mode: .* is invalid \(valid values: [a-z, ]*\)`)
	routingValidModes = regexp.MustCompile(`\(valid values: ([a-z, ]*)\)`)
)

func applyRoutingModeOrder(input []byte, _ Options) ([]byte, error) {
	return rewriteLines(input, func(line string) string {
		if !routingInvalid.MatchString(line) {
			return line
		}
		match := routingValidModes.FindStringSubmatchIndex(line)
		modes := strings.Split(line[match[2]:match[3]], ", ")
		sort.Strings(modes)
		return line[:match[0]] + "(valid values: " + strings.Join(modes, ", ") + ")" + line[match[1]:]
	}), nil
}

// configRowKey returns the key of a config show row, "  KEY = VALUE  (SOURCE)"
// with the key padded to the widest key (cmd/bd/config_show.go:383).
func configRowKey(line string) (string, bool) {
	content := lineContent(line)
	if !strings.HasPrefix(content, "  ") {
		return "", false
	}
	key, _, found := strings.Cut(content[2:], " = ")
	key = strings.TrimRight(key, " ")
	if !found || key == "" || strings.ContainsAny(key, " \t") {
		return "", false
	}
	return key, true
}

// sortRuns sorts, within each run of adjacent items with the same key, the
// items by less; items without a key keep their place.
func sortRuns[T any](items []T, key func(T) (string, bool), less func(T, T) bool) {
	for start := 0; start < len(items); {
		runKey, ok := key(items[start])
		end := start + 1
		for ok && end < len(items) {
			next, nextOK := key(items[end])
			if !nextOK || next != runKey {
				break
			}
			end++
		}
		run := items[start:end]
		sort.SliceStable(run, func(left, right int) bool { return less(run[left], run[right]) })
		start = end
	}
}

func applyConfigTieRows(input []byte, _ Options) ([]byte, error) {
	lines := splitLines(input)
	tail := ""
	if len(lines) > 0 && !strings.HasSuffix(lines[len(lines)-1], "\n") {
		tail = lines[len(lines)-1]
		lines = lines[:len(lines)-1]
	}
	sortRuns(lines, configRowKey, func(left, right string) bool { return left < right })
	return []byte(strings.Join(lines, "") + tail), nil
}

func applyGraphHTMLNodeOrder(input []byte, _ Options) ([]byte, error) {
	const prefix, suffix, separator = `const nodes = [{"id":`, `}];`, `},{"id":`
	return rewriteLines(input, func(line string) string {
		if len(line) < len(prefix)+len(suffix) || !strings.HasPrefix(line, prefix) || !strings.HasSuffix(line, suffix) {
			return line
		}
		nodes := strings.Split(line[len(prefix):len(line)-len(suffix)], separator)
		sort.Strings(nodes)
		return prefix + strings.Join(nodes, separator) + suffix
	}), nil
}

var watchHeaderTime = regexp.MustCompile(`(?m)(Beads - Open & In Progress \()\d{2}:\d{2}:\d{2}\)$`)

func applyWatchHeaderTime(input []byte, _ Options) ([]byte, error) {
	return watchHeaderTime.ReplaceAll(input, []byte("${1}"+timeMarker+")")), nil
}

var watchCanceled = regexp.MustCompile(`^Error refreshing issues: .*context canceled$`)

// applyWatchRefreshNoise drops refresh errors that a cancellation caused and
// a refresh error that repeats the line printed right before it.
func applyWatchRefreshNoise(input []byte, _ Options) ([]byte, error) {
	var output strings.Builder
	previous, printed := "", false
	for _, line := range splitLines(input) {
		content := lineContent(line)
		if watchCanceled.MatchString(content) {
			continue
		}
		if printed && strings.HasPrefix(content, "Error refreshing issues:") && content == previous {
			continue
		}
		output.WriteString(line)
		previous, printed = content, true
	}
	return []byte(output.String()), nil
}
