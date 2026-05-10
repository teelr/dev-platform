#!/usr/bin/env bash
# Start {{PROJECT_NAME}} dev server.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ -f .env ]]; then
    set -o allexport
    # shellcheck disable=SC1091
    source .env
    set +o allexport
fi

PORT="${PORT:-{{PORT}}}"
echo "Starting {{PROJECT_NAME}} on :${PORT}"
exec go run main.go
