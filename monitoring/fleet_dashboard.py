#!/usr/bin/env python3
"""dev-platform fleet dashboard.

Reads monitoring/projects.json and reports per-project state across the
fleet: last-commit recency, current branch, uncommitted file count,
taxonomy compliance (via scripts/check_spec_taxonomy.sh), and
consumer-template adoption flag.

Read-only. No fleet sweep (that's scripts/fleet-gate.sh); no mutations
(that's v0.8 Phase 3's fleet-install-template.sh).

Usage:
    python3 monitoring/fleet_dashboard.py                    # markdown, all enabled
    python3 monitoring/fleet_dashboard.py --format json      # machine-readable
    python3 monitoring/fleet_dashboard.py --project dev-platform
    python3 monitoring/fleet_dashboard.py --registry <path>  # override registry path

Exits 0 on success, 1 on registry / per-project errors, 2 on argparse / setup error.

Registry schema reference: monitoring/projects.json
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

REPO = Path(__file__).resolve().parent.parent
REGISTRY_DEFAULT = REPO / "monitoring" / "projects.json"
TAXONOMY_CHECKER = REPO / "scripts" / "check_spec_taxonomy.sh"
QUERY_TIMEOUT_S = 10
BRANCH_TRUNCATE_LEN = 20


@dataclass
class ProjectState:
    name: str
    path: str
    branch: str
    last_commit_iso: Optional[str]
    last_commit_sha: Optional[str]
    last_commit_subject: Optional[str]
    last_commit_age_days: Optional[int]
    uncommitted_count: int
    taxonomy_ok: bool
    # "self" for dev-platform, True if template installed, False otherwise.
    dev_platform_gate_installed: object


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


def query_project(entry: dict) -> ProjectState:
    """Run all per-project queries against one registry entry."""
    name = entry["name"]
    path_raw = entry["path"]
    target = (REPO if path_raw == "." else REPO / path_raw).resolve()

    branch = "?"
    last_iso = None
    last_sha = None
    last_subject = None
    last_age = None
    uncommitted = 0
    taxonomy_ok = True
    gate_installed: object = False

    if not target.is_dir() or not (target / ".git").exists():
        # Not a git repo — mark everything unknown but don't crash.
        return ProjectState(
            name=name, path=path_raw, branch="(no git)",
            last_commit_iso=None, last_commit_sha=None,
            last_commit_subject=None, last_commit_age_days=None,
            uncommitted_count=0, taxonomy_ok=True,
            dev_platform_gate_installed=False,
        )

    # 1. Last commit (timestamp, sha, subject) — single git call, pipe-delimited.
    rc, out = _run(
        ["git", "-C", str(target), "log", "-1", "--format=%cI|%h|%s"],
        cwd=target,
    )
    if rc == 0 and "|" in out:
        parts = out.split("|", 2)
        if len(parts) == 3:
            last_iso = parts[0]
            last_sha = parts[1]
            last_subject = parts[2]
            try:
                commit_dt = datetime.fromisoformat(last_iso)
                now = datetime.now(commit_dt.tzinfo or timezone.utc)
                last_age = (now - commit_dt).days
            except ValueError:
                pass

    # 2. Current branch
    rc, out = _run(
        ["git", "-C", str(target), "rev-parse", "--abbrev-ref", "HEAD"],
        cwd=target,
    )
    if rc == 0 and out:
        branch = out

    # 3. Uncommitted count
    rc, out = _run(
        ["git", "-C", str(target), "status", "--porcelain"],
        cwd=target,
    )
    if rc == 0:
        uncommitted = len([ln for ln in out.splitlines() if ln.strip()])

    # 4. Taxonomy compliance — delegate to the canonical checker
    rc, _ = _run(
        ["bash", str(TAXONOMY_CHECKER), str(target)],
        cwd=target,
    )
    taxonomy_ok = (rc == 0)

    # 5. Consumer-template adoption flag
    template_path = target / ".github" / "workflows" / "dev-platform-gate.yml"
    if name == "dev-platform":
        gate_installed = "self"
    elif template_path.exists():
        gate_installed = True
    else:
        gate_installed = False

    return ProjectState(
        name=name,
        path=path_raw,
        branch=branch,
        last_commit_iso=last_iso,
        last_commit_sha=last_sha,
        last_commit_subject=last_subject,
        last_commit_age_days=last_age,
        uncommitted_count=uncommitted,
        taxonomy_ok=taxonomy_ok,
        dev_platform_gate_installed=gate_installed,
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


def format_age(days: Optional[int]) -> str:
    """Render a commit-age parenthetical: '(today)', '(3d)', or '?' if unknown."""
    if days is None:
        return "?"
    if days == 0:
        return "(today)"
    return f"({days}d)"


def truncate_branch(branch: str, n: int = BRANCH_TRUNCATE_LEN) -> str:
    """Truncate a branch name with ellipsis if longer than n chars."""
    if len(branch) <= n:
        return branch
    return branch[: n - 1] + "…"


def format_gate(flag: object) -> str:
    """Render the adoption flag: 'self' for dev-platform, '✓' if installed, '—' otherwise."""
    if flag == "self":
        return "self"
    if flag is True:
        return "✓"
    return "—"


def render_markdown(states: list[ProjectState], registry_path: Path) -> str:
    """Format the per-project state list as a markdown report with header + table."""
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    enabled_count = len(states)
    rel_registry = registry_path
    try:
        rel_registry = registry_path.relative_to(REPO)
    except ValueError:
        pass

    lines = [
        "# Fleet Dashboard",
        "",
        f"Generated: {now_iso}",
        f"Registry: {rel_registry} ({enabled_count} enabled)",
        "",
        "| Project           | Branch                 | Last commit         | Uncommitted | Taxonomy | dev-platform-gate |",
        "| ----------------- | ---------------------- | ------------------- | ----------- | -------- | ----------------- |",
    ]
    for s in states:
        if s.last_commit_iso:
            date_str = s.last_commit_iso[:10]
            age_str = format_age(s.last_commit_age_days)
            commit_col = f"{date_str} {age_str}"
        else:
            commit_col = "?"
        tax_col = "OK" if s.taxonomy_ok else "DRIFT"
        lines.append(
            f"| {s.name:<17} | {truncate_branch(s.branch):<22} | {commit_col:<19} | {s.uncommitted_count:<11} | {tax_col:<8} | {format_gate(s.dev_platform_gate_installed):<17} |"
        )
    return "\n".join(lines) + "\n"


def render_json(states: list[ProjectState], registry_path: Path) -> str:
    """Format the per-project state list as a JSON payload (machine-readable)."""
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    rel_registry = str(registry_path)
    try:
        rel_registry = str(registry_path.relative_to(REPO))
    except ValueError:
        pass
    payload = {
        "generated_at": now_iso,
        "registry_path": rel_registry,
        "projects": [asdict(s) for s in states],
    }
    return json.dumps(payload, indent=2) + "\n"


def main() -> int:
    """CLI entry point: parse args, load registry, run concurrent per-project queries, render."""
    parser = argparse.ArgumentParser(
        description="Fleet Dashboard — per-project state across the dev-platform fleet.",
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
    args = parser.parse_args()

    registry_path = Path(args.registry).resolve()
    entries = load_registry(registry_path)
    # Match fleet-gate.sh's stricter semantics: entries must opt-in via
    # explicit `enabled: true`. Missing field → excluded (not included).
    enabled = [e for e in entries if e.get("enabled", False)]
    if args.project:
        enabled = [e for e in enabled if e["name"] == args.project]
        if not enabled:
            sys.stderr.write(
                f"ERROR: project '{args.project}' not found in registry (or disabled)\n"
            )
            return 2

    # Parallel per-project queries. I/O-bound (subprocess + filesystem),
    # so ThreadPoolExecutor is correct.
    with ThreadPoolExecutor(max_workers=8) as pool:
        states = list(pool.map(query_project, enabled))

    if args.format == "json":
        sys.stdout.write(render_json(states, registry_path))
    else:
        sys.stdout.write(render_markdown(states, registry_path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
