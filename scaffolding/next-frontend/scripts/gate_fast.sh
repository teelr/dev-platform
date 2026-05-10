#!/usr/bin/env bash
# {{PROJECT_NAME}} gate fast — constitutional checks before commit.
# Runs: lint, typecheck, taxonomy check.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ ! -d node_modules ]]; then
    echo "installing deps"
    npm install
fi

echo "=== lint ==="
npm run lint
echo "OK"

echo "=== typecheck ==="
npm run typecheck
echo "OK"

echo "=== spec taxonomy (dev-platform enforcement) ==="
bash /home/rich/dev/scripts/check_spec_taxonomy.sh
echo "OK"

echo ""
echo "gate fast: PASS"
