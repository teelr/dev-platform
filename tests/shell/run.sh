#!/usr/bin/env bash
# tests/shell/run.sh — regression suite for shell/profile.d/claude-tmux.sh (cc).
#
# Sourced contract: uses record_pass/record_fail/record_skip from
# tests/helpers/assert.sh; never exit-s (the orchestrator owns the exit code).
#
# tmux isolation: every session test runs against its own tmux server via
# TMUX_TMPDIR pointed at a temp dir, with TMUX unset. The trap kills that
# server. This suite must never touch the user's real sessions — one of them
# is usually the Claude Code session running it.
#
# Bash syntax for shell/profile.d/*.sh is covered by gate_fast.sh's lift check
# (v1.18 added "${REPO}/shell" to its find roots), so it is not repeated here.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
CC_SH="${REPO}/shell/profile.d/claude-tmux.sh"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

# Must come AFTER the source above — deploy_source_repo lives in assert.sh.
# The file under test stays at ${REPO} (this checkout's copy); the DEPLOYED
# symlink target is main's path, since v1.25 install.sh always deploys from the
# main checkout whichever worktree invokes it.
CC_SH_DEPLOYED="$(deploy_source_repo "${REPO}")/shell/profile.d/claude-tmux.sh"

TMP="$(mktemp -d /tmp/r3-shell.XXX)"
cleanup() {
    if [[ -d "${TMP}/tmux" ]]; then
        TMUX_TMPDIR="${TMP}/tmux" tmux kill-server >/dev/null 2>&1 || true
    fi
    rm -rf "${TMP}"
}
trap cleanup EXIT

# --- helpers -----------------------------------------------------------------

# run_cc <<args>> — source the function in a clean subshell under `set -u` and
# invoke it. Echoes combined output; returns cc's exit status.
run_cc() {
    bash -c '
        set -uo pipefail
        source "$1"; shift
        cc "$@"
    ' _ "${CC_SH}" "$@" 2>&1
}

# --- 1. sources cleanly under set -u and defines cc ---------------------------
out="$(bash -c 'set -uo pipefail; source "$1"; type -t cc' _ "${CC_SH}" 2>&1)"
if [[ "${out}" == "function" ]]; then
    record_pass "shell: sources under set -u and defines cc"
else
    record_fail "shell: sourcing under set -u (got: ${out})"
fi

# --- 1b. a pre-existing `cc` alias must not shadow the function ---------------
# Regression: alias expansion happens at PARSE time, so with `alias cc=...` live
# the `cc() {` line is a syntax error and the alias silently wins. This only
# reproduces in an INTERACTIVE shell — every `bash -c` test above passes either
# way, which is exactly how the bug shipped. `bash -i <script>` is the cheapest
# way to get interactive alias expansion without a tty.
alias_probe="${TMP}/alias-probe.sh"
cat > "${alias_probe}" <<PROBE
alias cc='echo ALIAS-WON'
source ${CC_SH}
type -t cc
PROBE
out="$(bash -i "${alias_probe}" 2>&1 | tail -1)"
if [[ "${out}" == "function" ]]; then
    record_pass "shell: pre-existing cc alias does not shadow the function"
else
    record_fail "shell: cc alias shadowing (type -t cc = '${out}', expected 'function')"
fi

# --- 2. --help ----------------------------------------------------------------
out="$(run_cc --help)"; rc=$?
if [[ ${rc} -eq 0 ]] && grep -q "CC_PROJECT_ROOT" <<<"${out}"; then
    record_pass "shell: --help exits 0 and documents CC_PROJECT_ROOT"
else
    record_fail "shell: --help (rc=${rc}, out: ${out})"
fi

# --- 3. --kill with no name (regression: bare \$2 aborts under set -u) ---------
out="$(run_cc --kill)"; rc=$?
if [[ ${rc} -eq 1 ]] && grep -q -- "--kill needs a session name" <<<"${out}"; then
    record_pass "shell: --kill with no name errors cleanly under set -u"
else
    record_fail "shell: --kill with no name (rc=${rc}, out: ${out})"
fi

# --- 4. -n with no name (same regression) -------------------------------------
out="$(run_cc -n)"; rc=$?
if [[ ${rc} -eq 1 ]] && grep -q -- "-n needs a name" <<<"${out}"; then
    record_pass "shell: -n with no name errors cleanly under set -u"
else
    record_fail "shell: -n with no name (rc=${rc}, out: ${out})"
fi

