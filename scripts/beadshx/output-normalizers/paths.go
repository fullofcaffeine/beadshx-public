package main

import (
	"bytes"
	"fmt"
	"sort"
)

// pathValue is one declared path and the marker that replaces it.
type pathValue struct {
	value, marker string
}

// pathValues lists the paths of the enabled path normalizers, longest first,
// so that the work directory wins over its parent, the state root.
func pathValues(enabled map[string]bool, options Options) []pathValue {
	var values []pathValue
	add := func(name, marker string, paths []string) {
		if !enabled[name] {
			return
		}
		for _, path := range paths {
			values = append(values, pathValue{value: path, marker: marker})
		}
	}
	add("work-path", workMarker, options.Work)
	add("home-path", homeMarker, options.Home)
	add("state-path", stateMarker, options.State)
	sort.SliceStable(values, func(left, right int) bool { return len(values[left].value) > len(values[right].value) })
	return values
}

// isNameByte reports whether b can continue a file name: a letter, a digit,
// one of "_-+~@%", or a byte of a non-ASCII character.
func isNameByte(b byte) bool {
	return b >= 'a' && b <= 'z' || b >= 'A' && b <= 'Z' || b >= '0' && b <= '9' || b >= 0x80 ||
		bytes.IndexByte([]byte("_-+~@%"), b) >= 0
}

// pathEnds reports whether a path that ends right before text[at] ends there:
// at the end of the text, before a byte that cannot continue a name, or before
// a dot that no name byte follows (the end of a sentence, or "...").
func pathEnds(text []byte, at int) bool {
	if at == len(text) {
		return true
	}
	if text[at] == '.' {
		return at+1 == len(text) || !isNameByte(text[at+1])
	}
	return !isNameByte(text[at])
}

// pathStarts reports whether a path that starts at text[at] starts there: the
// byte before it, if any, must not be a name byte or a dot. A slash may come
// before it, as in file:///path.
func pathStarts(text []byte, at int) bool {
	return at == 0 || (!isNameByte(text[at-1]) && text[at-1] != '.')
}

// replacePaths replaces each declared path, as a whole path, with its marker,
// in one scan from the left. At each place the longest declared path wins.
// Declared paths are absolute, so a match starts at a slash.
func replacePaths(input []byte, values []pathValue) ([]byte, error) {
	markers := map[string]string{}
	for _, value := range values {
		if marker, ok := markers[value.value]; ok && marker != value.marker {
			return nil, fmt.Errorf("%s is declared as both %s and %s", value.value, marker, value.marker)
		}
		markers[value.value] = value.marker
	}
	var output bytes.Buffer
	output.Grow(len(input))
	for at := 0; at < len(input); {
		if input[at] == '/' && pathStarts(input, at) {
			matched := false
			for _, value := range values {
				end := at + len(value.value)
				if bytes.HasPrefix(input[at:], []byte(value.value)) && pathEnds(input, end) {
					output.WriteString(value.marker)
					at = end
					matched = true
					break
				}
			}
			if matched {
				continue
			}
		}
		output.WriteByte(input[at])
		at++
	}
	return output.Bytes(), nil
}
