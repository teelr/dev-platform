#!/usr/bin/env bash
# tests/worktree-default/run.sh — install.sh / verify.sh must behave correctly
# when invoked from a git worktree, because dev-platform is now worktree-mode
# and gate_fast.sh runs verify.sh on every gate.
#
# The bug this guards: both scripts derived REPO from BASH_SOURCE, so a
# worktree-invoked verify reported every ~/.claude symlink as an "orphan"
# against a deployment that was actually correct — 21 false failures, and a red
# gate on every worktree run. Both now resolve REPO to the MAIN checkout via
# git-common-dir.
#
# Two things this suite is careful about:
#   1. A worktree checks out HEAD, NOT the working tree. The scripts under test
#      are therefore COPIED into the probe worktree after it is created —
#      otherwise the suite silently tests whatever HEAD happens to contain and
#      passes or fails for the wrong reason.
#   2. Every install targets a throwaway HOME. This suite must never touch the
#      real ~/.claude deployment.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

# --- 1. syntax ----------------------------------------------------------------
for s in install verify; do
    if bash -n "${REPO}/scripts/${s}.sh" 2>/dev/null; then
        record_pass "worktree-default: ${s}.sh bash syntax clean"
    else
        record_fail "worktree-default: ${s}.sh bash syntax error"
    fi
done

# --- probe worktree -----------------------------------------------------------
WT="$(mktemp -d /tmp/r3-wtd.XXX)/wt"
BR="wtd-probe-$$"
CLEANUP_WT=0
cleanup() {
    [[ "${CLEANUP_WT}" -eq 1 ]] && git -C "${REPO}" worktree remove --force "${WT}" >/dev/null 2>&1
    git -C "${REPO}" branch -D "${BR}" >/dev/null 2>&1
    git -C "${REPO}" worktree prune >/dev/null 2>&1
    rm -rf "$(dirname "${WT}")"
}
trap cleanup EXIT

if ! git -C "${REPO}" worktree add -q "${WT}" -b "${BR}" 2>/dev/null; then
    record_skip "worktree-default: worktree assertions (git worktree add failed)"
