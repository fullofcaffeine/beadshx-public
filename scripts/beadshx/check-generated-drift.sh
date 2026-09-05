#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fixture="${BEADSHX_GENERATED_FIXTURE:-$repository_root/engdocs/beadshx/generated/bootstrap-fixture.json}"
evidence_root="$repository_root/build/evidence/generated-drift"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-generated-drift.XXXXXX")"
candidate="$evidence_root/candidate.json"

cleanup() {
	find "$temporary_root" -mindepth 1 -delete
	rmdir "$temporary_root"
}
trap cleanup EXIT

cd "$repository_root"
case "$fixture" in
	/*) ;;
	*) fixture="$repository_root/$fixture" ;;
esac
generated_root="$repository_root/$(jq -er '.generatedRoot' "$fixture")"

jq -r '.owners.haxeSources[].path' "$fixture" | sort >"$temporary_root/expected-haxe-sources.txt"
find src/beadshx -type f -name '*.hx' -print | sort >"$temporary_root/current-haxe-sources.txt"
if ! diff -u "$temporary_root/expected-haxe-sources.txt" \
	"$temporary_root/current-haxe-sources.txt" >"$temporary_root/haxe-source-diff.txt"; then
	printf 'generated-source owner inventory changed\n' >&2
	cat "$temporary_root/haxe-source-diff.txt" >&2
	exit 1
fi

expected_compiler="$(jq -r '.owners.compilerRevision' "$fixture")"
actual_compiler="$(git -C .toolchains/haxe.go rev-parse HEAD)"
if [[ "$actual_compiler" != "$expected_compiler" ]]; then
	printf 'haxe.go compiler revision changed\nexpected: %s\nactual:   %s\n' \
		"$expected_compiler" "$actual_compiler" >&2
	exit 1
fi

npx haxe compile.bootstrap.hxml -D go_no_build
find "$generated_root" -type f -name '*.go' -print0 |
	while IFS= read -r -d '' file; do
		format_diff="$(gofmt -d "$file")"
		if [[ -n "$format_diff" ]]; then
			printf 'generated Go source is not gofmt-stable: %s\n%s\n' \
				"$file" "$format_diff" >&2
			exit 1
		fi
	done

mkdir -p "$evidence_root"
files_json="$temporary_root/files.json"
find "$generated_root" -type f -print0 | sort -z |
	while IFS= read -r -d '' file; do
		relative="${file#"$generated_root"/}"
		if [[ "$relative" == ".gitignore" ]]; then
			continue
		fi
		digest="$(shasum -a 256 "$file" | awk '{print $1}')"
		jq -cn --arg path "$relative" --arg sha256 "$digest" '{path:$path, sha256:$sha256}'
	done | jq -s '.' >"$files_json"

jq --slurpfile files "$files_json" '.files = $files[0]' "$fixture" >"$candidate"

for input in \
	"$(jq -r '.owners.hxml.path' "$fixture")" \
	"$(jq -r '.owners.compilerLock.path' "$fixture")"; do
	expected="$(jq -r --arg path "$input" '
		if .owners.hxml.path == $path then .owners.hxml.sha256
		else .owners.compilerLock.sha256 end
	' "$fixture")"
	actual="$(shasum -a 256 "$input" | awk '{print $1}')"
	if [[ "$actual" != "$expected" ]]; then
		printf 'generated-source owner changed: %s\nexpected: %s\nactual:   %s\n' \
			"$input" "$expected" "$actual" >&2
		exit 1
	fi
done

while IFS=$'\t' read -r input expected; do
	actual="$(shasum -a 256 "$input" | awk '{print $1}')"
	if [[ "$actual" != "$expected" ]]; then
		printf 'generated-source owner changed: %s\nexpected: %s\nactual:   %s\n' \
			"$input" "$expected" "$actual" >&2
		exit 1
	fi
done < <(jq -r '.owners.haxeSources[] | [.path, .sha256] | @tsv' "$fixture")

if ! diff -u <(jq -S '.files' "$fixture") <(jq -S '.files' "$candidate") >"$evidence_root/diff.txt"; then
	printf 'generated Go drift detected\n' >&2
	printf 'authored Haxe owners:\n' >&2
	jq -r '.owners.haxeSources[].path | "  " + .' "$fixture" >&2
	printf 'HXML owner: %s\n' "$(jq -r '.owners.hxml.path' "$fixture")" >&2
	printf 'haxe.go compiler revision: %s\n' \
		"$(jq -r '.owners.compilerRevision' "$fixture")" >&2
	printf 'candidate manifest: build/evidence/generated-drift/candidate.json\n' >&2
	printf 'byte diff: build/evidence/generated-drift/diff.txt\n' >&2
	exit 1
fi

printf 'generated Go drift: PASS\n'
