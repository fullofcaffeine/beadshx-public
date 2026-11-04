"""Prove host tool execution preserves the requested lint target and lock."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LintLauncherTest(unittest.TestCase):
    def run_launcher(self, *, bad_sum=False, lint_exit=0):
        with tempfile.TemporaryDirectory(prefix="beadshx-lint-launcher-") as temp:
            root = Path(temp)
            scripts = root / "scripts/beadshx"
            scripts.mkdir(parents=True)
            shutil.copy2(ROOT / "scripts/beadshx/run-golangci.sh", scripts)
            locks = root / "engdocs/beadshx/program"
            locks.mkdir(parents=True)
            shutil.copy2(ROOT / "engdocs/beadshx/program/toolchain-locks.json", locks)
            lock = json.loads((locks / "toolchain-locks.json").read_text())
            bindir = root / "bin"
            bindir.mkdir()
            fake_go = bindir / "go"
            fake_go.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
lock = json.loads(pathlib.Path(os.environ['FIXTURE_LOCK']).read_text())
if args == ['env', 'GOROOT']:
    print(os.environ['FIXTURE_ROOT'])
elif args == ['env', 'GOVERSION']:
    print(lock['common']['go'])
elif args == ['env', 'GOHOSTOS']:
    print('darwin')
elif args == ['env', 'GOHOSTARCH']:
    print('arm64')
elif args[:2] == ['mod', 'download']:
    module = lock['golangciLintModule']
    print(json.dumps(dict(Path=module['path'], Version=lock['common']['golangciLint'], Sum='bad' if os.environ['BAD_SUM']=='1' else module['sum'], GoModSum=module['goModSum'])))
elif args[0] == 'install':
    assert os.environ['GOOS'] == 'darwin', 'tool must be built for host OS'
    assert os.environ['GOARCH'] == 'arm64', 'tool must be built for host architecture'
    assert args[1] == lock['golangciLintModule']['path'] + '/cmd/golangci-lint@' + lock['common']['golangciLint']
    tool = pathlib.Path(os.environ['GOBIN']) / 'golangci-lint'
    tool.write_text("#!/usr/bin/env python3\\nimport json, os, sys\\nprint(json.dumps(dict(target=os.environ['GOOS'], arch=os.environ['GOARCH'], args=sys.argv[1:])))\\nsys.exit(int(os.environ['LINT_EXIT']))\\n")
    tool.chmod(0o755)
    pathlib.Path(os.environ['FIXTURE_ROOT'], 'installed-path').write_text(str(tool))
elif args[0] == 'run':
    sys.exit('cannot execute target Windows binary on Darwin host')
else:
    sys.exit('unexpected Go command: ' + repr(args))
''')
            fake_go.chmod(0o755)
            env = dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ["PATH"],
                       FIXTURE_ROOT=str(root), FIXTURE_LOCK=str(locks / "toolchain-locks.json"),
                       BAD_SUM=str(int(bad_sum)), LINT_EXIT=str(lint_exit),
                       GOOS="windows", GOARCH="amd64")
            result = subprocess.run(["bash", str(scripts / "run-golangci.sh"), "--timeout=5m", "./example path/..."],
                                    env=env, text=True, capture_output=True, timeout=15)
            receipt = root / "installed-path"
            installed = receipt.exists()
            if installed:
                self.assertFalse(Path(receipt.read_text()).exists(), "temporary tool must be cleaned up")
            return result, installed

    def test_host_binary_receives_original_target_and_arguments(self):
        result, installed = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(installed)
        self.assertEqual(json.loads(result.stdout), {
            "target": "windows", "arch": "amd64", "args": ["run", "--timeout=5m", "./example path/..."]})

    def test_lint_failure_is_preserved(self):
        result, _ = self.run_launcher(lint_exit=17)
        self.assertEqual(result.returncode, 17, result.stderr)

    def test_bad_lock_stops_before_install(self):
        result, installed = self.run_launcher(bad_sum=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(installed)
        self.assertIn("module bytes do not match", result.stderr)


if __name__ == "__main__":
    unittest.main()
