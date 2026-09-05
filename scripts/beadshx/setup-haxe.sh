#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repository_root"

npm ci
shasum -a 256 package-lock.json | awk '{print $1}' \
	>node_modules/.beadshx-package-lock.sha256

if [[ ! -d haxe_libraries ]]; then
	npx lix scope create
fi

compiler_commit="$(jq -er '.requiredCommit' upstream/locks/haxe-go.json)"
compiler_remote="$(jq -er '.remote' upstream/locks/haxe-go.json)"
compiler_root="$repository_root/.toolchains/haxe.go"

npx lix download haxe 4.3.7
npx lix use haxe 4.3.7
npx lix download

if [[ ! -d "$compiler_root/.git" ]]; then
	mkdir -p "$(dirname "$compiler_root")"
	if git -C "$repository_root/../haxe.go" cat-file -e "$compiler_commit^{commit}" 2>/dev/null; then
		git clone --quiet --reference-if-able "$repository_root/../haxe.go" \
			--dissociate --no-checkout "$repository_root/../haxe.go" "$compiler_root"
	else
		git clone --quiet --no-checkout https://github.com/fullofcaffeine/reflaxe.go.git "$compiler_root"
	fi
fi

if ! git -C "$compiler_root" cat-file -e "$compiler_commit^{commit}" 2>/dev/null; then
	git -C "$compiler_root" fetch --quiet "$compiler_remote" master
fi
if ! git -C "$compiler_root" cat-file -e "$compiler_commit^{commit}" 2>/dev/null; then
	printf 'locked haxe.go commit is unavailable after fetching origin/master: %s\n' \
		"$compiler_commit" >&2
	exit 1
fi

if [[ -n "$(git -C "$compiler_root" status --porcelain --untracked-files=all)" ]]; then
	printf 'haxe.go checkout has tracked or untracked changes; preserve them before setup\n' >&2
	exit 1
fi

compiler_git_dir="$(git -C "$compiler_root" rev-parse --absolute-git-dir)"
alternates="$compiler_git_dir/objects/info/alternates"
if [[ -f "$alternates" ]]; then
	git -C "$compiler_root" repack -a -d
	rm "$alternates"
fi

git -C "$compiler_root" checkout --quiet --detach "$compiler_commit"
resolved_compiler="$(git -C "$compiler_root" rev-parse HEAD)"
if [[ "$resolved_compiler" != "$compiler_commit" ]]; then
	echo "expected haxe.go $compiler_commit, got $resolved_compiler" >&2
	exit 1
fi
if [[ -n "$(git -C "$compiler_root" status --porcelain --untracked-files=all)" ]]; then
	printf 'haxe.go checkout is not clean after selecting the locked commit\n' >&2
	exit 1
fi
if [[ -f "$alternates" ]]; then
	printf 'haxe.go checkout still depends on a shared object store\n' >&2
	exit 1
fi

resolved_haxe="$(npx haxe --version)"
if [[ "$resolved_haxe" != "4.3.7" ]]; then
	echo "expected Haxe 4.3.7, got $resolved_haxe" >&2
	exit 1
fi

expected_formatter="$(jq -er '.common.haxeFormatter' \
	engdocs/beadshx/program/toolchain-locks.json)"
resolved_formatter="$(npx lix run formatter --help 2>&1 | \
	sed -n -E 's/^Haxe Formatter ([0-9.]+)$/\1/p' | head -n 1)"
if [[ "$resolved_formatter" != "$expected_formatter" ]]; then
	echo "expected Haxe Formatter $expected_formatter, got ${resolved_formatter:-unavailable}" >&2
	exit 1
fi
