"""Pytest configuration and fixtures for beads-mcp tests.

This module provides safety checks to prevent test pollution in production databases (bd-2c5a).
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

DISPOSABLE_MARKER = ".beadshx-disposable-fixture"


def _routes_bd(name: str) -> bool:
    """Tell whether an inherited variable could route bd to another database, home, or repository."""
    return name.startswith(("BEADS_", "BD_", "GIT_")) or name == "GT_ROOT"


def _isolation_env(root: Path, bd_executable: str) -> dict[str, str]:
    """Return the variables that keep bd's database, home, and config under root.

    Like scripts/ci/lib/test-env.sh, this prevents inherited configuration from
    redirecting a real integration command to a maintainer's database or home.
    The telemetry and event-flush switches match scripts/beadshx/test-parity-smoke.sh.
    BEADS_NO_AUTO_FLUSH stays unset: bd ignores it, and the MCP server would pass
    it on as --no-auto-flush, which bd no longer accepts.
    """
    return {
        "HOME": str(root / "home"),
        "USERPROFILE": str(root / "home"),
        "XDG_CONFIG_HOME": str(root / "xdg-config"),
        "DOLT_ROOT_PATH": str(root / "dolt-root"),
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": str(root / "gitconfig"),
        "BEADS_TEST_MODE": "1",
        "BEADS_TEST_IGNORE_REPO_CONFIG": "1",
        "BEADS_TELEMETRY_DISABLED": "1",
        "BD_NON_INTERACTIVE": "1",
        "BD_DISABLE_METRICS": "1",
        "BD_DISABLE_EVENT_FLUSH": "1",
        "BEADS_PATH": bd_executable,
    }


def _make_marked_workspace(root: Path) -> Path:
    """Create root/workspace with the disposable-fixture marker, and its own home and config beside it."""
    workspace = root / "workspace"
    workspace.mkdir()
    (workspace / DISPOSABLE_MARKER).touch()
    for name in ("home", "xdg-config", "dolt-root"):
        (root / name).mkdir()
    (root / "gitconfig").touch()
    return workspace


def init_marked_workspace(workspace: Path, env: dict[str, str], bd_executable: str) -> None:
    """Run bd init in a marked workspace only, without hooks or agent setup."""
    if not (workspace / DISPOSABLE_MARKER).is_file():
        pytest.fail("Refusing to initialize an unmarked integration workspace")
    result = subprocess.run(
        [bd_executable, "init", "--prefix", "test", "--non-interactive", "--skip-agents", "--skip-hooks"],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        cwd=workspace,
        env=env,
        check=False,
    )
    if result.returncode != 0:
        pytest.fail(f"Failed to initialize test database: {result.stderr}")


def clone_tree(source: Path, destination: Path) -> None:
    """Copy the contents of source into the existing destination directory.

    On macOS, cp -c clones the files on APFS (and copies them elsewhere), like
    copy_fixture_tree in scripts/beadshx/test-parity-smoke.sh.
    """
    if sys.platform == "darwin":
        subprocess.run(["/bin/cp", "-cR", f"{source}/", str(destination)], check=True)
    else:
        shutil.copytree(source, destination, symlinks=True, dirs_exist_ok=True)


@pytest.fixture(scope="session")
def bd_executable():
    """Use the real bd executable selected by the package gate's PATH."""
    bd_path = shutil.which("bd")
    if not bd_path:
        pytest.fail("bd executable not found in PATH. Install bd before running integration tests.")
    return bd_path


@pytest.fixture(scope="session")
def bd_init_isolation_flags_supported(bd_executable):
    """Skip integration tests when bd cannot suppress unrelated setup."""
    result = subprocess.run([bd_executable, "init", "--help"], capture_output=True, text=True, check=False)
    help_text = f"{result.stdout}\n{result.stderr}"
    required_flags = ("--non-interactive", "--skip-agents", "--skip-hooks")
    missing_flags = [flag for flag in required_flags if flag not in help_text]
    if missing_flags:
        pytest.skip("bd init lacks required test isolation flags: " + ", ".join(missing_flags))


