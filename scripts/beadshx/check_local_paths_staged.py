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


def private_patterns(root: Path) -> list[bytes]:
    """Share the same local-only policy across linked worktrees and scan modes."""
    common = Path(os.fsdecode(git(root, ["rev-parse", "--git-common-dir"]).strip()))
    if not common.is_absolute():
        common = root / common
    policy_path = common / "info/private-content-patterns.json"
    if policy_path.exists():
        policy = json.loads(policy_path.read_text(encoding="utf-8"))
        patterns = policy.get("patterns") if isinstance(policy, dict) else None
        if not isinstance(patterns, list) or not patterns or any(
            not isinstance(value, str) or not value.strip() for value in patterns
        ):
            raise ScanError("invalid local private-content policy")
        return [value.casefold().encode("utf-8") for value in patterns]
    return []


def has_private_value(value: bytes, patterns: list[bytes]) -> bool:
    folded = value.decode("utf-8", "replace").casefold().encode("utf-8")
    return any(pattern in folded for pattern in patterns)


def commit_identities(root: Path, revisions: list[str], patterns: list[bytes]) -> list[str]:
    """Read stored identities, including empty commits and all merge parents.

    Revisions travel on standard input, so a long list of published exclusions
    cannot exceed the command-line limit or be read as an option.
    """
    if git(root, ["rev-parse", "--is-shallow-repository"]).strip() == b"true":
        return ["commit metadata: incomplete history; fetch full history before scanning a range"]
    metadata = git(root, [
        "--no-replace-objects", "log", "-z", "--encoding=UTF-8",
        "--format=%H%x00%an%x00%ae%x00%cn%x00%ce",
        "--stdin", "--",
    ], input_bytes="".join(revision + "\n" for revision in revisions).encode("ascii"))
    fields = metadata.split(b"\0")
    if fields.pop() != b"" or len(fields) % 5:
        raise ScanError("Git returned malformed commit metadata")
    findings: list[str] = []
    for index in range(0, len(fields), 5):
        oid, author_name, author_email, committer_name, committer_email = fields[index:index + 5]
        for role, name, email in [
            ("AUTHOR", author_name, author_email),
            ("COMMITTER", committer_name, committer_email),
        ]:
            if has_private_value(name, patterns) or has_private_value(email, patterns):
                findings.append(
                    f"commit {oid.decode('ascii')}: {role}: private identity; "
                    "use approved public attribution"
                )
    return findings


def tag_target(root: Path, oid: str, patterns: list[bytes], oid_pattern: re.Pattern[bytes]) \
        -> tuple[str | None, list[str]]:
    """Check every annotated tagger before peeling to a commit, tree, or blob."""
    findings: list[str] = []
    while True:
        kind = git(root, ["--no-replace-objects", "cat-file", "-t", oid]).strip()
        if kind == b"commit":
            return oid, findings
        if kind in {b"tree", b"blob"}:
            return None, findings
        if kind != b"tag":
            raise ScanError("unsupported outgoing object type")
        headers = git(root, ["--no-replace-objects", "cat-file", "tag", oid]).split(b"\n\n", 1)[0]
        targets = [line[7:] for line in headers.splitlines() if line.startswith(b"object ")]
        taggers = [line[7:] for line in headers.splitlines() if line.startswith(b"tagger ")]
        if len(targets) != 1 or not oid_pattern.fullmatch(targets[0]) or len(taggers) > 1:
            raise ScanError("malformed outgoing tag")
        if any(has_private_value(tagger, patterns) for tagger in taggers):
            findings.append(f"tag {oid}: TAGGER: private identity; use approved public attribution")
        oid = targets[0].decode("ascii")


