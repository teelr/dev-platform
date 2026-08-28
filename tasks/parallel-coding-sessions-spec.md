# v1.19: Parallel Coding Sessions

## Coding Specification for Implementation

## Design Philosophy

Starting a second, third, or fourth Claude Code session on the same project is
harder than it should be. `cc` names its tmux session after the directory and
attaches to an existing one, so a second `cc kermit-v3` just reattaches to the
first. The only escape hatch is `cc -n <name> kermit-v3` — which makes you invent
a session name and then remember it to get back. `shell/new-session.sh` (v1.7)
covers a different case (worktree + branch + window when the branch name is known
upfront), has a third interface, and was never deployed by `install.sh` at all,
only reachable by full path.

The fix is one flag: `cc --new` starts the next numbered session — `kermit-v3-2`,
then `-3`, then `-4` — in the same directory, and attaches. Nothing to name,
nothing to remember. Getting back is `cc -n kermit-v3-2`, which the existing
argument handling already covers with zero new code (`-n` attaches when the
session exists, `shell/profile.d/claude-tmux.sh:146`).

**`cc --new` deliberately performs no git operations.** The obvious-looking
alternative — have `cc` create a worktree per session so each one gets its own
branch — is wrong for a reason this repo already discovered when it built worktree
mode: a fresh worktree needs the project's heavy git-ignored paths (`.env`,
`node_modules`) symlinked in from the main checkout, and the list of those paths
is per-project, declared in a committed `.claude/worktree-deps` manifest
(`shell/worktree/README.md`). `cc` cannot invent that manifest, so a worktree it
created for a project that never opted in would be a checkout the app can't run
from. That is exactly why worktree mode is opt-in.

So isolation stays where it already lives and is already tested. For the five
projects that have opted in (`kermit`, `kermit-pa`, `kermit-v3`, `keystone`,
`SQRL`), `/plan` Step 2 calls `EnterWorktree` and moves the session into
`.claude/worktrees/<branch>` the moment the user decides what to build, and
`/merge` Step 5 tears it down after the PR lands. Two `cc --new` sessions sitting
in the main checkout on `main` collide over nothing — they're both just reading
until `/plan` runs. `cc --new` needs to add exactly one thing to that picture: a
tmux session with a free name.

For the thirteen branch-mode projects, two sessions genuinely do share one working
tree and one branch. `cc --new` says so on the way in rather than pretending
otherwise, and points at the opt-in. Making those projects work properly is an
opt-in decision per project, not something this spec forces — see **What NOT to
Do**.

With `--new` shipped, `new-session.sh` has no remaining job: `cc --new` covers the
"another session here" case and `/plan` covers branch creation. It is deleted in
Phase 2, taking the repo from three overlapping ways to start a session down to
one.

**Branching strategy:** single branch and single PR for the whole spec, per the
per-Spec-Phase branching rule in `/home/rich/dev/CLAUDE.md`. Both Spec Phases are
small (well under the ~150–200 LOC threshold) and Phase 2 deletes the script
Phase 1 supersedes — shipping Phase 2 alone would remove a working tool with no
replacement, so the Phases are not independently shippable.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `cc --new` flag | Bash | Extends the existing sourced function in `shell/profile.d/claude-tmux.sh`. It must run in the user's interactive shell before any Claude Code process exists, so it has to be shell. No new component or service. |
| `tests/shell/` assertions | Bash | Matches the existing suite contract (`record_pass`/`record_fail` from `tests/helpers/assert.sh`, never `exit`s). |

The Language Architecture Decision Matrix governs new services and components
(network → Go, compute → Rust, AI → Python, UI → TypeScript). This spec adds
neither — it is shell tooling for the development environment itself, the same
class as every other file under `shell/`.

## Overview

**Phase 1: The `--new` flag**

1. Change 1: Add `--new` to `cc` — lowest-free numbering plus the `-n` conflict guard
2. Change 2: Report whether the new session is worktree-isolated
3. Change 3: Cover `--new` in `tests/shell/run.sh`

**Phase 2: Retire `new-session.sh`**

4. Change 4: Delete `shell/new-session.sh` and update the two code comments naming it
5. Change 5: Rewrite the `shell/README.md` sections that document both

---

## Phase 1: The `--new` flag

### Change 1: Add `--new` to `cc` — lowest-free numbering plus the `-n` conflict guard

**Problem:** A second `cc <project>` reattaches to the first session instead of
starting another one. The only way to get a second session is `cc -n <name>
<project>`, which forces the user to invent a name and remember it.

