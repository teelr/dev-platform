#!/usr/bin/env python3
"""dev-platform fleet pin inspector.

Reads monitoring/projects.json and reports each project's adoption
of the dev-platform-gate consumer template + its `@vX.Y` pin
relative to the latest dev-platform release tag.

The pin that matters is the one on the project's DEFAULT BRANCH on
GitHub — that is the file GitHub Actions runs. Until v1.27 this read
the local working copy under projects/<name>/ instead, which is a
different file: OPIE's local copy read @v1.12 while its live workflow
ran @v1.2, because an uncommitted `fleet-install-template.sh --force`
overwrite sat in its working tree. Every consumer-pin claim
dev-platform made rested on that local file. Both are read now, and a
mismatch is reported as drift rather than silently resolved.

Read-only. No fleet sweep (that's scripts/fleet-gate.sh); no
mutations (that's scripts/fleet-install-template.sh, governed by
the v0.8 Phase 3 Scope-rule carve-out).

Usage:
    python3 monitoring/fleet_pins.py                          # markdown, all enabled
    python3 monitoring/fleet_pins.py --format json            # machine-readable
    python3 monitoring/fleet_pins.py --project atlas
    python3 monitoring/fleet_pins.py --registry <path>        # override (tests)
    python3 monitoring/fleet_pins.py --latest v0.8            # override latest-release lookup (tests)
    python3 monitoring/fleet_pins.py --source local           # local working copies only (offline)
    python3 monitoring/fleet_pins.py --source github          # default-branch copies only

Exits 0 on success, 2 on argparse / setup error.

Registry schema reference: monitoring/projects.json
"""
from __future__ import annotations

import argparse
import base64
import binascii
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

REPO = Path(__file__).resolve().parent.parent
REGISTRY_DEFAULT = REPO / "monitoring" / "projects.json"
QUERY_TIMEOUT_S = 10

# Resolve off __file__, not the cwd — same idiom (and same reason) as
# scripts/check_version_collision.py. Both helpers below are shared rules with
# exactly one implementation each: deriving owner/repo (repo_slug.py, extracted
# in v1.21 after three scripts hardcoded the host — issue #77) and resolving the
# main checkout from a worktree (main_checkout.py, extracted in v1.27 after five
# fleet scripts each did it wrong). Do not add a local copy of either.
sys.path.insert(0, str(REPO / "scripts" / "lib"))
from main_checkout import main_checkout  # noqa: E402
from repo_slug import parse_repo_slug  # noqa: E402

# Registry entries' relative paths (`projects/<name>`) are written against the
# MAIN checkout — `projects/` is gitignored, so it exists nowhere else. REPO is
# the worktree when run from one, which is right for this repo's own files and
# wrong for those. See scripts/lib/main_checkout.sh.
FLEET_ROOT = main_checkout(REPO)

# The one path the consumer template lives at, in a consumer repo. Used
# for BOTH the local filesystem read and the `gh api` contents read, so
# the two can never drift apart.
TEMPLATE_REL_PATH = ".github/workflows/dev-platform-gate.yml"

# Matches the consumer template's `uses:` line and captures the pin
# (the bit after the `@`). Anchored at start-of-line (optionally
# indented) so a YAML comment containing `# uses: ...` can't shadow
# the real directive. MULTILINE so `^` matches line starts within the
# template's full content.
USES_RE = re.compile(
    r"^\s*uses:\s+teelr/dev-platform/[^@]+@(\S+)",
    re.MULTILINE,
)

# Semver tag like v0.7 or v0.7.3 — captures (major, minor); ignores patch.
SEMVER_RE = re.compile(r"^v(\d+)\.(\d+)(?:\.\d+)?$")


