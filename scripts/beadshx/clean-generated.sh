#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
generated_root="$repository_root/generated/go"

if [[ -d "$generated_root" ]]; then
	for path in "$generated_root/bootstrap" "$generated_root/bdhx" "$generated_root/hxrt"; do
		if [[ -d "$path" ]]; then
			find "$path" -mindepth 1 -delete
			rmdir "$path"
		fi
	done
fi

license_root="$repository_root/LICENSES"
if [[ -d "$license_root" ]]; then
	for entry in \
		'HAXE-GO-GENERATED-MIT.txt:6889cefcfdc5bf1b6fb9fc4807b0ae080db219ca3c82208c9455c1cf7e81ef94' \
		'HAXE-STDLIB-MIT.txt:61c9e5c8ca48e1f6e27f66cc6fb2eb11865a08672e1c793a13cfdaa89ad1bb74'; do
		name="${entry%%:*}"
		expected="${entry#*:}"
		path="$license_root/$name"
		if [[ -f "$path" ]]; then
			actual="$(shasum -a 256 "$path" | awk '{print $1}')"
			if [[ "$actual" != "$expected" ]]; then
				printf 'refusing to remove changed generated license: %s\n' "$path" >&2
				exit 1
			fi
			rm -f -- "$path"
		fi
	done
	if [[ -n "$(find "$license_root" -mindepth 1 -print -quit)" ]]; then
		printf 'refusing to remove generated license directory with unknown files: %s\n' \
			"$license_root" >&2
		exit 1
	fi
	rmdir "$license_root"
fi

for path in \
	"$repository_root/build/bin/bdhx" \
	"$repository_root/build/bin/bd-upstream" \
	"$repository_root/build/packages/beadshx-development-bootstrap.zip"; do
	if [[ -f "$path" ]]; then
		rm -f -- "$path"
	fi
done