**File:** `shell/profile.d/claude-tmux.sh` (existing file — declaration line 69,
argument loop lines 79–105, name derivation lines 131–137, usage text lines 41–62,
header comment lines 28–37)

**Implementation:**

Add a `new_session` flag and the numbering search. Four edits to one function:

1. **Local declaration (line 69).** Add the new locals to the existing `local`
   line, keeping the same style (assigned ones first, bare ones after):

   ```bash
   local name="" dir="" target="" resolved claude_bin cmd base n
   local new_session=0
   ```

2. **Argument loop (inside the `case` at lines 80–104).** Add a `--new` arm
   alongside the existing `--list|-l` and `--kill` arms, before the `-n` arm:

   ```bash
   --new)
       new_session=1; shift ;;
   ```

   `--new` takes no argument, so there is no `${2:-}` guard to write here — but
   do not add a bare `$2` reference anywhere in this arm either (v1.18 shipped
   that bug twice; under `set -u` it aborts the caller's shell instead of
   printing a usage error).

3. **Conflict guard (immediately after the `done` closing the argument loop,
   line 105).** `--new` derives a name and `-n` supplies one; asking for both is
   a contradiction, and silently letting one win would be worse than an error:

   ```bash
   if [ "$new_session" -eq 1 ] && [ -n "$name" ]; then
       printf 'cc: --new and -n are mutually exclusive\n' >&2
       return 1
   fi
   ```

   This must sit after the loop (so both flags have been parsed regardless of
   order) and before the name-derivation block at line 131 (which is what
   `--new` modifies).

4. **Numbering (immediately after the empty-name guard at lines 133–137, before
   the `claude_bin` resolution at line 141).** By this point `$name` holds the
   sanitised directory-derived base name:

   ```bash
   # --new: take the lowest free suffix rather than a counter, so killing
   # session -2 makes the next --new reuse -2 instead of climbing forever.
   if [ "$new_session" -eq 1 ]; then
       base="$name"
       n=2
       while [ "$n" -le 99 ] && tmux has-session -t "=${base}-${n}" 2>/dev/null; do
           n=$((n + 1))
       done
       if [ "$n" -gt 99 ]; then
           printf 'cc: no free session name for %s (tried -2 through -99)\n' "$base" >&2
           return 1
       fi
       name="${base}-${n}"
   fi
   ```

   Numbering starts at 2 unconditionally — `--new` always means "another one",
   whether or not the base session is currently live. The `-t "=${base}-${n}"`
   exact-match form matches every other `has-session`/`kill-session` call in the
   file; without the `=` prefix tmux prefix-matches and `kermit-v3` would match
   `kermit-v3-2`.

   The 99 cap exists so a broken `has-session` can never spin forever. It is not
   expected to be reachable.

Because `--new` only changes `$name`, the rest of the function is untouched: the
create path at lines 146–152 starts the session in `$dir` with the same
`exec "$SHELL" -l` fallback, and the attach at lines 157–161 is unchanged.

Then update the two places that document the flag set, keeping their existing
wording style:

- **Usage heredoc (lines 45–52)** — add a line after the `cc <project> [args...]`
  entry:

  ```text
    cc --new [project]      another session for the same project (-2, -3, ...)
  ```

- **Header comment `Usage:` block (lines 30–37)** — add the matching line after
  `cc kermit-v3 --resume`:

  ```text
  #   cc --new kermit-v3      another session for it (kermit-v3-2, then -3)
  #   cc -n kermit-v3-2       get back to that one
  ```

**Acceptance Test:**

```bash
# Isolated tmux server, stub claude — never touch the real sessions.
export TMUX_TMPDIR=$(mktemp -d); unset TMUX
mkdir -p /tmp/ccp/demo && export CC_PROJECT_ROOT=/tmp/ccp
source shell/profile.d/claude-tmux.sh

cc --new demo >/dev/null 2>&1; cc --new demo >/dev/null 2>&1
tmux list-sessions -F '#{session_name}'   # expect: demo-2, demo-3

cc --new -n foo demo                      # expect rc=1, "mutually exclusive"
tmux kill-server
```

---

### Change 2: Report whether the new session is worktree-isolated

**Problem:** In a worktree-mode project the new session will get its own copy of
the repo as soon as `/plan` runs, so it is safe to code in. In a branch-mode
project it shares one working tree and one branch with every other session, and
`/plan`'s `git checkout -b` in one session switches the tree out from under the
others. The user cannot tell which project they are in from the prompt, and
finding out the hard way means a corrupted working tree.

**File:** `shell/profile.d/claude-tmux.sh` (existing file — inside the
session-creation branch at lines 146–152, after the `cc: started session` printf
at line 152)