@dataclass
class ProjectPin:
    name: str
    path: str
    # True / False / "self" for dev-platform.
    adopted: object
    # The AUTHORITATIVE pin: the live one when GitHub answered, else the
    # local one. Kept as `pin` so anything already reading this field
    # keeps working — its meaning got more accurate, not different.
    pin: Optional[str]
    latest: Optional[str]
    # One of: "self", "up-to-date", "behind", "floating", "unparseable",
    # "not-adopted", "unverifiable".
    status: str
    # For sortability when status == "behind"; (major_diff * 1000) + minor_diff.
    minor_delta: Optional[int]
    # owner/repo, or None when it can't be derived (no checkout, no remote).
    repo: Optional[str]
    # What's on this machine's disk — the pre-v1.27 answer.
    local_pin: Optional[str]
    # What's on the repo's default branch, i.e. what CI actually runs.
    live_pin: Optional[str]
    # One of: "ok", "absent", "unreachable", "skipped".
    live_state: str
    # Both pins known and unequal — the local file is not what CI runs.
    drift: bool


def _run(cmd: list[str], cwd: Path) -> tuple[int, str]:
    """Run a subprocess with a hard timeout. Returns (rc, stdout-stripped)."""
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=QUERY_TIMEOUT_S,
        )
        return result.returncode, result.stdout.strip()
    except subprocess.TimeoutExpired:
        return 124, ""
    except (FileNotFoundError, OSError):
        return 127, ""


def fetch_latest_release(repo_slug: str = "teelr/dev-platform") -> Optional[str]:
    """Resolve the latest dev-platform release tag via `gh api`.

    Returns the tag string (e.g. "v0.7") or None if gh is unavailable,
    not authenticated, the repo has no releases yet, or any other
    failure. Best-effort — the dashboard renders without it.
    """
    rc, out = _run(
        ["gh", "api", f"repos/{repo_slug}/releases/latest", "--jq", ".tag_name"],
        cwd=REPO,
    )
    if rc != 0 or not out:
        return None
    return out


def repo_slug_for(project_dir: Path) -> Optional[str]:
    """Derive owner/repo from a project checkout's origin remote.

    Returns None when the checkout is missing, has no origin, or the URL
    doesn't parse — all of which mean "can't ask GitHub about this one",
    not "this project is fine".
    """
    rc, out = _run(["git", "remote", "get-url", "origin"], cwd=project_dir)
    if rc != 0 or not out:
        return None
    return parse_repo_slug(out)


def fetch_live_pin(slug: str) -> tuple[Optional[str], str]:
    """Read the pin from the consumer template on the repo's default branch.

    Returns (pin, live_state) where live_state is one of:
      "ok"          — the file was read; pin is the captured value, or ""
                      when the content has no parseable `uses:` line.
      "absent"      — repo is reachable but has no template at that path.
      "unreachable" — the repo itself did not resolve.

    The repo probe runs first precisely so those last two stay distinct.
    `gh` returns the same 404 for "file not there" and "this account
    can't see this repo" — Osigin-LLC/SQRL is the second, and without
    the probe it would be reported as a consumer that never adopted the
    template. An unknown rendered as a fact is the defect this function
    exists to avoid.
    """
    rc, _ = _run(["gh", "api", f"repos/{slug}", "--jq", ".full_name"], cwd=REPO)
    if rc != 0:
        return None, "unreachable"

    rc, out = _run(
        ["gh", "api", f"repos/{slug}/contents/{TEMPLATE_REL_PATH}", "--jq", ".content"],
        cwd=REPO,
    )
    if rc != 0:
        return None, "absent"
    if not out:
        # The file is there but empty — adopted, and unparseable. Distinct
        # from "absent", which means the default branch has no such file.
        return "", "ok"

    try:
        # The contents API returns base64 with embedded newlines; b64decode
        # ignores those. A repo can hold a non-UTF-8 workflow file, so decode
        # permissively rather than raising — an unparseable pin is a real
        # state the report already renders.
        content = base64.b64decode(out).decode("utf-8", "replace")
    except (binascii.Error, ValueError):
        return "", "ok"

    m = USES_RE.search(content)
    # Same anchored regex as the local path, so a `# uses: ...` comment
    # can't shadow the real directive on either one.
    return (m.group(1) if m else ""), "ok"


