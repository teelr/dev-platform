#!/usr/bin/env python3
"""CT-VERSION-COLLISION — a Roadmap Phase version number this branch's ROADMAP.md
introduces must not already be used by origin/main or a differently-titled GitHub
milestone.

Two-layer check:
  1. Local (no network beyond `git fetch`, always runs): every Roadmap Phase
     entry — heading form (`## v<N>.<M>: <Title>`) or list form
     (`- **v<N>.<M>: <Title>** ...`), both supported, matching
     check_spec_taxonomy.sh's own dual-form pattern — present in the WORKING
     TREE's ROADMAP.md but absent from origin/main's ROADMAP.md is a "new"
     version this branch is introducing. If origin/main's ROADMAP.md ALSO has
     that exact v<N>.<M> under a DIFFERENT title, that's a collision — the
     number shipped as something else while this branch was in flight — UNLESS
     the GitHub milestone for that version already carries this branch's
     title. Renaming the milestone first is the deliberate step that marks a
     rename as intentional (v1.46, issue #147). If the milestone has the old
     or another title, has no entry, or the lookup cannot run, it stays a
     collision: a change is never passed through on a check that did not run.
  2. GitHub milestone cross-check (best-effort — SKIPs, does not FAIL, if `gh`
     is unavailable/unauthenticated): for each "new" version from step 1,
     check every open+closed milestone titled `v<N>.<M>: ...`. A match with a
     DIFFERENT title than this branch's ROADMAP.md entry is a collision —
     someone else has claimed or shipped that number.

Exit 0 if fully checked and clean. Exit 1 on a real collision (always wins over
a degraded check, even if some layer was skipped), with the colliding
version(s) and both titles printed. Exit 2 if the check degraded to partial
coverage (origin/main unreachable, or `gh` unavailable/unauthenticated) and no
collision was found in whatever WAS checked — matches this project's
CT-SCHEMA/gate_fast.sh convention of a distinct SKIP exit code rather than
silently reporting PASS on a check that couldn't fully run.

A note on the roadmap path itself: set ROADMAP_PATH (relative to the repo
root, e.g. "docs/roadmap.md") if your roadmap doesn't live at the default
ROADMAP.md. Do NOT satisfy this by symlinking a root ROADMAP.md to the real
file — `git show origin/main:ROADMAP.md` does not dereference symlinks, it
returns the raw symlink target-path string as the file's "content," which
makes every real version look "new" and produces false COLLISION failures
against your own milestone history. Set ROADMAP_PATH instead.

Usage: python3 scripts/check_version_collision.py [project_root]
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

# Resolve off __file__, not the cwd: consumers' CI runs this by absolute path
# against their own checkout (see .github/workflows/taxonomy-check.yml).
sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from repo_slug import parse_repo_slug  # noqa: E402
from roadmap_path import roadmap_path as _roadmap_path  # noqa: E402

_VERSION_HEADER_HEADING_RE = re.compile(r"^## (v(\d+)\.(\d+)): (.+?)\s*(?:—.*)?$", re.MULTILINE)
_VERSION_HEADER_LIST_RE = re.compile(r"^- \*\*(v(\d+)\.(\d+)): (.+?)\*\*", re.MULTILINE)
_MILESTONE_TITLE_RE = re.compile(r"^(v(\d+)\.(\d+)):\s*(.+)$")


def _run(args: list[str], timeout: int = 15) -> str | None:
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    return result.stdout if result.returncode == 0 else None


def _versions_in(text: str) -> dict[str, str]:
    """version token (e.g. 'v0.74') -> title, for every Roadmap Phase entry —
    heading form ('## v<N>.<M>: <Title>') or list form
    ('- **v<N>.<M>: <Title>** ...'), matching check_spec_taxonomy.sh's
    dual-form support."""
    out: dict[str, str] = {}
    for full, _maj, _min, title in _VERSION_HEADER_HEADING_RE.findall(text):
        out[full] = title.strip()
    for full, _maj, _min, title in _VERSION_HEADER_LIST_RE.findall(text):
        out[full] = title.strip()
    return out


def _gh_available() -> bool:
    return _run(["gh", "auth", "status"]) is not None or _run(["gh", "--version"]) is not None


def _repo_slug() -> str | None:
    override = os.environ.get("VERSION_GUARD_REPO_SLUG")
    if override:
        print(
            f"warning: VERSION_GUARD_REPO_SLUG={override!r} override active — "
            "querying this repo instead of git remote origin. Test-only; unset "
            "this env var for a real run.",
            file=sys.stderr,
        )
        return override
    url = _run(["git", "remote", "get-url", "origin"])
    if url is None:
        return None
    return parse_repo_slug(url)


def _milestone_titles() -> tuple[dict[str, str] | None, str]:
    """version token -> milestone title for every open+closed GitHub milestone.
    Returns (None, <SKIP message>) when the lookup cannot run."""
    if not _gh_available():
        return None, "SKIP: gh CLI unavailable/unauthenticated — milestone cross-check unavailable"
    repo_slug = _repo_slug()
    if repo_slug is None:
        return None, "SKIP: could not determine owner/repo from origin remote"
    raw = _run([
        "gh", "api", "--paginate", f"repos/{repo_slug}/milestones?state=all",
        "--jq", ".[].title",
    ], timeout=20)
    if raw is None:
        return None, "SKIP: gh api call failed — milestone cross-check unavailable"
    titles: dict[str, str] = {}
    for line in raw.splitlines():
        m = _MILESTONE_TITLE_RE.match(line.strip())
        if m:
            titles[m.group(1)] = m.group(4).strip()
    return titles, ""


def main(project_root: Path) -> int:
    roadmap_path = _roadmap_path()
    roadmap = project_root / roadmap_path
    if not roadmap.exists():
        print(f"no {roadmap_path} — nothing to check")
        return 0

    local_text = roadmap.read_text()
    local_versions = _versions_in(local_text)

    fetch_ok = _run(["git", "fetch", "origin", "main", "--quiet"]) is not None
    main_text = _run(["git", "show", f"origin/main:{roadmap_path}"], timeout=20)
    if not fetch_ok or main_text is None:
        print("SKIP: could not fetch origin/main — local-only check unavailable")
        return 2
    main_versions = _versions_in(main_text)

    # "New" = this branch introduces the version token at all (absent from
    # main — needs the Layer 2 milestone cross-check, since an unmerged
    # sibling branch's claim won't show up in main's ROADMAP.md yet).
    new_versions = {v: t for v, t in local_versions.items() if v not in main_versions}
    # "Reused" = the version token already means something on main, but this
    # branch's ROADMAP.md now has a DIFFERENT title for it — a direct,
    # locally-detectable collision (main already shipped that number as a
    # different feature). No network needed to catch this one.
    reused_versions = {
        v: t for v, t in local_versions.items()
        if v in main_versions and main_versions[v] != t
    }
    if not new_versions and not reused_versions:
        print("OK: no new Roadmap Phase version headers introduced")
        return 0

    collisions: list[str] = []
    renames: list[str] = []
    reused_collision = False
    degraded = False

    # GitHub milestones, best-effort, fetched once for both layers below. A
    # failed fetch degrades NEW versions to SKIP (exit 2) rather than silently
    # reporting a confident PASS on a partial check. It never rescues a REUSED
    # version: without a milestone to confirm the rename, that stays a
    # collision.
    milestone_titles: dict[str, str] | None = None
    if new_versions or reused_versions:
        milestone_titles, skip_reason = _milestone_titles()
        if milestone_titles is None:
            print(skip_reason)

    # Layer 1: version token already used by origin/main under a different
    # title. A collision unless the GitHub milestone already carries this
    # branch's title: renaming the milestone first is the deliberate step that
    # marks a rename as intentional (issue #147).
    for version, local_title in reused_versions.items():
        if milestone_titles is not None and milestone_titles.get(version) == local_title:
            renames.append(
                f"{version} renamed from {main_versions[version]!r} to {local_title!r} "
                "— GitHub milestone already carries the new title"
            )
            continue
        suffix = (
            "" if milestone_titles is not None
            else " (milestone lookup unavailable, so a rename cannot be confirmed)"
        )
        reused_collision = True
        collisions.append(
            f"{version}: this branch claims {local_title!r}, but origin/main's "
            f"{roadmap_path} already titles it {main_versions[version]!r}{suffix}"
        )

    # Layer 2: new versions against the milestone list.
    if new_versions:
        if milestone_titles is not None:
            for version, local_title in new_versions.items():
                existing_title = milestone_titles.get(version)
                if existing_title is not None and existing_title != local_title:
                    collisions.append(
                        f"{version}: this branch claims {local_title!r}, "
                        f"but a GitHub milestone already titles it {existing_title!r}"
                    )
        else:
            degraded = True

    if collisions:
        for c in collisions:
            print(f"COLLISION: {c}")
        print(
            "Renumber this branch's ROADMAP.md/planning.md/milestone to a free version "
            "before committing."
        )
        if reused_collision:
            print(
                "If this is a deliberate rename, rename the GitHub milestone to the "
                "new title first, then re-run."
            )
        return 1

    if degraded:
        print(
            f"SKIP: {len(new_versions)} new version header(s) checked against origin/main only "
            "— milestone cross-check unavailable, coverage is partial"
        )
        return 2

    for r in renames:
        print(f"OK: {r}")
    if new_versions:
        print(f"OK: {len(new_versions)} new version header(s), no collision detected")
    else:
        print(f"OK: {len(renames)} renamed version header(s) confirmed by GitHub milestone")
    return 0


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    sys.exit(main(root))