**Implementation:**

Print the isolation status only on the `--new` create path. A first session has
nothing to collide with, and an attach is not creating anything, so neither case
should say anything:

```bash
if [ "$new_session" -eq 1 ]; then
    # Presence of the committed marker = worktree opt-in; see
    # shell/worktree/README.md. /plan Step 2 does the actual isolation.
    if [ -f "$dir/.claude/worktree-deps" ]; then
        printf 'cc: %s is worktree-isolated — /plan gives this session its own copy of the repo\n' "${dir##*/}"
    else
        printf 'cc: NOTE %s is not worktree-isolated — this session shares one working tree and one branch with the others\n' "${dir##*/}" >&2
        printf 'cc:      opt in by committing .claude/worktree-deps (see shell/worktree/README.md)\n' >&2
    fi
fi
```

The warning goes to stderr and the safe case to stdout, matching how the rest of
the function splits them (errors and cautions to `>&2`, status to stdout).

Known limitation, worth a one-line comment but not worth code: the marker is
looked for at `$dir/.claude/worktree-deps`, so running `cc --new` from *inside* an
existing worktree (`.claude/worktrees/<branch>`) reports "not worktree-isolated"
even though the project has opted in. `cc --new` is meant to be run from the
project root. Do not add git plumbing to resolve the main checkout — that is
scope creep for a message.

**Acceptance Test:**

```bash
# continues from Change 1's setup
cc --new demo 2>&1 | grep "not worktree-isolated"      # branch-mode project
mkdir -p /tmp/ccp/demo/.claude && touch /tmp/ccp/demo/.claude/worktree-deps
cc --new demo 2>&1 | grep "is worktree-isolated"       # after opting in
```

---

### Change 3: Cover `--new` in `tests/shell/run.sh`

**Problem:** Every other `cc` behavior has a regression assertion; `--new` needs
the same, including the two edge cases most likely to break silently (lowest-free
reuse, and the `=` exact-match that stops `kermit-v3` from prefix-matching
`kermit-v3-2`).

**File:** `tests/shell/run.sh` (existing file — non-tmux assertions before the
`if ! command -v tmux` guard; session assertions inside the `else` branch, after
the existing `--kill` assertion at "13" and before "14")

**Implementation:**

Follow the file's existing conventions exactly: `run_cc` for the non-session
assertions, the sourced `cc` plus `tmux_sessions` helper for session ones,
`record_pass`/`record_fail` only, never `exit`. Note the existing warning in the
file — **never assert on `cc`'s exit status for the create path**, because its
last statement is `tmux attach-session`, which fails with "open terminal failed"
under a non-TTY runner. Assert on tmux state and on the stub's output instead.

Non-session assertion (place after the existing "-n with no name" test):

- `--new` combined with `-n` exits 1 and prints "mutually exclusive"
  (`run_cc --new -n foo`).

Session assertions (place after the existing `--kill` assertion):

- `cc --new 'v0.37+phase-1'` creates `v0_37+phase-1-2`; the sanitised base name
  is reused, not re-derived.
- A second `cc --new` on the same project creates `-3`; a third creates `-4`.
  Assert all three names are live at once.
- The `--new` session's stub wrote `pwd=` equal to the project directory — a new
  session, same working directory, no git operation.
- Extra arguments still reach claude verbatim through `--new`
  (`cc --new 'v0.37+phase-1' --resume` → stub records `args=--resume`).
- `cc -n v0_37+phase-1-2` reattaches: session count is unchanged and the output
  contains "attaching to existing session". This is the documented way back to a
  numbered session, so it needs a guard.
- Lowest-free reuse: `cc --kill v0_37+phase-1-2`, then `cc --new` recreates
  `-2` rather than climbing to `-5`.
- Marker absent → creation output contains "not worktree-isolated"; after
  `mkdir -p <dir>/.claude && touch <dir>/.claude/worktree-deps`, a further
  `--new` contains "is worktree-isolated". Capture with `2>&1` since the warning
  goes to stderr.

The stub writes to a single `CC_STUB_OUT` path, so read it immediately after the
`sleep 1` for the session under test, before starting the next one.

**Acceptance Test:**

```bash
bash tests/shell/run.sh      # every new assertion PASS, no FAIL
./scripts/gate_fast.sh       # 262 PASS today; expect ~271 with these added
```

---

## Phase 2: Retire `new-session.sh`

### Change 4: Delete `shell/new-session.sh` and update the two code comments naming it

