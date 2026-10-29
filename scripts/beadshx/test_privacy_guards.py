#!/usr/bin/env python3
"""Exercise publication guards against real staged Git data in disposable repos."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class PrivacyGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Bootstrap invokes this suite before the separate secret-scan lane.
        # Prepare the real pinned scanner once, before creating isolated repos.
        verifier = ROOT / "scripts/beadshx/verify-gitleaks.sh"
        if subprocess.run([str(verifier)], capture_output=True).returncode != 0:
            subprocess.run([str(ROOT / "scripts/beadshx/install-gitleaks.sh")], check=True)
        subprocess.run([str(verifier)], check=True, capture_output=True)

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="beadshx-privacy-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git("init", "--quiet")
        self.git("config", "user.name", "Safety fixture")
        self.git("config", "user.email", "safety@example.invalid")
        self.git("config", "core.hooksPath", "/dev/null")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args])

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def guard(self):
        return subprocess.run(
            ["python3", str(ROOT / "scripts/beadshx/check_local_paths_staged.py"),
             "--repository", str(self.root)], capture_output=True, text=True,
        )

    def baseline(self):
        self.write("README.md", "safe\n")
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "baseline")

    def test_safe_initial_commit(self):
        self.write("README.md", "safe\n")
        self.git("add", ".")
        result = self.guard()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_private_content_is_read_from_index_and_redacted(self):
        self.baseline()
        value = "private fixture identity"
        self.write(".git/info/private-content-patterns.json", json.dumps({"patterns": [value]}))
        self.write("README.md", value + "\n")
        self.git("add", ".")
        self.write("README.md", "safe unstaged copy\n")
        result = self.guard()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(value, result.stdout + result.stderr)

    def test_private_filename_is_rejected(self):
        self.baseline()
        for filename in [".beads/issues.jsonl", "example/project/.beads/issues.jsonl"]:
            with self.subTest(filename=filename):
                self.write(filename, "private task data\n")
                self.git("add", "-f", filename)
                self.assertNotEqual(self.guard().returncode, 0)
                self.git("reset", "--quiet", "HEAD", "--", filename)

    def test_private_commit_identity_is_rejected(self):
        self.baseline()
        self.write(".git/info/private-content-patterns.json",
                   json.dumps({"patterns": ["private-person@example.invalid"]}))
        self.git("config", "user.email", "private-person@example.invalid")
        result = self.guard()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("private-person@example.invalid", result.stdout + result.stderr)

    def test_malformed_local_privacy_policy_fails_closed(self):
        self.baseline()
        self.write(".git/info/private-content-patterns.json", '{"patterns": [""]}')
        self.assertNotEqual(self.guard().returncode, 0)

    def test_real_commit_author_override_is_rejected(self):
        self.baseline()
        self.write(".git/info/private-content-patterns.json",
                   json.dumps({"patterns": ["private-person@example.invalid"]}))
        self.write("README.md", "changed\n")
        self.git("add", "README.md")
        guard = ROOT / "scripts/beadshx/check_local_paths_staged.py"
        self.write(".git/hooks/pre-commit", "#!/bin/sh\nexec python3 " +
                   shlex.quote(str(guard)) + " --repository " + shlex.quote(str(self.root)) + "\n")
        (self.root / ".git/hooks/pre-commit").chmod(0o755)
        self.git("config", "--unset", "core.hooksPath")
        result = subprocess.run(["git", "-C", str(self.root), "commit", "--quiet",
                                 "--author", "Private fixture <private-person@example.invalid>",
                                 "-m", "fixture"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("GIT_AUTHOR_IDENT", result.stderr)
        self.assertNotIn("private-person@example.invalid", result.stderr)

    def test_local_path_diagnostic_does_not_echo_value(self):
        self.baseline()
        value = "/" + "Users/fixture-person/private"
        self.write("README.md", value + "\n")
        self.git("add", ".")
        result = self.guard()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(value, result.stdout + result.stderr)

    def setup_secret_policy(self):
        self.baseline()
        for name in ["check-staged-secrets.sh", "verify-gitleaks.sh",
                     "check_gitleaks_ignore_contract.py", "materialize_scan_tree.py", "gitleaks.toml"]:
            source = ROOT / "scripts/beadshx" / name
            if source.exists():
                target = self.root / "scripts/beadshx" / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
        self.write("engdocs/beadshx/program/toolchain-locks.json",
                   (ROOT / "engdocs/beadshx/program/toolchain-locks.json").read_text())
        scanner = self.root / ".toolchains/bin/gitleaks"
        scanner.parent.mkdir(parents=True)
        scanner.symlink_to(ROOT / ".toolchains/bin/gitleaks")
        self.write("fixture.txt", "reviewed fixture\n")
        fingerprint = "fixture.txt:generic-api-key:1"
        self.write(".gitleaksignore", fingerprint + "\n")
        self.write("engdocs/beadshx/program/gitleaks-ignore-contract.json", json.dumps({
            "schemaVersion": 1, "exceptions": [{"fingerprint": fingerprint,
                "lineSha256": hashlib.sha256(b"reviewed fixture").hexdigest()}],
        }))
        self.git("add", "scripts", "engdocs", "fixture.txt", ".gitleaksignore")
        self.git("commit", "--quiet", "-m", "policy fixture")

    def secret_guard(self, env=None):
        return subprocess.run([str(self.root / "scripts/beadshx/check-staged-secrets.sh")],
                              capture_output=True, text=True, env=env)

    def test_staged_exception_cannot_borrow_safe_worktree_bytes(self):
        self.setup_secret_policy()
        self.write("fixture.txt", "changed exception\n")
        self.git("add", "fixture.txt")
        self.write("fixture.txt", "reviewed fixture\n")
        self.assertNotEqual(self.secret_guard().returncode, 0)

    def test_safe_staged_tree_passes_without_changing_index(self):
        self.setup_secret_policy()
        self.write("new.txt", "safe fixture\n")
        self.git("add", "new.txt")
        before = (self.root / ".git/index").read_bytes()
        result = self.secret_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, (self.root / ".git/index").read_bytes())

    def test_unstaged_scanner_config_cannot_hide_staged_secret(self):
        self.setup_secret_policy()
        value = "ghp_" + hashlib.sha256(b"synthetic publication fixture").hexdigest()[:36]
        self.write("new.txt", "token=" + value + "\n")
        self.git("add", "new.txt")
        self.write("scripts/beadshx/gitleaks.toml", '[allowlist]\nregexes = [".*"]\n')
        self.assertNotEqual(self.secret_guard().returncode, 0)

    def test_unstaged_ignore_cannot_authorize_staged_secret(self):
        self.setup_secret_policy()
        value = "ghp_" + hashlib.sha256(b"synthetic publication fixture").hexdigest()[:36]
        self.write("new.txt", "token=" + value + "\n")
        self.git("add", "new.txt")
        fingerprint = "new.txt:github-pat:1"
        self.write(".gitleaksignore", fingerprint + "\n")
        self.write("engdocs/beadshx/program/gitleaks-ignore-contract.json", json.dumps({
            "schemaVersion": 1, "exceptions": [{"fingerprint": fingerprint,
                "lineSha256": hashlib.sha256(("token=" + value).encode()).hexdigest()}],
        }))
        self.assertNotEqual(self.secret_guard().returncode, 0)

    def test_export_ignore_cannot_hide_staged_secret(self):
        self.setup_secret_policy()
        value = "ghp_" + hashlib.sha256(b"synthetic publication fixture").hexdigest()[:36]
        self.write("new.txt", "token=" + value + "\n")
        self.write(".gitattributes", "new.txt export-ignore\n")
        self.git("add", "new.txt", ".gitattributes")
        self.assertNotEqual(self.secret_guard().returncode, 0)

    def test_scan_materializer_does_not_follow_symlinks(self):
        self.baseline()
        (self.root / "link").symlink_to("README.md")
        self.git("add", "link")
        tree = self.git("write-tree").decode().strip()
        target = self.root / "scan"
        target.mkdir()
        subprocess.run(["python3", str(ROOT / "scripts/beadshx/materialize_scan_tree.py"),
                        "--repository", str(self.root), "--tree", tree,
                        "--destination", str(target)], check=True)
        self.assertFalse((target / "link").is_symlink())
        self.assertEqual((target / "link").read_text(), "README.md")

    def test_inline_allow_and_environment_config_cannot_hide_secret(self):
        self.setup_secret_policy()
        # Public synthetic scanner fixture, assembled to avoid a real credential.
        value = "ghp_" + hashlib.sha256(b"synthetic publication fixture").hexdigest()[:36]
        for inline, override in [(True, False), (False, True), (True, True)]:
            with self.subTest(inline=inline, override=override):
                annotation = " # gitleaks:" + "allow" if inline else ""
                self.write("new.txt", "token=" + value + annotation + "\n")
                self.git("add", "new.txt")
                environment = os.environ.copy()
                if override:
                    environment["GITLEAKS_CONFIG_TOML"] = '[allowlist]\nregexes = [".*"]\n'
                result = self.secret_guard(environment)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(value, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
