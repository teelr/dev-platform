#!/usr/bin/env bash
# scripts/fleet-status.sh — fleet dashboard CLI.
# Thin wrapper that delegates to monitoring/fleet_dashboard.py.
#
# Usage:
#   ./scripts/fleet-status.sh                       # markdown, all enabled projects
#   ./scripts/fleet-status.sh --format json         # machine-readable
#   ./scripts/fleet-status.sh --project dev-platform
#   ./scripts/fleet-status.sh --registry <path>     # override registry path (tests)
#   ./scripts/fleet-status.sh --help

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DASHBOARD="${REPO}/monitoring/fleet_dashboard.py"

if [[ ! -f "${DASHBOARD}" ]]; then
    echo "ERROR: dashboard not found at ${DASHBOARD}" >&2
    exit 1
fi

# Pass args through. Python script handles --help.
exec python3 "${DASHBOARD}" "$@"