def published_commits(root: Path, destination: str, oid_pattern: re.Pattern[bytes]) -> list[str]:
    """List local commits that the push destination itself already advertises.

    Commits that the destination already has are already public there, so a
    push cannot newly expose them. Only the destination's own answer counts:
    local refs, including remote-tracking refs, never exempt a commit. If the
    destination cannot be read, the push fails closed.
    """
    if not destination or destination.startswith("-"):
        raise ScanError("invalid push destination")
    advertised = git(root, ["ls-remote", destination])
    oids: list[bytes] = []
    for line in advertised.splitlines():
        fields = line.split(b"\t")
        if len(fields) != 2 or not oid_pattern.fullmatch(fields[0]):
            raise ScanError("malformed destination ref advertisement")
        oids.append(fields[0])
    if not oids:
        return []
    # A peeled tag line (`ref^{}`) names its commit, so commits alone suffice.
    kinds = git(root, ["--no-replace-objects", "cat-file", "--batch-check=%(objectname) %(objecttype)"],
                input_bytes=b"\n".join(dict.fromkeys(oids)) + b"\n")
    commits: list[str] = []
    for line in kinds.splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[1] == b"commit" and oid_pattern.fullmatch(fields[0]):
            commits.append(fields[0].decode("ascii"))
    return commits


def outgoing_identities(root: Path, ref_input: bytes, destination: str) -> list[str]:
    """Check Git's actual push tuples without trusting HEAD or local refs."""
    oid_size = len(git(root, ["hash-object", "--stdin"], input_bytes=b"").strip())
    oid_pattern = re.compile(rb"[0-9a-f]{" + str(oid_size).encode("ascii") + rb"}")
    updates: list[tuple[str, str]] = []
    # The shell hook's existing capture/replay yields one blank line for no refs.
    for line in ref_input.splitlines() if ref_input.strip() else []:
        fields = line.split()
        if len(fields) != 4:
            raise ScanError("malformed pre-push ref tuple")
        local_ref, local_oid, remote_ref, remote_oid = fields
        if not oid_pattern.fullmatch(local_oid) or not oid_pattern.fullmatch(remote_oid) \
                or not remote_ref.startswith(b"refs/"):
            raise ScanError("malformed pre-push object or ref")
        if any(ref.startswith(b"refs/dolt/") or ref.split(b"/")[-1] == b"__dolt_remote_info__"
               for ref in (local_ref, remote_ref)):
            return ["outgoing ref: private Beads data must not be pushed from the code repository"]
        if ZERO_OID.fullmatch(local_oid):
            if local_ref != b"(delete)" or ZERO_OID.fullmatch(remote_oid):
                raise ScanError("malformed deleted ref")
            continue
        if local_oid != remote_oid:
            updates.append((local_oid.decode("ascii"), remote_oid.decode("ascii")))
    if not updates:
        return []
    patterns = private_patterns(root)
    if not patterns:
        return []
    published = published_commits(root, destination, oid_pattern)
    findings: list[str] = []
    for local_oid, remote_oid in updates:
        local_commit, tag_findings = tag_target(root, local_oid, patterns, oid_pattern)
        findings.extend(tag_findings)
        if local_commit is None:
            continue
        exclusions = list(published)
        if not ZERO_OID.fullmatch(remote_oid.encode("ascii")):
            remote_commit, _ = tag_target(root, remote_oid, [], oid_pattern)
            if remote_commit:
                exclusions.append(remote_commit)
        # Scan only what the destination does not already have.
        revisions = [local_commit, *("^" + commit for commit in exclusions)]
        findings.extend(commit_identities(root, revisions, patterns))
    return list(dict.fromkeys(findings))


def scan(root: Path, revision_range: str | None) -> list[str]:
    findings: list[str] = []
    patterns = private_patterns(root)
    if revision_range is None and patterns:
        for identity in ["GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"]:
            if has_private_value(git(root, ["var", identity]), patterns):
                findings.append(f"{identity}: private identity; use approved public attribution")

    if revision_range is not None and patterns:
        findings.extend(commit_identities(root, [revision_range], patterns))

    for path, old_oid, new_oid in changed_blobs(root, revision_range):
        old = blob(root, old_oid)
        new = blob(root, new_oid)
        display_path = "[private filename]" if has_private_value(path, patterns) else repr(os.fsdecode(path))
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
        if has_private_value(path, patterns) or has_private_value(new, patterns):
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
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--range", dest="revision_range")
    mode.add_argument("--pre-push", metavar="DESTINATION", dest="push_destination",
                      help="check push tuples on stdin against this push destination URL")
    arguments = parser.parse_args()
    root = arguments.repository.resolve(strict=True)
    try:
        findings = outgoing_identities(root, sys.stdin.buffer.read(), arguments.push_destination) \
            if arguments.push_destination is not None else scan(root, arguments.revision_range)
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
