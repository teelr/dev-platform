# v1.18: Tmux Session Helper

## Coding Specification for Implementation

## Design Philosophy

Claude Code sessions on this box die several times a day. The cause is the VS Code
remote server: it runs with `--enable-remote-auto-shutdown` and a 5-minute timer
(`300*1e3` in its bundle), so it exits five minutes after the last client
disconnects. Its exit destroys the pty host, which hangs up every terminal and
kills every `claude` running in one. A sleeping laptop, a closed window, or a VS
Code update is enough. The machine's own logs confirm it — `Could not find pty
37/38/39 on pty host` on reconnect, every `claude` process started within seconds
of the current server, and a server-start folder for roughly every day while
uptime sits at 18 days. tmux fixes it because its server is owned by init (parent
PID 1, verified from inside a VS Code terminal), so its terminals sit outside the
VS Code process tree and survive.

The fix is a sourced shell function, `cc`, that attaches to (or starts) a tmux
session per project. It is deliberately not an alias: it resolves `claude` to an
absolute path first, because an already-running tmux server does not inherit the
calling shell's `PATH`; it falls back to a login shell when claude exits, so
quitting claude does not destroy the session; and it strips `.` and `:` from
session names, which tmux treats as target-syntax separators. All three were
verified against a stub `claude` on an isolated tmux server before this spec was
written.

Shipping `cc` also closes a deployment gap that already exists. `shell/README.md`
claims `scripts/install.sh` "symlinks shell helpers into `~/.shell-platform/` ...
and prints the line to add to `.bashrc`". No such code exists — there is no
`shell` category in `scripts/install.sh` at all, which is why `shell/new-session.sh`
(shipped v1.7, PR #41) is still unreachable except by full path. This spec adds
the category, corrects the README, and brings `shell/` under the same
install/verify/gate coverage every other tracked directory already has.

Three defects in the drafted material were found while exploring and are folded in
rather than shipped as-is:

- `.gitignore:48` (`shell/**`) hides `shell/profile.d/*`. `!shell/*.sh` only reaches
  the top level, so the new file would be silently untracked. Confirmed with
  `git check-ignore -v`.
- `scripts/uninstall.sh` sweeps `find "${HOME}/.claude" -maxdepth 2 -type l`. A
  deploy target of `~/.claude/shell/profile.d/` puts the symlinks at depth 3, so
  uninstall would leave them behind and `.bashrc` would keep sourcing the repo —
  breaking uninstall's stated contract. Deploying to `~/.claude/profile.d/`
  (depth 2, same as `git-hooks/` and `worktree/`) fixes it with no change to
  `uninstall.sh`.
- `cc --kill` and `cc -n` with no argument reference `$2` unguarded (draft lines
  69 and 77). Under `set -u` that aborts the shell instead of printing the usage
  error. Reproduced directly; fixed with `${2:-}`.

**Branching strategy:** one Phase, one branch, one PR. The whole change is well
under the ~150-200 LOC threshold in `/home/rich/dev/CLAUDE.md`, and the pieces are
not independently shippable — the gitignore rule must land before the new file can
be tracked, and the new file is inert until `install.sh` deploys it.

**Naming:** `cc` shadows `/usr/bin/cc` (the C compiler, via `/etc/alternatives`)
in interactive shells. This is an accepted, deliberate trade-off — build tools
(`make`, `cargo`, `cmake`) invoke `cc` through `execvp`, and bash functions are
not inherited by child processes, so builds are unaffected. Only typing `cc foo.c`
at a prompt changes behavior; `command cc` and `\cc` still reach the compiler. The
shadowing must be documented in `shell/README.md` (Change 7) — not left for
someone to discover.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `shell/profile.d/claude-tmux.sh` | Bash | Shell-startup integration. It defines a function in the user's interactive shell and drives `tmux` — there is no other language that can do this. Outside the Language Architecture Decision Matrix, which covers services (network → Go, compute → Rust, AI → Python, UI → TypeScript), not shell glue. |
| `scripts/install.sh`, `scripts/verify.sh`, `scripts/gate_fast.sh` | Bash | Existing files; matching their language is mandatory. |
| `tests/shell/run.sh` | Bash | Matches every other runner under `tests/`, auto-discovered by `gate_fast.sh`. |

## Overview

Phase 1 — Tmux Session Helper (7 Changes):

1. `.gitignore` — allow `shell/profile.d/*` so the new file can be tracked.
2. `shell/profile.d/claude-tmux.sh` — the `cc` function (new file).
3. `scripts/install.sh` — new `shell` category deploying to `~/.claude/profile.d/`.
4. `scripts/verify.sh` — drift check for the new category.
5. `scripts/gate_fast.sh` — add `shell/` to the bash-syntax scan roots.
6. `tests/shell/run.sh` — regression suite (new file).
7. Docs — `shell/README.md`, `README.md`, `CLAUDE.md`.

---

## Phase 1: Tmux Session Helper

### Change 1: `.gitignore` — allow `shell/profile.d/*`

**Problem:** `.gitignore:48` ignores `shell/**`. The re-includes that follow are
`!shell/*.sh` and `!shell/*.md` (top level only), plus per-subdirectory rules
`!shell/git-hooks/*` and `!shell/worktree/*`. A new `shell/profile.d/` directory
has no rule, so `git add shell/profile.d/claude-tmux.sh` is silently a no-op.
Verified: `git check-ignore -v shell/profile.d/claude-tmux.sh` reports
`.gitignore:48:shell/**`.

**File:** `.gitignore` (existing file, immediately after the `!shell/worktree/*`
block near line 118)

**Implementation:**

Add, matching the shape and comment style of the two rules above it:

```gitignore
# v1.18: sourced shell functions live under shell/profile.d/ (claude-tmux.sh).
# Top-level !shell/*.sh doesn't reach subdirectories, so allow every file inside
# shell/profile.d/ (same shape as the shell/git-hooks/ and shell/worktree/ rules
# above). The profile.d/ split exists because shell/*.sh at the top level are
# executable scripts, not function libraries — see shell/README.md.
!shell/profile.d/*
```

This Change must land first. Every later Change assumes the file is trackable.

**Acceptance Test:**

```bash
mkdir -p shell/profile.d && touch shell/profile.d/probe.sh
git check-ignore -q shell/profile.d/probe.sh; echo "expect exit 1: $?"
git add -n shell/profile.d/probe.sh          # expect: add 'shell/profile.d/probe.sh'
rm shell/profile.d/probe.sh
```

Exit 1 from `check-ignore -q` (path is not ignored) is the pass condition. Do NOT
use `-v` here: with `-v`, git reports negation matches too and exits 0 even when
the path is tracked — `shell/worktree/*` behaves identically. `git add -n` is the
unambiguous check.

---

### Change 2: `shell/profile.d/claude-tmux.sh` — the `cc` function

**Problem:** No everyday path to start Claude Code in a session that outlives the
VS Code server. `shell/new-session.sh` covers a different job (deliberately
creating a NEW worktree + branch + window when the branch name is known upfront)
and is itself unreachable.

**File:** `shell/profile.d/claude-tmux.sh` (new file)

**Implementation:**

Write the file exactly as below. It is the drafted-and-tested version with three
corrections applied: `${2:-}` guards on the two argument checks, the deployment
path corrected to `~/.claude/profile.d/`, and the `/usr/bin/cc` shadowing
documented in the header.

```bash
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
    local name="" dir="" target="" claude_bin cmd

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
        elif [ -d "$CC_PROJECT_ROOT/$target" ]; then
            dir="$CC_PROJECT_ROOT/$target"; shift
        elif [ "${target#-}" = "$target" ]; then
            printf 'cc: no such project or directory: %s\n' "$target" >&2
            printf 'cc: looked in %s\n' "$CC_PROJECT_ROOT" >&2
            return 1
        fi
    fi
    [ -n "$dir" ] || dir="$PWD"

    dir="$(cd "$dir" 2>/dev/null && pwd -P)" || {
        printf 'cc: cannot enter %s\n' "$dir" >&2
        return 1
    }

    # tmux gives . and : special meaning in target names.
    [ -n "$name" ] || name="$(printf '%s' "${dir##*/}" | tr '.:' '__')"

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
```

Note the final `[ -n "${TMUX:-}" ]` — the draft used a bare `$TMUX`, which has the
same `set -u` problem as the two argument guards.

**Acceptance Test:**

```bash
bash -c 'set -uo pipefail
  source shell/profile.d/claude-tmux.sh
  type -t cc                      # expect: function
  cc --help >/dev/null; echo "help rc=$?"        # expect 0
  cc --kill; echo "kill rc=$?"                   # expect 1, no unbound-variable abort
  cc -n;    echo "n rc=$?"                       # expect 1, no abort'
