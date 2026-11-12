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


class CommitIdentityGuards(unittest.TestCase):
    """Metadata-only contracts need Git, not the separate secret scanner."""

    setUp = PrivacyGuards.setUp
    git = PrivacyGuards.git
    write = PrivacyGuards.write
    baseline = PrivacyGuards.baseline
    private_name = "Synthetic Private Display"

    def policy(self):
        self.write(".git/info/private-content-patterns.json",
                   json.dumps({"patterns": [self.private_name]}))

    def scan(self, revision_range=None, environment=None):
        command = ["python3", str(ROOT / "scripts/beadshx/check_local_paths_staged.py"),
                   "--repository", str(self.root)]
        if revision_range:
            command += ["--range", revision_range]
        return subprocess.run(command, capture_output=True, text=True, env=environment)

    def identity_environment(self, role):
        environment = os.environ.copy()
        for identity in ["AUTHOR", "COMMITTER"]:
            environment["GIT_" + identity + "_NAME"] = (
                self.private_name if role == identity else "Public fixture")
            environment["GIT_" + identity + "_EMAIL"] = "fixture@users.noreply.github.com"
        return environment

    def assert_private_rejected(self, result, role):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(role, result.stderr)
        self.assertNotIn(self.private_name, result.stdout + result.stderr)

    def test_staged_private_names_with_public_emails(self):
        self.baseline()
        self.policy()
        for role in ["AUTHOR", "COMMITTER"]:
            with self.subTest(role=role):
                self.assert_private_rejected(self.scan(environment=self.identity_environment(role)), role)

    def test_range_checks_actual_author_and_committer(self):
        self.baseline()
        base = self.git("rev-parse", "HEAD").decode().strip()
        self.policy()
        for role in ["AUTHOR", "COMMITTER"]:
            with self.subTest(role=role):
                subprocess.run(["git", "-C", str(self.root), "commit", "--allow-empty",
                                "-m", "metadata fixture"], check=True, capture_output=True,
                               env=self.identity_environment(role))
                head = self.git("rev-parse", "HEAD").decode().strip()
                self.assert_private_rejected(self.scan(base + ".." + head), role)
                base = head

    def test_range_checks_merge_commit_without_file_changes(self):
        self.baseline()
        base = self.git("rev-parse", "HEAD").decode().strip()
        self.git("checkout", "--quiet", "-b", "side")
        self.git("commit", "--quiet", "--allow-empty", "-m", "side")
        self.git("checkout", "--quiet", "--detach", base)
        self.policy()
        subprocess.run(["git", "-C", str(self.root), "merge", "--no-ff", "side",
                        "-m", "merge fixture"], check=True, capture_output=True,
                       env=self.identity_environment("COMMITTER"))
        self.assert_private_rejected(self.scan(base + "..HEAD"), "COMMITTER")

    def test_replacement_ref_cannot_hide_stored_private_identity(self):
        self.baseline()
        base = self.git("rev-parse", "HEAD").decode().strip()
        self.policy()
        subprocess.run(["git", "-C", str(self.root), "commit", "--allow-empty",
                        "-m", "private metadata fixture"], check=True, capture_output=True,
                       env=self.identity_environment("AUTHOR"))
        private_commit = self.git("rev-parse", "HEAD").decode().strip()
        tree = self.git("rev-parse", "HEAD^{tree}").decode().strip()
        replacement = self.git("commit-tree", tree, "-p", base,
                               "-m", "safe replacement fixture").decode().strip()
        self.git("replace", private_commit, replacement)
        self.assert_private_rejected(self.scan(base + "..HEAD"), "AUTHOR")

    def test_shallow_range_fails_closed_only_with_local_policy(self):
        self.baseline()
        base = self.git("rev-parse", "HEAD").decode().strip()
        self.policy()
        subprocess.run(["git", "-C", str(self.root), "commit", "--allow-empty",
                        "-m", "private ancestor fixture"], check=True, capture_output=True,
                       env=self.identity_environment("AUTHOR"))
        self.git("commit", "--quiet", "--allow-empty", "-m", "safe tip fixture")
        head = self.git("rev-parse", "HEAD").decode().strip()
        self.assert_private_rejected(self.scan(base + "..HEAD"), "AUTHOR")
        self.write(".git/shallow", head + "\n")
        result = self.scan(base + "..HEAD")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("incomplete history", result.stderr)
        self.assertNotIn(self.private_name, result.stdout + result.stderr)
        self.assertNotIn(base, result.stderr)
        (self.root / ".git/info/private-content-patterns.json").unlink()
        self.assertEqual(self.scan(base + "..HEAD").returncode, 0)

    def test_empty_range_with_local_policy_passes(self):
        self.baseline()
        self.policy()
        result = self.scan("HEAD..HEAD")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_unrelated_identity_and_missing_local_policy_remain_allowed(self):
        self.baseline()
        base = self.git("rev-parse", "HEAD").decode().strip()
        self.git("commit", "--quiet", "--allow-empty", "-m", "contributor fixture")
        self.policy()
        self.assertEqual(self.scan(base + "..HEAD").returncode, 0)
        (self.root / ".git/info/private-content-patterns.json").unlink()
        subprocess.run(["git", "-C", str(self.root), "commit", "--allow-empty",
                        "-m", "no local policy fixture"], check=True, capture_output=True,
                       env=self.identity_environment("AUTHOR"))
        self.assertEqual(self.scan(base + "..HEAD").returncode, 0)


