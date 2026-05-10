#!/usr/bin/env bash
# {{PROJECT_NAME}} gate fast — constitutional checks before commit.
# Runs: gofmt diff, go vet, go build, taxonomy check.
# Failure = exit non-zero; commit is blocked until fixed.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "=== gofmt ==="
fmt_diff="$(gofmt -l .)"
if [[ -n "${fmt_diff}" ]]; then
    echo "FAIL: gofmt found unformatted files:"
    echo "${fmt_diff}"
    echo "Run: gofmt -w ."
    exit 1
fi
echo "OK"

echo "=== go vet ==="
go vet ./...
echo "OK"

echo "=== go build ==="
go build ./...
echo "OK"

echo "=== spec taxonomy (dev-platform enforcement) ==="
bash /home/rich/dev/scripts/check_spec_taxonomy.sh
echo "OK"

echo ""
echo "gate fast: PASS"
