#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: assert-disposable-workspace.sh <workspace>" >&2
	exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(cd "$script_dir/../.." && pwd -P)"
candidate="$1"

if [[ ! -d "$candidate" ]]; then
	echo "disposable workspace does not exist: $candidate" >&2
	exit 1
fi

candidate="$(cd "$candidate" && pwd -P)"
case "$candidate/" in
"$repository_root/" | "$repository_root/"*)
	echo "refusing source-tree workspace: $candidate" >&2
	exit 1
	;;
esac

# A fixture must not be nested in any source checkout, including siblings.
ancestor="$candidate"
while [[ "$ancestor" != "/" ]]; do
	if [[ -e "$ancestor/.git" ]]; then
		echo "refusing workspace inside a source checkout: $candidate" >&2
		exit 1
	fi
	ancestor="$(dirname "$ancestor")"
done

if [[ ! -f "$candidate/.beadshx-disposable-fixture" ]]; then
	echo "missing disposable fixture marker: $candidate/.beadshx-disposable-fixture" >&2
	exit 1
fi

# An ambient database override may only point inside the marked fixture.
if [[ -n "${BEADS_DB:-}" ]]; then
	database_parent="$(dirname "$BEADS_DB")"
	if [[ ! -d "$database_parent" ]]; then
		echo "ambient BEADS_DB parent does not exist: $database_parent" >&2
		exit 1
	fi
	database_parent="$(cd "$database_parent" && pwd -P)"
	case "$database_parent/" in
	"$candidate/"*) ;;
	*)
		echo "ambient BEADS_DB escapes disposable fixture: $BEADS_DB" >&2
		exit 1
		;;
	esac
fi

echo "$candidate"
