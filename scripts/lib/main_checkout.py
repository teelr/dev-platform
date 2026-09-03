#!/usr/bin/env python3
"""main_checkout.py — resolve the MAIN checkout's root, from anywhere in the
repo including a worktree.

The Python half of `scripts/lib/main_checkout.sh`; that file carries the full
rationale. In short: a worktree-mode repo has two roots, and conflating them is
a bug. The script's own repo root is the worktree (correct for the files being
edited). The main checkout is where git-ignored, never-copied directories live —
`projects/` above all, which every registry entry's relative `path` is written
against.

`monitoring/fleet_pins.py` and `monitoring/fleet_dashboard.py` used the first as
the second, so from a worktree they resolved `projects/<name>` to a path that
does not exist and reported every consumer as "not adopted" rather than failing
(v1.27).

The rule: `git rev-parse --git-common-dir` resolves to `<main>/.git` from a
worktree and from the main checkout alike, so the main checkout is its parent.
On any failure — not a git repo, no `git` on PATH, a timeout — the input is
returned unchanged, so a tarball checkout keeps working.

    from main_checkout import main_checkout
    FLEET_ROOT = main_checkout(REPO)

Never raises. CLI: prints the resolved path and exits 0.

    python3 scripts/lib/main_checkout.py /path/to/repo
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

RESOLVE_TIMEOUT_S = 10


def main_checkout(candidate: Path) -> Path:
    """Return the main checkout's root for `candidate`, or `candidate` itself.

    Pass the repo root — a script's own `REPO`, or a worktree's root. The
    return value is the main checkout even when `candidate` is a worktree.

    A subdirectory is not a supported input: git may report `--git-common-dir`
    as the bare relative `.git`, which is resolved against `candidate`, so only
    a root resolves correctly. Every caller passes a root.
    """
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--git-common-dir"],
            cwd=candidate,
            capture_output=True,
            text=True,
            timeout=RESOLVE_TIMEOUT_S,
        )
    except (OSError, subprocess.SubprocessError):
        return candidate

    if result.returncode != 0:
        return candidate
    common = result.stdout.strip()
    if not common:
        return candidate

    # Bare ".git" is relative to the candidate; a worktree gets an absolute
    # path. Joining against the candidate handles both — an absolute path
    # replaces the left side, which is exactly what's wanted.
    try:
        common_abs = (candidate / common).resolve()
    except OSError:
        return candidate
    return common_abs.parent


if __name__ == "__main__":
    start = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
    print(main_checkout(start))
