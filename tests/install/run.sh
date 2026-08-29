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

# --- 8 + 9. vscode: unreachable server must skip, not fail the whole install ---
# Regression (issue #84): `code` is the VSCode REMOTE CLI and talks to the
# running server over $VSCODE_IPC_HOOK_CLI. A shell outliving a VSCode
# reconnect holds a dead socket path, every extension call fails with ENOENT,
# and install_vscode's all-failed branch turned that into a non-zero install —
# failing checks 1, 2 and 5 above and, through them, the whole commit gate.
# Driven by a stub `code` so the assertion never depends on the developer's
# editor actually being connected, which is the entire point of the fix.
STUB_BIN="${FAKE}/stubbin"
mkdir -p "${STUB_BIN}"
cat > "${STUB_BIN}/code" <<'STUB'
#!/usr/bin/env bash
# Stub VSCode CLI. STUB_CODE_REACHABLE=0 emulates a dead IPC socket: the
# reachability probe fails exactly as the real CLI does with ENOENT.
case "${1:-}" in
    --list-extensions)
        [[ "${STUB_CODE_REACHABLE:-1}" == "1" ]] || exit 1
        echo "stub.extension"
        ;;
    --install-extension)
        [[ "${STUB_CODE_REACHABLE:-1}" == "1" ]] || exit 1
        ;;
    *) exit 1 ;;
esac
STUB
chmod +x "${STUB_BIN}/code"

HOME="${FAKE}" bash "${REPO}/scripts/uninstall.sh" >/dev/null 2>&1
rm -f "${FAKE}/.claude/CLAUDE.md"

out="$(HOME="${FAKE}" PATH="${STUB_BIN}:${PATH}" STUB_CODE_REACHABLE=0 \
        bash "${REPO}/scripts/install.sh" 2>&1)"
rc=$?
if [[ ${rc} -eq 0 ]] && grep -q "cannot reach a VSCode server" <<<"${out}"; then
    record_pass "install: unreachable VSCode server skips instead of failing the install"
else
    record_fail "install: unreachable-server skip (rc=${rc}, out: $(tail -3 <<<"${out}"))"
fi

# The skip must be conditional — a reachable CLI still deploys extensions.
out="$(HOME="${FAKE}" PATH="${STUB_BIN}:${PATH}" STUB_CODE_REACHABLE=1 \
        bash "${REPO}/scripts/install.sh" 2>&1)"
rc=$?
if [[ ${rc} -eq 0 ]] && grep -q "extensions installed/verified" <<<"${out}"; then
    record_pass "install: reachable VSCode server still installs extensions"
else
    record_fail "install: reachable-server path (rc=${rc}, out: $(tail -3 <<<"${out}"))"
fi