def parse_semver_minor(tag: Optional[str]) -> Optional[tuple[int, int]]:
    """Parse vX.Y (or vX.Y.Z, ignoring patch) into (major, minor).

    Returns None if the tag doesn't match the semver shape — including
    None input or any non-vX.Y ref like "main".
    """
    if tag is None:
        return None
    m = SEMVER_RE.match(tag)
    if m is None:
        return None
    return int(m.group(1)), int(m.group(2))


def classify(pin: Optional[str], latest: Optional[str]) -> tuple[str, Optional[int]]:
    """Categorize a pin relative to the latest release.

    Returns (status, minor_delta). status is one of:
      "not-adopted" — pin is None (no template file at all).
      "unparseable" — file exists but no `uses:` line matched.
      "floating"   — pin is a non-semver ref (e.g. "main").
      "up-to-date" — pin == latest (or pin > latest, treated as fine).
      "behind"     — pin is older minor than latest; minor_delta set.
    When latest is None, "behind" cannot be computed; the other states
    still surface, and we degrade behind/up-to-date into a best-effort
    "up-to-date" label since the comparison axis is gone.
    """
    if pin is None:
        return "not-adopted", None
    if pin == "":
        return "unparseable", None

    pin_minor = parse_semver_minor(pin)
    if pin_minor is None:
        return "floating", None

    if latest is None:
        # Adopted + parseable, but we can't compare without a baseline.
        # Surface as up-to-date so the row isn't visually alarming.
        return "up-to-date", None

    latest_minor = parse_semver_minor(latest)
    if latest_minor is None:
        # Latest came back as a non-semver ref — same degraded case.
        return "up-to-date", None

    if pin_minor == latest_minor:
        return "up-to-date", 0
    if pin_minor > latest_minor:
        # Consumer is ahead of latest (e.g. pre-release pin). Not stale.
        return "up-to-date", 0

    major_diff = latest_minor[0] - pin_minor[0]
    minor_diff = latest_minor[1] - pin_minor[1]
    # Cross-major: the minor difference can be negative (e.g. pin v0.10
    # vs latest v1.0 → minor_diff = -10). Clamp at the major boundary so
    # format_status reports "⚠ N major behind" rather than decoding a
    # nonsensical "990 minor behind".
    if major_diff > 0:
        return "behind", major_diff * 1000
    return "behind", minor_diff


def extract_pin(template_path: Path) -> Optional[str]:
    """Read a consumer template and return the pin from its `uses:` line.

    Returns:
      None         — file does not exist (not adopted).
      ""           — file exists but no `uses:` line matched USES_RE.
      "<value>"    — the captured pin (e.g. "v0.7", "main", "v0.7.3").
    """
    if not template_path.exists():
        return None
    try:
        content = template_path.read_text(encoding="utf-8")
    except OSError:
        return ""
    m = USES_RE.search(content)
    if m is None:
        return ""
    return m.group(1)


