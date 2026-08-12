#!/usr/bin/env python3
"""claim_roadmap_version.py — compute the next free Roadmap Phase version number
and atomically create its GitHub milestone.

Checks BOTH origin/main's ROADMAP.md (Roadmap Phase entries in either heading
form `## v<N>.<M>: <Title>` or list form `- **v<N>.<M>: <Title>** ...`) AND
every open+closed GitHub milestone matching v<N>.<M>: for the highest
currently-used minor version, proposes max+1, and creates the milestone for
it. Retries forward on a narrow race (another session's milestone for the
exact same number appears between the check and the create call).

Usage: python3 scripts/claim_roadmap_version.py "Feature Title" [--major N]

Prints the claimed version (e.g. "v0.75") and milestone number/URL on success.
Exit 0 on success, non-zero on failure (no `gh` auth, repo detection failed, or
every retry attempt raced).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

_ROADMAP_VERSION_RE = re.compile(r"^(?:## |- \*\*)v(\d+)\.(\d+):", re.MULTILINE)
_MILESTONE_VERSION_RE = re.compile(r"^v(\d+)\.(\d+):")
_MAX_CLAIM_ATTEMPTS = 5


def _run(args: list[str]) -> str:
    result = subprocess.run(args, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise RuntimeError(f"{' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout


def _repo_slug() -> str:
    override = os.environ.get("VERSION_GUARD_REPO_SLUG")
    if override:
        print(
            f"warning: VERSION_GUARD_REPO_SLUG={override!r} override active — "
            "querying this repo instead of git remote origin. Test-only; unset "
            "this env var for a real run.",
            file=sys.stderr,
        )
        return override
    # git@github.com:owner/repo.git OR https://github.com/owner/repo.git
    url = _run(["git", "remote", "get-url", "origin"]).strip()
    m = re.search(r"github\.com[:/]([^/]+)/([^/.]+?)(?:\.git)?$", url)
    if not m:
        raise RuntimeError(f"could not parse owner/repo from origin URL: {url!r}")
    return f"{m.group(1)}/{m.group(2)}"


def _highest_minor_in_roadmap(major: int) -> int:
    _run(["git", "fetch", "origin", "main", "--quiet"])
    roadmap_text = _run(["git", "show", "origin/main:ROADMAP.md"])
    highest = 0
    for maj_s, min_s in _ROADMAP_VERSION_RE.findall(roadmap_text):
        if int(maj_s) == major:
            highest = max(highest, int(min_s))
    return highest


def _highest_minor_in_milestones(repo_slug: str, major: int) -> int:
    raw = _run([
        "gh", "api", "--paginate", f"repos/{repo_slug}/milestones?state=all",
        "--jq", ".[].title",
    ])
    highest = 0
    for line in raw.splitlines():
        m = _MILESTONE_VERSION_RE.match(line.strip())
        if m and int(m.group(1)) == major:
            highest = max(highest, int(m.group(2)))
    return highest


def _create_milestone(repo_slug: str, title: str, description: str) -> tuple[int, str]:
    raw = _run([
        "gh", "api", f"repos/{repo_slug}/milestones", "--method", "POST",
        "-f", f"title={title}", "-f", f"description={description}",
    ])
    data = json.loads(raw)
    return data["number"], data["html_url"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("title", help="Feature title, e.g. 'Roadmap Version Collision Guard'")
    parser.add_argument("--major", type=int, default=0, help="Major version (default 0)")
    args = parser.parse_args()

    try:
        repo_slug = _repo_slug()
        roadmap_high = _highest_minor_in_roadmap(args.major)
        milestone_high = _highest_minor_in_milestones(repo_slug, args.major)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    minor = max(roadmap_high, milestone_high) + 1

    description = f"{args.title} — claimed via scripts/claim_roadmap_version.py"
    for _ in range(_MAX_CLAIM_ATTEMPTS):
        version = f"v{args.major}.{minor}"
        title = f"{version}: {args.title}"
        try:
            number, url = _create_milestone(repo_slug, title, description)
        except RuntimeError as exc:
            if "already_exists" in str(exc) or "already exists" in str(exc):
                # Race: someone claimed this exact number between our check and
                # the create call. Bump and retry rather than failing outright.
                minor += 1
                continue
            print(f"error: {exc}", file=sys.stderr)
            return 1
        print(f"Claimed {version} — milestone #{number}: {title}")
        print(url)
        return 0

    print(
        f"error: {_MAX_CLAIM_ATTEMPTS} consecutive collisions while claiming a version — "
        "another session is claiming numbers unusually fast; try again",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