# --- 4b. --new and -n are mutually exclusive ---------------------------------
# --new derives a name, -n supplies one. Letting either silently win would put
# the user in a session they did not ask for.
out="$(run_cc --new -n foo)"; rc=$?
if [[ ${rc} -eq 1 ]] && grep -q -- "--new and -n are mutually exclusive" <<<"${out}"; then
    record_pass "shell: --new with -n errors instead of picking one"
else
    record_fail "shell: --new/-n conflict (rc=${rc}, out: ${out})"
fi

# --- 5. unknown project name --------------------------------------------------
out="$(CC_PROJECT_ROOT="${TMP}/projects" run_cc no-such-project-here)"; rc=$?
if [[ ${rc} -eq 1 ]] \
    && grep -q "no such project or directory: no-such-project-here" <<<"${out}" \
    && grep -q "looked in ${TMP}/projects" <<<"${out}"; then
    record_pass "shell: unknown project exits 1 and names the searched root"
else
    record_fail "shell: unknown project (rc=${rc}, out: ${out})"
fi

# --- 6. tmux missing from PATH ------------------------------------------------
# Not `PATH=... run_cc`: that hides `bash` from the helper itself. Empty PATH
# inside the subshell, after it has already started, so only cc sees it.
mkdir -p "${TMP}/emptybin"
out="$(bash -c '
    set -uo pipefail
    source "$1"; shift
    PATH="$1"; shift
    cc "$@"
' _ "${CC_SH}" "${TMP}/emptybin" 2>&1)"; rc=$?
if [[ ${rc} -eq 1 ]] && grep -q "tmux is not installed" <<<"${out}"; then
    record_pass "shell: reports tmux missing and exits 1"
else
    record_fail "shell: tmux-missing path (rc=${rc}, out: ${out})"
fi

# --- 5b. CC_PROJECT_ROOT unset after sourcing, under set -u -------------------
# Same class as the $2 / $TMUX guards: the function re-defaults internally so
# an unset global cannot abort the caller's shell.
out="$(bash -c '
    set -uo pipefail
    source "$1"
    unset CC_PROJECT_ROOT
    cc no-such-project-here
' _ "${CC_SH}" 2>&1)"; rc=$?
if [[ ${rc} -eq 1 ]] && grep -q "looked in ${HOME}/dev/projects" <<<"${out}"; then
    record_pass "shell: unset CC_PROJECT_ROOT falls back instead of aborting"
else
    record_fail "shell: unset CC_PROJECT_ROOT (rc=${rc}, out: ${out})"
fi

# --- 6b. directory exists but is not searchable: error must name the path -----
# Regression: assigning the resolved path straight into $dir blanked it out
# before the error branch could print it ("cc: cannot enter ").
if [[ -d /root && ! -x /root ]]; then
    out="$(run_cc /root)"; rc=$?
    if [[ ${rc} -eq 1 ]] && grep -q "cannot enter /root" <<<"${out}"; then
        record_pass "shell: unenterable directory error names the path"
    else
        record_fail "shell: unenterable directory (rc=${rc}, out: ${out})"
    fi
else
    record_skip "shell: no unsearchable directory available to test with"
fi

# --- 6c. root directory has no last path segment to name a session for --------
out="$(run_cc /)"; rc=$?
if [[ ${rc} -eq 1 ]] && grep -q "cannot derive a session name" <<<"${out}"; then
    record_pass "shell: / gives an actionable error, not tmux's 'invalid session:'"
else
    record_fail "shell: / session-name guard (rc=${rc}, out: ${out})"
fi

# --- session tests (require tmux) ---------------------------------------------
if ! command -v tmux >/dev/null 2>&1; then
    record_skip "shell: tmux absent — session tests skipped"
else
    mkdir -p "${TMP}/tmux" "${TMP}/bin" "${TMP}/projects/v0.37+phase-1"
    export TMUX_TMPDIR="${TMP}/tmux"
    unset TMUX

    # Stub claude. Writes its cwd and argv where the test can read them, then
    # sleeps so the session stays alive for inspection. CC_STUB_OUT/CC_STUB_SLEEP
    # come from the environment cc passes through to the tmux server.
    cat > "${TMP}/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf 'pwd=%s\nargs=%s\n' "${PWD}" "$*" > "${CC_STUB_OUT}"