**Problem:** `new-session.sh` starts a worktree + branch + tmux window when the
branch name is known upfront. `cc --new` now covers "another session here" and
`/plan` covers branch creation, so it is a third interface for a job two commands
already do. It is also not deployed — `install_shell` only symlinks
`shell/profile.d/*.sh` (`scripts/install.sh:305`) — so it is reachable only by
full path and has no users to migrate.

**File:** `shell/new-session.sh` (delete), `scripts/install.sh` (existing file,
comment at lines 296–298), `shell/profile.d/claude-tmux.sh` (existing file,
header comment at lines 22–26)

**Implementation:**

1. `git rm shell/new-session.sh`.

2. `scripts/install.sh:296–298` currently reads:

   ```bash
   # Only profile.d/ is deployed. Top-level shell/*.sh (new-session.sh) are
   # executable scripts, not function libraries — sourcing new-session.sh
   # ...
   ```

   Rewrite it to state the rule without the deleted example: only `profile.d/` is
   deployed because those files are sourced into the interactive shell; any
   top-level `shell/*.sh` are executable scripts run by full path, and sourcing
   one would run its side effects at shell startup. Do not delete the comment —
   the rule it documents is still live and is why the `profile.d/` split exists.

3. `shell/profile.d/claude-tmux.sh:22–26` is the "Relationship to
   shell/new-session.sh" paragraph. Replace it with a short paragraph on `--new`:
   `cc` attaches to (or starts) the session for a project; `cc --new` starts an
   additional numbered one in the same directory; isolation for those extra
   sessions is `/plan`'s job via worktree mode, not `cc`'s.

Leave `.gitignore:122` (`!shell/*.sh`) alone — the directory contract still allows
top-level executable scripts, there just aren't any right now.

Do **not** edit the `new-session.sh` mentions in `ROADMAP.md` (v1.7, v1.18
entries), `planning.md`, or `tasks/tmux-session-helper-spec.md`. Those are
historical records of what shipped at the time; the v1.19 entry records the
retirement.

**Acceptance Test:**

```bash
test ! -e shell/new-session.sh                              # gone
grep -rn "new-session" --include='*.sh' --include='*.md' \
    scripts/ shell/ tests/ commands/ skills/                # no live references
./scripts/gate_fast.sh                                      # PASS
```

---

### Change 5: Rewrite the `shell/README.md` sections that document both

**Problem:** `shell/README.md` documents `new-session.sh` in two places — the
sourced-vs-executed file split (which uses it as the worked example of an
unsourceable script) and a closing paragraph on how it and `cc` coexist. Both go
stale the moment Change 4 lands, and the `cc` usage block does not list `--new`.

**File:** `shell/README.md` (existing file — "What goes here" bullet list, the
`cc` usage code block, and the closing coexistence paragraph)

**Implementation:**

1. **"What goes here" bullets.** The second bullet names `new-session.sh` as the
   example of a top-level executable script and cites its `${1:?usage}` guard.
   Keep the rule, drop the dead example: top-level `shell/*.sh` are executed, not
   sourced, and must never be sourced because a script's top-level side effects
   and `${1:?...}` guards would run at shell startup — which is why the sourced
   set lives in `profile.d/`. Note that no top-level scripts currently ship.

2. **`cc` usage block.** Add the two lines, matching the flag order used in the
   function's own usage text:

   ```text
   cc --new                another session for the same project (-2, -3, ...)
   cc -n kermit-v3-2       get back to a numbered session
   ```

3. **Closing paragraph** ("`cc` and `new-session.sh` coexist: ..."). Replace with
   a short paragraph on parallel sessions: `cc --new` starts the next numbered
   session in the same directory and does no git work; in a project that has
   opted into worktree mode, `/plan` moves each session into its own copy of the
   repo, and `cc --new` says on start-up which of the two situations you are in.
   Link `shell/worktree/README.md` for the opt-in.

Keep the existing markdown conventions: blank line after every heading, fenced
blocks tagged `text`.

**Acceptance Test:**

```bash
grep -c "new-session" shell/README.md    # expect 0
grep -q -- "--new" shell/README.md       # documented
./scripts/gate_fast.sh                   # PASS (docs-only checks included)
```

---

## What NOT to Do

- **Do not make `cc` create git worktrees.** A worktree for a project that has
  not committed `.claude/worktree-deps` has no `.env` and no `node_modules`, so
  the app cannot run from it. `cc` has no way to know which paths a given project
  needs. This is the whole reason worktree mode is opt-in.
- **Do not sibling-dir the worktrees** (`<repo>-2`, the pattern `new-session.sh`
  used). `/merge` Step 4 detects worktrees by matching `*/.claude/worktrees/*`
  (`commands/merge.md:73`) and would not tear them down; worse, `/merge`'s
  branch-mode path runs `git checkout main`, which fails inside a sibling
  worktree because `main` is checked out in the primary. Sibling worktrees would
  break `/merge`.
