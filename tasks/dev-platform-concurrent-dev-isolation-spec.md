# v1.4 Concurrent Dev Isolation

## Coding Specification for Implementation

## Design Philosophy

The problem this solves, plainly: Rich runs more than one Claude Code chat against the same project at the same time (Kermit, Kermit PA, Keystone, SQRL). All the chats share one project folder, so they trip over each other three ways:

1. **Shared files and branch** — one chat runs `/code`, does `git checkout -b`, and the working tree switches branches out from under the other chat's uncommitted work. This is the collision that actually bit this session.
2. **Shared running app** — both chats start the backend on the same port, or both run `/gate fast` (which stops and restarts that one backend), and they crash each other.
3. **Shared database** — one chat's cleanup deletes rows the other chat is reading.

The fix has two layers, and they are independent. Layer 1 (files and branch) is fixed by **worktrees**: each chat gets its own copy of the repo on its own branch under `.claude/worktrees/<name>`, so two chats can never share a working tree. The harness already provides this through the `EnterWorktree` tool — we do not hand-roll `git worktree add` plumbing. Layer 2 (shared app and database) is harder, but Rich confirmed he does **not** need two chats running the app live at the same time. So we do not build per-chat ports or per-chat databases. Instead, chats **take turns**: a lock makes the second `/gate fast` wait for the first to finish stopping and restarting the backend, instead of both fighting over it.

Scope follows the dev-platform charter ([CLAUDE.md](CLAUDE.md)): this repo ships the shared mechanism — the `/code` worktree behavior, a script that links a project's heavy ignored files into each fresh worktree, the `/merge` cleanup, and a reusable take-turns lock. The four projects each turn it on and supply their own config (which files to link, wrapping their own backend restart in the lock) **from their own sessions**, because writing into another project's repo from here is forbidden ([CLAUDE.md](CLAUDE.md) cross-project rule). Turning it on is **opt-in per project**: a project opts in by adding a `.claude/worktree-deps` file. Projects without that file — dev-platform itself, the NVR dashboard, scaffolding repos — keep the current `git checkout -b` behavior unchanged.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `shell/worktree/link-deps.sh` | Bash | Symlinks files and reads a line-based manifest. Pure filesystem glue; matches existing `shell/` and `scripts/` tooling. Zero new dependencies. |
| `shell/worktree/gate-lock.sh` | Bash | A sourceable `flock` wrapper. `flock` is a shell builtin-adjacent coreutil; the natural home is a shell function other gate scripts source. |
| `commands/code.md`, `commands/merge.md` | Markdown (slash-command prompt) | These are agent instructions, not code. The worktree create/enter/exit steps are driven by the `EnterWorktree`/`ExitWorktree` harness tools the command invokes. |
| `scripts/install.sh` / `uninstall.sh` / `verify.sh` extensions | Bash | Inline extension to the existing bash installers. Same shape as the v1.2 `git-hooks` category. |
| `tests/worktree/run.sh` | Bash | Per-suite runner, same pattern as every other `tests/<suite>/run.sh`. |

No new languages. v1.4 reuses the harness worktree tools and tightens existing bash tooling.

## Overview

Three Phases, seven Changes:

**Phase 1 — `/code` starts in a worktree (opt-in)**

1. **Change 1:** `shell/worktree/README.md` — define the `.claude/worktree-deps` manifest format and the opt-in rule.
2. **Change 2:** `shell/worktree/link-deps.sh` + the `worktree` install category (install / uninstall / verify / .gitignore consumer audit).
3. **Change 3:** Rewrite `commands/code.md` Step 1 — enter a worktree and link deps when the project opts in; otherwise create a branch the current way. Add `EnterWorktree` to allowed-tools.

**Phase 2 — clean exit + take-turns lock**

4. **Change 4:** Make `commands/merge.md` worktree-aware — return the session to the main checkout, pull main, remove the merged worktree. Add `ExitWorktree` to allowed-tools.
5. **Change 5:** `shell/worktree/gate-lock.sh` reusable lock; dev-platform's own `gate_fast.sh` adopts it as the reference; document how the four projects wrap their backend restart.

**Phase 3 — tests + docs**

