#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
locks="$repository_root/engdocs/beadshx/program/toolchain-locks.json"
install_root="$repository_root/.toolchains/bin"
version="$(jq -er '.secretScanner.version' "$locks")"

case "$(uname -s):$(uname -m)" in
    Darwin:arm64) asset=darwin_arm64 ;;
    Darwin:x86_64) asset=darwin_x64 ;;
    Linux:aarch64|Linux:arm64) asset=linux_arm64 ;;
    Linux:x86_64) asset=linux_x64 ;;
    *)
        printf 'gitleaks has no lock for %s/%s\n' "$(uname -s)" "$(uname -m)" >&2
        exit 1
        ;;
esac

archive="gitleaks_${version}_${asset}.tar.gz"
expected="$(jq -er --arg asset "$asset" '.secretScanner.assets[$asset]' "$locks")"
expected_binary="$(jq -er --arg asset "$asset" \
    '.secretScanner.binarySha256[$asset]' "$locks")"
download_root="$(mktemp -d "${TMPDIR:-/tmp}/beadshx-gitleaks.XXXXXX")"
trap 'find "$download_root" -mindepth 1 -delete; rmdir "$download_root"' EXIT

curl --fail --location --silent --show-error \
    "https://github.com/gitleaks/gitleaks/releases/download/v${version}/${archive}" \
    --output "$download_root/$archive"

actual="$(shasum -a 256 "$download_root/$archive" | awk '{print $1}')"
if [[ "$actual" != "$expected" ]]; then
    printf 'gitleaks archive mismatch: expected %s, got %s\n' "$expected" "$actual" >&2
    exit 1
fi

tar -xzf "$download_root/$archive" -C "$download_root" gitleaks
actual_binary="$(shasum -a 256 "$download_root/gitleaks" | awk '{print $1}')"
if [[ "$actual_binary" != "$expected_binary" ]]; then
    printf 'gitleaks binary mismatch: expected %s, got %s\n' \
        "$expected_binary" "$actual_binary" >&2
    exit 1
fi
mkdir -p "$install_root"
install -m 0755 "$download_root/gitleaks" "$install_root/gitleaks"

"$repository_root/scripts/beadshx/verify-gitleaks.sh"
