#!/usr/bin/env python3
"""scripts/merge_settings.py — deploy the tracked settings baseline into a live
local settings file without clobbering runtime grants.

dev-platform deploys ~/.claude/settings.json as a REAL local file (v1.6 Local
Settings Isolation), not a symlink into the repo — so Claude Code's "always
allow" grants accumulate locally and never pollute the tracked repo. This helper
is how install.sh pushes baseline updates into that live file.

Merge rules (baseline = settings/settings.json, live = ~/.claude/settings.json):
  - permissions.allow / .deny / .ask / .additionalDirectories → UNION
    (sorted(set(baseline ∪ live))). Preserves the live file's runtime grants AND
    adds any new baseline entries.
  - every other key (hooks, model, enabledPlugins, ...) → BASELINE WINS
    (dev-platform-managed config overwrites the live value).
  - live missing/empty → result is the baseline verbatim (first-install seed).

RETRACTING a permission: a plain union can ADD but not REMOVE, so deleting an
entry from the baseline leaves it in the live file. Pass `--retract <file>` (a
JSON object `{"allow": [...]}`) and every listed string is removed from the live
`permissions.allow` after the union. Matching is EXACT string equality — a
retract of `Bash(bash *)` leaves `Bash(bash ~/x/*)` alone. Retract only touches
`allow`, and an entry that is in both the baseline allow list and the retract
list is a contradiction (exit 2). See settings/README.md.

Writes the merged JSON to <live_path> only. NEVER writes <baseline_path>.

Usage:
    merge_settings.py <baseline_path> <live_path> [--retract <path>] [--dry-run]

Exit code:
    0 — merged (or dry-run printed)
    2 — malformed JSON in baseline, live or retract file; missing retract file;
        or a baseline allow entry that is also retracted
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# permissions subkeys that hold rule lists and should be unioned, not overwritten.
PERMISSION_LIST_KEYS = ("allow", "deny", "ask", "additionalDirectories")


def load_json(path: Path, label: str) -> dict:
    """Load a JSON object. Missing/empty file → {}. Malformed → exit 2."""
    if not path.exists() or path.stat().st_size == 0:
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError) as exc:
        sys.stderr.write(f"ERROR: {label} ({path}) is not valid JSON: {exc}\n")
        sys.exit(2)
    if not isinstance(data, dict):
        sys.stderr.write(f"ERROR: {label} ({path}) must be a JSON object\n")
        sys.exit(2)
    return data


def load_retract(path: Path) -> list[str]:
    """Load the retract list. Unlike load_json, a missing file is an error: the
    caller named it explicitly, so silently skipping it would skip the tightening."""
    if not path.exists():
        sys.stderr.write(f"ERROR: retract file ({path}) does not exist\n")
        sys.exit(2)
    data = load_json(path, "retract")
    entries = data.get("allow", [])
    if not isinstance(entries, list) or not all(isinstance(e, str) for e in entries):
        sys.stderr.write(f"ERROR: retract file ({path}) 'allow' must be a list of strings\n")
        sys.exit(2)
    return entries


def apply_retract(merged: dict, baseline: dict, retract: list[str]) -> dict:
    """Remove exact-match retract entries from merged permissions.allow."""
    contradictions = sorted(
        set(retract) & set((baseline.get("permissions", {}) or {}).get("allow", []) or [])
    )
    if contradictions:
        sys.stderr.write(
            "ERROR: entries are in both the baseline allow list and the retract list: "
            + ", ".join(contradictions) + "\n"
        )
        sys.exit(2)
    perms = merged.get("permissions")
    if isinstance(perms, dict) and isinstance(perms.get("allow"), list):
        drop = set(retract)
        perms["allow"] = [e for e in perms["allow"] if e not in drop]
    return merged


def merge(baseline: dict, live: dict) -> dict:
    """Merge baseline into live per the module rules. Returns a new dict."""
    result = dict(live)  # start from live so any live-only top-level keys survive

    for key, base_val in baseline.items():
        if key == "permissions" and isinstance(base_val, dict):
            result["permissions"] = _merge_permissions(
                base_val, live.get("permissions", {}) or {}
            )
        else:
            # Baseline wins on all config keys.
            result[key] = base_val

    return result


def _merge_permissions(base_perms: dict, live_perms: dict) -> dict:
    """Union the rule-list subkeys; baseline wins on any other permissions subkey."""
    merged = dict(live_perms)
    for key, base_val in base_perms.items():
        if key in PERMISSION_LIST_KEYS:
            live_list = live_perms.get(key, []) or []
            base_list = base_val or []
            merged[key] = sorted(set(live_list) | set(base_list))
        else:
            merged[key] = base_val
    return merged


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Merge the tracked settings baseline into a live local settings file.",
    )
    parser.add_argument("baseline_path", help="Tracked baseline (read-only input)")
    parser.add_argument("live_path", help="Live local file (written; never the baseline)")
    parser.add_argument(
        "--retract", metavar="PATH",
        help="JSON file {\"allow\": [...]}: exact entries to remove from the live allow list",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print the merged result to stdout; write nothing",
    )
    args = parser.parse_args()

    baseline_path = Path(args.baseline_path)
    live_path = Path(args.live_path)

    baseline = load_json(baseline_path, "baseline")
    live = load_json(live_path, "live")
    merged = merge(baseline, live)
    if args.retract:
        merged = apply_retract(merged, baseline, load_retract(Path(args.retract)))
    rendered = json.dumps(merged, indent=2) + "\n"

    if args.dry_run:
        sys.stdout.write(rendered)
        return 0

    with open(live_path, "w", encoding="utf-8") as f:
        f.write(rendered)
    return 0


if __name__ == "__main__":
    sys.exit(main())
