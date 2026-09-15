#!/usr/bin/env bash
# tests/vscode-client/run.sh — fixture suite for v1.35 client-side VSCode
# coverage. Mocks cmd.exe/wslpath/cygpath since no real Windows machine
# exists in this build environment — see the spec's Design Philosophy.
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 (R3) auto-discovery
# contract.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
MOCK_BIN="${HERE}/fixtures/mock-bin"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

SYNC="${REPO}/scripts/sync-vscode-client.sh"
INSTALL="${REPO}/scripts/install.sh"
TRACKED_SETTINGS="${REPO}/extensions/vscode/client-settings.json"
TRACKED_KEYBINDINGS="${REPO}/extensions/vscode/client-keybindings.json"

# Checks 7/8 (capture) write to the real tracked path — sync-vscode-client.sh
# has no override for the capture DESTINATION, only --dir for the live
# source. Back up whatever's there now (normally nothing — see the spec's
# Design Philosophy: /code never populates these) and restore it on exit, so
# this suite never leaves the tracked path any different from how it found
# it, pass or fail.
RT="$(mktemp -d /tmp/vc-rt.XXXXXX)"
ORIG_SETTINGS_BACKUP=""
ORIG_KEYBINDINGS_BACKUP=""
[[ -f "${TRACKED_SETTINGS}" ]] && { ORIG_SETTINGS_BACKUP="${RT}/orig-settings.json"; cp "${TRACKED_SETTINGS}" "${ORIG_SETTINGS_BACKUP}"; }
[[ -f "${TRACKED_KEYBINDINGS}" ]] && { ORIG_KEYBINDINGS_BACKUP="${RT}/orig-keybindings.json"; cp "${TRACKED_KEYBINDINGS}" "${ORIG_KEYBINDINGS_BACKUP}"; }
restore_tracked_files() {
    if [[ -n "${ORIG_SETTINGS_BACKUP}" ]]; then
        cp "${ORIG_SETTINGS_BACKUP}" "${TRACKED_SETTINGS}"
    else
        rm -f "${TRACKED_SETTINGS}"
    fi
    if [[ -n "${ORIG_KEYBINDINGS_BACKUP}" ]]; then
        cp "${ORIG_KEYBINDINGS_BACKUP}" "${TRACKED_KEYBINDINGS}"
    else
        rm -f "${TRACKED_KEYBINDINGS}"
    fi
}
# shellcheck disable=SC2064
trap "restore_tracked_files; rm -rf '${RT}'" EXIT

# Check 1: syntax
if bash -n "${SYNC}"; then
    record_pass "vscode-client: sync-vscode-client.sh bash syntax clean"
else
    record_fail "vscode-client: sync-vscode-client.sh bash syntax error"
fi

# Check 2: real environment on this (Linux) gate machine — resolve fails cleanly
out="$(env -u WSL_DISTRO_NAME -u APPDATA bash "${SYNC}" resolve 2>&1)"; rc=$?
if [[ ${rc} -eq 1 ]] && echo "${out}" | grep -q "could not detect a Windows VSCode client environment"; then
    record_pass "vscode-client: resolve fails cleanly on a non-Windows machine"
else
    record_fail "vscode-client: resolve did not fail cleanly — rc=${rc}, out=${out:0:200}"
fi

# Check 3: --dir short-circuits detection
out="$(bash "${SYNC}" resolve --dir /tmp/whatever 2>&1)"
if [[ "${out}" == "/tmp/whatever" ]]; then
    record_pass "vscode-client: --dir override short-circuits detection"
else
    record_fail "vscode-client: --dir override did not short-circuit — got '${out}'"
fi

# Check 4: WSL branch resolves via mocked cmd.exe + wslpath
WSL_ROOT="$(mktemp -d /tmp/vc-wsl.XXXXXX)"
out="$(WSL_DISTRO_NAME=test-distro MOCK_APPDATA_WIN='C:\Users\test\AppData\Roaming' \
        MOCK_WSL_ROOT="${WSL_ROOT}" PATH="${MOCK_BIN}:${PATH}" \
        bash "${SYNC}" resolve 2>&1)"
