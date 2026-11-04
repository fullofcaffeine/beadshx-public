"""Exercise exact image admission without a hosted runner or real toolchain install."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RunnerImagesTest(unittest.TestCase):
    def verify(self, image, *, manifest=None, wrong_git=False):
        with tempfile.TemporaryDirectory(prefix="beadshx-runner-images-") as temp:
            root = Path(temp)
            scripts = root / "scripts/beadshx"
            scripts.mkdir(parents=True)
            for source in (ROOT / "scripts/beadshx").glob("verify-*image*.sh"):
                shutil.copy2(source, scripts)
            shutil.copy2(ROOT / "scripts/beadshx/verify-runner.sh", scripts)
            lock = json.loads((ROOT / "engdocs/beadshx/program/toolchain-locks.json").read_text())
            # Match local native tools; only the image admission is under test.
            profile = lock["linuxCi"]
            profile["bash"] = subprocess.check_output(["bash", "-c", 'printf "%s" "$BASH_VERSION"'], text=True)
            profile["git"] = subprocess.check_output(["git", "--version"], text=True).strip().removeprefix("git version ")
            profile["jq"] = subprocess.check_output(["jq", "--version"], text=True).strip()
            if manifest is not None:
                if "images" in profile:
                    for item in profile["images"]:
                        item["manifest"] = manifest
                else:
                    profile["manifest"] = manifest
            if wrong_git:
                profile["git"] = "0.0.0"
            locks = root / "engdocs/beadshx/program"
            locks.mkdir(parents=True)
            (locks / "toolchain-locks.json").write_text(json.dumps(lock))
            bindir = root / "bin"
            bindir.mkdir()
            uname = bindir / "uname"
            uname.write_text("#!/bin/sh\nprintf 'Linux\n'\n")
            uname.chmod(0o755)
            env = dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ["PATH"], ImageOS="ubuntu24")
            env.pop("ImageVersion", None)
            if image is not None:
                env["ImageVersion"] = image
            return subprocess.run(["bash", str(scripts / "verify-runner.sh"), "--profile=linux-ci"], env=env, capture_output=True, text=True, timeout=15)

    def test_each_reviewed_rollout_image_is_admitted(self):
        for image in ("20261026.354.1", "20261101.360.1"):
            with self.subTest(image=image):
                result = self.verify(image)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_unreviewed_image_is_rejected(self):
        result = self.verify("20990101.1.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("runner-image", result.stderr)

    def test_missing_image_is_rejected(self):
        result = self.verify(None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("runner-image", result.stderr)

    def test_image_without_manifest_provenance_is_rejected(self):
        result = self.verify("20261101.360.1", manifest="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("runner-image", result.stderr)


    def test_mutable_manifest_reference_is_rejected(self):
        result = self.verify("20261101.360.1", manifest="https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("runner-image", result.stderr)

    def test_reviewed_image_still_requires_exact_native_tools(self):
        result = self.verify("20261101.360.1", wrong_git=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Git mismatch", result.stderr)


if __name__ == "__main__":
    unittest.main()
