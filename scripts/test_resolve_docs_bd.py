#!/usr/bin/env python3
"""Resolve the upstream docs release when the code fork has no release tags."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class ResolveDocsRelease(unittest.TestCase):
    def test_tag_is_fetched_from_upstream_in_a_tagless_fork(self):
        with tempfile.TemporaryDirectory(prefix="beadshx-docs-pin-") as temporary:
            root = Path(temporary)
            environment = os.environ.copy()
            environment.update(HOME=str(root), GIT_CONFIG_GLOBAL=str(root / "gitconfig"),
                               GIT_CONFIG_NOSYSTEM="1", GIT_TERMINAL_PROMPT="0")

            def git(*args, cwd=root):
                return subprocess.check_output(["git", *args], cwd=cwd, env=environment,
                                               stderr=subprocess.PIPE, text=True).strip()

            for name in ["upstream", "fork"]:
                (root / name).mkdir()
                git("init", "--quiet", cwd=root / name)
                git("-c", "user.name=Docs fixture", "-c", "user.email=docs@example.invalid",
                    "commit", "--allow-empty", "--quiet", "-m", name + " fixture", cwd=root / name)
            git("tag", "v1.1.0", cwd=root / "upstream")
            upstream_commit = git("rev-parse", "HEAD", cwd=root / "upstream")
            fork = root / "fork"
            git("remote", "add", "origin", str(root / "fork"), cwd=fork)
            git("config", "--global", f"url.{(root / 'upstream').as_uri()}.insteadOf",
                "https://github.com/gastownhall/beads.git")
            (fork / "docs").mkdir()
            (fork / "docs/cli-docs.pin").write_text("v1.1.0\n")
            (fork / "scripts").mkdir()
            shutil.copy2(Path(__file__).with_name("resolve-docs-bd.sh"), fork / "scripts")

            # The boundary under test is source selection; do not compile the
            # product in this fixture. Record the source revision at build time.
            (root / "bin").mkdir()
            compiler = root / "bin/go"
            compiler.write_text('#!/bin/sh\nset -eu\nwhile [ "$1" != "-o" ]; do shift; done\n'
                                'shift\ngit rev-parse HEAD > "$1"\nchmod +x "$1"\n')
            compiler.chmod(0o755)
            environment["PATH"] = str(root / "bin") + os.pathsep + environment["PATH"]
            result = subprocess.run([str(fork / "scripts/resolve-docs-bd.sh")],
                                    env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(Path(result.stdout.strip()).read_text().strip(), upstream_commit)
            self.assertEqual(git("rev-parse", "refs/tags/v1.1.0", cwd=fork), upstream_commit)


if __name__ == "__main__":
    unittest.main()
