"""Smoke test for {{PROJECT_NAME}}: package imports cleanly."""
from __future__ import annotations

import pytest


@pytest.mark.fast
def test_package_imports() -> None:
    import backend  # noqa: F401
    from backend.agent import run_once

    result = run_once()
    assert isinstance(result, dict)
    assert result.get("status") == "ok"