6. **Change 6:** `tests/worktree/` suite covering link-deps and the lock; install integration.
7. **Change 7:** `docs/CONCURRENT-DEV.md` plain-English how-to + README/ROADMAP/planning/lessons closeout + the per-project adoption runbook (runs post-merge, each project's own session).

**Demo:** A project opts in by committing a `.claude/worktree-deps` file listing its heavy ignored paths (e.g. `.env`, `frontend/node_modules`). From then on, `/code` in that project starts in `.claude/worktrees/<branch>` on a fresh branch off `origin/main`, with those paths symlinked in so the app runs. Two chats get two worktrees and never touch each other's files. `/gate fast` in both chats takes turns on the shared backend through the lock. `/merge` removes the worktree and returns the session to the main checkout.

---

## Phase 1: `/code` starts in a worktree (opt-in)

### Change 1: `shell/worktree/README.md` — manifest format + opt-in rule

**Problem:** There is no convention yet for a project to say "I run more than one chat at once, isolate my `/code` sessions." We need a single, file-based opt-in switch that also carries the list of heavy ignored files to link into each worktree. One file does both jobs.

**File:** `shell/worktree/README.md` (new, directory contract)

**Implementation:**

Document the convention:

- **Opt-in marker:** a project opts into worktree mode by committing a file named `.claude/worktree-deps` at its repo root. Presence of the file = opt-in. Absence = current `git checkout -b` behavior, unchanged.
- **Manifest format:** one path per line, relative to the repo root. Blank lines and lines starting with `#` are ignored. Each listed path is a heavy, git-ignored artifact that a fresh worktree needs in order to run but should not be re-created per worktree (it would be slow or wrong). Examples a project might list:

  ```text
  # .claude/worktree-deps — paths symlinked from the main checkout into each worktree
  .env
  frontend/node_modules
  frontend/.next
  ```

- **What it links and how:** `link-deps.sh` (Change 2) symlinks each listed path from the main checkout into the worktree. It does NOT copy. A missing source path is a warning, not an error (the project may not have run `npm install` yet).
- **Where worktrees live:** `EnterWorktree` creates them under `.claude/worktrees/<name>`. Each opting-in project MUST have `.claude/` (or at least `.claude/worktrees/`) in its `.gitignore` so worktrees are never committed. Note that dev-platform already ignores `.claude/` ([.gitignore:138](.gitignore#L138)).
- **What this directory is NOT:** not Claude Code hooks (`hooks/`), not git hooks (`shell/git-hooks/`), not general shell helpers (`shell/*.sh`). It is the worktree-isolation toolset.

**Consumer Audit per [CLAUDE.md](CLAUDE.md) (new files under `shell/`):** `shell/worktree/` is a new subdirectory of `shell/`. The `.sh` files in Change 2 are covered by existing `!shell/**/*.sh`-style allow-lists, but verify with `git check-ignore -v` during /code. The README is markdown — covered by `!**/*.md` allow-lists; verify.

**Acceptance Test:** `shell/worktree/README.md` exists and documents the four points above (opt-in marker, manifest format, link-not-copy + missing-source-is-warning, gitignore requirement). `git check-ignore -v shell/worktree/README.md` returns a re-include rule (tracked, not ignored).

### Change 2: `shell/worktree/link-deps.sh` + `worktree` install category

**Problem:** A fresh worktree has none of the project's git-ignored heavy files (`.env`, `node_modules`), so the app can't run there. We need a script that links them in from the main checkout, and it must be deployed where every project's `/code` session can call it by absolute path (the same distribution problem the v1.2 `git-hooks` category solved).

**File:** `shell/worktree/link-deps.sh` (new, executable) + `scripts/install.sh` / `scripts/uninstall.sh` / `scripts/verify.sh` (extend) + `.gitignore` (verify allow-list)

**Implementation:**

`shell/worktree/link-deps.sh` — usage `link-deps.sh <main-checkout-dir> <worktree-dir>`:

```bash
#!/usr/bin/env bash
# shell/worktree/link-deps.sh — symlink a project's heavy git-ignored paths
# from the main checkout into a fresh worktree, per the project's
# .claude/worktree-deps manifest. Link, never copy. Missing source = warn.
#
# Usage: link-deps.sh <main-checkout-dir> <worktree-dir>
# Deployed to ~/.claude/worktree/link-deps.sh by scripts/install.sh worktree.

set -uo pipefail

MAIN="${1:?usage: link-deps.sh <main-checkout-dir> <worktree-dir>}"
WT="${2:?usage: link-deps.sh <main-checkout-dir> <worktree-dir>}"
MANIFEST="${MAIN}/.claude/worktree-deps"

[[ -f "${MANIFEST}" ]] || { echo "[link-deps] no manifest at ${MANIFEST} — nothing to link"; exit 0; }

linked=0; missing=0
while IFS= read -r raw; do
    line="${raw%%#*}"; line="$(echo "${line}" | xargs)"   # strip comment + trim
    [[ -z "${line}" ]] && continue
    src="${MAIN}/${line}"
    dst="${WT}/${line}"
    if [[ ! -e "${src}" ]]; then
        echo "[link-deps] WARN source missing, skipped: ${line}" >&2
        missing=$((missing + 1)); continue
    fi
    mkdir -p "$(dirname "${dst}")"
    ln -sfn "${src}" "${dst}"
    echo "[link-deps] linked ${line}"
    linked=$((linked + 1))
done < "${MANIFEST}"

echo "[link-deps] ${linked} linked, ${missing} missing"
exit 0
```

`scripts/install.sh` — add `install_worktree()` mirroring `install_git_hooks()` ([scripts/install.sh:189](scripts/install.sh#L189)): `mkdir -p "${HOME_CLAUDE}/worktree"`, loop tracked files under `shell/worktree/` (skip `README.md`), `link_file` each into `~/.claude/worktree/`. Wire `worktree)` into the `case` block and into the `all)` chain. Update the usage comment block (lines 9-16) and the `Usage:` error line to list `worktree`.

`scripts/uninstall.sh` — no change needed: `remove_repo_symlinks` ([scripts/uninstall.sh:17](scripts/uninstall.sh#L17)) already removes any symlink under `~/.claude/` that resolves into the repo, at `-maxdepth 2`. `~/.claude/worktree/link-deps.sh` is depth 2 — covered. Verify during /code with an actual install+uninstall round-trip; if depth is wrong, that is the only edit.

`scripts/verify.sh` — add a `Verifying worktree...` block after the git-hooks block ([scripts/verify.sh:79-85](scripts/verify.sh#L79-L85)), looping tracked `shell/worktree/*` (skip `README.md`) and calling `check_symlink` against `~/.claude/worktree/<name>`.

`.gitignore` — `shell/worktree/link-deps.sh` should already be allowed by the same rule that allows `shell/git-hooks/*` and other `shell/` content. Confirm with `git check-ignore -v shell/worktree/link-deps.sh` (must return a re-include line). If not, add `!shell/worktree/` + the file.

`chmod +x shell/worktree/link-deps.sh`.

**Acceptance Test:** `bash -n shell/worktree/link-deps.sh` passes. `git check-ignore -v shell/worktree/link-deps.sh` returns a re-include rule. With a temp `main/` containing `.claude/worktree-deps` listing `.env` (present) and `frontend/node_modules` (absent) and a temp `wt/`: running the script creates `wt/.env` as a symlink to `main/.env`, prints a WARN for the missing `node_modules`, and exits 0. `./scripts/install.sh worktree` creates `~/.claude/worktree/link-deps.sh` as a symlink; `./scripts/verify.sh` reports it healthy; `./scripts/uninstall.sh` removes it.

### Change 3: `commands/code.md` Step 1 — enter a worktree when the project opts in

**Problem:** `/code` Step 1 currently does `git checkout -b <branch>` in the shared working tree ([commands/code.md:33](commands/code.md#L33)). That is the exact move that switches the tree out from under a second chat. For opted-in projects, `/code` must instead start in its own worktree.

**File:** `commands/code.md` (existing — rewrite Step 1 + frontmatter `allowed-tools`)

**Implementation:**

Add `EnterWorktree` to the frontmatter `allowed-tools` line ([commands/code.md:4](commands/code.md#L4)).

Rewrite Step 1's "Branch auto-creation" block ([commands/code.md:22-36](commands/code.md#L22-L36)). New logic:

1. Derive the branch name exactly as today: `v<X.Y>/phase-<N>-<slug>` (slug from spec filename, phase from `git log`).
2. **Decide the mode by checking for the opt-in marker:**

   ```bash
   test -f .claude/worktree-deps && echo "worktree mode" || echo "branch mode"
   ```

3. **Worktree mode** (`.claude/worktree-deps` exists):
   - Record the main checkout path first: `MAIN=$(git rev-parse --show-toplevel)`.
   - Call the **`EnterWorktree` tool** with `name` = the branch name (e.g. `v1.4/phase-1-foo`). This creates `.claude/worktrees/v1.4/phase-1-foo` on a fresh branch off `origin/<default>` (the harness `worktree.baseRef` default is `fresh`) and re-roots the session into it. Do NOT call `git worktree add` directly — use the tool, which also re-roots the session so subsequent edits land in the worktree.
   - Link the heavy deps in: `bash "${HOME}/.claude/worktree/link-deps.sh" "${MAIN}" "$(pwd)"`. Report what it linked.
   - Report: worktree path, branch name, linked deps.
4. **Branch mode** (no marker): keep today's behavior exactly — `git checkout -b <branch>`, report the branch.
5. **If already in a worktree or already on a feature branch:** skip creation, proceed (same as today's "already on a feature branch" rule).

Document, in the command, that worktree mode is opt-in via the project's `.claude/worktree-deps` file and that `/merge` (Change 4) tears the worktree down.

**Acceptance Test:** `commands/code.md` frontmatter lists `EnterWorktree`. The command's command-frontmatter validator suite (`tests/commands/`) still passes. Step 1 prose describes both modes and the marker check. A dry read shows: no project file is created by `/code` (the marker is committed by the project itself, Change 7 runbook). In branch mode the behavior is byte-for-byte today's `git checkout -b`.

---

## Phase 2: clean exit + take-turns lock

### Change 4: `commands/merge.md` worktree-aware teardown

**Problem:** `/merge` Step 5 runs `git checkout main && git pull --ff-only` in the current directory ([commands/merge.md:78-83](commands/merge.md#L78-L83)). In worktree mode the session is inside `.claude/worktrees/<branch>`, whose branch git refuses to switch to `main` (main is checked out in the main working tree), and `gh pr merge --delete-branch` can't delete a local branch that a worktree holds. The session must return to the main checkout, then the worktree gets removed.

**File:** `commands/merge.md` (existing — add worktree handling to Steps 4-5 + frontmatter `allowed-tools`)

**Implementation:**

Add `ExitWorktree` to the frontmatter `allowed-tools` line ([commands/merge.md:3](commands/merge.md#L3)).

In Step 4, detect worktree mode before the merge:

```bash
git rev-parse --git-common-dir   # if it differs from .git, we're in a worktree
```

A reliable check: `[[ "$(git rev-parse --is-inside-work-tree)" == "true" && "$(git rev-parse --show-toplevel)" == *"/.claude/worktrees/"* ]]`.

Keep the squash-merge as is: `gh pr merge "${PR_NUM}" --squash --delete-branch`. The remote branch is deleted; gh may warn it can't delete the local branch while the worktree holds it — that is expected and handled next.

Replace Step 5 with mode-aware sync:

- **Branch mode (not in a worktree):** unchanged — `git checkout main && git pull --ff-only`.
- **Worktree mode:** record `WT="$(git rev-parse --show-toplevel)"` and `BR="$(git branch --show-current)"`. Call the **`ExitWorktree` tool** with `action: "keep"` (not `remove` — the squashed commits aren't on this branch as commits, so `remove` would hit the uncommitted/unmerged-changes refusal; `keep` returns the session to the main checkout cleanly). Then in the main checkout:

  ```bash
  git checkout main && git pull --ff-only
  git worktree remove --force "${WT}"      # drop the now-merged worktree
  git branch -D "${BR}" 2>/dev/null || true # drop the local branch gh couldn't
  git worktree prune
  ```

Step 6 (report) is unchanged except: in worktree mode, also report that the worktree was removed and the session is back in the main checkout.

**Acceptance Test:** `commands/merge.md` frontmatter lists `ExitWorktree`. The command-frontmatter validator suite passes. Prose covers both modes. The worktree-mode teardown sequence is spelled out in the order above (ExitWorktree keep → pull main → `git worktree remove --force` → `git branch -D` → prune). Branch-mode Step 5 is byte-for-byte today's behavior.

### Change 5: `shell/worktree/gate-lock.sh` reusable take-turns lock

**Problem:** Two chats in two worktrees both run `/gate fast`. In the four stack projects, the gate stops and restarts the one shared backend; simultaneous runs collide on the port (the 8402 failures this session). Take-turns = a lock so the second gate waits. Worktrees of one repo share a common git dir, so a lockfile there is naturally shared across all of a project's worktrees.

**File:** `shell/worktree/gate-lock.sh` (new, sourceable) + `scripts/gate_fast.sh` (adopt as reference)

**Implementation:**

`shell/worktree/gate-lock.sh` — a sourceable helper, no shebang-run:

```bash
# shell/worktree/gate-lock.sh — take-turns lock for gate runs across worktrees.
# Source this, then wrap the shared-resource region (backend stop/restart) in
# with_gate_lock. The lockfile lives in the shared git common dir, so all
# worktrees of one repo contend on the same lock. flock blocks (waits its turn);
# it does not fail fast.
#
# Usage:
#   source ~/.claude/worktree/gate-lock.sh
#   with_gate_lock my_backend_restart_fn         # or: with_gate_lock bash -c '...'

_gate_lockfile() {
    local common; common="$(git rev-parse --git-common-dir 2>/dev/null)" || common="/tmp"
    # git-common-dir may be relative to cwd; resolve it
    [[ "${common}" != /* ]] && common="$(cd "${common}" && pwd)"
    echo "${common}/gate.lock"
}

with_gate_lock() {
    local lf; lf="$(_gate_lockfile)"
    if command -v flock >/dev/null 2>&1; then
        ( flock 9; "$@" ) 9>"${lf}"
    else
        # flock absent (e.g. macOS without util-linux): run without serialization,
        # but say so — silent no-lock is worse than a warning.
        echo "[gate-lock] flock not found — running WITHOUT serialization" >&2
        "$@"
    fi
}
```

`scripts/gate_fast.sh` adopts it as the reference implementation and to give the test suite something real: source the helper near the top (after the assert.sh source, [scripts/gate_fast.sh:21](scripts/gate_fast.sh#L21)) from the deployed path with a tracked-path fallback:

```bash
# Take-turns lock (v1.4): serialize the live ~/.claude/ verify across concurrent
# gates so two worktree sessions don't race on the shared deploy.
_LOCK_HELPER="${HOME}/.claude/worktree/gate-lock.sh"
[[ -f "${_LOCK_HELPER}" ]] || _LOCK_HELPER="${REPO}/shell/worktree/gate-lock.sh"
# shellcheck disable=SC1090
source "${_LOCK_HELPER}"
```

Wrap ONLY the live `~/.claude/` verify step ([scripts/gate_fast.sh:80-86](scripts/gate_fast.sh#L80-L86)) in `with_gate_lock`, since that is the one step touching shared deploy state. Do not wrap the whole gate — taxonomy, syntax, and the per-suite runners are worktree-local and need no lock. Keep the existing pass/fail recording.

Document in `shell/worktree/README.md` (extend Change 1's file) how the four projects adopt it: `source ~/.claude/worktree/gate-lock.sh` in their `scripts/gate_fast.sh`, then wrap their backend stop/restart call in `with_gate_lock`. That adoption happens in each project's own session (Change 7 runbook), not here.

**Acceptance Test:** `bash -n shell/worktree/gate-lock.sh` passes. `git check-ignore -v shell/worktree/gate-lock.sh` returns a re-include rule. Sourcing it and running `with_gate_lock true` exits 0. A serialization test (Change 6) proves two concurrent `with_gate_lock` calls do not overlap. `./scripts/gate_fast.sh` still passes end-to-end with the lock wrapping the verify step; total PASS count rises by the Change 6 suite size.

---

## Phase 3: tests + docs

### Change 6: `tests/worktree/` suite

**Problem:** link-deps and the lock need regression coverage so later edits can't silently break them.

**File:** `tests/worktree/run.sh` (new, executable) + fixtures under `tests/worktree/fixtures/`

**Implementation:**

Per the suite contract ([tests/README.md](tests/README.md)) and the orchestrator's `! -path "*/fixtures/*"` filter ([scripts/gate_fast.sh:117-119](scripts/gate_fast.sh#L117-L119)), runners live at `tests/worktree/run.sh`; fixtures under `fixtures/`. Source `tests/helpers/assert.sh`. Tests:

1. **link-deps links a present path:** mktemp `main/` with `.claude/worktree-deps` listing `.env`; create `main/.env`; mktemp `wt/`; run `link-deps.sh main wt`; assert `wt/.env` is a symlink resolving to `main/.env`; assert exit 0.
2. **link-deps warns on a missing path:** manifest lists `frontend/node_modules` with no such source; assert exit 0 AND stderr contains `WARN source missing` (substring assertion per [tasks/lessons.md](tasks/lessons.md) negative-test rule).
3. **link-deps ignores comments and blanks:** manifest with a `#` comment line and a blank line plus one real path; assert only the real path is linked (`linked, ` count check via stdout substring).
4. **link-deps no-op without a manifest:** `main/` has no `.claude/worktree-deps`; assert exit 0 and the "nothing to link" message.
5. **gate-lock runs the wrapped command:** source `gate-lock.sh` in a temp git repo (`git init`), `with_gate_lock true`; assert exit 0.
6. **gate-lock serializes:** in a temp git repo, launch two background `with_gate_lock` calls that each append a marker, sleep briefly, append a second marker; assert the markers do NOT interleave (first call's pair is contiguous). Keep the sleep tiny; do not introduce a multi-second test. If `flock` is absent, record SKIP for this one assertion (don't FAIL the suite on a platform without util-linux).
7. **install integration:** run `./scripts/install.sh worktree` with `HOME=<tmpdir>`; assert `<tmpdir>/.claude/worktree/link-deps.sh` and `gate-lock.sh` are symlinks resolving back to the tracked sources.

Use the two-line exit-code capture (`out="$(cmd 2>&1)"; rc=$?`), never `cmd || true; check $?` (per [tasks/lessons.md](tasks/lessons.md)). `trap 'rm -rf "${tmp}"' EXIT` per test; each test its own tmpdir.

**Consumer Audit:** fixture `.sh` files and the runner are covered by `!tests/**/*.sh`; verify with `git check-ignore -v`. The orchestrator auto-discovers `tests/worktree/` with no edit (the fixtures filter already excludes `fixtures/`).

**Acceptance Test:** `bash tests/worktree/run.sh` records all assertions PASS (one possible SKIP on a flock-less host). `./scripts/gate_fast.sh` auto-discovers the suite; total PASS climbs from 163 (v1.3) to ~170. No `/tmp` residue after the run.

### Change 7: docs + closeout + per-project adoption runbook

**Problem:** The feature needs a plain-English how-to a human can follow, the standard doc updates, and a runbook for turning it on in each of the four projects (which happens in their own sessions, post-merge).

**File:** `docs/CONCURRENT-DEV.md` (new) + `README.md` / `ROADMAP.md` / `planning.md` / `tasks/lessons.md` (closeout, handled by `/code`'s doc step)

**Implementation:**

`docs/CONCURRENT-DEV.md` — written in plain language per the new [CLAUDE.md](CLAUDE.md) "Plain Language" rule. Cover:

- The problem in one paragraph (two chats, one folder, they trip over each other).
- How to turn it on for a project: commit a `.claude/worktree-deps` file listing the heavy ignored paths; make sure `.claude/worktree-deps` actually lists what the app needs to run (`.env`, `node_modules`, build caches); ensure `.claude/` is gitignored.
- What changes after that: `/code` starts in `.claude/worktrees/<branch>`, deps linked; `/merge` cleans the worktree up; two chats never share files; `/gate fast` takes turns on the backend.
- The take-turns adoption step for the gate: `source ~/.claude/worktree/gate-lock.sh` and wrap the backend restart in `with_gate_lock`.
- The honest limit: this does NOT let two chats run the app live at the same time. They share one backend and one database; the lock makes them take turns. If you ever need two live apps at once, that's a bigger per-project change (own ports + own database) and is out of scope here.

Closeout doc updates (`/code` final step, same commit):

- `README.md` — add `worktree` to the install-categories list ([README.md:38](README.md#L38)) and the script line if relevant.
- `ROADMAP.md` — add the `v1.4: Concurrent Dev Isolation` entry with ship date and summary.
- `planning.md` — update "Current state" / "In flight" / "Recently shipped".
- `tasks/lessons.md` — capture anything non-obvious from /code.

**Per-project adoption runbook (post-merge, each project's OWN session — NOT this repo):** for each of Kermit, Kermit PA, Keystone, SQRL, in that project's working directory:

1. Create `.claude/worktree-deps` listing that project's heavy ignored paths.
2. Confirm `.claude/` (or `.claude/worktrees/`) is in the project's `.gitignore`.
3. In the project's `scripts/gate_fast.sh` (or equivalent), `source ~/.claude/worktree/gate-lock.sh` and wrap the backend stop/restart in `with_gate_lock`.
4. Verify: open two chats, run `/code` in each, confirm two separate `.claude/worktrees/...` dirs and that the app runs in each.

This runbook lives in `docs/CONCURRENT-DEV.md` so each project's session can follow it. dev-platform does NOT write these files into the projects ([CLAUDE.md](CLAUDE.md) cross-project rule).

**Acceptance Test:** `docs/CONCURRENT-DEV.md` exists, reads in plain language, and covers turn-on, behavior change, gate adoption, and the honest limit. README/ROADMAP/planning updated. `gh api repos/teelr/dev-platform/milestones` shows a `v1.4:` milestone. Markdown lints clean.

---

## What NOT to Do

- **Do not hand-roll `git worktree add` in `/code`.** Use the `EnterWorktree` tool — it re-roots the session so edits land in the worktree. Raw `git worktree add` leaves the session in the main checkout and every edit would need an absolute path into the worktree. Reuse the harness primitive ([CLAUDE.md](CLAUDE.md) reuse-first / official-SDK rule).
- **Do not build per-chat ports or per-chat databases.** Rich confirmed he does not need two live apps at once. Take-turns (the lock) is the agreed scope. Per-chat stacks are explicitly out of scope.
- **Do not make worktree mode the unconditional default.** It is opt-in via `.claude/worktree-deps`. dev-platform itself and server-less projects keep `git checkout -b`. A blanket default would add pure overhead to projects with no shared services.
- **Do not write `.claude/worktree-deps`, gitignore entries, or gate edits into Kermit / Kermit PA / Keystone / SQRL from this repo.** That is cross-project writing, forbidden by [CLAUDE.md](CLAUDE.md). dev-platform ships the mechanism and the runbook; each project turns it on from its own session.
- **Do not use `ExitWorktree action: "remove"` in `/merge`.** After a squash-merge the branch's commits aren't present as commits, so `remove` hits the unmerged-changes refusal. Use `keep`, return to the main checkout, then `git worktree remove --force` + `git branch -D`.
- **Do not wrap the whole gate in `with_gate_lock`.** Only the shared-state step (backend restart; in dev-platform's own gate, the live `~/.claude/` verify) needs the lock. Worktree-local checks (taxonomy, syntax, suite runners) must stay parallel — locking them would serialize unrelated work and kill the point of worktrees.
- **Do not let `link-deps.sh` copy instead of symlink.** Copying `node_modules` per worktree is slow and wastes disk; symlinks share the one install. Copying `.env` would also let the copies drift.
- **Do not fail `link-deps.sh` on a missing source path.** A project may not have run `npm install` yet. Warn and continue — the worktree is still usable for code that doesn't need that dep.
- **Do not bundle the unrelated `settings/settings.json` permission-list drift into this work.** It is pre-existing and tracked separately ([planning.md](planning.md)).

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `shell/worktree/README.md` | New | Manifest format + opt-in rule + gate-lock adoption note |
| `shell/worktree/link-deps.sh` | New | Symlink manifest deps into a worktree (executable) |
| `shell/worktree/gate-lock.sh` | New | Sourceable take-turns lock (`with_gate_lock`) |
| `commands/code.md` | Modify | Step 1 worktree-vs-branch mode; add `EnterWorktree` to allowed-tools |
| `commands/merge.md` | Modify | Worktree-aware teardown; add `ExitWorktree` to allowed-tools |
| `scripts/install.sh` | Modify | `install_worktree()` + `worktree` category + usage |
| `scripts/verify.sh` | Modify | `Verifying worktree...` symlink-health block |
| `scripts/uninstall.sh` | Verify | Likely no change (depth-2 symlink sweep already covers it) |
| `scripts/gate_fast.sh` | Modify | Source the lock; wrap the live `~/.claude/` verify in `with_gate_lock` |
| `tests/worktree/run.sh` | New | ~7-assertion suite (link-deps + lock + install) |
| `tests/worktree/fixtures/*` | New | Manifest + mock dirs for the suite |
| `.gitignore` | Verify | Confirm `shell/worktree/*` + `tests/worktree/**` are allow-listed |
| `docs/CONCURRENT-DEV.md` | New | Plain-English how-to + per-project adoption runbook |
| `README.md` | Modify | Add `worktree` install category |
| `ROADMAP.md` | Modify | v1.4 entry |
| `planning.md` | Modify | Current state + recently shipped |
| `tasks/lessons.md` | Modify | Any new lessons |
| `tasks/dev-platform-concurrent-dev-isolation-spec.md` | (this file) | Spec |

## Implementation Order

One branch (`v1.4/phase-1-...` etc. per the per-Spec-Phase strategy, or a single branch if it stays under ~200 LOC). Order:

1. **Change 1** — `shell/worktree/README.md`. Defines the contract everything else references.
2. **Change 2** — `link-deps.sh` + install/verify wiring. Verify `git check-ignore` and an install round-trip first.
3. **Change 3** — `commands/code.md` Step 1 rewrite. Depends on Change 2's deployed script path.
4. **Change 4** — `commands/merge.md` teardown.
5. **Change 5** — `gate-lock.sh` + dev-platform gate adoption.
6. **Change 6** — `tests/worktree/` suite. Run it; confirm PASS count rises.
7. **Change 7** — docs + closeout. Docs land in the same commit as the code.

Phases 1-2 are tooling; Phase 3 is tests + docs. If split across branches per the per-Spec-Phase strategy, Phase 1 (Changes 1-3) is one PR, Phase 2 (Changes 4-5) a second, Phase 3 (Changes 6-7) folds into whichever lands last so the gate count stays honest.

## Verification Checklist

- [ ] `bash -n` passes on `link-deps.sh`, `gate-lock.sh`, and every modified script.
- [ ] `git check-ignore -v` confirms `shell/worktree/*` and `tests/worktree/**` are tracked, not ignored.
- [ ] `commands/code.md` and `commands/merge.md` pass the command-frontmatter validator; `allowed-tools` lists `EnterWorktree` / `ExitWorktree` respectively.
- [ ] In branch mode (no `.claude/worktree-deps`), `/code` Step 1 and `/merge` Step 5 behave exactly as before.
- [ ] `link-deps.sh`: links present paths as symlinks, warns + continues on missing, ignores comments/blanks, no-ops without a manifest.
- [ ] `with_gate_lock` serializes two concurrent calls (or records SKIP where `flock` is absent).
- [ ] `./scripts/install.sh worktree` deploys both scripts; `verify.sh` healthy; `uninstall.sh` removes them.
- [ ] `./scripts/gate_fast.sh` passes with the lock wrapping the verify step; total PASS rises from 163 toward ~170.
- [ ] `tests/worktree/run.sh` all PASS; no `/tmp` residue.
- [ ] `docs/CONCURRENT-DEV.md` is plain-English and states the honest limit (no two live apps at once).
- [ ] No file under `projects/` modified. Per-project adoption is a documented post-merge runbook, run from each project's own session.
- [ ] v1.4 GitHub milestone exists.
- [ ] `/security-review` NOT required — no auth, credentials, external input, or new endpoints. (`link-deps.sh` only symlinks paths from a repo-local manifest; no external input.)
