#!/usr/bin/env bash
# tests/install/run.sh — install / verify / uninstall round-trip on a
# throwaway $HOME. Extracts the previously-conversation-derived round-trip
# logic into the canonical suite. Cleans up via trap regardless of pass/fail.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

FAKE="$(mktemp -d /tmp/r3-install.XXX)"
trap "rm -rf '${FAKE}'" EXIT

# 1. install fresh
if HOME="${FAKE}" bash "${REPO}/scripts/install.sh" >/dev/null 2>&1; then
    record_pass "install: fresh deploy"
else
    record_fail "install: fresh deploy"
fi

# 2. verify after install (expect exit 0)
if HOME="${FAKE}" bash "${REPO}/scripts/verify.sh" >/dev/null 2>&1; then
    record_pass "install: verify-after-install (exit 0)"
else
    record_fail "install: verify-after-install (expected exit 0)"
fi

# 3. uninstall
if HOME="${FAKE}" bash "${REPO}/scripts/uninstall.sh" >/dev/null 2>&1; then
    record_pass "install: uninstall succeeds"
else
    record_fail "install: uninstall failed"
fi

# 4. verify after uninstall (expect exit 1 — drift)
HOME="${FAKE}" bash "${REPO}/scripts/verify.sh" >/dev/null 2>&1
rc=$?
if [[ ${rc} -eq 1 ]]; then
    record_pass "install: verify-after-uninstall (exit 1 expected)"
else
    record_fail "install: verify-after-uninstall (expected exit 1, got ${rc})"
fi

# 5. re-install (idempotency)
if HOME="${FAKE}" bash "${REPO}/scripts/install.sh" >/dev/null 2>&1 \
    && HOME="${FAKE}" bash "${REPO}/scripts/verify.sh" >/dev/null 2>&1; then
    record_pass "install: re-install idempotent"
else
    record_fail "install: re-install not idempotent"
fi

# 6. refuse-to-clobber test (real file at deployed path)
HOME="${FAKE}" bash "${REPO}/scripts/uninstall.sh" >/dev/null 2>&1
echo "real content" > "${FAKE}/.claude/CLAUDE.md"
HOME="${FAKE}" bash "${REPO}/scripts/install.sh" >/dev/null 2>&1
rc=$?
if [[ ${rc} -ne 0 ]]; then
    record_pass "install: refuse-to-clobber returns non-zero"
else
    record_fail "install: refuse-to-clobber did NOT block (exit 0)"
fi

# 7. real file preserved through the refuse-to-clobber
if [[ "$(cat "${FAKE}/.claude/CLAUDE.md" 2>/dev/null)" == "real content" ]]; then
    record_pass "install: real file preserved through refuse-to-clobber"
else
    record_fail "install: real file destroyed by refuse-to-clobber"
fi