sleep "${CC_STUB_SLEEP:-30}"
STUB
    chmod +x "${TMP}/bin/claude"

    export PATH="${TMP}/bin:${PATH}"
    export CC_PROJECT_ROOT="${TMP}/projects"
    export CC_STUB_OUT="${TMP}/stub.txt"

    # cc's last statement is `tmux attach-session`, which fails with
    # "open terminal failed: not a terminal" under a non-TTY test runner. The
    # session is already created by then, so assert on tmux state and on the
    # stub's own output — never on cc's exit status for the create path.
    # shellcheck disable=SC1090
    source "${CC_SH}"

    tmux_sessions() { tmux list-sessions -F '#{session_name}' 2>/dev/null; }

    # --- 7 + 8. creates one session, name sanitised (. and : -> _) ---
    cc 'v0.37+phase-1' --resume --model sonnet >/dev/null 2>&1
    sleep 1
    sessions="$(tmux_sessions)"
    if [[ "${sessions}" == "v0_37+phase-1" ]]; then
        record_pass "shell: creates one session, dots sanitised to underscores"
    else
        record_fail "shell: session name/count (got: ${sessions//$'\n'/,})"
    fi

    # --- 9. stub ran with cwd = target directory ---
    if grep -qx "pwd=${TMP}/projects/v0.37+phase-1" "${CC_STUB_OUT}" 2>/dev/null; then
        record_pass "shell: claude starts in the resolved project directory"
    else
        record_fail "shell: pane cwd (got: $(cat "${CC_STUB_OUT}" 2>&1))"
    fi

    # --- 10. extra args reach claude verbatim ---
    if grep -qx "args=--resume --model sonnet" "${CC_STUB_OUT}" 2>/dev/null; then
        record_pass "shell: extra arguments pass through to claude verbatim"
    else
        record_fail "shell: arg pass-through (got: $(cat "${CC_STUB_OUT}" 2>&1))"
    fi

    # --- 11. second call reattaches, does not duplicate ---
    out="$(cc 'v0.37+phase-1' 2>&1)"
    count="$(tmux_sessions | wc -l)"
    if [[ "${count}" -eq 1 ]] && grep -q "attaching to existing session" <<<"${out}"; then
        record_pass "shell: second call reattaches instead of duplicating"
    else
        record_fail "shell: reattach (count=${count}, out: ${out})"
    fi

    # --- 12. -n creates a separate session for the same directory ---
    cc -n review 'v0.37+phase-1' >/dev/null 2>&1
    sleep 1
    count="$(tmux_sessions | wc -l)"
    if [[ "${count}" -eq 2 ]] && tmux_sessions | grep -qx "review"; then
        record_pass "shell: -n creates a separately-named second session"
    else
        record_fail "shell: -n second session (count=${count}, got: $(tmux_sessions | tr '\n' ','))"
    fi

    # --- 13. --kill removes one session ---
    cc --kill review >/dev/null 2>&1
    if ! tmux_sessions | grep -qx "review"; then
        record_pass "shell: --kill ends the named session"
    else
        record_fail "shell: --kill left the session alive"
    fi

    # --- 13a + 13b. --new starts a numbered second session; the base name is
    #     the sanitised one, not re-derived. Warns that the tree is shared,
    #     since this fixture project has no .claude/worktree-deps marker. ---
    out="$(cc --new 'v0.37+phase-1' 2>&1)"
    sleep 1
    if tmux_sessions | grep -qx "v0_37+phase-1-2"; then
        record_pass "shell: --new starts a numbered second session (-2)"
    else
        record_fail "shell: --new -2 (got: $(tmux_sessions | tr '\n' ','))"
    fi
    if grep -q "not worktree-isolated" <<<"${out}"; then
        record_pass "shell: --new warns when the project is not worktree-isolated"
    else
        record_fail "shell: --new isolation warning (out: ${out})"
    fi

    # --- 13c. the new session starts in the project directory (no git work) ---
    if grep -qx "pwd=${TMP}/projects/v0.37+phase-1" "${CC_STUB_OUT}" 2>/dev/null; then
        record_pass "shell: --new session starts in the same project directory"
    else
        record_fail "shell: --new pane cwd (got: $(cat "${CC_STUB_OUT}" 2>&1))"
    fi

    # --- 13d. extra arguments still reach claude through --new ---
    cc --new 'v0.37+phase-1' --resume >/dev/null 2>&1
    sleep 1
    if grep -qx "args=--resume" "${CC_STUB_OUT}" 2>/dev/null; then
        record_pass "shell: --new passes extra arguments to claude verbatim"
    else
        record_fail "shell: --new arg pass-through (got: $(cat "${CC_STUB_OUT}" 2>&1))"
    fi

    # --- 13e. successive --new calls climb: -2, -3, -4 all live at once ---
    cc --new 'v0.37+phase-1' >/dev/null 2>&1
    sleep 1
    if tmux_sessions | grep -qx "v0_37+phase-1-3" \
        && tmux_sessions | grep -qx "v0_37+phase-1-4"; then
        record_pass "shell: successive --new calls create -3 and -4 alongside -2"
    else
        record_fail "shell: --new numbering (got: $(tmux_sessions | tr '\n' ','))"
    fi

    # --- 13f. -n <numbered name> is the documented way back in ---
    before="$(tmux_sessions | wc -l)"
    out="$(cc -n 'v0_37+phase-1-2' 2>&1)"
    after="$(tmux_sessions | wc -l)"
    if [[ "${before}" -eq "${after}" ]] && grep -q "attaching to existing session" <<<"${out}"; then
        record_pass "shell: -n reattaches to a --new session without duplicating"
    else
        record_fail "shell: --new reattach (before=${before}, after=${after}, out: ${out})"
    fi

    # --- 13g. lowest free suffix, not a counter: killing -2 frees -2 ---
    cc --kill 'v0_37+phase-1-2' >/dev/null 2>&1
    cc --new 'v0.37+phase-1' >/dev/null 2>&1
    sleep 1
    if tmux_sessions | grep -qx "v0_37+phase-1-2" \
        && ! tmux_sessions | grep -qx "v0_37+phase-1-5"; then
        record_pass "shell: --new reuses the lowest free number after a kill"
    else
        record_fail "shell: --new lowest-free reuse (got: $(tmux_sessions | tr '\n' ','))"
    fi

    # --- 13h. marker present => reports isolation instead of warning ---
    mkdir -p "${TMP}/projects/v0.37+phase-1/.claude"
    touch "${TMP}/projects/v0.37+phase-1/.claude/worktree-deps"
    out="$(cc --new 'v0.37+phase-1' 2>&1)"
    sleep 1
    if grep -q "is worktree-isolated" <<<"${out}" \
        && ! grep -q "not worktree-isolated" <<<"${out}"; then
        record_pass "shell: --new reports isolation when .claude/worktree-deps exists"
    else
        record_fail "shell: --new isolation notice (out: ${out})"
    fi

    # --- 13i. --new numbers from 2 even when no base session exists. The
    #     first session for a project is not implicitly "-1". ---
    mkdir -p "${TMP}/projects/fresh"
    cc --new fresh >/dev/null 2>&1
    sleep 1
    if tmux_sessions | grep -qx "fresh-2" && ! tmux_sessions | grep -qx "fresh"; then
        record_pass "shell: --new starts at -2 with no base session present"
    else
        record_fail "shell: --new fresh-project numbering (got: $(tmux_sessions | tr '\n' ','))"
    fi

    # --- 14. session survives claude exiting (exec \$SHELL -l fallback) ---
    mkdir -p "${TMP}/projects/shortlived"
    CC_STUB_SLEEP=0 cc shortlived >/dev/null 2>&1
    sleep 2
    if tmux_sessions | grep -qx "shortlived"; then
        record_pass "shell: session survives claude exiting (shell fallback)"
    else
        record_fail "shell: session died when claude exited"
    fi

    tmux kill-server >/dev/null 2>&1 || true
    unset CC_PROJECT_ROOT CC_STUB_OUT
