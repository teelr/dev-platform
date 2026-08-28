# shellcheck shell=bash
# shell/profile.d/claude-tmux.sh — run Claude Code inside tmux.
#
# Why: the VS Code remote server is started with --enable-remote-auto-shutdown
# and exits 5 minutes after the last client disconnects (timer confirmed in the
# server bundle: 300*1e3). When it exits it destroys the pty host, which hangs
# up every terminal and kills every claude running in one. A laptop sleeping, a
# closed window, or a VS Code update is enough to trigger it.
#
# tmux runs as its own server owned by init (verified: parent PID 1 when started
# from inside a VS Code terminal), so its terminals sit outside that tree and
# survive. Reconnecting reattaches to the live session.
#
# Name collision, accepted deliberately: this shadows /usr/bin/cc (the C
# compiler) in interactive shells. Build tools invoke cc via execvp and bash
# functions are not inherited by child processes, so make/cargo/cmake are
# unaffected — only typing `cc foo.c` at a prompt. Use `command cc` or `\cc` to
# reach the compiler.
#
# Relationship to shell/new-session.sh: that script is for deliberately starting
# a NEW parallel session on a NEW branch + worktree, when the branch name is
# known upfront. This is the everyday "attach me to my session for this project,
# or start one" path. Both name their tmux session after the directory/repo, so
# cc attaches to a session new-session.sh created rather than duplicating it.
#
# Deployment: symlinked to ~/.claude/profile.d/ by scripts/install.sh
# (category: shell). Sourced by ~/.bashrc via the profile.d loop.
#
# Usage:
#   cc                      session named for the current directory
#   cc kermit-v3            resolved under $CC_PROJECT_ROOT, attach or create
#   cc ~/some/path          any directory works
#   cc kermit-v3 --resume   unrecognised arguments pass through to claude
#   cc -n review kermit-v3  explicit session name (a second one, same project)
#   cc --list               show live sessions
#   cc --kill NAME          end one session
#   cc --help

CC_PROJECT_ROOT="${CC_PROJECT_ROOT:-$HOME/dev/projects}"

_cc_usage() {
    cat <<'USAGE'
cc — run Claude Code in tmux so the session survives a disconnect

  cc                      session named for the current directory
  cc <project>            resolved under $CC_PROJECT_ROOT
  cc <path>               any directory
  cc <project> [args...]  extra arguments pass through to claude
  cc -n <name> [project]  explicit session name
  cc --list               show live sessions
  cc --kill <name>        end one session
  cc --help               this text

Inside tmux: ctrl-b d detaches (claude keeps running), ctrl-b [ scrolls
(q to exit scroll), ctrl-b c opens another window.

This shadows /usr/bin/cc; use `command cc` for the C compiler.
USAGE
}

cc() {
    local name="" dir="" target="" resolved claude_bin cmd
    # Re-default rather than reading the global directly: the function stays
    # correct under `set -u` even if CC_PROJECT_ROOT was unset after sourcing.
    local root="${CC_PROJECT_ROOT:-$HOME/dev/projects}"

    if ! command -v tmux >/dev/null 2>&1; then
        printf 'cc: tmux is not installed\n' >&2
        return 1
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --help|-h)
                _cc_usage; return 0 ;;
            --list|-l)
                tmux list-sessions 2>/dev/null || printf 'no tmux sessions\n'
                return 0 ;;
            --kill)
                # ${2:-} not $2: under `set -u` a bare $2 aborts the shell
                # instead of reaching this usage error.
                if [ -z "${2:-}" ]; then
                    printf 'cc: --kill needs a session name\n' >&2
                    return 1
                fi
                tmux kill-session -t "=$2" || return 1
                printf 'cc: killed session %s\n' "$2"
                return 0 ;;
            -n)
                if [ -z "${2:-}" ]; then
                    printf 'cc: -n needs a name\n' >&2
                    return 1
                fi
                name="$2"; shift 2 ;;
            *)
                break ;;
        esac
    done

    # First remaining argument is the project or directory, if it resolves to
    # one. Anything it doesn't resolve to is left for claude.
    if [ "$#" -gt 0 ]; then
        target="$1"
        if [ -d "$target" ]; then
            dir="$target"; shift
        elif [ -d "$root/$target" ]; then
            dir="$root/$target"; shift
        elif [ "${target#-}" = "$target" ]; then
            printf 'cc: no such project or directory: %s\n' "$target" >&2
            printf 'cc: looked in %s\n' "$root" >&2
            return 1
        fi
    fi
    [ -n "$dir" ] || dir="$PWD"

    # Resolve via a temp var: assigning straight into $dir would blank it out
    # before the error branch could name the directory that failed.
    resolved="$(cd "$dir" 2>/dev/null && pwd -P)" || {
        printf 'cc: cannot enter %s\n' "$dir" >&2
        return 1
    }
    dir="$resolved"

    # tmux gives . and : special meaning in target names.
    [ -n "$name" ] || name="$(printf '%s' "${dir##*/}" | tr '.:' '__')"
    if [ -z "$name" ]; then
        # dir is "/", so there is no last path segment to name the session for.
        printf 'cc: cannot derive a session name from %s — pass -n <name>\n' "$dir" >&2
        return 1
    fi

    # Resolve claude to an absolute path: a pre-existing tmux server does not
    # inherit this shell's PATH.
    claude_bin="$(command -v claude)" || {
        printf 'cc: claude is not on PATH\n' >&2
        return 1
    }

    if ! tmux has-session -t "=$name" 2>/dev/null; then
        cmd="$(printf '%q' "$claude_bin")"
        [ "$#" -gt 0 ] && cmd="$cmd$(printf ' %q' "$@")"
        # Fall back to a shell rather than closing the window when claude exits.
        cmd="$cmd; exec \"\$SHELL\" -l"
        tmux new-session -d -s "$name" -c "$dir" "$cmd" || return 1
        printf 'cc: started session %s in %s\n' "$name" "$dir"
    else
        printf 'cc: attaching to existing session %s\n' "$name"
    fi

    if [ -n "${TMUX:-}" ]; then
        tmux switch-client -t "=$name"   # already inside tmux; do not nest
    else
        tmux attach-session -t "=$name"
    fi
}
