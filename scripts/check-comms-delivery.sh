#!/usr/bin/env bash
# scripts/check-comms-delivery.sh — verify every post-migration ask-communique
# links a live upstream GitHub issue. Thin wrapper around
# monitoring/comms_delivery.py.
#
# NOT wired into gate_fast.sh: it makes gh network calls and scans projects/
# paths that may not be cloned. Standalone fleet-style tool, like fleet-pins.sh.
#
# Usage:
#   ./scripts/check-comms-delivery.sh                       # all active consumers
#   ./scripts/check-comms-delivery.sh --consumer kermit-pa
#   ./scripts/check-comms-delivery.sh --offline             # no gh; no-ref check only
#   ./scripts/check-comms-delivery.sh --json
#   ./scripts/check-comms-delivery.sh --help

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="${REPO}/monitoring/comms_delivery.py"

if [[ ! -f "${CHECKER}" ]]; then
    echo "ERROR: checker not found at ${CHECKER}" >&2
    exit 2
fi

exec python3 "${CHECKER}" "$@"