def query_project(entry: dict, latest: Optional[str], source: str = "both") -> ProjectPin:
    """Run all per-project queries against one registry entry."""
    name = entry["name"]
    path_raw = entry["path"]
    target = (REPO if path_raw == "." else FLEET_ROOT / path_raw).resolve()

    # dev-platform is the source of truth, not a consumer — short-circuit
    # before any filesystem read so we don't accidentally classify it as
    # not-adopted.
    if name == "dev-platform":
        return ProjectPin(
            name=name,
            path=path_raw,
            adopted="self",
            pin=None,
            latest=latest,
            status="self",
            minor_delta=None,
            repo=None,
            local_pin=None,
            live_pin=None,
            live_state="skipped",
            drift=False,
        )

    template_path = target / TEMPLATE_REL_PATH
    local_pin = extract_pin(template_path) if source in ("local", "both") else None

    slug: Optional[str] = None
    live_pin: Optional[str] = None
    live_state = "skipped"
    if source in ("github", "both"):
        slug = repo_slug_for(target)
        if slug is None:
            # No checkout / no remote / unparseable URL — we can't ask, and
            # saying so beats guessing from the local file.
            live_state = "skipped"
        else:
            live_pin, live_state = fetch_live_pin(slug)

    # Whenever GitHub answered — with a template OR with its absence — that
    # answer is authoritative, because it is what CI runs. "absent" therefore
    # means not-adopted even when a local copy exists: a template sitting
    # uncommitted in someone's working tree runs on nobody's CI, and reporting
    # its pin would be the same wrong-file failure this phase exists to fix,
    # just in the other direction.
    if live_state == "ok":
        pin = live_pin
    elif live_state == "absent":
        pin = None
    else:
        pin = local_pin

    if live_state in ("ok", "absent"):
        adopted = live_state == "ok"
    else:
        adopted = template_path.exists()

    status, minor_delta = classify(pin, latest)

    # An unreachable repo is an unknown, and must stay one. Falling back to
    # the local copy here would report a pin no CI run has ever used.
    if live_state == "unreachable":
        status, minor_delta = "unverifiable", None

    # Drift is "the local file is not what CI runs", which covers both a
    # different pin and a local template the default branch does not have.
    drift = live_state in ("ok", "absent") and local_pin not in (None, "") and live_pin != local_pin

    return ProjectPin(
        name=name,
        path=path_raw,
        adopted=adopted,
        pin=pin,
        latest=latest,
        status=status,
        minor_delta=minor_delta,
        repo=slug,
        local_pin=local_pin,
        live_pin=live_pin,
        live_state=live_state,
        drift=drift,
    )


def load_registry(path: Path) -> list[dict]:
    """Load + validate the fleet registry JSON. Exits 2 on missing or malformed."""
    if not path.is_file():
        sys.stderr.write(f"ERROR: registry not found at {path}\n")
        sys.exit(2)
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list):
        sys.stderr.write(f"ERROR: registry must be a JSON array (got {type(data).__name__})\n")
        sys.exit(2)
    return data


def format_adopted(flag: object) -> str:
    """Render the adoption column: 'self' / '✓' / '—'."""
    if flag == "self":
        return "self"
    if flag is True:
        return "✓"
    return "—"


def format_pin(pin: Optional[str], status: str) -> str:
    """Render the pin column."""
    if status == "self":
        return "—"
    if pin is None or pin == "":
        return "—"
    return pin


def format_status(status: str, minor_delta: Optional[int]) -> str:
    """Render the human-friendly status column."""
    if status == "self":
        return "self"
    if status == "up-to-date":
        return "✓ up-to-date"
    if status == "behind":
        if minor_delta is None:
            return "⚠ behind"
        # Same encoding as classify(): cross-major is exactly N*1000
        # (minor diff clamped); within-major is the raw minor count.
        if minor_delta >= 1000:
            major = minor_delta // 1000
            return f"⚠ {major} major behind"
        return f"⚠ {minor_delta} minor behind"
    if status == "floating":
        return "⚠ floating pin"
    if status == "unparseable":
        return "⚠ unparseable"
    if status == "not-adopted":
        return "— not adopted"
    if status == "unverifiable":
        return "? unverifiable (no gh access)"
    return status


def render_markdown(pins: list[ProjectPin], registry_path: Path, latest: Optional[str]) -> str:
    """Format the pin list as a markdown report with header + table."""
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    rel_registry = registry_path
    try:
        rel_registry = registry_path.relative_to(REPO)
    except ValueError:
        pass

    lines = [
        "# Fleet Pins",
        "",
        f"Generated: {now_iso}",
        f"Latest dev-platform release: {latest or '?'}",
        f"Registry: {rel_registry} ({len(pins)} enabled)",
        "",
        "| Project            | Adopted | Pin (live) | Pin (local) | Status                       |",
        "| ------------------ | ------- | ---------- | ----------- | ---------------------------- |",
    ]
    for p in pins:
        status_cell = format_status(p.status, p.minor_delta)
        if p.drift:
            live_desc = p.live_pin if p.live_pin else "no template on the default branch"
            status_cell += f" ⚠ local ≠ live ({p.local_pin} vs {live_desc})"
        lines.append(
            f"| {p.name:<18} | {format_adopted(p.adopted):<7} "
            f"| {format_pin(p.live_pin, p.status):<10} "
            f"| {format_pin(p.local_pin, p.status):<11} "
            f"| {status_cell:<28} |"
        )
    if any(p.drift for p in pins):
        lines += [
            "",
            "⚠ A drifting row's local copy is NOT what CI runs — GitHub Actions uses "
            "the default-branch file. The usual cause is an uncommitted local edit to "
            f"`{TEMPLATE_REL_PATH}` in that project's working tree.",
        ]
    return "\n".join(lines) + "\n"


