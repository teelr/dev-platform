#!/usr/bin/env bash
# scripts/check-concurrent-sessions.sh — report the live Claude Code sessions
# working in THIS repo, what is isolated between them, and what is shared.
#
# Why this exists: cc --new (v1.19) made two, three, or four sessions on one
# project routine, but nothing in commands/ knew that. /dev improvised a warning
# from raw ps output and got it wrong — it told the user not to run the gate
# while another session was building, when the project wires the take-turns lock
# that makes exactly that safe. Prose in a command file is advice a model may
# follow; this script prints the same facts every time.
#
# WHAT IT REPORTS:
#   sessions   — live `claude` processes whose cwd is inside this repo's main
#                checkout or any of its worktrees, one line each
#   isolation  — whether the project opted into worktree mode
#                (.claude/worktree-deps present), i.e. whether /plan gives each
#                session its own copy of the repo
#   shared     — the running app and its database, always, in every mode
#   gate       — whether a concurrent /gate fast takes turns, which needs BOTH
#                the project's gate script to reference the lock AND the helper
#                to be deployed at ~/.claude/worktree/gate-lock.sh
#
# WHAT IT CANNOT SEE: a session whose cwd has moved outside the repo, and any
# session on another machine. It reads /proc, so it is Linux-only — on a host
# without /proc it reports `unknown` rather than claiming you are alone. A false
# "no other sessions" is the dangerous answer here, not an unhelpful one.
#
# NOT wired into gate_fast.sh: this is a diagnostic, not a gate check — same
# call as check-phase-milestones.sh and check-comms-delivery.sh. Only its
# offline test suite (tests/concurrent-sessions/) is gate-discovered.
#
# Read-only: it inspects paths and process metadata, never writes, and never
# touches another session's worktree.
#
# Usage:
#   ./scripts/check-concurrent-sessions.sh        # the repo containing $PWD
#   bash /home/rich/dev/scripts/check-concurrent-sessions.sh   # from any project
#   ./scripts/check-concurrent-sessions.sh --help
#
# Exit codes:
#   0  always, except a usage error. This is a report, not a gate check.
#   2  usage error (unknown argument)

set -uo pipefail

# Overridable so tests/concurrent-sessions/ can point at a fixture tree instead
# of the live process table. Default behavior is unchanged.
CCS_PROC_ROOT="${CCS_PROC_ROOT:-/proc}"

usage() {
    cat <<'USAGE'
check-concurrent-sessions.sh — who else is working in this repo, and what is safe

  ./scripts/check-concurrent-sessions.sh     report on the repo containing $PWD
  --help                                     this text

Reports live sessions, whether worktree mode isolates them, what stays shared,
and whether a concurrent /gate fast takes turns. Read-only; always exits 0.
USAGE
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    "") ;;
    *) printf 'check-concurrent-sessions: unknown argument: %s\n' "$1" >&2
       usage >&2; exit 2 ;;
esac

# --- 1. this repo's worktree roots -------------------------------------------
# The main checkout is git's first entry; every other line is a worktree.
mapfile -t ROOTS < <(git worktree list --porcelain 2>/dev/null \
    | awk '/^worktree /{print substr($0, 10)}')

if [ "${#ROOTS[@]}" -eq 0 ]; then
    printf 'not a git repository — nothing to report\n'
    exit 0
fi
MAIN_CHECKOUT="${ROOTS[0]}"

# This repo's shared git directory. It is the authoritative membership test: a
# path-prefix check is NOT enough, because independent repos nest inside each
# other on this box (every project lives under dev-platform's own repo root at
# /home/rich/dev/projects/*), so prefix-matching reports every session on the
# machine as belonging to whichever outer repo you ran from. The common dir also
# unifies a repo with its worktrees, which is exactly the grouping wanted here.
common_dir_of() {
    ( cd "$1" 2>/dev/null \
        && d="$(git rev-parse --git-common-dir 2>/dev/null)" || exit 1
      cd "${d}" 2>/dev/null && pwd -P )
}
MY_COMMON="$(common_dir_of "${MAIN_CHECKOUT}")"

# --- 2. live sessions inside those roots -------------------------------------
# root_for <cwd> — echo the LONGEST root containing cwd, or nothing.
# Longest, not first: the main checkout is a string prefix of every worktree
# under it (.claude/worktrees/<branch>), so first-match-wins would label every
# worktree session as "main" — erasing the one distinction this report exists
# to make.
root_for() {
    local cwd="$1" best="" r
    for r in "${ROOTS[@]}"; do
        if [ "$cwd" = "$r" ] || [ "${cwd#"${r}/"}" != "$cwd" ]; then
            [ "${#r}" -gt "${#best}" ] && best="$r"
        fi
    done
    printf '%s' "$best"
}

# ppid_of <pid> — parent PID from /proc/<pid>/status, NOT from field 4 of
# /proc/<pid>/stat: stat's second field is the parenthesized comm and may
# contain spaces, which shifts every field after it.
ppid_of() {
    awk '/^PPid:/{print $2; exit}' "${CCS_PROC_ROOT}/$1/status" 2>/dev/null
}

