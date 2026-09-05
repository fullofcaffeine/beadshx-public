#!/usr/bin/env python3
"""Bind every Gitleaks exception to the exact reviewed source line."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import sys


def regular_file(root: Path, relative: str) -> Path:
    path = root / relative
    absolute = path.absolute()
    if os.path.commonpath((os.fspath(root), os.fspath(absolute))) != os.fspath(root):
        raise ValueError(f"path escapes repository: {relative}")
    details = path.lstat()
    if not stat.S_ISREG(details.st_mode):
        raise ValueError(f"path is not a regular file: {relative}")
    return path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True, type=Path)
    arguments = parser.parse_args()
    root = arguments.repository.resolve(strict=True)
    try:
        contract_path = regular_file(
            root, "engdocs/beadshx/program/gitleaks-ignore-contract.json"
        )
        ignore_path = regular_file(root, ".gitleaksignore")
        contract = json.loads(contract_path.read_text(encoding="utf-8"))
        if contract.get("schemaVersion") != 1:
            raise ValueError("unsupported Gitleaks ignore contract schema")
        exceptions = contract.get("exceptions")
        if not isinstance(exceptions, list) or not exceptions:
            raise ValueError("Gitleaks ignore contract has no exceptions")
        actual_fingerprints = [
            line
            for line in ignore_path.read_text(encoding="utf-8").splitlines()
            if line and not line.startswith("#")
        ]
        expected_fingerprints = [item.get("fingerprint") for item in exceptions]
        if actual_fingerprints != expected_fingerprints:
            raise ValueError(".gitleaksignore does not exactly match its contract")
        for item in exceptions:
            fingerprint = item["fingerprint"]
            path_text, rule, line_text = fingerprint.rsplit(":", 2)
            if not rule or not line_text.isdigit():
                raise ValueError(f"invalid exception fingerprint: {fingerprint}")
            source = regular_file(root, path_text)
            lines = source.read_bytes().splitlines()
            line_number = int(line_text)
            if line_number < 1 or line_number > len(lines):
                raise ValueError(f"exception line is missing: {fingerprint}")
            actual = hashlib.sha256(lines[line_number - 1]).hexdigest()
            if actual != item.get("lineSha256"):
                raise ValueError(f"exception content changed: {fingerprint}")
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"Gitleaks ignore contract: FAIL: {error}", file=sys.stderr)
        return 1
    print("Gitleaks ignore contract: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
