#!/usr/bin/env python3
"""Reject private content and local paths without printing the rejected values.

Private literals belong in Git's local info/private-content-patterns.json file,
never in repository policy. The index is authoritative for staged content.
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


ZERO_OID = re.compile(rb"^0+$")
UNIX_PATH = re.compile(
    rb"/(?:Users/|home/|var/folders/|private/var/folders/)"
    rb"[^\s\"'<>()[\]{}]+"
)
WINDOWS_PATH = re.compile(
    rb"[A-Za-z]:\\+Users\\+[^\s\"'<>()[\]{}]+",
    re.IGNORECASE,
)
RELATIVE_PATH = re.compile(
    rb"(?<![A-Za-z0-9_])((?:\./|\.\./)[^\s\"'<>()[\]{}]+)"
)
TOKEN_TRAILING = b".,;:!?"


class ScanError(RuntimeError):
    """A Git or content operation failed, so the policy must fail closed."""


def git(root: Path, arguments: list[str], *, input_bytes: bytes | None = None) -> bytes:
    completed = subprocess.run(
        ["git", "-C", os.fspath(root), *arguments],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", "replace").strip()
        raise ScanError(f"git {' '.join(arguments)} failed: {detail}")
    return completed.stdout


def changed_blobs(root: Path, revision_range: str | None) -> list[tuple[bytes, bytes, bytes]]:
    if revision_range is None:
        arguments = [
            "diff",
            "--cached",
            "--raw",
            "-z",
            "--no-abbrev",
            "--no-renames",
            "--",
        ]
    else:
        if ".." not in revision_range:
            raise ScanError("--range must have the form BASE..HEAD")
        base, head = revision_range.split("..", 1)
        if not base or not head:
            raise ScanError("--range must have the form BASE..HEAD")
        arguments = [
            "diff",
            "--raw",
            "-z",
            "--no-abbrev",
            "--no-renames",
            base,
            head,
            "--",
        ]

    fields = git(root, arguments).split(b"\0")
    records: list[tuple[bytes, bytes, bytes]] = []
    index = 0
    while index < len(fields) and fields[index]:
        header = fields[index]
        index += 1
        if index >= len(fields):
            raise ScanError("Git returned a truncated raw diff record")
        path = fields[index]
        index += 1
        parts = header.removeprefix(b":").split()
        if len(parts) != 5:
            raise ScanError(f"Git returned an unexpected raw diff header: {header!r}")
        old_mode, new_mode, old_oid, new_oid, status = parts
        if status not in {b"A", b"M", b"T"}:
            continue
        if new_mode == b"160000":
            continue
        records.append((path, old_oid, new_oid))
    return records


def blob(root: Path, oid: bytes) -> bytes:
    if ZERO_OID.fullmatch(oid):
        return b""
    completed = subprocess.run(
        ["git", "-C", os.fspath(root), "cat-file", "blob", oid.decode("ascii")],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", "replace").strip()
        raise ScanError(f"cannot read staged blob {oid.decode('ascii')}: {detail}")
    return completed.stdout


def added_lines(old: bytes, new: bytes) -> list[tuple[int, bytes]]:
    old_lines = old.splitlines()
    new_lines = new.splitlines()
    matcher = difflib.SequenceMatcher(None, old_lines, new_lines, autojunk=False)
    additions: list[tuple[int, bytes]] = []
    for operation, _old_start, _old_end, new_start, new_end in matcher.get_opcodes():
        if operation in {"insert", "replace"}:
            additions.extend((line + 1, new_lines[line]) for line in range(new_start, new_end))
    return additions


def outside_reference(root: Path, source_path: bytes, reference: bytes) -> bool:
    decoded_path = os.fsdecode(source_path)
    decoded_reference = os.fsdecode(reference.rstrip(TOKEN_TRAILING))
    source_directory = root.joinpath(decoded_path).parent
    candidate = os.path.abspath(os.path.join(source_directory, decoded_reference))
    try:
        return os.path.commonpath((os.fspath(root), candidate)) != os.fspath(root)
    except ValueError:
        return True


def scan(root: Path, revision_range: str | None) -> list[str]:
    findings: list[str] = []
    common = Path(os.fsdecode(git(root, ["rev-parse", "--git-common-dir"]).strip()))
    if not common.is_absolute():
        common = root / common
    policy_path = common / "info/private-content-patterns.json"
    private_patterns: list[bytes] = []
    if policy_path.exists():
        policy = json.loads(policy_path.read_text(encoding="utf-8"))
        patterns = policy.get("patterns") if isinstance(policy, dict) else None
        if not isinstance(patterns, list) or not patterns or any(
            not isinstance(value, str) or not value.strip() for value in patterns
        ):
            raise ScanError("invalid local private-content policy")
        private_patterns = [value.casefold().encode("utf-8") for value in patterns]

    def has_private_value(value: bytes) -> bool:
        folded = value.decode("utf-8", "replace").casefold().encode("utf-8")
        return any(pattern in folded for pattern in private_patterns)

    if revision_range is None and private_patterns:
        for identity in ["GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"]:
            if has_private_value(git(root, ["var", identity])):
                findings.append(f"{identity}: private identity; use approved public attribution")

    for path, old_oid, new_oid in changed_blobs(root, revision_range):
        old = blob(root, old_oid)
        new = blob(root, new_oid)
        display_path = "[private filename]" if has_private_value(path) else repr(os.fsdecode(path))
        parts = Path(os.fsdecode(path)).parts
        if (
            (".beads" in parts and not (
                len(parts) > 2 and parts[:2] == (".beads", "formulas")
                and ".beads" not in parts[2:]
            ))
            or ".dolt" in parts
            or any(part in {".env", ".beads-credential-key", "id_rsa", "id_ed25519"} for part in parts)
            or (parts and parts[-1].startswith(".env.") and not parts[-1].endswith((".example", ".sample", ".template")))
            or path == b"issues.jsonl"
        ):
            findings.append(f"{display_path}: private runtime or credential file")
        if has_private_value(path) or has_private_value(new):
            findings.append(f"{display_path}: matches local private-content policy (value redacted)")
        for line_number, line in added_lines(old, new):
            for match in UNIX_PATH.finditer(line):
                findings.append(f"{display_path}:{line_number}: machine-local path (value redacted)")
            for match in WINDOWS_PATH.finditer(line):
                findings.append(f"{display_path}:{line_number}: machine-local path (value redacted)")
            for match in RELATIVE_PATH.finditer(line):
                reference = match.group(1)
                if outside_reference(root, path, reference):
                    findings.append(
                        f"{display_path}:{line_number}: relative path escapes repository (value redacted)"
                    )
    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True, type=Path)
    parser.add_argument("--range", dest="revision_range")
    arguments = parser.parse_args()
    root = arguments.repository.resolve(strict=True)
    try:
        findings = scan(root, arguments.revision_range)
    except (OSError, ValueError, ScanError, subprocess.SubprocessError):
        print("privacy guard could not complete; check Git and the local privacy policy", file=sys.stderr)
        return 2
    if findings:
        print("privacy guard: private content or unsafe paths found", file=sys.stderr)
        print("\n".join(findings), file=sys.stderr)
        return 1
    print("privacy guard: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
