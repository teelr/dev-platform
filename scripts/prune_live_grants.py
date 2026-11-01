#!/usr/bin/env python3
"""scripts/prune_live_grants.py — list (and optionally remove) one-off grants that
piled up in the live ~/.claude/settings.json.

Claude Code writes an "always allow" entry into the live settings file every time
the user accepts a prompt. Many are one-offs that will never match again (a `kill`
of a specific PID) or that grant more than they should (`sudo ...`). The tracked
retract list is the wrong place to remove them: it is public, so retracting a
one-off would publish its text.

Candidates are live `permissions.allow` entries that are NOT in the baseline. Each
is classified by the first matching rule:

  pid-kill      `Bash(kill [-SIG] <digits>)` — a PID that no longer exists
  sudo          `Bash(sudo ...)`
  scratch-path  mentions `/tmp/claude-` — a per-session scratchpad path
  inline-token  mentions `GH_TOKEN=` — a token read inline from a file
  unclassified  everything else — listed, never removed

Default is list-only. `--apply` writes a backup (`<live>.bak-<UTC stamp>`, 0600)
and then removes the first four classes. Nothing else in the file changes, and the
baseline is never written.

Usage:
    prune_live_grants.py <baseline_path> <live_path> [--apply]

Exit code:
    0 — listed (or applied)
    2 — malformed JSON in baseline or live file
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

# Reuse the sibling's JSON loader so error handling and exit codes stay identical.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from merge_settings import load_json  # noqa: E402

PID_KILL = re.compile(r"^Bash\(kill( -\w+)? \d+\)$")
REMOVABLE = ("pid-kill", "sudo", "scratch-path", "inline-token")
SHOW = 100  # entries can embed paths and token-file names; never print more


def classify(entry: str) -> str:
    """Return the class of one allow entry; first matching rule wins."""
    if PID_KILL.match(entry):
        return "pid-kill"
    if entry.startswith("Bash(sudo "):
        return "sudo"
    if "/tmp/claude-" in entry:
        return "scratch-path"
    if "GH_TOKEN=" in entry:
        return "inline-token"
    return "unclassified"


def allow_list(settings: dict) -> list[str]:
    perms = settings.get("permissions")
    if not isinstance(perms, dict):
        return []
    allow = perms.get("allow")
    return [e for e in allow if isinstance(e, str)] if isinstance(allow, list) else []


def main() -> int:
    parser = argparse.ArgumentParser(
        description="List one-off grants in the live settings file; --apply removes them.",
    )
    parser.add_argument("baseline_path", help="Tracked baseline (read-only input)")
    parser.add_argument("live_path", help="Live settings file (written only with --apply)")
    parser.add_argument(
        "--apply", action="store_true",
        help="Back up the live file, then remove pid-kill, sudo, scratch-path and inline-token grants",
    )
    args = parser.parse_args()

    baseline = load_json(Path(args.baseline_path), "baseline")
    live_path = Path(args.live_path)
    live = load_json(live_path, "live")

    base_set = set(allow_list(baseline))
    candidates = [e for e in allow_list(live) if e not in base_set]
    classes = {e: classify(e) for e in candidates}

    for entry in candidates:
        text = entry if len(entry) <= SHOW else entry[:SHOW] + "..."
        print(f"{classes[entry]:13} {text}")

    counts = Counter(classes.values())
    print()
    print(f"live grants: {len(allow_list(live))}, not in baseline: {len(candidates)}")
    for name in (*REMOVABLE, "unclassified"):
        print(f"  {name:13} {counts.get(name, 0)}")

    if not args.apply:
        print("list only; nothing written. Re-run with --apply to remove the first four classes.")
        return 0

    drop = {e for e, c in classes.items() if c in REMOVABLE}
    if not drop:
        print("nothing to remove; no backup written.")
        return 0
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup = live_path.with_name(f"{live_path.name}.bak-{stamp}")
    fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(live_path.read_bytes())

    live["permissions"]["allow"] = [e for e in live["permissions"]["allow"] if e not in drop]
    with open(live_path, "w", encoding="utf-8") as f:
        f.write(json.dumps(live, indent=2) + "\n")
    print(f"removed {len(drop)} grants; backup at {backup}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