else
    CLEANUP_WT=1
    # Test the WORKING-TREE scripts, not HEAD's copies. See header note 1.
    cp "${REPO}/scripts/install.sh" "${REPO}/scripts/verify.sh" \
       "${REPO}/scripts/uninstall.sh" "${WT}/scripts/"

    # --- 2. a worktree-invoked verify AGREES with a main-invoked one ----------
    # The invariant, stated environment-independently: both resolve to the same
    # main checkout, so both must reach the same verdict. Do NOT assert rc == 0
    # here — on a CI runner there is no ~/.claude at all, so verify legitimately
    # exits 1 with "NOT deployed" for every tracked file (gate_fast.sh guards
    # its own live-verify with a -d "${HOME}/.claude" skip for exactly this).
    # Zero ORPHAN lines is the actual regression guard: orphans are what a
    # worktree-derived REPO produced, and they were 21 before this phase.
    vout="$(bash "${WT}/scripts/verify.sh" 2>&1)"; vrc=$?
    mout="$(bash "${REPO}/scripts/verify.sh" 2>&1)"; mrc=$?
    orphans="$(grep -c "orphan symlink" <<<"${vout}")"
    if [[ ${vrc} -eq ${mrc} && "${orphans}" -eq 0 ]]; then
        record_pass "worktree-default: verify.sh from a worktree agrees with main, no orphan symlinks"
    else
        record_fail "worktree-default: verify from worktree (worktree rc=${vrc}, main rc=${mrc}, orphans=${orphans})"
    fi

    # --- 3. the notice is actually conditional --------------------------------
    if grep -q "main checkout" <<<"${vout}" && ! grep -q "main checkout" <<<"${mout}"; then
        record_pass "worktree-default: verify's main-checkout notice fires only from a worktree"
    else
        record_fail "worktree-default: verify notice not conditional"
    fi

    # --- 4. install from the worktree targets the MAIN checkout ---------------
    FAKE="$(mktemp -d /tmp/r3-wtd-home.XXX)"
    iout="$(HOME="${FAKE}" bash "${WT}/scripts/install.sh" 2>&1)"; irc=$?
    target="$(readlink -f "${FAKE}/.claude/commands/code.md" 2>/dev/null)"
    if [[ ${irc} -eq 0 && "${target}" == "${REPO}/commands/code.md" ]]; then
        record_pass "worktree-default: install.sh from a worktree symlinks into the main checkout"
    else
        record_fail "worktree-default: install target (rc=${irc}, target=${target})"
    fi

    # --- 5. install's after-merge notice is conditional -----------------------
    FAKE2="$(mktemp -d /tmp/r3-wtd-home2.XXX)"
    iout_main="$(HOME="${FAKE2}" bash "${REPO}/scripts/install.sh" 2>&1)"
    if grep -q "after merge" <<<"${iout}" && ! grep -q "after merge" <<<"${iout_main}"; then
        record_pass "worktree-default: install's after-merge notice fires only from a worktree"
    else
        record_fail "worktree-default: install notice not conditional"
    fi

    # --- 6. install-then-verify agree from the worktree -----------------------
    if HOME="${FAKE}" bash "${WT}/scripts/verify.sh" >/dev/null 2>&1; then
        record_pass "worktree-default: install-then-verify round-trips from a worktree"
    else
        record_fail "worktree-default: worktree install/verify disagree"
    fi
    rm -rf "${FAKE}" "${FAKE2}"

    # --- 6b. uninstall from a worktree actually removes main's symlinks -------
    # This one failed SILENTLY before the sweep: uninstall.sh removes a symlink
    # only if its target resolves under REPO, so a worktree-derived REPO matched
    # none of main's links — 21 survived and it still printed "Uninstall
    # complete", which also broke tests/install/run.sh's verify-after-uninstall
    # assertion. Assert on the link count, never on the exit code.
    FAKE3="$(mktemp -d /tmp/r3-wtd-home3.XXX)"
    HOME="${FAKE3}" bash "${WT}/scripts/install.sh" >/dev/null 2>&1
    before="$(find "${FAKE3}/.claude" -type l 2>/dev/null | wc -l)"
    HOME="${FAKE3}" bash "${WT}/scripts/uninstall.sh" >/dev/null 2>&1
    after="$(find "${FAKE3}/.claude" -type l 2>/dev/null | wc -l)"
    if [[ "${before}" -gt 0 && "${after}" -eq 0 ]]; then
        record_pass "worktree-default: uninstall.sh from a worktree removes main's symlinks"
    else
        record_fail "worktree-default: worktree uninstall left ${after} of ${before} symlinks"
    fi
    rm -rf "${FAKE3}"

    # --- 7. link-deps no-ops on dev-platform's comment-only manifest ---------
    if [[ -f "${REPO}/.claude/worktree-deps" ]]; then
        lout="$(bash "${REPO}/shell/worktree/link-deps.sh" "${REPO}" "${WT}" 2>&1)"; lrc=$?
        if [[ ${lrc} -eq 0 ]]; then
            record_pass "worktree-default: link-deps exits 0 on the comment-only manifest"
        else
            record_fail "worktree-default: link-deps (rc=${lrc}, out: ${lout})"
        fi
    else
        record_fail "worktree-default: .claude/worktree-deps missing — dev-platform is not worktree-mode"
    fi
fi

# --- 8. the BASH_SOURCE fallback still works outside a git repo ---------------
# Nothing else exercises this branch; without it a non-git invocation would die
# on the git-common-dir probe instead of falling back.
OUTSIDE="$(mktemp -d /tmp/r3-wtd-nogit.XXX)"
mkdir -p "${OUTSIDE}/scripts"
cp "${REPO}/scripts/verify.sh" "${OUTSIDE}/scripts/"
fout="$(cd "${OUTSIDE}" && bash "${OUTSIDE}/scripts/verify.sh" 2>&1)"; frc=$?
if [[ ${frc} -ne 0 ]] && ! grep -qi "rev-parse\|not a git repository: command" <<<"${fout}"; then
    record_pass "worktree-default: falls back to BASH_SOURCE outside a git repo (no crash)"
else
    record_fail "worktree-default: non-git fallback (rc=${frc}, out: $(head -2 <<<"${fout}"))"
fi
rm -rf "${OUTSIDE}"
