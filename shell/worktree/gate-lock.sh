# shell/worktree/gate-lock.sh — take-turns lock for gate runs across worktrees.
# The lockfile lives in the shared git common dir, so all worktrees of one repo
# contend on the same lock. flock blocks (waits its turn); it does not fail fast.
#
# Two public shapes, because gates need both:
#
#   with_gate_lock <cmd> [args...]     wrap ONE command
#   gate_lock_acquire [label]          hold across a region; releases on
#   gate_lock_release                  gate_lock_release or process exit
#
# The acquire/release pair exists because a gate that stops a shared backend so
# its tests can bind the ports must hold the lock across the whole stop → test →
# restart window — a shape with_gate_lock cannot express. Both consumer projects
# had hand-rolled the identical `exec 9>…; flock 9; …; exec 9>&-` block against
# the private _gate_lockfile before this existed. Use these instead.
#
# A third, read-only shape answers "is a gate running right now" for a caller
# that only wants to know — a health check, a cron job, a systemd unit:
#
#   gate_lock_holder_alive [repo-dir] [max-age-minutes]
#
# It reads the holder note and nothing else; it never opens, creates or waits on
# gate.lock, so it can neither delay a gate nor be delayed by one. It exists so
# consumers do not each parse the note format, which is private to this file.
#
# **fd 9 is reserved by this helper.** Callers must not use it for anything else.
#
# Contention is announced on stderr; an uncontended acquire is silent, so the
# common single-session case adds no noise. Waiting used to be invisible, which
# made a queued gate indistinguishable from a hung one.
#
# Holder metadata lives in a SIBLING file (gate.lock.holder), never in the
# lockfile itself: `9>` truncates at open, BEFORE flock is called, so a waiter
# opening the lockfile would erase the holder's own stamp before it ever
# blocked. The holder file is advisory only — flock releases automatically when
# a holder dies, so the file can outlive its process; readers must treat a
# recorded pid as a hint, never as proof something is running.
#
# Not executable / no shebang — this file is sourced, not run.

# _gate_lockfile [dir] — path of the lockfile for the repo containing dir
# (default: the current directory). gate_lock_holder_alive passes a dir because
# its callers (a cron job, a systemd unit) have no git working directory.
_gate_lockfile() {
    local base="${1:-.}" common
    common="$(git -C "${base}" rev-parse --git-common-dir 2>/dev/null)" || common="/tmp"
    # git-common-dir may be relative to base; resolve it from there.
    [[ "${common}" != /* ]] && common="$(cd "${base}" 2>/dev/null && cd "${common}" 2>/dev/null && pwd || echo /tmp)"
    echo "${common}/gate.lock"
}

_gate_lock_holderfile() {
    printf '%s.holder' "$(_gate_lockfile "${1:-}")"
}

# Record who holds the lock. Only ever called while the lock IS held, so this
# never races another writer. Best-effort: a read-only git dir must not turn a
# working lock into a failed gate.
_gate_lock_stamp() {
    printf 'pid=%s started=%s label=%s\n' \
        "$$" "$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)" "${1:-gate}" \
        > "$(_gate_lock_holderfile)" 2>/dev/null || true
}

_gate_lock_clear() {
    rm -f "$(_gate_lock_holderfile)" 2>/dev/null || true
}

# Describe the current holder for a waiting message. Degrades to a bare
# "another session" whenever the file is missing, unreadable, malformed, or
# names a pid that is no longer alive — never invent a live holder.
_gate_lock_describe_holder() {
    local hf pid started
    hf="$(_gate_lock_holderfile)"
    if [[ -r "${hf}" ]]; then
        pid="$(_gate_lock_holder_field "${hf}" pid)"
        started="$(_gate_lock_holder_field "${hf}" started)"
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            printf 'pid %s (since %s)' "${pid}" "${started:-unknown}"
            return 0
        fi
    fi
    printf 'another session'
}

# _gate_lock_holder_field <holderfile> <pid|started|label> — print one field of
# the note _gate_lock_stamp writes (`pid=N started=S label=L`). The ONE place the
# note format is parsed: _gate_lock_describe_holder and gate_lock_holder_alive
# both read through it, so they cannot drift apart. label is last on the line
# and may contain spaces. Prints nothing when the file or field is missing.
_gate_lock_holder_field() {
    case "${2:-}" in
        pid)     sed -n 's/^pid=\([0-9]*\).*/\1/p' "${1}" 2>/dev/null ;;
        started) sed -n 's/.*started=\([^ ]*\).*/\1/p' "${1}" 2>/dev/null ;;
        label)   sed -n 's/.*label=\(.*\)$/\1/p' "${1}" 2>/dev/null ;;
    esac
}