```

Behavioral coverage lives in Change 6; this is the smoke check.

---

### Change 3: `scripts/install.sh` — new `shell` category

**Problem:** Nothing installs anything under `shell/`. `shell/README.md:9` already
documents a deployment that does not exist, and `shell/new-session.sh` has been
unreachable since v1.7.

**File:** `scripts/install.sh` (existing file — new function after
`install_worktree()` at line 288; usage header near line 18; case block at lines
290-303)

**Implementation:**

Add `install_shell` immediately after `install_worktree()`, following that
function's structure exactly:

```bash
install_shell() {
    # v1.18 — sourced shell functions. Symlinks each tracked file under
    # shell/profile.d/ into ~/.claude/profile.d/ so .bashrc can source the
    # directory by a stable path that survives a repo move.
    #
    # Only profile.d/ is deployed. Top-level shell/*.sh (new-session.sh) are
    # executable scripts, not function libraries — sourcing new-session.sh
    # errors out on its ${1:?usage} guard and would break shell startup.
    #
    # Target is ~/.claude/profile.d/, NOT ~/.claude/shell/profile.d/:
    # uninstall.sh sweeps `find ~/.claude -maxdepth 2 -type l`, and a
    # three-deep path would survive uninstall with .bashrc still sourcing it.
    mkdir -p "${HOME_CLAUDE}/profile.d"
    local count=0
    for f in "${REPO}/shell/profile.d"/*.sh; do
        [[ -f "${f}" ]] || continue
        local name; name="$(basename "${f}")"
        link_file "${f}" "${HOME_CLAUDE}/profile.d/${name}"
        count=$((count + 1))
    done
    echo "  shell: ${count} files linked to ${HOME_CLAUDE}/profile.d/"
    echo "         Source them by adding this to ~/.bashrc:"
    echo "           if [ -d \"\$HOME/.claude/profile.d\" ]; then"
    echo "               for _f in \"\$HOME/.claude/profile.d\"/*.sh; do"
    echo "                   [ -r \"\$_f\" ] && . \"\$_f\""
    echo "               done"
    echo "               unset _f"
    echo "           fi"
}
```

Printing the snippet rather than editing `~/.bashrc` matches `install_git_hooks`,
which prints the `git config core.hooksPath` line instead of running it. The
actual `.bashrc` edit is a post-merge step (see below).

Then wire it in:

- Usage header, after line 18 (`worktree`):
  `#   ./scripts/install.sh shell      # v1.18 — sourced shell functions (cc)`
- Case block, after `worktree)` (line 298): `    shell)      install_shell ;;`
- `all)` line 299: append `; install_shell` after `install_worktree`.
- Unknown-category message, line 301: add `|shell` before `|all`.

**Deploy it on this machine as part of this Change, not post-merge.** Change 4
adds a `verify.sh` check for `~/.claude/profile.d/`, and `gate_fast.sh` runs
`verify.sh` as an always-on lift check. `/gate fast` must pass *before* commit,
while post-merge runs *after* — so deferring the deploy makes the gate fail with
`live ~/.claude/ verify (drift)` and blocks the commit. Run `./scripts/install.sh shell`
(real `$HOME`) once Change 4 lands. This is the normal live-cutover pattern for a
new install category; v1.2 git-hooks and v1.4 worktree are deployed here the same
way.

**Acceptance Test:**

```bash
FAKE=$(mktemp -d)
HOME="$FAKE" ./scripts/install.sh shell
ls -l "$FAKE/.claude/profile.d/claude-tmux.sh"     # symlink into this repo
HOME="$FAKE" ./scripts/install.sh shell            # idempotent, no error
HOME="$FAKE" ./scripts/uninstall.sh | grep profile.d   # must show it removed
test -e "$FAKE/.claude/profile.d/claude-tmux.sh" && echo FAIL || echo OK
rm -rf "$FAKE"
```

The uninstall assertion is the point of the `~/.claude/profile.d/` path choice —
it must pass without any edit to `uninstall.sh`.

---

### Change 4: `scripts/verify.sh` — drift check for the new category

**Problem:** Consumer Audit rule (`/home/rich/dev/CLAUDE.md`): a new file type in a
glob-managed directory must be audited against install AND verify scripts. Every
other install category has a matching verify block; `shell` would be the only one
without, and `gate_fast.sh` runs `verify.sh` as its live-deploy lift check, so an
unverified category is invisible to the gate.

**File:** `scripts/verify.sh` (existing file — new block after the "Verifying
worktree..." loop, lines 149-155, before "Verifying remotes..." at line 157)

**Implementation:**

```bash
echo "Verifying shell..."
for f in "${REPO}/shell/profile.d"/*.sh; do
    [[ -f "${f}" ]] || continue
    name="$(basename "${f}")"
    check_symlink "${f}" "${HOME_CLAUDE}/profile.d/${name}"
done
```

Note `[[ -f "${f}" ]]` (not `-e`): an unmatched glob leaves the literal pattern,
which `-f` rejects — the same guard `install_shell` uses.

Also update the file header comment (lines 4-5), which currently says the script
"Walks every tracked file in commands/, skills/, settings/, hooks/" — it already
walks git-hooks and worktree too. Make it accurate:

```bash
# Walks every tracked file in commands/, skills/, settings/, hooks/,
# shell/git-hooks/, shell/worktree/, and shell/profile.d/ and verifies the
# corresponding ~/.claude/ path is a symlink pointing back into this repo.
```

**Acceptance Test:**

```bash
FAKE=$(mktemp -d)
HOME="$FAKE" ./scripts/install.sh >/dev/null
HOME="$FAKE" ./scripts/verify.sh | grep -A1 "Verifying shell"   # OK line
rm "$FAKE/.claude/profile.d/claude-tmux.sh"
HOME="$FAKE" ./scripts/verify.sh; echo "expect 1: $?"           # NOT deployed
rm -rf "$FAKE"
```

---

### Change 5: `scripts/gate_fast.sh` — scan `shell/` for bash syntax

**Problem:** The gate's bash-syntax lift check (lines 71-87) walks `scripts/`,
`hooks/`, `scaffolding/*/scripts`, and `tests/` — not `shell/`. `tests/worktree/run.sh:19-30`
compensates with its own `bash -n` calls and a comment saying so, and
`shell/new-session.sh` is covered by nothing at all. Adding a new sourced file to
`shell/` without closing that gap means a syntax error in the one file that runs
at every shell startup would reach the user's `.bashrc`.

**File:** `scripts/gate_fast.sh` (existing file, lines 81-86)

**Implementation:**

Add `"${REPO}/shell" \` to the `find` roots:

```bash
done < <(find \
    "${REPO}/scripts" \
    "${REPO}/hooks" \
    "${REPO}/scaffolding"/*/scripts \
    "${REPO}/shell" \
    "${REPO}/tests" \
    -type f -name "*.sh" -print0 2>/dev/null)
```

This picks up `shell/new-session.sh`, `shell/worktree/*.sh`, and the new
`shell/profile.d/*.sh`. All three existing files already pass `bash -n` (verified),
so the count rises and nothing breaks. `shell/git-hooks/pre-commit` is
extension-less by git convention and stays out of the `*.sh` glob — unchanged
behavior.

Leave `tests/worktree/run.sh` alone. Its syntax checks become redundant, but
rewriting a passing suite for tidiness is churn the gate does not need. Do NOT
add `shell/*` to `DOCS_ONLY_ALLOW_PATTERNS` (line 44) — shell files are code.

**Acceptance Test:**

```bash
./scripts/gate_fast.sh 2>&1 | grep "bash syntax"
# count must be higher than before this Change; still PASS
printf 'if [\n' >> shell/profile.d/claude-tmux.sh   # deliberate breakage
./scripts/gate_fast.sh 2>&1 | grep -E "bash syntax: shell/profile.d"  # must FAIL
git checkout shell/profile.d/claude-tmux.sh
```

---

### Change 6: `tests/shell/run.sh` — regression suite

**Problem:** No coverage for the one file that runs at every shell startup.

**File:** `tests/shell/run.sh` (new file, `chmod +x`)

**Implementation:**

Follow the contract in `tests/README.md` and the shape of `tests/worktree/run.sh`:
`set -uo pipefail`, source `tests/helpers/assert.sh`, use
`record_pass`/`record_fail`/`record_skip`, never call `exit` (the orchestrator owns
the exit code), clean up via `trap`.

Three constraints, all established by probing the real script before this spec was
written — do not re-derive them, and do not "fix" the tests by relaxing them:

- **Isolate tmux with `TMUX_TMPDIR`, and `unset TMUX`.** Pointing `TMUX_TMPDIR` at
  a temp directory gives the test its own tmux server without adding a `-L` flag
  to the function. The trap must `tmux kill-server` against that same
  `TMUX_TMPDIR` so no stray server survives a failure. The suite must never touch
  the user's real sessions.
- **`cc` returns non-zero on the create path in a test.** Its last statement is
  `tmux attach-session`, which fails with `open terminal failed: not a terminal`
  when there is no TTY. The session is already created by then. Assert on
  `tmux list-sessions` and on stub output — never on `cc`'s exit status for the
  create path.
- **Do not assert via `tmux display-message -p '#{pane_current_path}'` or
  `'#{pane_current_command}'`.** Both return empty here. Have the stub `claude`
  write what you need (`$PWD`, `$*`) to a file and read that instead.

The stub: an executable `claude` in a directory prepended to `PATH`. For tests
that need the session to stay alive, the stub ends in `sleep 30`; for the
claude-exits test it returns immediately.

Assertions — no tmux required (run these unconditionally):

1. Sources cleanly under `set -u` and `cc` is a function.
2. `cc --help` exits 0 and its output mentions `CC_PROJECT_ROOT`.
3. `cc --kill` with no name exits 1 with `--kill needs a session name` and does
   not abort the shell. **Regression test for the `${2:-}` fix — the bare `$2`
   version aborts here.**
4. `cc -n` with no name exits 1 with `-n needs a name`, same reason.
5. Unknown project name exits 1 and the message names the searched root.
5b. `CC_PROJECT_ROOT` unset after sourcing, under `set -u`: falls back to
   `$HOME/dev/projects` instead of aborting the caller's shell. Added during
   `/code` — same class as the `$2`/`$TMUX` guards, and the last unguarded
   expansion in the file.
6. With `tmux` removed from `PATH`, `cc` exits 1 with `tmux is not installed`.
   Empty `PATH` *inside* the subshell, after it has started — a `PATH=... run_cc`
   prefix hides `bash` from the helper itself.
6b. A directory that exists but is not searchable (`/root`) exits 1 with an error
   that still names the path. Added during `/code`: resolving straight into
   `$dir` blanked it before the error branch could print it.
6c. `cc /` exits 1 with `cannot derive a session name` rather than leaking tmux's
   `invalid session:`. Added during `/code`: `${dir##*/}` is empty for `/`.

Assertions — tmux required. Guard the whole block with
`if ! command -v tmux >/dev/null 2>&1; then record_skip "shell: tmux absent — session tests skipped"; else ... fi`
so a CI runner without tmux skips rather than fails:

7. `cc <dir>` creates exactly one session, named after the directory, with dots
   sanitised: a directory named `v0.37+phase-1` yields session `v0_37+phase-1`.
   (Implemented as one assertion — comparing the full session list to the exact
   sanitised name proves both the count and the name; two assertions would check
   the same string twice.)
8. The stub runs with cwd equal to the target directory (stub writes `$PWD`).
9. Extra arguments reach claude verbatim — `--resume --model sonnet` (stub writes `$*`).
10. A second `cc` on the same directory does not create a second session.
11. `cc -n other <dir>` creates a second, separately-named session.
12. `cc --kill <name>` removes it.
13. After the stub exits, the session is still alive — the `exec "$SHELL" -l`
    fallback.

Assertions — install integration (throwaway `$HOME`, same pattern as
`tests/install/run.sh`):

14. `HOME=$FAKE install.sh shell` creates a symlink at
    `$FAKE/.claude/profile.d/claude-tmux.sh` resolving into `$REPO`.
15. `HOME=$FAKE uninstall.sh` removes it. **This is the depth-2 regression test** —
    it is what makes the `~/.claude/profile.d/` path choice load-bearing rather
    than cosmetic.

**Acceptance Test:**

```bash
chmod +x tests/shell/run.sh
bash tests/shell/run.sh              # every assertion PASS (or SKIP on no tmux)
./scripts/gate_fast.sh | grep "tests/shell/run.sh"   # auto-discovered by the orchestrator
tmux list-sessions                   # unchanged — the suite touched no real session
```

---

### Change 7: Docs — `shell/README.md`, `README.md`, `CLAUDE.md`

**Problem:** `shell/README.md:9` documents a deployment that has never existed
(`~/.shell-platform/`). The root `README.md` category list and `CLAUDE.md`'s
Install/Deploy line both omit the new category. Per the Honesty About What Ships
rule, a README claiming a feature the code does not have is exactly what this
Change removes.

**File:** `shell/README.md` (existing, lines 5 and 9), `README.md` (existing,
lines 27 and 40), `CLAUDE.md` (existing, Repo Structure table + Install / Deploy
section)

**Implementation:**

`shell/README.md` — rewrite line 9 (Deployment) to describe what Change 3 actually
does, and extend line 5 (What goes here) with the profile.d split:

- What goes here: state the split explicitly — `shell/profile.d/*.sh` are
  **sourced** into the user's interactive shell (function libraries, must be safe
  to source at startup); top-level `shell/*.sh` are **executed** (`new-session.sh`
  aborts on its `${1:?usage}` guard if sourced, which would break shell startup);
  `git-hooks/` and `worktree/` keep their existing meanings.
- Deployment: `./scripts/install.sh shell` symlinks `shell/profile.d/*.sh` into
  `~/.claude/profile.d/` and prints the `.bashrc` loop to add. Say why the target
  is `~/.claude/profile.d/` and not a nested path (uninstall's `-maxdepth 2`).
  Note that top-level `shell/*.sh` are not deployed and are run by full path.
  Git hook templates remain opt-in per repo via `git config core.hooksPath`.
- Add a short `cc` subsection: what it does, the usage lines, `CC_PROJECT_ROOT`,
  and the `/usr/bin/cc` shadowing with the `command cc` escape hatch.

`README.md`:

- Line 27, `shell/` table row: add `shell/profile.d/` (sourced shell functions,
  v1.18) alongside the existing git-hook and worktree mentions.
- Line 40, category list: add `` `shell` (v1.18 — sourced shell functions, `cc`) ``
  before `or `all``. While there, add the two categories the line already omits
  (`managed`, v1.11) so the list matches the case block in `install.sh`.

`CLAUDE.md`:

- Repo Structure table, `shell/` row: add `shell/profile.d/`.
- Install / Deploy section: the sentence listing categories reads ``(`commands`,
  `skills`, `settings`, `hooks`, `vscode`, or `all`)`` — add `shell` and the other
  missing categories so it matches `install.sh`.

**Acceptance Test:**

```bash
grep -c "shell-platform" shell/README.md          # expect 0
grep -n "profile.d" shell/README.md README.md CLAUDE.md   # present in all three
./scripts/install.sh shell 2>&1 | tail -8         # printed snippet matches the README
./scripts/gate_fast.sh                            # markdownlint/taxonomy still PASS
```

---

## What NOT to Do

- **Do not deploy to `~/.claude/shell/profile.d/`.** `scripts/uninstall.sh` uses
  `find -maxdepth 2`; a three-deep path survives uninstall while `.bashrc` keeps
  sourcing the repo, silently breaking uninstall's contract. If you think the
  nested path is nicer, the cost is editing `uninstall.sh`'s sweep depth for every
  category — don't, for one category's cosmetics.
- **Do not have `install.sh` edit `~/.bashrc`.** Print the snippet, like
  `install_git_hooks` prints its `git config` line. Auto-editing a user's shell
  startup is hard to make idempotent and harder to undo. The `.bashrc` edit is a
  post-merge step with the user in the loop.
- **Do not put `cc` in a top-level `shell/*.sh` file.** The `profile.d/` split is
  what keeps `new-session.sh` out of the sourced set; collapsing them means a
  future `install.sh` glob sources a script whose `${1:?usage}` guard kills the
  login shell.
- **Do not skip Change 1.** `git add shell/profile.d/claude-tmux.sh` is a silent
  no-op until the gitignore rule lands, and the file will appear to exist locally
  while being absent from the PR.
- **Do not use a bare `$2` or `$TMUX`.** `${2:-}` and `${TMUX:-}`. This file is
  sourced into every shell; an unbound-variable abort under `set -u` breaks more
  than the function.
- **Do not let the test suite touch the real tmux server.** `TMUX_TMPDIR` to a
  temp dir, `unset TMUX`, `kill-server` in the trap. A test that kills the user's
  live Claude sessions is worse than no test.
- **Do not assert on `cc`'s exit status for the create path in tests.** It ends in
  `tmux attach-session`, which correctly fails without a TTY.
- **Do not rename `cc` to dodge the `/usr/bin/cc` collision.** That was decided:
  keep `cc`, document the shadowing. Builds are unaffected because bash functions
  are not inherited by `execvp`.
- **Do not add `shell/*` to `DOCS_ONLY_ALLOW_PATTERNS`** in `gate_fast.sh:44`.
  Shell files are code; a docs-only skip that swallowed them would skip the one
  suite that tests them.
- **Do not restore the lost tmux save/restore-layout workflow here.** The dead
  aliases pointed at a `dev-session` / `dev4` / `save-tmux-layout.sh` toolkit that
  is unrecoverable (`~/dev/tools` was never tracked in git). Removing the dead
  aliases is in scope; rebuilding that toolkit is a separate Roadmap Phase.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `.gitignore` | Modify | `!shell/profile.d/*` re-include so the new file is trackable |
| `shell/profile.d/claude-tmux.sh` | New | The `cc` function; `${2:-}` / `${TMUX:-}` guards applied |
| `scripts/install.sh` | Modify | `install_shell()` → `~/.claude/profile.d/`; usage header, case block, `all`, error message |
| `scripts/verify.sh` | Modify | "Verifying shell..." drift block; accurate header comment |
| `scripts/gate_fast.sh` | Modify | `"${REPO}/shell"` added to the bash-syntax `find` roots |
| `tests/shell/run.sh` | New | 18 assertions: arg handling, tmux session behavior, install/uninstall round-trip |
| `shell/README.md` | Modify | Replace the false `~/.shell-platform/` deployment claim; document the profile.d split and `cc` |
| `README.md` | Modify | `shell/` table row + `install.sh` category list |
| `CLAUDE.md` | Modify | Repo Structure row + Install / Deploy category list |

## Implementation Order

1. **Change 1** (`.gitignore`) — must be first; nothing after it is trackable otherwise.
2. **Change 2** (`shell/profile.d/claude-tmux.sh`) — the artifact everything else deploys and tests.
3. **Change 3** (`scripts/install.sh`) — depends on Change 2 existing.
4. **Change 4** (`scripts/verify.sh`) — depends on Change 3's deploy path.
5. **Change 5** (`scripts/gate_fast.sh`) — independent of 3 and 4, but run after 2 so the new file is in the scan.
6. **Change 6** (`tests/shell/run.sh`) — depends on Changes 2, 3, and 4 (it exercises install and uninstall).
7. **Change 7** (docs) — last; describes the finished behavior.

One commit for the whole Phase, per the branching decision in Design Philosophy.

## Post-merge (coordination — NOT dev-platform code)

What remains here is the `~/.bashrc` edit. It changes the user's shell startup and
is outside the repo, so **pause and confirm with the user before running it**, and
back the file up first. The `~/.claude/profile.d/` deploy is NOT deferred to this
step — see Change 3.

1. `./scripts/install.sh shell` already ran during `/code` (see Change 3 — the
   gate's live-verify check forces it to happen before commit, not here). Re-run
   it only if `./scripts/verify.sh` reports drift.
2. `cp ~/.bashrc ~/.bashrc.bak-$(date +%F)`.
3. Edit `~/.bashrc` (254 lines today; every claim below re-verified against the
   live file before this spec was written):
   - Delete line 128, `export PATH="$PATH:/home/rich/dev/tools"` — `/home/rich/dev/tools`
     does not exist. **Leave line 127 alone** (`/home/rich/dev/projects/meeting_analyzer`
     does exist).
   - Delete lines 194-217 — 15 aliases (`dev-session`, `devsesh`, `ds`,
     `dev-kermit`, `dev-dave`, `dev-ai`, `dev4`, `dev4-kermit`, `dev4-dave`,
     `save-layout`, `restore-layout`, `save-session`, `restore-session`,
     `list-sessions`, `kermit-dev`) all pointing into that missing directory.
   - Delete lines 219-222 — sources `~/dev/ai_dev/.bash_aliases`, which also does
     not exist.
   - Add the profile.d loop `install.sh shell` printed, in their place.
4. Verify in a **fresh login shell** (not this one): `type -t cc` prints `function`;
   `cc dev-platform` starts or attaches a session; `ctrl-b d` detaches and `cc
   dev-platform` reattaches to the same one.
5. Verify the tmux server is outside the VS Code process tree:
   `ps -o ppid= -p "$(pgrep -x tmux | head -1)"` should print `1`.
6. `./scripts/verify.sh` — no drift.

Not in scope, worth a follow-on decision: the deleted aliases were a tmux
save/restore-layout workflow (`dev-session`, a 4-pane `dev4`, layout save/restore)
that was lost when the untracked `~/dev/tools` directory was wiped. `cc` does not
replace it. If that capability is still wanted, it is its own Roadmap Phase, built
in-repo under `shell/` this time so it cannot be lost the same way.

## Verification Checklist

- [ ] `git check-ignore -q shell/profile.d/claude-tmux.sh` exits 1 (not `-v` — see Change 1)
- [ ] `git status` shows `shell/profile.d/claude-tmux.sh` as a new tracked file
- [ ] Sourcing the file under `set -uo pipefail` defines `cc` and does not abort
- [ ] `cc --kill` and `cc -n` with no argument exit 1 with their usage errors under `set -u`
- [ ] `cc --help` exits 0; `cc <unknown>` exits 1 naming the searched root
- [ ] `install.sh shell` symlinks into `~/.claude/profile.d/`, is idempotent, and prints the `.bashrc` snippet
- [ ] The category is deployed on this machine (real `$HOME`) so `gate_fast`'s live-verify lift check passes before commit
- [ ] `uninstall.sh` removes the `profile.d` symlink (depth-2 requirement holds)
- [ ] `verify.sh` reports the shell category OK after install, exit 1 after deleting the link
- [ ] `gate_fast.sh` bash-syntax count includes `shell/` files and still PASSes
- [ ] `tests/shell/run.sh` is executable, auto-discovered by `gate_fast.sh`, all assertions PASS (or SKIP without tmux)
- [ ] The test suite leaves the user's real tmux sessions untouched (`tmux list-sessions` unchanged)
- [ ] `shell/README.md` contains no `~/.shell-platform/` claim and documents the `cc`/`/usr/bin/cc` shadowing
- [ ] `README.md` and `CLAUDE.md` category lists match `install.sh`'s case block
- [ ] `./scripts/gate_fast.sh` PASSes end to end
- [ ] Language architecture matrix followed (Bash is correct for shell integration; matrix covers services, not shell glue)
- [ ] `/security-review` NOT required — no auth, credentials, external input, or new endpoints. `cc` executes only `tmux` and the resolved `claude` binary, with `%q`-quoted arguments.
