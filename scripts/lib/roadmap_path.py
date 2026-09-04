#!/usr/bin/env python3
"""roadmap_path.py — read ROADMAP_PATH the way the shell scripts already do.

Two families of dev-platform scripts read the same `ROADMAP_PATH` env var, and
before v1.31 they disagreed about what an EMPTY value means:

    $ ROADMAP_PATH= bash -c 'echo "${ROADMAP_PATH:-ROADMAP.md}"'
    ROADMAP.md                      # bash `:-` treats empty as unset

    $ ROADMAP_PATH= python3 -c "import os; print(repr(os.environ.get('ROADMAP_PATH','ROADMAP.md')))"
    ''                              # Python .get() treats empty as a VALUE

The Python behaviour is the wrong one, and it fails destructively rather than
visibly. `Path(project_root) / ""` is `project_root` itself — a DIRECTORY.
`.exists()` returns True for it, so the "no roadmap — nothing to check" guard is
skipped, and `read_text()` then raises:

    $ ROADMAP_PATH= python3 scripts/check_version_collision.py .
    IsADirectoryError: [Errno 21] Is a directory: '.'
    rc=1

Exit 1 is what `.github/workflows/taxonomy-check.yml` renders as
"::error::version collision detected" — so an empty value produces a FALSE
collision failure on a repo that has no collision at all.

The reusable workflow defaults its `roadmap_path` input to `ROADMAP.md`, which
keeps CI off this path entirely. This helper exists for the other callers: the
env var is also exported by hand for local `/plan` and `gate_fast.sh` runs,
where nothing validates it and a stray `export ROADMAP_PATH=` is easy to write.

One definition, imported by both Python readers — per the Derivation Sweep rule
in CLAUDE.md. The bash readers (`check_spec_taxonomy.sh`, `check-phase-tags.sh`)
already use `${VAR:-default}` and are correct as they stand; do not "align" them
to call this.
"""
from __future__ import annotations

import os

DEFAULT_ROADMAP = "ROADMAP.md"


def roadmap_path(env: dict[str, str] | None = None) -> str:
    """Return the roadmap path relative to the repo root.

    Empty or whitespace-only ROADMAP_PATH is treated as unset, matching bash's
    `${ROADMAP_PATH:-ROADMAP.md}`. `env` is injectable for testing.
    """
    source = os.environ if env is None else env
    value = (source.get("ROADMAP_PATH") or "").strip()
    return value or DEFAULT_ROADMAP
