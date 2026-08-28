#!/usr/bin/env bash
# tests/concurrent-sessions/run.sh — regression suite for
# scripts/check-concurrent-sessions.sh.
#
# Sourced contract: uses record_pass/record_fail/record_skip from
# tests/helpers/assert.sh; never exit-s (the orchestrator owns the exit code).
#
# Entirely offline. No real `claude` process is ever spawned or inspected: every
# case builds a fixture /proc tree and points the script at it with
# CCS_PROC_ROOT. The suite runs on every gate, so it must not depend on what the
# user happens to have open.
#
# The repo fixtures ARE real — `git init` plus `git worktree add` — so
# `git worktree list --porcelain` and `git rev-parse --git-common-dir` return
# genuine output rather than a stub. Both are load-bearing to the script.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
CCS="${REPO}/scripts/check-concurrent-sessions.sh"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

TMP="$(mktemp -d /tmp/r3-ccs.XXX)"
trap 'rm -rf "${TMP}"' EXIT

# --- helpers -----------------------------------------------------------------

# mkproc <procroot> <pid> <comm> <cwd> <ppid>
mkproc() {
    mkdir -p "$1/$2"
    echo "$3" > "$1/$2/comm"
    printf 'PPid:\t%s\n' "$5" > "$1/$2/status"
    ln -sfn "$4" "$1/$2/cwd"
}

# mkrepo <dir> — a real git repo with one commit.
mkrepo() {
    mkdir -p "$1"
    git -C "$1" init -q 2>/dev/null
    git -C "$1" config user.email t@t && git -C "$1" config user.name t
    : > "$1/README.md"
    git -C "$1" add -A >/dev/null 2>&1
    git -C "$1" commit -qm init >/dev/null 2>&1
}

# run_ccs <procroot> <cwd> [home] — invoke the script under a fixture.
run_ccs() {
    local proc="$1" cwd="$2" home="${3:-${HOME}}"
    ( cd "${cwd}" && CCS_PROC_ROOT="${proc}" HOME="${home}" bash "${CCS}" 2>&1 )
}