# The calling session is the nearest `claude` ancestor of this shell.
SELF=""
if [ -d "${CCS_PROC_ROOT}" ]; then
    _p=$$
    # Bounded: a real /proc cannot contain a parent cycle, but a malformed
    # fixture can, and an unbounded walk would hang every gate run.
    _hops=0
    while [ -n "${_p}" ] && [ "${_p}" -gt 1 ] 2>/dev/null && [ "${_hops}" -lt 64 ]; do
        if [ "$(cat "${CCS_PROC_ROOT}/${_p}/comm" 2>/dev/null)" = "claude" ]; then
            SELF="${_p}"; break
        fi
        _p="$(ppid_of "${_p}")"
        _hops=$((_hops + 1))
    done
fi

PROC_OK=1
[ -d "${CCS_PROC_ROOT}" ] || PROC_OK=0

LINES=()
COUNT=0
SELF_LISTED=0
if [ "${PROC_OK}" -eq 1 ]; then
    for d in "${CCS_PROC_ROOT}"/[0-9]*; do
        [ -d "${d}" ] || continue
        [ "$(cat "${d}/comm" 2>/dev/null)" = "claude" ] || continue
        pid="${d##*/}"
        cwd="$(readlink "${d}/cwd" 2>/dev/null)" || continue
        [ -n "${cwd}" ] || continue
        # Membership: same repo, not merely a path underneath it.
        [ "$(common_dir_of "${cwd}")" = "${MY_COMMON}" ] || continue
        root="$(root_for "${cwd}")"
        [ -n "${root}" ] || continue          # inside the repo but under no root

        if [ "${root}" = "${MAIN_CHECKOUT}" ]; then
            kind="main"; rel="."
        else
            kind="worktree"; rel="${root#"${MAIN_CHECKOUT}/"}"
        fi

        if [ -n "${SELF}" ] && [ "${pid}" = "${SELF}" ]; then
            note="(this session)"; SELF_LISTED=1
        else
            note="$(ps -p "${pid}" -o etime= 2>/dev/null | tr -d ' ')"
        fi

        LINES+=("$(printf '  pid %-8s %-9s %-48s %s' "${pid}" "${kind}" "${rel}" "${note}")")
        COUNT=$((COUNT + 1))
    done
fi

if [ "${PROC_OK}" -eq 0 ]; then
    # Never fall through to a count here: reporting "1 (this one only)" when
    # detection did not run tells the user they are alone when they may not be.
    printf 'sessions: unknown — /proc not available on this platform\n'
elif [ "${SELF_LISTED}" -eq 1 ]; then
    if [ "${COUNT}" -eq 1 ]; then
        printf 'sessions: 1 (this one only)\n'
    else
        printf 'sessions: %d (this one + %d other)\n' "${COUNT}" "$((COUNT - 1))"
    fi
    printf '%s\n' "${LINES[@]}"
else
    # The caller is not itself working in this repo — reached when the script is
    # run cross-repo by absolute path. Every session listed is someone else's.
    if [ "${COUNT}" -eq 0 ]; then
        printf 'sessions: 0 (none in this repo)\n'
    else
        printf 'sessions: %d (none is this session)\n' "${COUNT}"
        printf '%s\n' "${LINES[@]}"
    fi
fi

# --- 3. isolation mode --------------------------------------------------------
if [ -f "${MAIN_CHECKOUT}/.claude/worktree-deps" ]; then
    printf 'isolation: worktree mode ON — /plan gives each session its own copy of the repo\n'
else
    printf 'isolation: worktree mode OFF — every session shares one working tree and one branch\n'
fi

# --- 4. what stays shared, and whether the gate takes turns -------------------
printf 'shared: the running app and its database — one backend, one DB across all sessions\n'

GATE=""
for candidate in "${MAIN_CHECKOUT}/scripts/gate_fast.sh" "${MAIN_CHECKOUT}/scripts/gate.sh"; do
    [ -f "${candidate}" ] && { GATE="${candidate}"; break; }
done

LOCK_HELPER="${HOME}/.claude/worktree/gate-lock.sh"
if [ -z "${GATE}" ]; then
    printf 'gate: unknown — no scripts/gate_fast.sh or scripts/gate.sh found\n'
# Match the lock by FILE reference or by either helper function. kermit-v3
# sources gate-lock.sh and then calls _gate_lockfile + `flock 9` directly, with
# no with_gate_lock call anywhere — grepping only for with_gate_lock reports it
# as unlocked, which is the false negative this script exists to prevent.
elif ! grep -qE 'gate-lock\.sh|with_gate_lock|_gate_lockfile' "${GATE}"; then
    printf 'gate: NO lock in %s — concurrent /gate fast runs will fight over the backend\n' \
        "${GATE#"${MAIN_CHECKOUT}/"}"
elif [ ! -f "${LOCK_HELPER}" ]; then
    printf 'gate: lock wired (%s) but helper missing — run ./scripts/install.sh worktree\n' \
        "${GATE#"${MAIN_CHECKOUT}/"}"
else
    printf 'gate: lock wired (%s) + helper deployed — concurrent /gate fast takes turns\n' \
        "${GATE#"${MAIN_CHECKOUT}/"}"
fi

exit 0