- **Do not touch `commands/plan.md` or `commands/code.md`.** `cc --new` leaves
  the session in the main checkout on `main`, which is exactly the state
  `/plan` Step 2 already expects. Anything that leaves the session on a detached
  HEAD or a placeholder branch *would* need those files changed, because
  `git branch --show-current` returns empty on a detached HEAD and Step 2 reads
  "not `main`" as "a branch already exists" — another reason not to go there.
- **Do not opt dev-platform into worktree mode as part of this spec.**
  `scripts/install.sh` symlinks `~/.claude/*` at repo paths; run from a worktree
  those symlinks point into a directory `/merge` later deletes, leaving the live
  deployment broken. It also needs a `.gitignore` negation, since `.gitignore:169`
  ignores all of `.claude/`. Real decision, separate spec.
- **Do not add a `-N` short flag** for `--new`. One character away from `-n`,
  which means something different and takes an argument.
- **Do not reference `$2` unguarded** in the new argument arm. Use `${2:-}` if a
  future arm needs it — v1.18 shipped that bug in both `--kill` and `-n`.
- **Do not assert on `cc`'s exit status for the create path** in tests. Its last
  statement is `tmux attach-session`, which fails under a non-TTY runner after
  the session is already created.
- **Do not let the test suite touch the user's real tmux sessions.** One of them
  is the Claude Code session running the gate. Use the suite's existing
  `TMUX_TMPDIR` isolation and stub `claude`.
- **Do not rewrite `ROADMAP.md`/`planning.md` history** for the `new-session.sh`
  removal. Those entries record what shipped at the time.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `shell/profile.d/claude-tmux.sh` | Modify | Add `--new` (lowest-free numbering, `-n` conflict guard), worktree-isolation notice, usage + header comment updates |
| `tests/shell/run.sh` | Modify | ~9 assertions covering numbering, reuse after kill, reattach by name, arg pass-through, both isolation messages, flag conflict |
| `shell/new-session.sh` | Delete | Superseded by `cc --new` + `/plan`; was never deployed by `install.sh` |
| `scripts/install.sh` | Modify | Rewrite the `install_shell` comment that used `new-session.sh` as its example |
| `shell/README.md` | Modify | Drop both `new-session.sh` references, document `--new` and the reattach form |
| `ROADMAP.md` | Modify | v1.19 entry (handled by `/code`'s doc step) |
| `planning.md` | Modify | Active-phase + recently-shipped update (handled by `/code`'s doc step) |

## Implementation Order

1. **Change 1** — `--new` flag. Everything else depends on the flag existing.
2. **Change 2** — isolation notice. Depends on Change 1's `new_session` local.
3. **Change 3** — tests. Depends on Changes 1 and 2; run `./scripts/gate_fast.sh`
   here and confirm the count moved from 262 to ~271.
4. **Change 4** — delete `new-session.sh` and fix the two code comments.
   Independent of 1–3, but pointless before `--new` works.
5. **Change 5** — `shell/README.md`. Last, so it describes the shipped behavior.

## Verification Checklist

- [ ] `cc --new` in a project with no live session creates `<base>-2`
- [ ] Successive `cc --new` calls create `-3` and `-4`, all live simultaneously
- [ ] Killing `-2` makes the next `cc --new` reuse `-2`, not climb to `-5`
- [ ] `cc -n <base>-2` reattaches without creating a duplicate
- [ ] `cc --new -n foo` exits 1 with "mutually exclusive"
- [ ] `cc --new` starts claude in the project directory and passes extra args verbatim
- [ ] `cc --new` prints the shared-tree warning without `.claude/worktree-deps`, and the isolated notice with it
- [ ] `cc` with no `--new` is byte-for-byte unchanged in behavior (attach-or-create, no new output)
- [ ] `shell/new-session.sh` is gone and no live file under `scripts/`, `shell/`, `tests/`, `commands/`, `skills/` references it
- [ ] `shell/README.md` documents `--new` and the reattach form; zero `new-session` matches
- [ ] `bash tests/shell/run.sh` — all PASS
- [ ] `./scripts/gate_fast.sh` — PASS, count up from 262 by the number of new assertions
- [ ] `./scripts/install.sh shell && ./scripts/verify.sh` — no drift after deploy
- [ ] No hardcoded paths; `CC_PROJECT_ROOT` still respected and still re-defaulted under `set -u`
- [ ] Markdown: blank line after headings, fenced blocks tagged with a language