def render_json(pins: list[ProjectPin], registry_path: Path, latest: Optional[str]) -> str:
    """Format the pin list as a JSON payload (machine-readable)."""
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    rel_registry = str(registry_path)
    try:
        rel_registry = str(registry_path.relative_to(REPO))
    except ValueError:
        pass
    payload = {
        "generated_at": now_iso,
        "latest_release": latest,
        "registry_path": rel_registry,
        "projects": [asdict(p) for p in pins],
    }
    return json.dumps(payload, indent=2) + "\n"


def main() -> int:
    """CLI entry point: parse args, load registry, fetch latest, render."""
    parser = argparse.ArgumentParser(
        description="Fleet pin inspector — per-project dev-platform-gate pin tracking.",
    )
    parser.add_argument(
        "--format",
        choices=["markdown", "json"],
        default="markdown",
        help="Output format (default: markdown)",
    )
    parser.add_argument(
        "--project",
        help="Filter to a single project by name",
    )
    parser.add_argument(
        "--registry",
        default=str(REGISTRY_DEFAULT),
        help=f"Registry path (default: {REGISTRY_DEFAULT})",
    )
    parser.add_argument(
        "--latest",
        help="Override the latest-release lookup (skips gh api). For tests + offline use.",
    )
    parser.add_argument(
        "--source",
        choices=["local", "github", "both"],
        default="both",
        help=(
            "Which copy of each consumer template to read: 'github' (the "
            "default-branch file CI actually runs), 'local' (this machine's "
            "working copy — the pre-v1.27 behaviour, and the one to use with "
            "no network or no gh), or 'both' (default; reports drift between "
            "them)."
        ),
    )
    args = parser.parse_args()

    registry_path = Path(args.registry).resolve()
    entries = load_registry(registry_path)
    # Match fleet-gate.sh + fleet_dashboard.py: strict opt-in via
    # explicit `enabled: true`. Missing field → excluded.
    enabled = [e for e in entries if e.get("enabled", False)]
    if args.project:
        enabled = [e for e in enabled if e["name"] == args.project]
        if not enabled:
            sys.stderr.write(
                f"ERROR: project '{args.project}' not found in registry (or disabled)\n"
            )
            return 2

    # Resolve latest ONCE before fanning out — every worker reuses it.
    if args.latest is not None:
        # Fail-loud on malformed values: silently degrading would make
        # every project look up-to-date and hide a typo (e.g. `0.7`
        # missing the `v` prefix).
        if SEMVER_RE.match(args.latest) is None:
            sys.stderr.write(
                f"ERROR: --latest must be a semver tag (vX.Y or vX.Y.Z); "
                f"got '{args.latest}'\n"
            )
            return 2
        latest = args.latest
    else:
        latest = fetch_latest_release()
        if latest is None:
            sys.stderr.write(
                "WARNING: could not resolve latest dev-platform release "
                "(gh not on PATH, not authenticated, or no releases). "
                "Staleness comparison disabled.\n"
            )

    # Parallel per-project queries. I/O-bound (filesystem reads plus, under
    # --source github/both, two `gh api` calls each), so ThreadPoolExecutor
    # is correct and the network round-trips overlap across projects.
    with ThreadPoolExecutor(max_workers=8) as pool:
        pins = list(pool.map(lambda e: query_project(e, latest, args.source), enabled))

    if args.format == "json":
        sys.stdout.write(render_json(pins, registry_path, latest))
    else:
        sys.stdout.write(render_markdown(pins, registry_path, latest))
    return 0


if __name__ == "__main__":
    sys.exit(main())
