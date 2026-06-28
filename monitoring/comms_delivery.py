#!/usr/bin/env python3
"""dev-platform cross-repo comms delivery checker.

Confirms that every ask-communique written on/after the migration adoption date
links to a real upstream GitHub issue. The inbound comms rule ("file the ask as
a GitHub issue") is advisory; this checker makes "is the ask actually delivered"
queryable — the 2026-06-28 failure mode where PA's OllamaAdapter ask was filed
locally but never reached the harness.

Read-only. Scans each active consumer's tasks/communique-to-<dep_slug>-*.md
files and verifies each in-scope file links an upstream issue that exists
(via `gh issue view`). NOT wired into gate_fast.sh — it makes network calls and
scans projects/ paths that may not be cloned. The offline test suite at
tests/comms-delivery/run.sh is the gate's coverage.

Usage:
    python3 monitoring/comms_delivery.py                       # all active consumers
    python3 monitoring/comms_delivery.py --consumer kermit-pa  # one consumer
    python3 monitoring/comms_delivery.py --since 2026-06-28    # cutoff (default)
    python3 monitoring/comms_delivery.py --offline             # skip gh; no-ref check only
    python3 monitoring/comms_delivery.py --json                # machine-readable
    python3 monitoring/comms_delivery.py --registry <path>     # override (tests)

Exit code:
    0 — no FAIL (all in-scope communiques link a live issue, or are UNVERIFIED/SKIP)
    1 — at least one FAIL (a post-cutover communique links no issue, or a dead link)
    2 — argparse / setup error

Registry schema reference: monitoring/comms-consumers.json
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Optional

REPO = Path(__file__).resolve().parent.parent
REGISTRY_DEFAULT = REPO / "monitoring" / "comms-consumers.json"
DEFAULT_SINCE = "2026-06-28"  # cross-repo comms standard adopted (PR #33)
QUERY_TIMEOUT_S = 10

# YYYY-MM-DD anywhere in a communique filename. The convention is
# communique-to-<dep_slug>-YYYY-MM-DD-<slug>.md; undated legacy files exist too.
DATE_RE = re.compile(r"(\d{4})-(\d{2})-(\d{2})")

# Statuses, ranked worst-first for the summary tally.
OK, FAIL, UNVERIFIED, SKIP = "OK", "FAIL", "UNVERIFIED", "SKIP"


@dataclass
class FileResult:
    consumer: str
    path: str  # repo-relative path to the communique
    status: str  # OK | FAIL | UNVERIFIED | SKIP
    detail: str
    issues: list  # issue numbers referenced (may be empty)


def load_registry(path: Path) -> list:
    """Load + validate the consumer registry JSON. Exits 2 on missing/malformed."""
    if not path.is_file():
        sys.stderr.write(f"ERROR: registry not found at {path}\n")
        sys.exit(2)
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list):
        sys.stderr.write(
            f"ERROR: registry must be a JSON array (got {type(data).__name__})\n"
        )
        sys.exit(2)
    return data


def file_date(name: str) -> Optional[str]:
    """Extract the first YYYY-MM-DD from a filename as an ISO string, or None."""
    m = DATE_RE.search(name)
    if m is None:
        return None
    return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"


def build_issue_re(upstream_repo: str) -> re.Pattern:
    """Regex matching a repo-qualified reference to an upstream issue.

    For upstream_repo "teelr/kermit-harness" this matches:
      - full URL: https://github.com/teelr/kermit-harness/issues/200
      - org shorthand: teelr/kermit-harness#200
      - repo-name shorthand: kermit-harness#200

    A bare `#200` is deliberately NOT matched. The whole point of the checker
    is to confirm the communique points at THE upstream repo's issue; a bare
    `#N` matches any PR/issue number (e.g. "PR #121" referencing the consumer's
    own PR), which gives a false "delivered" signal — the exact failure mode the
    checker exists to catch. Require an explicit repo qualifier.

    Each alternative captures the issue number in its own group; exactly one
    group is set per match, so extract_issue_refs picks the non-empty one.
    """
    owner, repo = upstream_repo.split("/", 1)
    owner_e = re.escape(owner)
    repo_e = re.escape(repo)
    pattern = (
        rf"https://github\.com/{owner_e}/{repo_e}/issues/(\d+)"
        rf"|{owner_e}/{repo_e}#(\d+)"
        rf"|{repo_e}#(\d+)"
    )
    return re.compile(pattern)


def extract_issue_refs(text: str, issue_re: re.Pattern) -> list:
    """Return the sorted unique issue numbers referenced in text."""
    nums = set()
    for groups in issue_re.findall(text):
        # findall yields a tuple of the 3 alternation groups; exactly one is set.
        for g in groups:
            if g:
                nums.add(int(g))
                break
    return sorted(nums)


def _run(cmd: list, cwd: Path) -> tuple:
    """Run a subprocess with a hard timeout. Returns (rc, stdout, stderr)."""
    try:
        result = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=QUERY_TIMEOUT_S
        )
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"
    except (FileNotFoundError, OSError):
        return 127, "", "gh not found"


def verify_issue(repo: str, number: int) -> str:
    """Check an upstream issue's existence via gh. Returns 'exists'|'missing'|'unverified'.

    MUST use --json: the bare `gh issue view <n>` form fetches classic-Projects
    fields and dies with a "Projects (classic) is being deprecated" GraphQL
    error. `--json number,state` avoids that path entirely.
    """
    rc, out, err = _run(
        ["gh", "issue", "view", str(number), "--repo", repo, "--json", "number,state"],
        cwd=REPO,
    )
    if rc == 0 and out:
        return "exists"
    blob = (err + out).lower()
    if "could not resolve" in blob or "not found" in blob or "no issue found" in blob:
        return "missing"
    # gh absent (127), unauthenticated, timeout (124), rate-limited, offline:
    # cannot prove either way → unverified (never silently PASS).
    return "unverified"


def check_consumer(entry: dict, since: str, offline: bool) -> list:
    """Scan one consumer's ask-communiques. Returns a list of FileResult."""
    consumer = entry["consumer"]
    dep_slug = entry["dep_slug"]
    upstream_repo = entry["upstream_repo"]
    path_raw = entry["path"]
    tasks_dir = (REPO / path_raw / "tasks").resolve()

    if not tasks_dir.is_dir():
        return [
            FileResult(consumer, path_raw, SKIP, "consumer tasks/ not found (not cloned)", [])
        ]

    issue_re = build_issue_re(upstream_repo)
    results = []
    # Only asks TO the dependency: communique-to-<dep_slug>-*. Replies in the
    # other direction (communique-to-pa-*, ...) are not asks needing an issue.
    pattern = f"communique-to-{dep_slug}-*.md"
    for f in sorted(tasks_dir.glob(pattern)):
        # Repo-relative for readable output; fall back to absolute when the
        # consumer lives outside REPO (e.g. absolute paths in a test registry).
        try:
            rel = str(f.relative_to(REPO))
        except ValueError:
            rel = str(f)
        date = file_date(f.name)
        if date is None:
            results.append(FileResult(consumer, rel, SKIP, "legacy (undated)", []))
            continue
        if date < since:
            results.append(FileResult(consumer, rel, SKIP, f"legacy (pre-{since})", []))
            continue

        try:
            text = f.read_text(encoding="utf-8")
        except OSError as exc:
            results.append(FileResult(consumer, rel, FAIL, f"unreadable: {exc}", []))
            continue

        refs = extract_issue_refs(text, issue_re)
        if not refs:
            results.append(
                FileResult(consumer, rel, FAIL, "no upstream issue linked", [])
            )
            continue

        if offline:
            results.append(
                FileResult(consumer, rel, UNVERIFIED, f"links {refs}; gh skipped (--offline)", refs)
            )
            continue

        # Delivered if ANY referenced issue exists. A dead-only link is FAIL;
        # unverified-only is UNVERIFIED.
        states = {n: verify_issue(upstream_repo, n) for n in refs}
        if any(s == "exists" for s in states.values()):
            live = [n for n, s in states.items() if s == "exists"]
            results.append(FileResult(consumer, rel, OK, f"linked live issue {live}", refs))
        elif any(s == "missing" for s in states.values()):
            results.append(
                FileResult(
                    consumer, rel, FAIL,
                    f"linked issue {refs} not found on {upstream_repo}", refs,
                )
            )
        else:
            results.append(
                FileResult(consumer, rel, UNVERIFIED, f"links {refs}; gh unreachable", refs)
            )

    if not results:
        return [FileResult(consumer, path_raw, SKIP, "no in-scope ask-communiques", [])]
    return results