# gate_lock_holder_alive [repo-dir] [max-age-minutes] — is a gate running now?
# Prints `pid=N label=L started=S` and returns 0 when the holder note names a
# live pid and is not older than the limit (default 120 minutes; a /gate full
# browser tier takes about 45). Returns 1 when there is no such holder, 2 when
# max-age-minutes is not a whole number.
#
# READ-ONLY: reads gate.lock.holder and nothing else. It never opens, creates,
# probes or waits on gate.lock, so a caller that only wants to know can neither
# delay a gate nor be delayed by one. It touches no fd and no module state, so
# it is safe to call from inside a gate that holds the lock.
#
# The note is a hint, not proof, so it is distrusted three ways: a dead pid (a
# killed gate leaves the note behind), an empty or unparseable `started=`
# (`date -d ""` means midnight today, which would read as recent from 00:00 to
# 02:00), and an age over the limit (so a hung gate cannot silence a caller
# forever). A pid reused by an unrelated process after the gate died still
# reads as alive until the age limit passes. kill -0 also fails for a pid owned
# by another user, so another user's gate reads as "no gate".
gate_lock_holder_alive() {
    local repo_dir="${1:-}" max_min="${2:-}" hf pid started label started_s age_s
    [[ -n "${max_min}" ]] || max_min=120
    if [[ ! "${max_min}" =~ ^[0-9]+$ ]]; then
        echo "gate_lock_holder_alive: max-age-minutes must be a whole number" >&2
        return 2
    fi
    hf="$(_gate_lock_holderfile "${repo_dir}")"
    [[ -r "${hf}" ]] || return 1
    pid="$(_gate_lock_holder_field "${hf}" pid)"
    [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null || return 1
    started="$(_gate_lock_holder_field "${hf}" started)"
    [[ -n "${started}" ]] || return 1
    started_s="$(date -d "${started}" +%s 2>/dev/null)" || return 1
    age_s=$(( $(date +%s) - started_s ))
    # 10# so a limit like "08" is decimal, not an invalid octal literal.
    (( age_s <= 10#${max_min} * 60 )) || return 1
    label="$(_gate_lock_holder_field "${hf}" label)"
    printf 'pid=%s label=%s started=%s\n' "${pid}" "${label:-unknown}" "${started}"
}

# Take the lock on the already-open fd 9, announcing only if we actually wait.
_gate_lock_wait() {
    if flock -n 9 2>/dev/null; then
        return 0
    fi
    printf '[gate-lock] waiting for another session'"'"'s gate — held by %s\n' \
        "$(_gate_lock_describe_holder)" >&2
    local _start=${SECONDS}
    flock 9
    printf '[gate-lock] acquired after %ss\n' "$(( SECONDS - _start ))" >&2
}

# gate_lock_acquire [label] — hold the lock until gate_lock_release (or exit).
# Uses `exec` so fd 9 outlives the function, which is the entire point; that is
# also why this cannot be a subshell the way with_gate_lock is.
gate_lock_acquire() {
    local lf
    lf="$(_gate_lockfile)"
    if ! command -v flock >/dev/null 2>&1; then
        echo "[gate-lock] flock not found — running WITHOUT serialization" >&2
        _GATE_LOCK_HELD=0
        return 0
    fi
    # Probe writability with a scoped redirect FIRST. `exec 9>file 2>/dev/null`
    # has no command, so bash applies EVERY redirection to the shell itself,
    # permanently — including the 2>/dev/null, which silences the shell's stderr
    # for the rest of the run and swallows the very messages this helper exists
    # to print. Append, so the probe never truncates.
    if ! : >>"${lf}" 2>/dev/null; then
        echo "[gate-lock] cannot open ${lf} — running WITHOUT serialization" >&2
        _GATE_LOCK_HELD=0
        return 0
    fi
    exec 9>"${lf}"
    _gate_lock_wait
    _GATE_LOCK_HELD=1
    _gate_lock_stamp "${1:-gate}"
}

# gate_lock_release — safe to call without a prior acquire, and safe to repeat.
# Consumers call it from early-exit paths where the lock was never taken.
gate_lock_release() {
    [[ "${_GATE_LOCK_HELD:-0}" -eq 1 ]] || return 0
    _gate_lock_clear
    # No inline redirect here either — see gate_lock_acquire. Closing a fd this
    # function only reaches when it was opened cannot fail.
    exec 9>&-
    _GATE_LOCK_HELD=0
}

with_gate_lock() {
    local lf
    lf="$(_gate_lockfile)"
    if command -v flock >/dev/null 2>&1; then
        (
            _gate_lock_wait
            _gate_lock_stamp "with_gate_lock"
            "$@"
            rc=$?
            _gate_lock_clear
            exit "${rc}"
        ) 9>"${lf}"
    else
        # flock absent (e.g. macOS without util-linux): run without serialization,
        # but say so — a silent no-lock is worse than a visible warning.
        echo "[gate-lock] flock not found — running WITHOUT serialization" >&2
        "$@"
    fi
}
