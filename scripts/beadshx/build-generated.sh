#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
generated_root="$repository_root/generated/go/bdhx"
binary_root="$repository_root/build/bin"

if [[ ! -f "$generated_root/.reflaxe-go-owned.json" ]]; then
	printf 'generated bootstrap source is missing; run the generate command first\n' >&2
	exit 1
fi

mkdir -p "$binary_root"
(
	cd "$repository_root"
	find generated/go -type f -name '*.go' -print0 |
		while IFS= read -r -d '' source; do
			format_diff="$(gofmt -d "$source")"
			if [[ -n "$format_diff" ]]; then
				printf 'generated Go source is not gofmt-stable: %s\n%s\n' "$source" "$format_diff" >&2
				exit 1
			fi
		done
	go test -tags gms_pure_go \
		./internal/beadshx/... \
		./generated/go/bdhx
	go build -tags gms_pure_go -trimpath -ldflags='-s -w' \
		-o "$binary_root/bdhx" ./generated/go/bdhx
)

"$binary_root/bdhx"
BEADSHX_CANDIDATE_BIN="$binary_root/bdhx" \
	"$repository_root/scripts/beadshx/test-readonly-cli.sh"
