#!/usr/bin/env python3
"""Copy Git blob bytes for scanning, without filters, archive attributes or links.

Symlink targets are scanned as text, never followed. This is a scanner input,
not a build checkout. In particular, export-ignore must not hide a staged file.
"""

import argparse
from pathlib import Path, PurePosixPath
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True, type=Path)
    parser.add_argument("--tree", required=True)
    parser.add_argument("--destination", required=True, type=Path)
    args = parser.parse_args()
    root = args.destination.resolve(strict=True)
    if any(root.iterdir()):
        raise ValueError("scan destination must be empty")
    command = ["git", "-C", str(args.repository)]
    entries = subprocess.check_output(command + ["ls-tree", "-rz", "--full-tree", args.tree])
    reader = subprocess.Popen(command + ["cat-file", "--batch"],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    try:
        for entry in entries.split(b"\0"):
            if not entry:
                continue
            metadata, name = entry.split(b"\t", 1)
            mode, kind, oid = metadata.split()
            if kind != b"blob" or mode not in {b"100644", b"100755", b"120000"}:
                raise ValueError("scan tree contains an unsupported entry")
            relative = PurePosixPath(name.decode("utf-8", "surrogateescape"))
            if relative.is_absolute() or ".." in relative.parts or ".git" in relative.parts:
                raise ValueError("scan tree contains an unsafe path")
            path = root.joinpath(*relative.parts)
            path.parent.mkdir(parents=True, exist_ok=True)
            reader.stdin.write(oid + b"\n")
            reader.stdin.flush()
            header = reader.stdout.readline().split()
            if len(header) != 3 or header[1] != b"blob":
                raise ValueError("Git did not return the requested blob")
            size = int(header[2])
            data = reader.stdout.read(size)
            if len(data) != size or reader.stdout.read(1) != b"\n":
                raise ValueError("Git returned a truncated blob")
            with path.open("xb") as output:
                output.write(data)
    finally:
        reader.stdin.close()
        reader.stdout.close()
        reader.wait()
    if reader.returncode != 0:
        raise ValueError("Git blob reader failed")


if __name__ == "__main__":
    main()