if [[ "${out}" == "${WSL_ROOT}/Users/test/AppData/Roaming/Code/User" ]]; then
    record_pass "vscode-client: WSL branch resolves via mocked cmd.exe/wslpath"
else
    record_fail "vscode-client: WSL branch resolution wrong — got '${out}'"
fi
rm -rf "${WSL_ROOT}"

# Check 5: Git-Bash/MSYS branch resolves via mocked cygpath
CYG_ROOT="$(mktemp -d /tmp/vc-cyg.XXXXXX)"
out="$(env -u WSL_DISTRO_NAME APPDATA='C:\Users\test\AppData\Roaming' \
        MOCK_CYGPATH_ROOT="${CYG_ROOT}" PATH="${MOCK_BIN}:${PATH}" \
        bash "${SYNC}" resolve 2>&1)"
if [[ "${out}" == "${CYG_ROOT}/Users/test/AppData/Roaming/Code/User" ]]; then
    record_pass "vscode-client: Git-Bash/MSYS branch resolves via mocked cygpath"
else
    record_fail "vscode-client: Git-Bash/MSYS branch resolution wrong — got '${out}'"
fi
rm -rf "${CYG_ROOT}"

# Check 6: Git-Bash/MSYS branch falls back to naive substitution when cygpath is absent
SANDBOX_BIN="$(mktemp -d /tmp/vc-sandbox.XXXXXX)"
for cmd in bash dirname pwd grep cat mkdir test rm sed tr; do
    if path="$(command -v "${cmd}" 2>/dev/null)"; then
        ln -s "${path}" "${SANDBOX_BIN}/${cmd}" 2>/dev/null || true
    fi
done
out="$(env -u WSL_DISTRO_NAME APPDATA='C:\Users\test\AppData\Roaming' \
        PATH="${SANDBOX_BIN}" bash "${SYNC}" resolve 2>&1)"
if [[ "${out}" == "C:/Users/test/AppData/Roaming/Code/User" ]]; then
    record_pass "vscode-client: Git-Bash/MSYS fallback (no cygpath) does naive substitution"
else
    record_fail "vscode-client: fallback wrong — got '${out}'"
fi
rm -rf "${SANDBOX_BIN}"

# Check 16: cmd.exe failing outright (exit 1, no output) must fail cleanly,
# not abort the script under `set -e`/pipefail (regression check — this
# used to crash resolve_vscode_user_dir's caller silently before the
# `|| true` guards were added).
out="$(WSL_DISTRO_NAME=test-distro MOCK_CMD_EXE_FAIL=1 MOCK_WSL_ROOT=/tmp/unused \
        PATH="${MOCK_BIN}:${PATH}" bash "${SYNC}" resolve 2>&1)"; rc=$?
if [[ ${rc} -eq 1 ]] && echo "${out}" | grep -q "could not detect a Windows VSCode client environment"; then
    record_pass "vscode-client: a failing cmd.exe fails cleanly, does not crash"
else
    record_fail "vscode-client: failing cmd.exe did not degrade cleanly — rc=${rc}, out=${out:0:200}"
fi

# Check 17: cmd.exe succeeds but wslpath fails must fail cleanly, and must
# NOT report success with a bogus "/Code/User" (empty wslpath output plus
# the literal suffix looks like a valid absolute path but isn't one).
out="$(WSL_DISTRO_NAME=test-distro MOCK_APPDATA_WIN='C:\Users\test\AppData\Roaming' \
        MOCK_WSLPATH_FAIL=1 PATH="${MOCK_BIN}:${PATH}" bash "${SYNC}" resolve 2>&1)"; rc=$?
if [[ ${rc} -eq 1 ]] && echo "${out}" | grep -q "could not detect a Windows VSCode client environment"; then
    record_pass "vscode-client: a failing wslpath fails cleanly, does not report a bogus path"
else
    record_fail "vscode-client: failing wslpath did not degrade cleanly — rc=${rc}, out=${out:0:200}"
fi

