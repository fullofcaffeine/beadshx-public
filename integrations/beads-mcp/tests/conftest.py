"""Pytest configuration and fixtures for beads-mcp tests.

This module provides safety checks to prevent test pollution in production databases (bd-2c5a).
"""

import asyncio
import os
import shutil
import subprocess
from pathlib import Path

import pytest


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
    """Mark a disposable workspace and keep its database, home, and config local.

    Like scripts/ci/lib/test-env.sh, this prevents inherited configuration from
    redirecting a real integration command to a maintainer's database or home.
    """
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    (workspace / ".beadshx-disposable-fixture").touch()
    for name in ("home", "xdg-config", "dolt-root"):
        (tmp_path / name).mkdir()
    git_config = tmp_path / "gitconfig"
    git_config.touch()

    for name in tuple(os.environ):
        if name.startswith(("BEADS_", "BD_", "GIT_")) or name == "GT_ROOT":
            monkeypatch.delenv(name)
    for name, value in {
        "HOME": str(tmp_path / "home"),
        "USERPROFILE": str(tmp_path / "home"),
        "XDG_CONFIG_HOME": str(tmp_path / "xdg-config"),
        "DOLT_ROOT_PATH": str(tmp_path / "dolt-root"),
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": str(git_config),
        "BEADS_TEST_MODE": "1",
        "BEADS_TEST_IGNORE_REPO_CONFIG": "1",
        "BD_NON_INTERACTIVE": "1",
        "BD_DISABLE_METRICS": "1",
        "BEADS_PATH": bd_executable,
    }.items():
        monkeypatch.setenv(name, value)
    return workspace


@pytest.fixture
async def initialized_workspace(temp_workspace: Path, bd_executable, bd_init_isolation_flags_supported) -> Path:
    """Initialize only a marked workspace, without hooks or agent setup."""
    if not (temp_workspace / ".beadshx-disposable-fixture").is_file():
        pytest.fail("Refusing to initialize an unmarked integration workspace")
    process = await asyncio.create_subprocess_exec(
        bd_executable,
        "init",
        "--prefix",
        "test",
        "--non-interactive",
        "--skip-agents",
        "--skip-hooks",
        stdin=asyncio.subprocess.DEVNULL,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=temp_workspace,
    )
    _stdout, stderr = await process.communicate()
    if process.returncode != 0:
        pytest.fail(f"Failed to initialize test database: {stderr.decode()}")
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
