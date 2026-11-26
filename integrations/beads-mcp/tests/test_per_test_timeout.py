"""The package gate bounds each test, so a hang fails fast and names the test."""

import asyncio
import os

import pytest

PER_TEST_TIMEOUT_SECONDS = 120.0


def test_each_test_has_the_per_test_timeout(request):
    """pytest-timeout is active and bounds each test, fixture setup included."""
    assert request.config.pluginmanager.hasplugin("timeout")
    assert float(request.config.getini("timeout")) == PER_TEST_TIMEOUT_SECONDS


@pytest.mark.skipif(
    os.environ.get("BEADS_MCP_TIMEOUT_PROOF") != "1",
    reason="set BEADS_MCP_TIMEOUT_PROOF=1 to show a hang failing at the per-test timeout",
)
async def test_hang_fails_at_the_per_test_timeout():
    """Never returns. With BEADS_MCP_TIMEOUT_PROOF=1, it must fail at the timeout under its own name."""
    await asyncio.Event().wait()
