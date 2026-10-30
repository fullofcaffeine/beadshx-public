#!/usr/bin/env python3
"""Keep upgrade sources within the fork's supported version range."""

import json
from pathlib import Path
import subprocess
import unittest


FILTER = Path(__file__).with_name("upgrade-release-matrix.jq")


def release(tag, **flags):
    return {"tag_name": tag, "draft": False, "prerelease": False, **flags}


class UpgradeReleaseMatrix(unittest.TestCase):
    def select(self, pages, target="v1.2.1", count=5):
        return subprocess.run(
            ["jq", "-ce", "--arg", "target", target, "--argjson", "count",
             json.dumps(count), "-f", str(FILTER)],
            input=json.dumps(pages), capture_output=True, text=True,
        )

    def test_supported_sources_sorted_numerically_across_pages(self):
        result = self.select([
            [release("v1.1.9"), release("v1.3.0"), release("v1.2.1")],
            [release("v1.1.10"), release("v1.2.0"), release("v1.2.1")],
        ], count=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["v1.2.1", "v1.2.0", "v1.1.10"])

    def test_drafts_prereleases_and_nonversion_tags_are_excluded(self):
        result = self.select([[release("v1.2.1", draft=True),
                               release("v1.2.0", prerelease=True),
                               release("v1.2.1-rc.1"), release("nightly"),
                               release("v1.1.2")]])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["v1.1.2"])

    def test_no_eligible_sources_fails(self):
        self.assertNotEqual(self.select([[release("v1.3.0")]]).returncode, 0)

    def test_invalid_count_or_target_fails(self):
        for count in [0, -1, 1.5, "5"]:
            with self.subTest(count=count):
                self.assertNotEqual(self.select([[release("v1.2.1")]], count=count).returncode, 0)
        self.assertNotEqual(self.select([[release("v1.2.1")]], target="invalid").returncode, 0)


if __name__ == "__main__":
    unittest.main()