# run_ccs_as_self <procroot> <cwd> <home> <claude-pid> — same, but the shell
# that runs the script first registers ITSELF in the fixture proc tree as a
# child of <claude-pid>, then `exec`s the script. exec preserves the PID, so the
# script's own $$ IS the registered entry and its PPid walk terminates at the
# fixture claude. This is the only way to exercise self-identification against a
# mocked /proc — the runtime PID cannot be known in advance.
run_ccs_as_self() {
    local proc="$1" cwd="$2" home="$3" cpid="$4"
    ( cd "${cwd}" && CCS_PROC_ROOT="${proc}" HOME="${home}" bash -c '
        mkdir -p "$1/$$"
        echo bash > "$1/$$/comm"
        printf "PPid:\t%s\n" "$2" > "$1/$$/status"
        ln -sfn "$3" "$1/$$/cwd"
        exec bash "$4"
      ' _ "${proc}" "${cpid}" "${cwd}" "${CCS}" 2>&1 )
}

# --- 1. syntax ----------------------------------------------------------------
if bash -n "${CCS}" 2>/dev/null; then
    record_pass "ccs: bash syntax clean"
else
    record_fail "ccs: bash syntax error"
fi

# --- fixture repo: main checkout + one worktree + an unrelated nested repo -----
MAIN="${TMP}/proj"
mkrepo "${MAIN}"
git -C "${MAIN}" worktree add -q "${MAIN}/.claude/worktrees/feat-x" -b feat-x 2>/dev/null
WT="${MAIN}/.claude/worktrees/feat-x"
# A separate repo nested INSIDE the main checkout — the shape that broke a
# path-prefix membership test (every project lives under dev-platform's own
# repo root on this box).
NESTED="${MAIN}/projects/other"
mkrepo "${NESTED}"

# A HOME with the lock helper deployed, and one without.
HOME_OK="${TMP}/home-ok"; mkdir -p "${HOME_OK}/.claude/worktree"
: > "${HOME_OK}/.claude/worktree/gate-lock.sh"
HOME_BARE="${TMP}/home-bare"; mkdir -p "${HOME_BARE}"

# --- 2. alone: one session, in the main checkout ------------------------------
P1="${TMP}/proc1"
mkproc "${P1}" 90001 claude "${MAIN}" 1
out="$(run_ccs_as_self "${P1}" "${MAIN}" "${HOME_OK}" 90001)"; rc=$?
if [[ ${rc} -eq 0 ]] && grep -q "^sessions: 1 (this one only)" <<<"${out}"; then
    record_pass "ccs: a lone session reports 1 (this one only)"
else
    record_fail "ccs: lone session (rc=${rc}, out: ${out})"
fi

# --- 3. exit code is 0 even with findings -------------------------------------
P2="${TMP}/proc2"
mkproc "${P2}" 90001 claude "${MAIN}" 1        # caller's own session
mkproc "${P2}" 90002 claude "${WT}"  1         # another, in the worktree
mkproc "${P2}" 90003 claude "${NESTED}" 1      # different repo — must be excluded
mkproc "${P2}" 90004 bash   "${MAIN}" 1        # not claude — must be excluded
mkproc "${P2}" 90005 claude "${TMP}" 1         # outside the repo — must be excluded
out="$(run_ccs "${P2}" "${MAIN}" "${HOME_OK}")"; rc=$?
if [[ ${rc} -eq 0 ]]; then
    record_pass "ccs: exits 0 with sessions found (report, not a gate check)"
else
    record_fail "ccs: exit code with findings (rc=${rc})"
fi

# --- 4. both in-repo sessions listed ------------------------------------------
if grep -qE "^sessions: 2 " <<<"${out}"; then
    record_pass "ccs: counts exactly the two sessions inside the repo"
else
    record_fail "ccs: session count (out: ${out})"
fi

# --- 5. LONGEST-ROOT regression: the worktree session must not read as main ---
# The main checkout is a string prefix of the worktree path, so first-match-wins
# labels every worktree session "main" — erasing the whole distinction.
if grep -qE "pid 90002 +worktree +\.claude/worktrees/feat-x" <<<"${out}"; then
    record_pass "ccs: worktree session labeled worktree, not main (longest-root)"
else
    record_fail "ccs: worktree labeling (out: ${out})"
fi
if grep -qE "pid 90001 +main +\." <<<"${out}"; then
    record_pass "ccs: main-checkout session labeled main"
else
    record_fail "ccs: main labeling (out: ${out})"
fi

# --- 6. NESTED-REPO regression: a different repo underneath is excluded --------
if ! grep -q "pid 90003" <<<"${out}"; then
    record_pass "ccs: a nested but separate repo's session is excluded"
else
    record_fail "ccs: nested repo leaked into the report (out: ${out})"
fi

# --- 7. non-claude process inside the repo is excluded ------------------------
if ! grep -q "pid 90004" <<<"${out}"; then
    record_pass "ccs: non-claude process inside the repo is excluded"
else
    record_fail "ccs: non-claude process leaked (out: ${out})"
fi

# --- 8. a claude process outside the repo entirely is excluded ----------------
if ! grep -q "pid 90005" <<<"${out}"; then
    record_pass "ccs: claude session outside the repo is excluded"
else
    record_fail "ccs: outside-repo session leaked (out: ${out})"
fi

# --- 9. exactly one line is marked (this session) -----------------------------
# Self is found by walking PPid from the test's own shell, so build a chain that
# terminates at a fixture claude pid.
P3="${TMP}/proc3"
mkproc "${P3}" 90001 claude "${MAIN}" 1
mkproc "${P3}" 90002 claude "${WT}"  1
out3="$(run_ccs_as_self "${P3}" "${MAIN}" "${HOME_OK}" 90001)"
n_self="$(grep -c "(this session)" <<<"${out3}")"
if [[ "${n_self}" -eq 1 ]] && grep -qE "pid 90001 .*\(this session\)" <<<"${out3}"; then
    record_pass "ccs: exactly one session line is marked (this session)"
else
    record_fail "ccs: self-marking count=${n_self} (out: ${out3})"
fi

# --- 9b. with self present, the header counts it separately -------------------
if grep -q "^sessions: 2 (this one + 1 other)" <<<"${out3}"; then
    record_pass "ccs: header separates this session from the others"
else
    record_fail "ccs: self-aware header (out: ${out3})"
fi

# --- 10. isolation mode reflects the marker -----------------------------------
if grep -q "^isolation: worktree mode OFF" <<<"${out}"; then
    record_pass "ccs: reports worktree mode OFF without the marker"
else
    record_fail "ccs: isolation OFF (out: ${out})"
fi
mkdir -p "${MAIN}/.claude" && : > "${MAIN}/.claude/worktree-deps"
out_on="$(run_ccs "${P2}" "${MAIN}" "${HOME_OK}")"
if grep -q "^isolation: worktree mode ON" <<<"${out_on}"; then
    record_pass "ccs: reports worktree mode ON with .claude/worktree-deps"
else
    record_fail "ccs: isolation ON (out: ${out_on})"
fi

# --- 11. gate: no script at all => unknown, NOT "no lock" ---------------------
if grep -q "^gate: unknown" <<<"${out_on}"; then
    record_pass "ccs: no gate script reports unknown, not 'no lock'"
else
    record_fail "ccs: missing gate script (out: ${out_on})"
fi

# --- 12. LOCK-SHAPE regression: kermit-v3 sources gate-lock.sh and calls
#     _gate_lockfile + flock directly, with no with_gate_lock call anywhere.
#     Grepping only for with_gate_lock reports it unlocked — the exact false
#     negative that produced the wrong /dev advice this script exists to fix.
mkdir -p "${MAIN}/scripts"
cat > "${MAIN}/scripts/gate_fast.sh" <<'GATE'
#!/usr/bin/env bash
if [ -f ~/.claude/worktree/gate-lock.sh ]; then
    source ~/.claude/worktree/gate-lock.sh
    exec 9>"$(_gate_lockfile)"
    flock 9
fi
GATE
out_lock="$(run_ccs "${P2}" "${MAIN}" "${HOME_OK}")"
if grep -q "^gate: lock wired (scripts/gate_fast.sh) + helper deployed" <<<"${out_lock}"; then
    record_pass "ccs: detects the _gate_lockfile-only lock shape (no with_gate_lock)"
else
    record_fail "ccs: kermit-v3 lock shape (out: ${out_lock})"
fi

# --- 13. lock wired but helper not deployed => its own distinct line ----------
out_nohelper="$(run_ccs "${P2}" "${MAIN}" "${HOME_BARE}")"
if grep -q "^gate: lock wired (scripts/gate_fast.sh) but helper missing" <<<"${out_nohelper}"; then
    record_pass "ccs: wired-but-helper-missing is distinct from not-wired"
else
    record_fail "ccs: helper-missing line (out: ${out_nohelper})"
fi

# --- 14. gate script with no lock reference ----------------------------------
printf '#!/usr/bin/env bash\necho hi\n' > "${MAIN}/scripts/gate_fast.sh"
out_nolock="$(run_ccs "${P2}" "${MAIN}" "${HOME_OK}")"
if grep -q "^gate: NO lock in scripts/gate_fast.sh" <<<"${out_nolock}"; then
    record_pass "ccs: an unlocked gate script is reported as unlocked"
else
    record_fail "ccs: no-lock line (out: ${out_nolock})"
fi

# --- 15. /proc unavailable => unknown, and NO session count claimed -----------
out_noproc="$(run_ccs "${TMP}/no-such-proc" "${MAIN}" "${HOME_OK}")"; rc=$?
if [[ ${rc} -eq 0 ]] \
    && grep -q "^sessions: unknown" <<<"${out_noproc}" \
    && ! grep -qE "^sessions: [0-9]" <<<"${out_noproc}"; then
    record_pass "ccs: missing /proc reports unknown, never a session count"
else
    record_fail "ccs: /proc-unavailable path (rc=${rc}, out: ${out_noproc})"
fi

# --- 16. usage error exits 2; --help exits 0 ---------------------------------
out_bad="$(bash "${CCS}" --bogus 2>&1)"; rc_bad=$?
out_help="$(bash "${CCS}" --help 2>&1)"; rc_help=$?
if [[ ${rc_bad} -eq 2 ]] && grep -q "unknown argument" <<<"${out_bad}" \
    && [[ ${rc_help} -eq 0 ]]; then
    record_pass "ccs: --help exits 0, unknown argument exits 2"
else
    record_fail "ccs: arg handling (bad rc=${rc_bad}, help rc=${rc_help})"
fi

# --- 17. not a git repository ------------------------------------------------
NOGIT="${TMP}/nogit"; mkdir -p "${NOGIT}"
out_nogit="$(run_ccs "${P2}" "${NOGIT}" "${HOME_OK}")"; rc=$?
if [[ ${rc} -eq 0 ]] && grep -q "not a git repository" <<<"${out_nogit}"; then
    record_pass "ccs: outside a git repo says so and still exits 0"
else
    record_fail "ccs: non-repo path (rc=${rc}, out: ${out_nogit})"
fi
