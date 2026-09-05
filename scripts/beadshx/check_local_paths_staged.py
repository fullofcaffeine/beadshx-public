#!/usr/bin/env python3
"""Reject machine-local paths introduced by staged or committed changes."""

from __future__ import annotations

import argparse
import difflib
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
            "diff-index",
            "--cached",
            "--raw",
            "-z",
            "--full-index",
            "--no-renames",
            "HEAD",
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
            "--full-index",
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
    for path, old_oid, new_oid in changed_blobs(root, revision_range):
        old = blob(root, old_oid)
        new = blob(root, new_oid)
        display_path = os.fsdecode(path)
        for line_number, line in added_lines(old, new):
            for match in UNIX_PATH.finditer(line):
                value = match.group(0).decode("utf-8", "backslashreplace")
                findings.append(f"{display_path}:{line_number}: machine-local path {value}")
            for match in WINDOWS_PATH.finditer(line):
                value = match.group(0).decode("utf-8", "backslashreplace")
                findings.append(f"{display_path}:{line_number}: machine-local path {value}")
            for match in RELATIVE_PATH.finditer(line):
                reference = match.group(1)
                if outside_reference(root, path, reference):
                    value = reference.decode("utf-8", "backslashreplace")
                    findings.append(
                        f"{display_path}:{line_number}: relative path escapes repository: {value}"
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
    except (OSError, ScanError, subprocess.SubprocessError) as error:
        print(f"local path guard could not complete: {error}", file=sys.stderr)
        return 2
    if findings:
        print("local path guard: machine-local paths found", file=sys.stderr)
        print("\n".join(findings), file=sys.stderr)
        return 1
    print("local path guard: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