# Check 18: install.sh's own duplicated detection must also survive a
# failing cmd.exe without aborting the whole install run (this was the
# worse regression — install.sh's copy isn't inside an if/|| the way
# sync-vscode-client.sh's call sites are, so `set -e` used to kill the
# entire script here, silently skipping every category queued afterward).
out="$(WSL_DISTRO_NAME=test-distro MOCK_CMD_EXE_FAIL=1 MOCK_WSL_ROOT=/tmp/unused \
        PATH="${MOCK_BIN}:${PATH}" bash "${INSTALL}" vscode-client 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "not a Windows VSCode client environment"; then
    record_pass "vscode-client: install.sh survives a failing cmd.exe with a graceful skip"
else
    record_fail "vscode-client: install.sh did not survive a failing cmd.exe — rc=${rc}, out=${out:0:200}"
fi

# --- capture/deploy/diff round trip via --dir (content logic, detection already covered above) ---

# Check 7: capture copies both files when both exist
LIVE1="${RT}/live1"; mkdir -p "${LIVE1}"
echo '{"a": 1}' > "${LIVE1}/settings.json"
echo '{"b": 2}' > "${LIVE1}/keybindings.json"
out="$(bash "${SYNC}" capture --dir "${LIVE1}" 2>&1)"
if echo "${out}" | grep -q "captured 2/2" \
        && diff -q "${LIVE1}/settings.json" "${TRACKED_SETTINGS}" >/dev/null 2>&1 \
        && diff -q "${LIVE1}/keybindings.json" "${TRACKED_KEYBINDINGS}" >/dev/null 2>&1; then
    record_pass "vscode-client: capture copies both files (2/2)"
else
    record_fail "vscode-client: capture did not copy both files — out=${out:0:200}"
fi

# Check 8: capture skips a missing file with a WARN, still captures the other
LIVE2="${RT}/live2"; mkdir -p "${LIVE2}"
echo '{"c": 3}' > "${LIVE2}/settings.json"
# no keybindings.json in LIVE2
out="$(bash "${SYNC}" capture --dir "${LIVE2}" 2>&1)"
if echo "${out}" | grep -q "captured 1/2" && echo "${out}" | grep -q "keybindings.json not found"; then
    record_pass "vscode-client: capture skips a missing file with a WARN (1/2)"
else
    record_fail "vscode-client: capture did not degrade gracefully — out=${out:0:200}"
fi

# Check 9: deploy copies tracked files onto a fresh --dir, creating it if absent
DEPLOY_DIR1="${RT}/deploy1/nested/User"   # deliberately absent, multiple levels
out="$(bash "${SYNC}" deploy --dir "${DEPLOY_DIR1}" 2>&1)"
if [[ -f "${DEPLOY_DIR1}/settings.json" ]] && echo "${out}" | grep -q "deployed"; then
    record_pass "vscode-client: deploy creates the target dir and copies tracked files"
else
    record_fail "vscode-client: deploy did not create/populate target — out=${out:0:200}"
fi

# Check 10: diff reports no drift immediately after a deploy
out="$(bash "${SYNC}" diff --dir "${DEPLOY_DIR1}" 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "no drift"; then
    record_pass "vscode-client: diff reports no drift right after deploy"
else
    record_fail "vscode-client: diff false drift — rc=${rc}, out=${out:0:200}"
fi

# Check 11: diff reports drift when live disagrees with tracked
echo '{"changed": true}' > "${DEPLOY_DIR1}/settings.json"
out="$(bash "${SYNC}" diff --dir "${DEPLOY_DIR1}" 2>&1)"; rc=$?
if [[ ${rc} -eq 1 ]] && echo "${out}" | grep -q "changed"; then
    record_pass "vscode-client: diff detects drift (exit 1) and shows the change"
else
    record_fail "vscode-client: diff missed drift — rc=${rc}, out=${out:0:200}"
fi

# Check 12: deploy refuses cleanly when no tracked file exists at all.
# Deliberately removes the real tracked files Check 7/8 just created — the
# suite-wide trap above restores whatever was really there when the whole
# script exits, so nothing after this point (Checks 13-15) needs them back.
rm -f "${TRACKED_SETTINGS}" "${TRACKED_KEYBINDINGS}"
out="$(bash "${SYNC}" deploy --dir "${RT}/deploy-empty" 2>&1)"; rc=$?
if [[ ${rc} -eq 1 ]] && echo "${out}" | grep -q "no tracked client config"; then
    record_pass "vscode-client: deploy refuses cleanly with no tracked files"
