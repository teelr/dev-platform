# shell/worktree/gate-lock.sh — take-turns lock for gate runs across worktrees.
# Source this, then wrap the shared-resource region (backend stop/restart) in
# with_gate_lock. The lockfile lives in the shared git common dir, so all
# worktrees of one repo contend on the same lock. flock blocks (waits its
# turn); it does not fail fast.
#
# Usage:
#   source ~/.claude/worktree/gate-lock.sh
#   with_gate_lock my_backend_restart_fn        # or: with_gate_lock bash -c '...'
#
# Not executable / no shebang — this file is sourced, not run.

_gate_lockfile() {
    local common
    common="$(git rev-parse --git-common-dir 2>/dev/null)" || common="/tmp"
    # git-common-dir may be relative to the current directory; resolve it.
    [[ "${common}" != /* ]] && common="$(cd "${common}" 2>/dev/null && pwd || echo /tmp)"
    echo "${common}/gate.lock"
}

with_gate_lock() {
    local lf
    lf="$(_gate_lockfile)"
    if command -v flock >/dev/null 2>&1; then
        ( flock 9; "$@" ) 9>"${lf}"
    else
        # flock absent (e.g. macOS without util-linux): run without serialization,
        # but say so — a silent no-lock is worse than a visible warning.
        echo "[gate-lock] flock not found — running WITHOUT serialization" >&2
        "$@"
    fi
}
