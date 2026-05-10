#!/usr/bin/env bash
# Start {{PROJECT_NAME}} agent dev run.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ ! -d .venv ]]; then
    echo "creating .venv"
    python3.11 -m venv .venv
fi

# shellcheck disable=SC1091
source .venv/bin/activate

if ! python -c "import backend" 2>/dev/null; then
    echo "installing dev deps"
    pip install -e ".[dev]"
fi

if [[ -f .env ]]; then
    set -o allexport
    # shellcheck disable=SC1091
    source .env
    set +o allexport
fi

exec python main.py