class PrePushPrivacyGuards(unittest.TestCase):
    """Use the real hook and an owned bare remote, never a database or network."""

    private_name = "Synthetic Private Display"

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="beadshx-push-privacy-")
        self.addCleanup(self.temporary.cleanup)
        self.fixture = Path(self.temporary.name)
        self.root = self.fixture / "checkout"
        self.root.mkdir()
        (self.fixture / ".beadshx-disposable-fixture").touch()
        self.environment = os.environ.copy()
        for key in list(self.environment):
            if key.startswith(("GIT_", "BEADS_", "BD_")):
                self.environment.pop(key)
        home = self.fixture / "home"
        home.mkdir()
        self.environment.update(HOME=str(home), GIT_CONFIG_NOSYSTEM="1",
                                GIT_CONFIG_GLOBAL=os.devnull)
        self.receipt = self.fixture / "bd-receipt.json"
        binary = self.fixture / "bin"
        binary.mkdir()
        recorder = binary / "bd"
        recorder.write_text("#!/usr/bin/env python3\nimport json, os, sys\n"
                            "with open(os.environ['HOOK_BD_RECEIPT'], 'w') as output:\n"
                            "    json.dump({'args': sys.argv[1:], 'stdin': sys.stdin.read(), "
                            "'hook': os.environ.get('BD_GIT_HOOK')}, output)\n"
                            "sys.exit(int(os.environ.get('HOOK_BD_EXIT', '0')))\n")
        recorder.chmod(0o755)
        self.environment.update(PATH=str(binary) + os.pathsep + os.environ["PATH"],
                                HOOK_BD_RECEIPT=str(self.receipt))
        self.git("init", "--quiet")
        self.git("config", "user.name", "Public fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "core.hooksPath", ".githooks")
        for relative in [".githooks/pre-push", "scripts/beadshx/check-local-paths-staged.sh",
                         "scripts/beadshx/check_local_paths_staged.py"]:
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, destination)
        self.write("README.md", "safe\n")
        self.git("add", ".")
        self.commit("baseline")
        self.remote = self.fixture / "remote.git"
        subprocess.run(["git", "init", "--quiet", "--bare", str(self.remote)],
                       check=True, env=self.environment, capture_output=True)
        self.git("remote", "add", "origin", str(self.remote))

    def git(self, *args, environment=None):
        return subprocess.check_output(["git", "-C", str(self.root), *args],
                                       env=environment or self.environment,
                                       stderr=subprocess.PIPE)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def commit(self, message, role=None):
        environment = self.environment.copy()
        if role:
            environment["GIT_" + role + "_NAME"] = self.private_name
            environment["GIT_" + role + "_EMAIL"] = "fixture@users.noreply.github.com"
        # Deliberately construct invalid inputs without running unrelated hooks.
        self.git("-c", "core.hooksPath=" + os.devnull, "commit", "--quiet",
                 "--allow-empty", "-m", message, environment=environment)
        return self.git("rev-parse", "HEAD").decode().strip()

    def policy(self):
        common = Path(self.git("rev-parse", "--git-common-dir").decode().strip())
        if not common.is_absolute():
            common = self.root / common
        path = common / "info/private-content-patterns.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"patterns": [self.private_name]}))

    def push(self, *refs):
        return subprocess.run(["git", "-C", str(self.root), "push", "origin", *refs],
                              env=self.environment, capture_output=True, text=True)

    def remote_oid(self, ref):
        return subprocess.check_output(["git", "--git-dir", str(self.remote),
                                        "rev-parse", "--verify", ref],
                                       env=self.environment, stderr=subprocess.PIPE).decode().strip()

    def assert_remote_missing(self, ref):
        result = subprocess.run(["git", "--git-dir", str(self.remote),
                                 "rev-parse", "--verify", ref], env=self.environment,
                                capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def hook(self, tuples):
        return subprocess.run([str(self.root / ".githooks/pre-push"), "origin", str(self.remote)],
                              cwd=self.root, env=self.environment, input=tuples,
                              capture_output=True, text=True)

    def assert_blocked(self, result):
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.receipt.exists())
        self.assertNotIn(self.private_name, result.stdout + result.stderr)

    def test_real_push_rejects_unsafe_stored_author_before_beads(self):
        baseline = self.git("rev-parse", "HEAD").decode().strip()
        result = self.push("HEAD:refs/heads/main")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.policy()
        self.commit("unsafe metadata", "AUTHOR")
        self.receipt.unlink()
        result = self.push("HEAD:refs/heads/main")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.remote_oid("refs/heads/main"), baseline)
        self.assertFalse(self.receipt.exists())
        self.assertNotIn(self.private_name, result.stdout + result.stderr)

    def test_safe_contributor_and_missing_policy_keep_normal_push_behavior(self):
        self.policy()
        self.git("config", "user.name", "External contributor")
        self.git("config", "user.email", "contributor@example.invalid")
        head = self.commit("safe contributor")
        result = self.push("HEAD:refs/heads/main")
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = json.loads(self.receipt.read_text())
        self.assertEqual(receipt, {"args": ["hooks", "run", "pre-push", "origin", str(self.remote)],
                                   "stdin": "HEAD " + head + " refs/heads/main " + "0" * len(head) + "\n",
                                   "hook": "1"})
        (self.root / ".git/info/private-content-patterns.json").unlink()
        head = self.commit("missing local policy", "COMMITTER")
        result = self.push("HEAD:refs/heads/main")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.remote_oid("refs/heads/main"), head)

    def test_multiple_refs_include_unsafe_non_head_and_publish_nothing(self):
        baseline = self.git("rev-parse", "HEAD").decode().strip()
        self.git("checkout", "--quiet", "-b", "unsafe")
        self.commit("unsafe side", "COMMITTER")
        self.git("checkout", "--quiet", "--detach", baseline)
        self.commit("safe head")
        self.policy()
        result = self.push("HEAD:refs/heads/safe", "unsafe:refs/heads/unsafe")
        self.assert_blocked(result)
        self.assert_remote_missing("refs/heads/safe")
        self.assert_remote_missing("refs/heads/unsafe")

    def test_new_branch_walks_ancestors_without_exempting_private_backup_refs(self):
        baseline = self.git("rev-parse", "HEAD").decode().strip()
        self.git("checkout", "--quiet", "-b", "unsafe")
        unsafe = self.commit("unsafe ancestor", "AUTHOR")
        self.commit("safe tip")
        self.git("update-ref", "refs/remotes/private-backup/saved", unsafe)
        self.git("checkout", "--quiet", "--detach", baseline)
        self.policy()
        result = self.push("HEAD:refs/heads/safe")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.receipt.unlink()
        result = self.push("unsafe:refs/heads/new")
        self.assert_blocked(result)
        self.assert_remote_missing("refs/heads/new")

    def test_forced_replacement_scans_new_side_of_diverged_history(self):
        baseline = self.git("rev-parse", "HEAD").decode().strip()
        old = self.commit("old public tip")
        self.assertEqual(self.push("HEAD:refs/heads/main").returncode, 0)
        self.git("checkout", "--quiet", "--detach", baseline)
        self.commit("unsafe divergent tip", "COMMITTER")
        self.policy()
        self.receipt.unlink()
        result = self.push("+HEAD:refs/heads/main")
        self.assert_blocked(result)
        self.assertEqual(self.remote_oid("refs/heads/main"), old)

    def test_deletion_empty_and_unchanged_updates_preserve_beads_input(self):
        head = self.commit("already public without policy", "AUTHOR")
        self.assertEqual(self.push("HEAD:refs/heads/main").returncode, 0)
        self.policy()
        result = self.push(":refs/heads/main")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_remote_missing("refs/heads/main")
        receipt = json.loads(self.receipt.read_text())
        self.assertEqual(receipt["stdin"], "(delete) " + "0" * len(head) +
                         " refs/heads/main " + head + "\n")
        for tuples in ["", "HEAD " + head + " refs/heads/main " + head + "\n"]:
            with self.subTest(tuples=tuples):
                result = self.hook(tuples)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(self.receipt.read_text())["stdin"], tuples or "\n")

    def test_annotated_and_nested_tags_check_taggers_without_rewriting(self):
        self.policy()
        environment = self.environment.copy()
        environment.update(GIT_COMMITTER_NAME=self.private_name,
                           GIT_COMMITTER_EMAIL="fixture@users.noreply.github.com")
        self.git("tag", "-a", "inner", "-m", "fixture", environment=environment)
        self.git("tag", "-a", "outer", "inner", "-m", "nested fixture")
        for tag in ["inner", "outer"]:
            with self.subTest(tag=tag):
                before = self.git("rev-parse", tag)
                result = self.push("refs/tags/" + tag)
                self.assert_blocked(result)
                self.assertIn("TAGGER", result.stderr)
                self.assertEqual(self.git("rev-parse", tag), before)
                self.assert_remote_missing("refs/tags/" + tag)
        self.git("tag", "lightweight")
        self.git("tag", "-a", "safe-annotated", "-m", "safe fixture")
        result = self.push("refs/tags/lightweight", "refs/tags/safe-annotated")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_local_merge_metadata_is_checked_even_without_file_changes(self):
        baseline = self.git("rev-parse", "HEAD").decode().strip()
        self.git("checkout", "--quiet", "-b", "side")
        self.commit("side")
        self.git("checkout", "--quiet", "--detach", baseline)
        environment = self.environment.copy()
        environment["GIT_COMMITTER_NAME"] = self.private_name
        self.git("merge", "--no-ff", "side", "-m", "merge fixture", environment=environment)
        self.policy()
        result = self.push("HEAD:refs/heads/main")
        self.assert_blocked(result)
        self.assertIn("COMMITTER", result.stderr)
        self.assert_remote_missing("refs/heads/main")

    def test_worktree_uses_its_code_and_shared_private_policy(self):
        self.policy()
        worktree = self.fixture / "linked"
        self.git("worktree", "add", "--quiet", "--detach", str(worktree), "HEAD")
        self.root = worktree
        self.assertTrue((self.root / ".git").is_file())
        self.commit("linked unsafe author", "AUTHOR")
        result = self.push("HEAD:refs/heads/main")
        self.assert_blocked(result)
        self.assert_remote_missing("refs/heads/main")

    def test_pre_push_replacement_ref_cannot_hide_unsafe_stored_identity(self):
        baseline = self.git("rev-parse", "HEAD").decode().strip()
        unsafe = self.commit("unsafe raw metadata", "AUTHOR")
        self.git("checkout", "--quiet", "--detach", baseline)
        replacement = self.commit("safe replacement")
        self.git("replace", unsafe, replacement)
        self.policy()
        result = self.push(unsafe + ":refs/heads/main")
        self.assert_blocked(result)
        self.assertIn(unsafe, result.stderr)
        self.assertIn("AUTHOR", result.stderr)
        self.assert_remote_missing("refs/heads/main")

    def test_malformed_input_missing_objects_and_policy_fail_closed(self):
        self.policy()
        head = self.git("rev-parse", "HEAD").decode().strip()
        zero = "0" * len(head)
        for tuples in ["unexpected fields\n", "HEAD invalid refs/heads/main " + zero + "\n",
                       "HEAD " + "1" * len(head) + " refs/heads/main " + zero + "\n",
                       "HEAD " + head + " refs/heads/main " + "1" * len(head) + "\n"]:
            with self.subTest(tuples=tuples):
                self.assert_blocked(self.hook(tuples))
        (self.root / ".git/info/private-content-patterns.json").write_text('{"patterns": [""]}')
        self.assert_blocked(self.push("HEAD:refs/heads/main"))
        self.assert_remote_missing("refs/heads/main")

    def test_private_data_refs_never_reach_beads_or_disposable_remote(self):
        for destination in ["refs/dolt/data", "refs/heads/__dolt_remote_info__"]:
            with self.subTest(destination=destination):
                self.assert_blocked(self.push("HEAD:" + destination))
                self.assert_remote_missing(destination)
        head = self.git("rev-parse", "HEAD").decode().strip()
        self.git("update-ref", "refs/dolt/data", head)
        self.assert_blocked(self.push("refs/dolt/data:refs/heads/disguised"))
        self.assert_remote_missing("refs/heads/disguised")

    def test_release_check_still_blocks_before_beads_and_preserves_stdin(self):
        self.policy()
        helper = self.root / "scripts/check-versions.sh"
        helper.write_text("#!/bin/sh\necho release-fixture-checked >&2\nexit 7\n")
        helper.chmod(0o755)
        self.git("tag", "v0.0.0")
        result = self.push("refs/tags/v0.0.0")
        self.assert_blocked(result)
        self.assertIn("release-fixture-checked", result.stderr)
        self.assert_remote_missing("refs/tags/v0.0.0")
        helper.write_text("#!/bin/sh\nexit 0\n")
        result = self.push("refs/tags/v0.0.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(self.receipt.read_text())["stdin"].startswith("refs/tags/v0.0.0 "))

    def test_beads_exit_and_timeout_contracts_are_unchanged(self):
        self.policy()
        timeout = self.fixture / "bin/timeout"
        timeout.write_text("#!/bin/sh\nif [ \"$1\" = --version ]; then\n"
                           "  echo 'timeout (GNU coreutils) fixture'; exit 0\nfi\n"
                           "printf '%s\\n' \"$2\" > \"$HOOK_TIMEOUT_RECEIPT\"\n"
                           "shift; shift\n\"$@\"\n")
        timeout.chmod(0o755)
        timeout_receipt = self.fixture / "timeout-seconds"
        self.environment.update(BEADS_HOOK_TIMEOUT="17", HOOK_TIMEOUT_RECEIPT=str(timeout_receipt))
        for status in [37, 3, 124]:
            with self.subTest(status=status):
                self.commit("beads status fixture")
                self.environment["HOOK_BD_EXIT"] = str(status)
                result = self.push("HEAD:refs/heads/main")
                self.assertEqual(result.returncode == 0, status in {3, 124}, result.stderr)
                self.assertEqual(timeout_receipt.read_text(), "17\n")
                self.assertEqual(json.loads(self.receipt.read_text())["args"],
                                 ["hooks", "run", "pre-push", "origin", str(self.remote)])
                if status == 37:
                    self.assert_remote_missing("refs/heads/main")


if __name__ == "__main__":
    unittest.main()