@pytest.fixture
def temp_workspace(tmp_path: Path, monkeypatch, bd_executable) -> Path:
    """Mark a disposable workspace and keep its database, home, and config local."""
    workspace = _make_marked_workspace(tmp_path)
    for name in tuple(os.environ):
        if _routes_bd(name):
            monkeypatch.delenv(name)
    for name, value in _isolation_env(tmp_path, bd_executable).items():
        monkeypatch.setenv(name, value)
    return workspace


@pytest.fixture(scope="session")
def workspace_template(tmp_path_factory, bd_executable, bd_init_isolation_flags_supported) -> Path:
    """Initialize one marked workspace per session, for initialized_workspace to copy.

    bd init takes 4-9 s on a loaded macOS host; a copy takes a fraction of a second.
    """
    root = tmp_path_factory.mktemp("workspace-template")
    workspace = _make_marked_workspace(root)
    env = {name: value for name, value in os.environ.items() if not _routes_bd(name)}
    env.update(_isolation_env(root, bd_executable))
    init_marked_workspace(workspace, env, bd_executable)
    return workspace


@pytest.fixture
def initialized_workspace(temp_workspace: Path, workspace_template: Path) -> Path:
    """Give a marked workspace its own copy of the session's initialized database."""
    if not (temp_workspace / DISPOSABLE_MARKER).is_file():
        pytest.fail("Refusing to copy a database into an unmarked integration workspace")
    clone_tree(workspace_template, temp_workspace)
    return temp_workspace


def pytest_configure(config):
    """Called before test collection starts - ensure we're not polluting production."""
    # CRITICAL (bd-2c5a): Prevent tests from polluting production database

    # Set test mode flag
    os.environ["BEADS_TEST_MODE"] = "1"

    # Get the project root (where .git exists)
    current_dir = Path(__file__).parent.absolute()
    project_root = current_dir

    while project_root.parent != project_root:
        if (project_root / ".git").exists():
            break
        project_root = project_root.parent

    # If BEADS_DB or BEADS_WORKING_DIR point to production .beads/, fail immediately
    beads_db = os.environ.get("BEADS_DB", "")
    working_dir = os.environ.get("BEADS_WORKING_DIR", "")

    production_beads = str(project_root / ".beads")

    if beads_db and beads_db.startswith(production_beads):
        pytest.exit(
            f"PRODUCTION DATABASE POLLUTION DETECTED (bd-2c5a):\n"
            f"  BEADS_DB={beads_db}\n"
            f"  Production .beads/: {production_beads}\n"
            f"  Tests MUST use isolated temp databases.\n"
            f"  Remove BEADS_DB env var or point it to a temp directory.",
            returncode=1,
        )

    if (
        working_dir
        and working_dir.startswith(str(project_root))
        and Path(working_dir).resolve() == project_root.resolve()
    ):
        pytest.exit(
            f"PRODUCTION DATABASE POLLUTION RISK (bd-2c5a):\n"
            f"  BEADS_WORKING_DIR={working_dir}\n"
            f"  Project root: {project_root}\n"
            f"  Tests should use isolated temp directories.\n"
            f"  Remove BEADS_WORKING_DIR or set it to a temp directory.",
            returncode=1,
        )


def pytest_runtest_setup(item):
    """Called before each test - verify test isolation."""
    # Check if test is using bd_client fixture
    if "bd_client" in item.fixturenames:
        # Verify BEADS_DB is not set to production during test execution
        beads_db = os.environ.get("BEADS_DB", "")
        if beads_db and ".beads/beads.db" in beads_db:
            # Get temp directory
            import tempfile

            if not beads_db.startswith(tempfile.gettempdir()):
                pytest.fail(
                    f"Test {item.name} is using production database (bd-2c5a):\n"
                    f"  BEADS_DB={beads_db}\n"
                    f"  This test must use a temporary database.",
                    pytrace=False,
                )