def render_text(results: list, since: str) -> str:
    """One line per result + a summary tally."""
    lines = [f"Comms delivery check (asks on/after {since}):", ""]
    for r in results:
        lines.append(f"  {r.status:<10} {r.path}  — {r.detail}")
    tally = {OK: 0, FAIL: 0, UNVERIFIED: 0, SKIP: 0}
    for r in results:
        tally[r.status] = tally.get(r.status, 0) + 1
    lines.append("")
    lines.append(
        f"Summary: {tally[OK]} OK, {tally[FAIL]} FAIL, "
        f"{tally[UNVERIFIED]} UNVERIFIED, {tally[SKIP]} SKIP"
    )
    if tally[FAIL] > 0:
        lines.append("")
        lines.append(
            "FAIL — these asks are not delivered. File a GitHub issue on the "
            "upstream repo and link it in the communique (see docs/CROSS-REPO-COMMS.md)."
        )
    return "\n".join(lines) + "\n"


def render_json(results: list, since: str) -> str:
    tally = {OK: 0, FAIL: 0, UNVERIFIED: 0, SKIP: 0}
    for r in results:
        tally[r.status] = tally.get(r.status, 0) + 1
    payload = {
        "since": since,
        "summary": tally,
        "results": [asdict(r) for r in results],
    }
    return json.dumps(payload, indent=2) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify each post-migration ask-communique links a live upstream issue.",
    )
    parser.add_argument("--consumer", help="Restrict to one consumer by name")
    parser.add_argument(
        "--since", default=DEFAULT_SINCE,
        help=f"Only check communiques dated on/after this YYYY-MM-DD (default: {DEFAULT_SINCE})",
    )
    parser.add_argument(
        "--offline", action="store_true",
        help="Skip all gh calls; only the no-issue-linked check runs (UNVERIFIED for the rest)",
    )
    parser.add_argument("--json", action="store_true", help="Machine-readable output")
    parser.add_argument(
        "--registry", default=str(REGISTRY_DEFAULT),
        help=f"Registry path (default: {REGISTRY_DEFAULT})",
    )
    args = parser.parse_args()

    if DATE_RE.fullmatch(args.since) is None:
        sys.stderr.write(f"ERROR: --since must be YYYY-MM-DD; got '{args.since}'\n")
        return 2

    registry_path = Path(args.registry).resolve()
    entries = load_registry(registry_path)
    # Only consumers that currently file asks. Deprecated ones (active:false)
    # are skipped so historical atlas asks don't flag.
    active = [e for e in entries if e.get("active", False)]
    if args.consumer:
        active = [e for e in active if e["consumer"] == args.consumer]
        if not active:
            sys.stderr.write(
                f"ERROR: consumer '{args.consumer}' not found in registry (or inactive)\n"
            )
            return 2

    results = []
    for entry in active:
        results.extend(check_consumer(entry, args.since, args.offline))

    if args.json:
        sys.stdout.write(render_json(results, args.since))
    else:
        sys.stdout.write(render_text(results, args.since))

    return 1 if any(r.status == FAIL for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())
