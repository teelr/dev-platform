#!/usr/bin/env bash
# scripts/fleet-pins.sh — fleet pin inspector CLI.
# Thin wrapper that delegates to monitoring/fleet_pins.py.
#
# Usage:
#   ./scripts/fleet-pins.sh                       # markdown, all enabled projects
#   ./scripts/fleet-pins.sh --format json         # machine-readable
#   ./scripts/fleet-pins.sh --project atlas
#   ./scripts/fleet-pins.sh --latest v0.8         # override latest-release lookup (tests)
#   ./scripts/fleet-pins.sh --registry <path>     # override registry path (tests)
#   ./scripts/fleet-pins.sh --source local        # local working copies only (offline)
#   ./scripts/fleet-pins.sh --source github       # default-branch copies only
#   ./scripts/fleet-pins.sh --help
#
# --source defaults to `both`: the live default-branch pin is what CI runs,
# the local one is what's on this disk, and a mismatch between them is
# reported as drift rather than quietly resolved (v1.27).

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSPECTOR="${REPO}/monitoring/fleet_pins.py"

if [[ ! -f "${INSPECTOR}" ]]; then
    echo "ERROR: inspector not found at ${INSPECTOR}" >&2
    exit 1
fi

# Pass args through. Python script handles --help.
exec python3 "${INSPECTOR}" "$@"
