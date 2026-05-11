#!/usr/bin/env bash
# scripts/report.sh — display the dev-platform telemetry report.
#
# Thin Bash wrapper that delegates to monitoring/aggregator.py. Matches the
# existing entry-point pattern (gate_fast.sh, install.sh, verify.sh,
# new-project.sh) so users don't need to remember a Python invocation.
#
# Usage:
#   ./scripts/report.sh                       # daily, all projects, markdown
#   ./scripts/report.sh daily                 # same
#   ./scripts/report.sh weekly                # last 7 days
#   ./scripts/report.sh all                   # full history
#   ./scripts/report.sh daily dev-platform    # daily, single project
#   ./scripts/report.sh weekly kermit         # weekly, kermit project only
#   ./scripts/report.sh --json                # daily, machine-readable JSON
#   ./scripts/report.sh weekly --json         # weekly, JSON
#
# Exits 0 on success, 1 on missing log file or argparse error.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGG="${REPO}/monitoring/aggregator.py"

if [[ ! -f "${AGG}" ]]; then
    echo "ERROR: aggregator not found at ${AGG}" >&2
    exit 1
fi

# Argument parsing — accept positional period + project + optional --json.
PERIOD="daily"
PROJECT=""
JSON=""

for arg in "$@"; do
    case "${arg}" in
        --json)
            JSON="--json"
            ;;
        daily|weekly|all)
            PERIOD="${arg}"
            ;;
        --help|-h)
            cat <<'HELP'
scripts/report.sh — display the dev-platform telemetry report.

Thin Bash wrapper that delegates to monitoring/aggregator.py.

Usage:
  ./scripts/report.sh                       # daily, all projects, markdown
  ./scripts/report.sh daily                 # same
  ./scripts/report.sh weekly                # last 7 days
  ./scripts/report.sh all                   # full history
  ./scripts/report.sh daily dev-platform    # daily, single project
  ./scripts/report.sh weekly kermit         # weekly, kermit project only
  ./scripts/report.sh --json                # daily, machine-readable JSON
  ./scripts/report.sh weekly --json         # weekly, JSON

Arguments accepted in any order:
  daily | weekly | all     reporting window (default: daily)
  --json                   emit JSON instead of markdown
  <project>                filter to a single project (matches against
                           events' `project` field)
  --help, -h               this help
HELP
            exit 0
            ;;
        *)
            # Anything else is treated as a project filter.
            PROJECT="${arg}"
            ;;
    esac
done

ARGS=(--period "${PERIOD}")
[[ -n "${PROJECT}" ]] && ARGS+=(--project "${PROJECT}")
[[ -n "${JSON}" ]] && ARGS+=(--json)

exec python3 "${AGG}" "${ARGS[@]}"