else
    record_fail "vscode-client: deploy did not refuse cleanly — rc=${rc}, out=${out:0:200}"
fi

# --- install.sh vscode-client integration ---

# Check 13: real environment on this gate machine — graceful skip, exit 0
out="$(env -u WSL_DISTRO_NAME -u APPDATA bash "${INSTALL}" vscode-client 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "not a Windows VSCode client environment"; then
    record_pass "vscode-client: install.sh skips gracefully on a non-Windows machine"
else
    record_fail "vscode-client: install.sh did not skip gracefully — rc=${rc}, out=${out:0:200}"
fi

# Check 14: mocked WSL env, but no tracked files (still absent from Check 12) —
# graceful skip naming the capture step.
WSL_ROOT2="$(mktemp -d /tmp/vc-wsl2.XXXXXX)"
out="$(WSL_DISTRO_NAME=test-distro MOCK_APPDATA_WIN='C:\Users\test\AppData\Roaming' \
        MOCK_WSL_ROOT="${WSL_ROOT2}" PATH="${MOCK_BIN}:${PATH}" \
        bash "${INSTALL}" vscode-client 2>&1)"; rc=$?
rm -rf "${WSL_ROOT2}"
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "no tracked client config"; then
    record_pass "vscode-client: install.sh skips gracefully when Windows detected but nothing captured yet"
else
    record_fail "vscode-client: install.sh did not skip correctly — rc=${rc}, out=${out:0:200}"
fi

# Check 15: mocked WSL env + tracked files present — install.sh deploys end to end.
#
# install.sh always resolves REPO to the MAIN checkout (by design — see its
# own header), never to this worktree, so the real tracked files (which
# don't exist yet — see Design Philosophy) can't be used to exercise the
# copy step. Instead, copy install.sh into a throwaway directory OUTSIDE any
# git repo (so its REPO-resolution falls back to "wherever this script
# lives" — the same fallback path scripts/install.sh's own header documents)
# and give that scratch copy its own extensions/vscode/ tracked files. Same
# technique tests/worktree-default/run.sh uses to control what REPO resolves
# to, applied without needing a real git worktree.
SCRATCH="$(mktemp -d /tmp/vc-scratch.XXXXXX)"
mkdir -p "${SCRATCH}/scripts" "${SCRATCH}/extensions/vscode"
cp "${INSTALL}" "${SCRATCH}/scripts/install.sh"
echo '{"scratch": "settings"}' > "${SCRATCH}/extensions/vscode/client-settings.json"
echo '{"scratch": "keybindings"}' > "${SCRATCH}/extensions/vscode/client-keybindings.json"

WSL_ROOT3="$(mktemp -d /tmp/vc-wsl3.XXXXXX)"
out="$(WSL_DISTRO_NAME=test-distro MOCK_APPDATA_WIN='C:\Users\test\AppData\Roaming' \
        MOCK_WSL_ROOT="${WSL_ROOT3}" PATH="${MOCK_BIN}:${PATH}" \
        bash "${SCRATCH}/scripts/install.sh" vscode-client 2>&1)"; rc=$?
target="${WSL_ROOT3}/Users/test/AppData/Roaming/Code/User"
if [[ ${rc} -eq 0 ]] \
        && diff -q "${SCRATCH}/extensions/vscode/client-settings.json" "${target}/settings.json" >/dev/null 2>&1 \
        && diff -q "${SCRATCH}/extensions/vscode/client-keybindings.json" "${target}/keybindings.json" >/dev/null 2>&1; then
    record_pass "vscode-client: install.sh deploys end to end via its own duplicated detection"
else
    record_fail "vscode-client: install.sh did not deploy — rc=${rc}, out=${out:0:200}, target=${target}"
fi
rm -rf "${WSL_ROOT3}" "${SCRATCH}"
