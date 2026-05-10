#!/usr/bin/env bash
# {{PROJECT_NAME}} gate fast — constitutional checks before commit.
# Runs: ruff, mypy, pytest -m fast, taxonomy check.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ -d .venv ]]; then
    # shellcheck disable=SC1091
    source .venv/bin/activate
fi

echo "=== ruff ==="
ruff check .
echo "OK"

echo "=== mypy ==="
mypy backend/
echo "OK"

echo "=== pytest -m fast ==="
pytest -m fast
echo "OK"

echo "=== spec taxonomy (dev-platform enforcement) ==="
bash /home/rich/dev/scripts/check_spec_taxonomy.sh
echo "OK"

echo ""
echo "gate fast: PASS"