fi

# --- install / uninstall round-trip -------------------------------------------
FAKE="${TMP}/fakehome"
mkdir -p "${FAKE}"
if HOME="${FAKE}" bash "${REPO}/scripts/install.sh" shell >/dev/null 2>&1 \
    && [[ -L "${FAKE}/.claude/profile.d/claude-tmux.sh" ]] \
    && [[ "$(readlink -f "${FAKE}/.claude/profile.d/claude-tmux.sh")" == "$(readlink -f "${CC_SH_DEPLOYED}")" ]]; then
    record_pass "shell: install.sh shell symlinks into ~/.claude/profile.d/"
else
    record_fail "shell: install.sh shell did not deploy the symlink"
fi

# Depth regression: uninstall.sh sweeps `find ~/.claude -maxdepth 2 -type l`.
# A deploy target one level deeper (~/.claude/shell/profile.d/) survives
# uninstall with .bashrc still sourcing the repo. This is what makes the
# ~/.claude/profile.d/ path choice load-bearing.
HOME="${FAKE}" bash "${REPO}/scripts/uninstall.sh" >/dev/null 2>&1
if [[ ! -e "${FAKE}/.claude/profile.d/claude-tmux.sh" ]]; then
    record_pass "shell: uninstall.sh removes the profile.d symlink (depth-2)"
else
    record_fail "shell: uninstall.sh left the profile.d symlink behind"
fi
