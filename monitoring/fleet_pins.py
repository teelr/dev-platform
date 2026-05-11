#!/usr/bin/env python3
"""dev-platform fleet pin inspector.

Reads monitoring/projects.json and reports each project's adoption
of the dev-platform-gate consumer template + its `@vX.Y` pin
relative to the latest dev-platform release tag.

Read-only. No fleet sweep (that's scripts/fleet-gate.sh); no
mutations (that's scripts/fleet-install-template.sh, governed by
the v0.8 Phase 3 Scope-rule carve-out).

Usage:
    python3 monitoring/fleet_pins.py                          # markdown, all enabled
    python3 monitoring/fleet_pins.py --format json            # machine-readable
    python3 monitoring/fleet_pins.py --project atlas
    python3 monitoring/fleet_pins.py --registry <path>        # override (tests)
    python3 monitoring/fleet_pins.py --latest v0.8            # override latest-release lookup (tests)

Exits 0 on success, 2 on argparse / setup error.

Registry schema reference: monitoring/projects.json
"""
from __future__ import annotations

import argparse
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
    pin: Optional[str]
    latest: Optional[str]
    # One of: "self", "up-to-date", "behind", "floating", "unparseable", "not-adopted".
    status: str
    # For sortability when status == "behind"; (major_diff * 1000) + minor_diff.
    minor_delta: Optional[int]


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


def query_project(entry: dict, latest: Optional[str]) -> ProjectPin:
    """Run all per-project queries against one registry entry."""
    name = entry["name"]
    path_raw = entry["path"]
    target = (REPO if path_raw == "." else REPO / path_raw).resolve()

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
        )

    template_path = target / ".github" / "workflows" / "dev-platform-gate.yml"
    pin = extract_pin(template_path)
    adopted = template_path.exists()
    status, minor_delta = classify(pin, latest)

    return ProjectPin(
        name=name,
        path=path_raw,
        adopted=adopted,
        pin=pin,
        latest=latest,
        status=status,
        minor_delta=minor_delta,
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
        "| Project           | Adopted | Pin    | Status               |",
        "| ----------------- | ------- | ------ | -------------------- |",
    ]
    for p in pins:
        lines.append(
            f"| {p.name:<17} | {format_adopted(p.adopted):<7} | {format_pin(p.pin, p.status):<6} | {format_status(p.status, p.minor_delta):<20} |"
        )
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

    # Parallel per-project queries. I/O-bound (filesystem reads), so
    # ThreadPoolExecutor is correct.
    with ThreadPoolExecutor(max_workers=8) as pool:
        pins = list(pool.map(lambda e: query_project(e, latest), enabled))

    if args.format == "json":
        sys.stdout.write(render_json(pins, registry_path, latest))
    else:
        sys.stdout.write(render_markdown(pins, registry_path, latest))
    return 0


if __name__ == "__main__":
    sys.exit(main())
