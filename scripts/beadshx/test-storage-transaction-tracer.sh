#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-storage-transaction.XXXXXX")"
backup_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-storage-generated.XXXXXX")"
generated_root="$repository_root/generated/go"

cleanup() {
	if [[ -d "$backup_root/go" ]]; then
		if [[ -d "$generated_root" ]]; then
			find "$generated_root" -mindepth 1 -delete
			rmdir "$generated_root"
		fi
		mv -f "$backup_root/go" "$generated_root"
	fi
	rmdir "$backup_root"
	find "$fixture_root" -mindepth 1 -delete
	rmdir "$fixture_root"
}
trap cleanup EXIT

touch "$fixture_root/.beadshx-disposable-fixture"
"$repository_root/scripts/beadshx/assert-disposable-workspace.sh" "$fixture_root" >/dev/null

(
	cd "$repository_root"
	if [[ ! -f generated/go/bdhx/.reflaxe-go-owned.json ]]; then
		npx haxe compile.bootstrap.hxml
	fi
	cp -rf generated/go "$backup_root/go"
	npx haxe test/storage_transaction/compile.hxml
	CGO_ENABLED=1 GOFLAGS=-tags=gms_pure_go \
		go run ./generated/go/bdhx "$fixture_root"
)

actual_entries="$(find "$fixture_root" -mindepth 1 -print | sort)"
if [[ "$actual_entries" != "$fixture_root/.beadshx-disposable-fixture" ]]; then
	printf 'storage transaction tracer wrote persistent fixture state:\n%s\n' \
		"$actual_entries" >&2
	exit 1
fi

echo "storage transaction tracer safety: PASS"
