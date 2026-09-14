# v1.34: Cross-Session Collision Guardrails

## Coding Specification for Implementation

## Design Philosophy

[issue #120](https://github.com/teelr/dev-platform/issues/120) (verified via `gh issue view 120 --repo teelr/dev-platform`) is a dependency ask filed by kermit-v3 under the cross-repo comms protocol (`CLAUDE.md` → "Dependency asks go upstream as GitHub issues"): `cc --new` makes 3-4 concurrent sessions on one project routine, and two failure modes show up — (1) sessions not using worktree isolation share the literal same checkout directory, so one session's branch checkout, uncommitted files, or `git reset`/`checkout` affects every other session sitting there, and (2) a session proposes work another session is already doing, because it has no visibility into peers. The issue proposes three directions to spec out and is explicit that none is a commitment — "not a spec... the scoping call... was made at `/plan` time," the same framing [issue #118](https://github.com/teelr/dev-platform/issues/118) used for v1.33.

**What already exists, per the issue (don't rebuild):** worktree isolation (`shell/worktree/`, dev-platform-wide since v1.25 — `/plan` already gives a session its own worktree + branch, `commands/plan.md:26-80`); `scripts/check-concurrent-sessions.sh` (read-only, manually invoked from `/dev`, reports isolation mode + shared state + gate-lock status); `ListAgents`, a harness tool that lists peer sessions by name and location.

**Each of the issue's three directions was checked for whether it's actually buildable before being scoped in or out — this is where two of them changed shape:**

1. **Harden worktree adoption (buildable, scoped in as Change 3).** Verified live: `check-concurrent-sessions.sh` is correct but opt-in — nothing fires unless a human remembers to run `/dev`. A `SessionStart` hook can fire automatically, but it must not turn into a second enforcement system: `CLAUDE.md`'s Quick-fix / Trivial-Edit carve-out legitimately commits straight to `main` in the shared checkout with no branch at all, so the hook must fire ONLY on the actual collision shape — worktree mode ON, not already inside a worktree, AND on a non-default branch — never merely "not in a worktree." **Advisory, not enforced** — a `SessionStart` hook cannot block a tool call anyway (there is no tool call yet), and the issue's own framing ("flag or refuse") leaves room to pick the less disruptive of the two; refusing here would also have no bypass for legitimate cases the hook can't distinguish (e.g. a human deliberately resuming a colleague's branch to fix something small).
2. **Session self-naming (verified NOT buildable as the issue describes; scoped down).** The issue assumes `/plan` (or "session start") can set a session's own `ListAgents` display name. Checked directly: ran `ListAgents` mid-session and found the live evidence for the *problem* — this very session showed as `dev-93` (a generic `<dir>-<suffix>` default) alongside peers like `kermit-v3-47`, `kermit-95` (same generic shape) next to others with real descriptive titles (`"Canvas tab naming convention"`, `"MP3 transcription audit"`) — but then dispatched a `claude-code-guide` research agent to confirm the *mechanism*, since a spec Change built on an assumed capability is exactly the failure mode `/plan`'s own instructions warn against. Its sourced answer (`https://code.claude.com/docs/en/sessions.md`): accepting a plan in Claude Code's **built-in** plan mode auto-titles a session from the plan, and a human can run `/rename <name>` — but **no CLI flag, config, or tool call lets an agent set its own session's display name**, and dev-platform's `/plan` skill doesn't invoke the harness's plan-mode tools (`EnterPlanMode`/`ExitPlanMode`) — it runs directly as a Bash/Write-driven skill (`commands/plan.md:4` — no `EnterPlanMode` in `allowed-tools`). So "have `/plan` set the ListAgents name" is not a real capability to build against. Scoped down to what's real: `/plan` suggests the one-line human action (`/rename <title>`) instead (Change 2).
3. **Peer-visibility preflight (buildable, scoped in as Change 1).** `ListAgents` is already callable from any session — including this one, proven by the check above. `/plan` is the natural point to check it: it's already the place a Roadmap Phase gets claimed (`commands/plan.md` Step 2), i.e. the moment new work starts. Advisory only, matching the issue's own Non-goals — `ListAgents` carries no project or task metadata, so a "looks related" match is a prompt to ask the user, never a fact to act on or block on.

**Non-goals (per the issue, carried through unchanged):** no shared task-claim registry or locking system across sessions. Nothing project-specific — every Change here lands in dev-platform's own `commands/` and `hooks/`, never in a project under `projects/`.

**Scale, matching v1.33/v1.16/v1.29:** two Changes are instruction-file edits to `commands/plan.md` (no runtime to unit-test — `/plan`'s adherence is a matter of it following its own prose correctly, same class as `/code`'s Adversarial Self-Review). One Change is a small, narrowly-scoped Bash hook with an offline fixture-based test suite, following `hooks/session-start.sh` + `tests/concurrent-sessions/run.sh`'s existing conventions exactly.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `hooks/worktree-guard.sh` | Bash | Matches every existing hook script (`hooks/session-start.sh`, `hooks/pre-tool-use.sh`) and `scripts/check-concurrent-sessions.sh` — local environment tooling reading `git`/filesystem state, not one of the Language Matrix's four categories (network/compute/AI/UI), same as the rest of `hooks/` and `scripts/`. |
| `tests/worktree-guard/run.sh` | Bash | Matches `tests/concurrent-sessions/run.sh`'s existing fixture-repo convention. |
| `commands/plan.md` edits | Markdown | Agent instructions, not executable code — same as v1.33. |

No new service, no new language introduced. The Matrix governs new components with a runtime; this spec's one script is a local hook in the same class as everything already in `hooks/`.

## Overview

**Phase 1: Peer Visibility & Session Identity**

1. Change 1: `/plan` calls `ListAgents` before claiming a Roadmap Phase version, surfaces any peer session that looks related, and asks the user to confirm before proceeding.
2. Change 2: `/plan` suggests `/rename <title>` after creating the branch/worktree, so the session becomes identifiable to peers reading `ListAgents`.

**Phase 2: Worktree Adoption Guard**

3. Change 3: New `hooks/worktree-guard.sh`, wired as a `SessionStart` hook, flags — once, automatically, non-blocking — a session sitting in a worktree-mode project's shared main checkout on a non-default branch.

---

## Phase 1: Peer Visibility & Session Identity

### Change 1: `/plan` — peer-visibility preflight via `ListAgents`

**Problem:** Nothing today checks whether another session is already working on the same or overlapping work before `/plan` claims a Roadmap Phase version and creates a branch/worktree (`commands/plan.md` Step 2). `ListAgents` already carries the visibility (proven live in this spec's own Design Philosophy); nothing consults it.

**File:** `/home/rich/dev/commands/plan.md` (existing).

**Implementation:**

**1a. Frontmatter (`commands/plan.md:4`) — add `ListAgents` to `allowed-tools`:**

Change:

```markdown
allowed-tools: Read, Grep, Glob, Write, Bash, WebSearch, WebFetch, TodoWrite, EnterWorktree
```

to:

```markdown
allowed-tools: Read, Grep, Glob, Write, Bash, WebSearch, WebFetch, TodoWrite, EnterWorktree, ListAgents
```

**1b. Step 2 — insert a new paragraph between the existing intro paragraph and the numbered sub-steps (currently `commands/plan.md:28` and `:30`), so it runs before sub-step 1 rather than being folded into the numbered list (the numbered list's sub-steps 1-5 are cross-referenced by number later in the same file — e.g. sub-step 5 says "the guard described in sub-step 4" — so inserting here as its own paragraph avoids a renumbering sweep):**

```markdown
**Peer check, before claiming anything:** call the **`ListAgents`** tool. It lists every peer session — subagents, other local sessions, Remote Control, and cloud — each with a name and, for local/cloud sessions, a location hint (tmux pane, worktree path, cwd-derived name fragment). Skim the list for a peer that looks like it's already working on THIS project or THIS feature: a name containing the project's directory name (e.g. a `kermit-v3-*` session when planning inside kermit-v3), or a descriptive name that overlaps with the feature description in `$ARGUMENTS`. This is advisory, not a real task-claim registry — `ListAgents` carries no project or task metadata, only what a name and location happen to suggest, so treat a match as a prompt to ask, never a fact to act on:

- **No plausible overlap:** proceed silently — no need to mention the check in the report.
- **A plausible overlap:** tell the user which peer session looks related (name + location, quoted verbatim from `ListAgents`) and ask them to confirm before proceeding.

Never block on this automatically — there is no shared task board to check a name against, so a "looks related" match is common and the user is the only one who can resolve it.
```

**Acceptance Test:**

```bash
grep -n "ListAgents" commands/plan.md                    # appears in allowed-tools AND the new Step 2 paragraph
sed -n '1,6p' commands/plan.md                            # frontmatter line 4 includes ListAgents
sed -n '26,40p' commands/plan.md                          # new paragraph reads correctly between the intro and sub-step 1
bash tests/commands/frontmatter.sh                        # frontmatter still valid — this suite does not allowlist specific tool names, so the addition needs no separate registration
./scripts/gate_fast.sh                                    # full gate still PASS
```

Manual/live check (not scriptable — this is agent-followed prose, not a unit-testable primitive, same class as v1.33's circuit breaker): invoke `/plan` for a throwaway feature while another session with a descriptive `ListAgents` name is active, and confirm the Step 2 report mentions it and asks for confirmation.

---

### Change 2: `/plan` — suggest `/rename` after creating the branch/worktree

**Problem:** Interactive sessions default to a generic `<directory>-<suffix>` `ListAgents` name with no task info (live evidence: this session showed as `dev-93`). The issue's proposed fix — have `/plan` set the name itself — is not a real capability (see Design Philosophy, direction 2). The one real, low-cost fix is telling the human to run the one command that does work: `/rename`.

**File:** `/home/rich/dev/commands/plan.md` (existing).

**Implementation:**

Replace the final line of Step 2 (currently `commands/plan.md:80`):

```markdown
Report the branch/worktree path and (if renamed) the new tmux window name, then continue.
```

with:

```markdown
Report the branch/worktree path and (if renamed) the new tmux window name, then continue. **Also suggest the user run `/rename <title>`**, using the Title-Cased feature title from sub-step 3 (or, if this session skipped sub-step 3 because it was already on a feature branch, a title derived from the branch/slug instead) — interactive sessions default to a generic `<directory>-<suffix>` name in `ListAgents`, and no tool lets an agent set its own session's display name (only a human running `/rename`, or accepting a plan in Claude Code's own built-in plan mode, changes it). This is a suggestion for the human to act on, never something to invoke automatically — there is no tool call that does it.
```

**Acceptance Test:**

```bash
grep -n "/rename" commands/plan.md                        # the suggestion is present
sed -n '78,84p' commands/plan.md                           # reads correctly after the tmux-rename sub-step
bash tests/commands/frontmatter.sh
./scripts/gate_fast.sh
```

Manual/live check: run `/plan` end-to-end and confirm the Step 2 report includes a concrete `/rename <title>` suggestion with the actual claimed title substituted in, not a literal placeholder.

---

## Phase 2: Worktree Adoption Guard

### Change 3: `hooks/worktree-guard.sh` — automatic, non-blocking collision flag

**Problem:** `scripts/check-concurrent-sessions.sh` already detects "worktree mode ON, this session is in the shared main checkout" — but only when a human remembers to run `/dev`. Nothing fires automatically, so a session can sit in the shared checkout on a feature branch for its entire lifetime with no flag — the exact state the issue observed live at kermit-v3 on 2026-09-14.

**File:** `/home/rich/dev/hooks/worktree-guard.sh` (new), `/home/rich/dev/settings/settings.json` (existing, lines 130-140), `/home/rich/dev/tests/worktree-guard/run.sh` (new).

**Implementation:**

**3a. New file `hooks/worktree-guard.sh`:**

```bash
#!/usr/bin/env bash
# SessionStart — warns once, at session start, when a session is sitting in a
# worktree-mode project's shared main checkout on a non-default branch instead
# of an isolated worktree. This is failure mode 1 from
# https://github.com/teelr/dev-platform/issues/120: a session's branch
# checkout, uncommitted files, or git reset/checkout in the shared checkout
# affects every other session sitting there too.
# scripts/check-concurrent-sessions.sh already detects this, but only when a
# human remembers to run /dev; this fires automatically for every session.
#
# Advisory only — never blocks. SessionStart cannot refuse a session anyway,
# and a hard block would also catch the legitimate case: CLAUDE.md's
# Trivial-Edit / Quick-fix carve-out commits straight to `main` in the shared
# checkout with no branch at all, and must never warn. Only "worktree mode is
# ON, this is NOT a worktree, and the branch is NOT the default branch"
# warrants a flag.
#
# Known gap, not silently unhandled: this only catches the state a session
# STARTS in. A session that starts on `main` and later runs `git checkout -b`
# by hand mid-session (bypassing /plan's worktree flow) is not re-checked —
# SessionStart fires exactly once. See tasks/cross-session-collision-guardrails-spec.md.
#
# Fleet-wide assumption, verified against monitoring/projects.json (no
# project in the registry declares a default branch at all, let alone a
# non-`main` one): "not main and not master" is treated as "not the default
# branch" fleet-wide, matching every other dev-platform script's assumption.

set -uo pipefail   # NOT -e — never let a git failure crash the hook

# Silent, not a warning: not a git repo, or git isn't on PATH.
REPO_ROOT="$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null)" || exit 0

# Already isolated — EnterWorktree creates worktrees under
# <main-checkout>/.claude/worktrees/.
case "${REPO_ROOT}" in
    */.claude/worktrees/*) exit 0 ;;
esac

# Project hasn't opted into worktree mode — nothing to flag.
[ -f "${REPO_ROOT}/.claude/worktree-deps" ] || exit 0

BRANCH="$(git -C "${REPO_ROOT}" branch --show-current 2>/dev/null)" || exit 0
case "${BRANCH}" in
    main|master|"") exit 0 ;;   # empty = detached HEAD, not this hook's concern
esac

PROJECT="$(basename "${REPO_ROOT}")"
MSG="This session is in ${PROJECT}'s shared main checkout on branch '${BRANCH}', not an isolated worktree. ${PROJECT} is worktree-mode: other sessions here share this same working tree, so a git checkout/reset or uncommitted edit in this session affects them too. Run /plan (or EnterWorktree) to move this work into its own worktree, or confirm with the user that working directly in the shared checkout is intentional (e.g. a Trivial Edit)."

python3 -c 'import json,sys; print(json.dumps({"continue": True, "suppressOutput": False, "systemMessage": sys.argv[1]}))' "${MSG}"

exit 0
```

Then `chmod +x hooks/worktree-guard.sh` (per `hooks/README.md`: "Hooks should be `chmod +x` before commit").

**3b. `settings/settings.json` — add a second entry to the existing `SessionStart` array (currently lines 131-140):**

Change:

```json
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/rich/.claude/hooks/session-start.sh"
          }
        ]
      }
    ],
```

to:

```json
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/rich/.claude/hooks/session-start.sh"
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/rich/.claude/hooks/worktree-guard.sh"
          }
        ]
      }
    ],
```

This is additive and isolated — the existing telemetry hook's own JSON block is untouched, so a mistake in the new block can't break `session-start.sh`'s wiring. No `install.sh`/`verify.sh` changes needed: both already glob `hooks/*.sh` (`scripts/install.sh:179`, `scripts/verify.sh:142`), and `scripts/gate_fast.sh:121` already bash-syntax-checks every file under `hooks/`. `tests/worktree-guard/` is auto-discovered by `scripts/gate_fast.sh`'s suite loop (`scripts/gate_fast.sh:220-240` — every subdirectory of `tests/` except `helpers/` is a suite) with zero orchestrator changes.

**3c. New file `tests/worktree-guard/run.sh`** (mirrors `tests/concurrent-sessions/run.sh`'s fixture-repo convention exactly — real `git init` fixtures, offline, `record_pass`/`record_fail` from `tests/helpers/assert.sh`):

```bash
#!/usr/bin/env bash
# tests/worktree-guard/run.sh — regression suite for hooks/worktree-guard.sh.
#
# Sourced contract: uses record_pass/record_fail from tests/helpers/assert.sh;
# never exit-s (the orchestrator owns the exit code). Entirely offline — real
# git fixture repos, no live Claude Code session or hook dispatch involved.
# The hook is invoked directly as a subprocess with PWD set to the fixture,
# mirroring how hooks/pre-tool-use.sh already relies on $PWD rather than
# parsing the hook's stdin JSON.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
HOOK="${REPO}/hooks/worktree-guard.sh"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

TMP="$(mktemp -d /tmp/r3-wtg.XXX)"
trap 'rm -rf "${TMP}"' EXIT

# mkrepo <dir> <branch> — a real git repo with one commit, on <branch>.
mkrepo() {
    local dir="$1" branch="$2"
    mkdir -p "${dir}"
    git -C "${dir}" init -q 2>/dev/null
    git -C "${dir}" config user.email t@t
    git -C "${dir}" config user.name t
    : > "${dir}/README.md"
    git -C "${dir}" add -A >/dev/null 2>&1
    git -C "${dir}" commit -qm init >/dev/null 2>&1
    git -C "${dir}" checkout -qb "${branch}" 2>/dev/null \
        || git -C "${dir}" checkout -q "${branch}" 2>/dev/null
}

run_hook() { ( cd "$1" && bash "${HOOK}" 2>&1 ); }

# case 1: not a git repo -> silent
NOTGIT="${TMP}/notgit"; mkdir -p "${NOTGIT}"
out="$(run_hook "${NOTGIT}")"
[[ -z "${out}" ]] && record_pass "non-git directory: silent" \
    || record_fail "non-git directory: expected silence, got: ${out}"

# case 2: worktree mode OFF, feature branch -> silent
OFF="${TMP}/off"; mkrepo "${OFF}" "v1.0/phase-1-x"
out="$(run_hook "${OFF}")"
[[ -z "${out}" ]] && record_pass "worktree mode off: silent even on a feature branch" \
    || record_fail "worktree mode off: expected silence, got: ${out}"

# case 3: worktree mode ON, on main -> silent
ONMAIN="${TMP}/onmain"; mkrepo "${ONMAIN}" "main"
mkdir -p "${ONMAIN}/.claude"; : > "${ONMAIN}/.claude/worktree-deps"
out="$(run_hook "${ONMAIN}")"
[[ -z "${out}" ]] && record_pass "worktree mode on, on main: silent" \
    || record_fail "worktree mode on, on main: expected silence, got: ${out}"

# case 4: worktree mode ON, feature branch, shared main checkout -> flags
FLAG="${TMP}/flag"; mkrepo "${FLAG}" "v1.9/phase-1-collision"
mkdir -p "${FLAG}/.claude"; : > "${FLAG}/.claude/worktree-deps"
out="$(run_hook "${FLAG}")"
if [[ "${out}" == *"systemMessage"* && "${out}" == *"v1.9/phase-1-collision"* ]]; then
    record_pass "worktree mode on, feature branch, shared checkout: flags with branch name"
else
    record_fail "worktree mode on, feature branch, shared checkout: expected a flag, got: ${out}"
fi
echo "${out}" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null \
    && record_pass "flag output is valid JSON" \
    || record_fail "flag output is not valid JSON: ${out}"

# case 5: worktree mode ON, feature branch, but INSIDE .claude/worktrees/ -> silent
NESTED="${TMP}/main-checkout/.claude/worktrees/v1.9+phase-1-collision"
mkrepo "${NESTED}" "v1.9/phase-1-collision"
mkdir -p "${NESTED}/.claude"; : > "${NESTED}/.claude/worktree-deps"
out="$(run_hook "${NESTED}")"
[[ -z "${out}" ]] && record_pass "already inside .claude/worktrees/: silent regardless of branch" \
    || record_fail "already inside .claude/worktrees/: expected silence, got: ${out}"

# case 6: worktree mode ON, detached HEAD -> silent
DETACHED="${TMP}/detached"; mkrepo "${DETACHED}" "main"
mkdir -p "${DETACHED}/.claude"; : > "${DETACHED}/.claude/worktree-deps"
COMMIT="$(git -C "${DETACHED}" rev-parse HEAD)"
git -C "${DETACHED}" checkout -q "${COMMIT}" 2>/dev/null
out="$(run_hook "${DETACHED}")"
[[ -z "${out}" ]] && record_pass "detached HEAD: silent" \
    || record_fail "detached HEAD: expected silence, got: ${out}"
```

Then `chmod +x tests/worktree-guard/run.sh`.

**Acceptance Test:**

```bash
bash tests/worktree-guard/run.sh                          # all 7 assertions PASS (mutation-test: comment out the branch case-statement's exit 0 and confirm case 3/6 now FAIL, to prove the suite discriminates)
bash -n hooks/worktree-guard.sh                            # syntax check, same as gate_fast.sh's own check
test -x hooks/worktree-guard.sh                            # chmod +x applied
python3 -c "import json; json.load(open('settings/settings.json'))"   # settings.json still valid JSON after the edit
./scripts/gate_fast.sh                                     # full gate still PASS, new suite auto-discovered
```

---

## What NOT to Do

- **Do NOT make `worktree-guard.sh` fire on every `PreToolUse` call.** A `SessionStart`-only, fire-once check is deliberate: the collision risk is a property of the session's *state* (which branch, which directory), not of any individual tool call, and warning on every `Edit`/`Write` while a session legitimately does feature work in this state would be constant, ignorable noise — the opposite of a useful flag.
- **Do NOT have the hook always print `check-concurrent-sessions.sh`'s full report on every session start**, worktree-mode or not. That would add multi-line noise to every session start across the whole fleet for the common case (a single session, correctly isolated) where there is nothing to say. The hook stays silent unless the specific collision shape (worktree mode ON + shared checkout + non-default branch) is actually present — same "fallback asymmetry" the existing `hooks/pre-tool-use.sh` and `hooks/session-start.sh` already follow.
- **Do NOT try to make `/plan` (or any agent) call a `/rename`-equivalent tool.** Confirmed live with a `claude-code-guide` research pass: no such tool exists. Suggesting the command to the human (Change 2) is the whole scope here — do not invent a workaround (e.g. writing a session-name file somewhere and hoping the harness reads it) to fake the capability.
- **Do NOT build a shared task-claim registry, lock file, or "claimed work" ledger.** Explicitly out of scope per the issue's own Non-goals. Change 1's `ListAgents` check is advisory pattern-matching on names, nothing more.
- **Do NOT touch anything under `projects/`.** Every Change lands in dev-platform's own `commands/`, `hooks/`, `settings/`, `tests/` — this is environment tooling, not project-specific work, per the issue's own Non-goals and `CLAUDE.md`'s Scope rule.
- **Do NOT treat a branch name other than `main`/`master` as automatically risky when worktree mode is OFF.** The guard's second condition (`.claude/worktree-deps` present) must gate the whole check — most dev-platform-fleet projects are still branch-mode, where working on a feature branch in the one shared checkout is the normal, correct way to work.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `commands/plan.md` | Modify | Add `ListAgents` to `allowed-tools`; insert the peer-visibility preflight paragraph in Step 2; append the `/rename` suggestion to Step 2's closing line. |
| `hooks/worktree-guard.sh` | New | `SessionStart` hook — flags (once, non-blocking) a session in a worktree-mode project's shared main checkout on a non-default branch. |
| `settings/settings.json` | Modify | Add a second `SessionStart` array entry wiring `worktree-guard.sh`, alongside the existing `session-start.sh` entry. |
| `tests/worktree-guard/run.sh` | New | 7-assertion offline fixture suite for `worktree-guard.sh`, auto-discovered by `gate_fast.sh`. |

## Implementation Order

1. Change 1 (`commands/plan.md` — peer-visibility preflight) — independent of the others.
2. Change 2 (`commands/plan.md` — `/rename` suggestion) — same file as Change 1; land after it to keep the two Step-2 edits as separate, reviewable diffs rather than one large hunk.
3. Change 3 (`hooks/worktree-guard.sh` + `settings/settings.json` + `tests/worktree-guard/run.sh`) — fully independent of Changes 1-2; order relative to them doesn't matter.

## Verification Checklist

- [ ] `commands/plan.md` frontmatter `allowed-tools` includes `ListAgents`.
- [ ] `/plan` Step 2 calls `ListAgents` before claiming a version, and describes the advisory ask/proceed behavior for a plausible peer match.
- [ ] `/plan` Step 2's closing line suggests `/rename <title>` after branch/worktree creation.
- [ ] `hooks/worktree-guard.sh` exists, is executable, and is silent (no stdout) for: non-git cwd, worktree-mode-off projects, worktree-mode-on projects on `main`/`master`, and cwd already inside `.claude/worktrees/`.
- [ ] `hooks/worktree-guard.sh` emits valid JSON with a `systemMessage` naming the branch when worktree mode is ON, cwd is the shared main checkout, and the branch is not `main`/`master`.
- [ ] `settings/settings.json` remains valid JSON and wires `worktree-guard.sh` as a second `SessionStart` entry without altering the existing `session-start.sh` entry.
- [ ] `tests/worktree-guard/run.sh` passes all 7 assertions and is picked up by `./scripts/gate_fast.sh`'s auto-discovery with no orchestrator edit.
- [ ] `bash tests/commands/frontmatter.sh` still passes.
- [ ] `./scripts/gate_fast.sh` passes in full.
- [ ] No file under `projects/` is touched.
- [ ] Language Architecture Decision Matrix: N/A — no new network/compute/AI/UI component; one new Bash hook in the same class as the rest of `hooks/`.
