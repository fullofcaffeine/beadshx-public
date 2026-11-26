package main

import (
	"maps"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"
)

var (
	thanksContributor = regexp.MustCompile(`(?m)^\t"([^"]+)":\s+(\d+),$`)
	thanksStyle       = regexp.MustCompile(`\x1b\[[0-9;]*m`)
	thanksCellGap     = regexp.MustCompile(` {2,}`)
)

// thanksPage is upstream's contributor table and the page's styles.
type thanksPage struct {
	commits             map[string]int
	rank                map[string]int
	nameOpen, nameClose string
	dimOpen, dimClose   string
}

// applyThanksContributorOrder checks that the page lists every contributor of
// upstream's table once, by commit count, in upstream's layout for that
// order (cmd/bd/thanks.go:131-253), and lays the names out again in one order:
// by count, then in the table's order.
func applyThanksContributorOrder(input []byte, options Options) ([]byte, error) {
	page := thanksPage{commits: map[string]int{}, rank: map[string]int{}}
	for index, match := range thanksContributor.FindAllStringSubmatch(string(options.ThanksSource), -1) {
		count, err := strconv.Atoi(match[2])
		if err != nil {
			return nil, rejectf("contributor %q has a bad count %q", match[1], match[2])
		}
		page.commits[match[1]] = count
		page.rank[match[1]] = index
	}
	if !utf8.Valid(input) {
		return nil, rejectf("the page is not UTF-8")
	}
	lines := strings.Split(string(input), "\n")
	plain := make([]string, len(lines))
	for index, line := range lines {
		plain[index] = thanksStyle.ReplaceAllString(line, "")
	}
	featuredAt := slices.Index(plain, "  Featured Contributors")
	additionalAt := slices.Index(plain, "  Additional Contributors")
	if featuredAt < 0 || additionalAt < 0 {
		return nil, rejectf("the page has no Featured and Additional Contributors headings")
	}
	rowsStart, rowsEnd := featuredAt+2, additionalAt-1
	wrappedStart, wrappedEnd := additionalAt+2, len(lines)-2
	if rowsStart >= rowsEnd || wrappedStart >= wrappedEnd || plain[additionalAt-1] != "" ||
		!slices.Equal(plain[len(lines)-2:], []string{"", ""}) {
		return nil, rejectf("the page does not have upstream's sections, or does not end as upstream's does")
	}

	var order []string
	for _, row := range plain[rowsStart:rowsEnd] {
		for _, shown := range thanksCellGap.Split(strings.TrimRight(dropRunes(row, 2), " "), -1) {
			name, err := page.fullName(shown)
			if err != nil {
				return nil, err
			}
			order = append(order, name)
		}
	}
	var wrapped strings.Builder
	for _, line := range plain[wrappedStart:wrappedEnd] {
		wrapped.WriteString(dropRunes(line, 2))
	}
	for _, shown := range strings.Split(wrapped.String(), ", ") {
		name, err := page.fullName(shown)
		if err != nil {
			return nil, err
		}
		order = append(order, name)
	}
	listed, contributors := slices.Sorted(slices.Values(order)), slices.Sorted(maps.Keys(page.commits))
	if !slices.Equal(listed, contributors) {
		return nil, rejectf("the page does not name each contributor once")
	}
	for index := 1; index < len(order); index++ {
		if page.commits[order[index-1]] < page.commits[order[index]] {
			return nil, rejectf("the page does not sort the contributors by commit count")
		}
	}
	var err error
	if page.nameOpen, page.nameClose, err = styleOf(lines[rowsStart]); err != nil {
		return nil, err
	}
	if page.dimOpen, page.dimClose, err = styleOf(lines[wrappedStart]); err != nil {
		return nil, err
	}
	columns, rest, err := page.render(order)
	if err != nil {
		return nil, err
	}
	if !slices.Equal(columns, lines[rowsStart:rowsEnd]) || !slices.Equal(rest, lines[wrappedStart:wrappedEnd]) {
		return nil, rejectf("the rows differ from upstream's layout for the same order")
	}
	canonical := slices.Clone(order)
	sort.SliceStable(canonical, func(left, right int) bool {
		if page.commits[canonical[left]] != page.commits[canonical[right]] {
			return page.commits[canonical[left]] > page.commits[canonical[right]]
		}
		return page.rank[canonical[left]] < page.rank[canonical[right]]
	})
	if columns, rest, err = page.render(canonical); err != nil {
		return nil, err
	}
	output := slices.Concat(lines[:rowsStart], columns, lines[rowsEnd:wrappedStart], rest, lines[wrappedEnd:])
	return []byte(strings.Join(output, "\n")), nil
}

// dropRunes drops the first count characters of text.
func dropRunes(text string, count int) string {
	for ; count > 0 && text != ""; count-- {
		_, size := utf8.DecodeRuneInString(text)
		text = text[size:]
	}
	return text
}

// truncatedName is how upstream shows a name longer than 20 bytes: its first
// 17 bytes and "...".
func truncatedName(name string) (string, error) {
	cut := name[:17]
	if !utf8.ValidString(cut) {
		return "", rejectf("contributor %q cannot be cut after 17 bytes", name)
	}
	return cut + "...", nil
}

func (page thanksPage) fullName(shown string) (string, error) {
	if _, ok := page.commits[shown]; ok {
		return shown, nil
	}
	var matches []string
	for name := range page.commits {
		if len(name) <= 20 {
			continue
		}
		cut, err := truncatedName(name)
		if err != nil {
			return "", err
		}
		if cut == shown {
			matches = append(matches, name)
		}
	}
	if len(matches) != 1 {
		return "", rejectf("unknown contributor %q", shown)
	}
	return matches[0], nil
}

// styleOf returns the first two SGR sequences of a line: the opening and the
// closing style of its first name.
func styleOf(line string) (string, string, error) {
	codes := thanksStyle.FindAllString(line, -1)
	switch len(codes) {
	case 0:
		return "", "", nil
	case 1:
		return "", "", rejectf("a contributor line has one style sequence, not two")
	default:
		return codes[0], codes[1], nil
	}
}

// render lays out names as upstream does: the first 20 in rows of four cells,
// the rest wrapped after ", " to the width of the rows.
func (page thanksPage) render(names []string) ([]string, []string, error) {
	featured, rest := names, []string(nil)
	if len(names) > 20 {
		featured, rest = names[:20], names[20:]
	}
	if len(featured) == 0 {
		return nil, nil, rejectf("the page names no contributor")
	}
	width := 0
	for _, name := range featured {
		width = max(width, len(name))
	}
	width = min(width, 20) + 2
	cells := make([]string, len(featured))
	for index, name := range featured {
		cells[index] = name
		if len(name) > 20 {
			cut, err := truncatedName(name)
			if err != nil {
				return nil, nil, err
			}
			cells[index] = cut
		}
	}
	var columns []string
	for at := 0; at < len(cells); at += 4 {
		row := "  "
		for _, cell := range cells[at:min(at+4, len(cells))] {
			row += page.nameOpen + cell + strings.Repeat(" ", max(0, width-utf8.RuneCountInString(cell))) + page.nameClose
		}
		columns = append(columns, row)
	}
	var wrapped []string
	line, length := "  ", 2
	for index, name := range rest {
		entry := name
		if index < len(rest)-1 {
			entry += ", "
		}
		if length+len(entry) > width*4+4 && length > 2 {
			wrapped = append(wrapped, line)
			line, length = "  ", 2
		}
		line += page.dimOpen + entry + page.dimClose
		length += len(entry)
	}
	return columns, append(wrapped, line), nil
}
