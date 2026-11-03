# v1.48: Dependency Install Notice

## Coding Specification for Implementation

## Design Philosophy

Issue #151 (filed from kermit-v3) describes a gap in worktree mode. Every worktree symlinks `frontend/node_modules` back to the main checkout (`shell/worktree/link-deps.sh`, driven by the project's `.claude/worktree-deps`). So a dependency change that merges to `main` is not installed anywhere until someone runs `npm install` in the main checkout, and nothing in the workflow says so. On kermit-v3 that went unnoticed for a week; the install that finally ran replaced Next.js on disk under a running dev server, and every page returned 500 until the server was restarted (per the issue; read from the issue text, not re-verified here).

The user chose the narrow fix: when a merge changes a dependency file beside a dependency directory the project links, `/merge` prints a notice naming the directory and the exact install command for the main checkout, and says to restart the dev server afterwards. It does not install and it does not restart. Reasons: the incident's damage came from an install running under a live server, and a restart command is per-project and does not exist in any manifest. The issue's second ask (a gate check that fails when the lock file is newer than `node_modules`) is out of scope here; it belongs in each project's own `gate_fast.sh`, and this phase's reply on the issue says so.

The detection is a read-only report script, `scripts/check-dep-install-needed.sh`, called from `commands/merge.md` Step 6 by absolute path, the same shape as `scripts/check-concurrent-sessions.sh` called from `commands/dev.md:52`. Logic stays out of the command file (the command guard refuses compound, variable-bearing commands in a worktree session; see `CLAUDE.md`, "Commands a Worktree Session Runs Must Be Plain Single Commands"), and the script is testable offline with fixture repos. A notice must never fail a merge, so it exits 0 unless called with a bad argument.

Which directories count is read from data, not hard-coded per project: a manifest entry whose last path segment is `node_modules` names a dependency directory, and the files beside it (`package.json`, `package-lock.json`, `npm-shrinkwrap.json`, `yarn.lock`, `pnpm-lock.yaml`) are the dependency files. Verified against the fleet with `for p in projects/*/; do grep -v '^\s*#' "$p.claude/worktree-deps"; done`: kermit-pa, kermit-v3 and keystone list `frontend/node_modules`; SQRL lists `node_modules`, `server/node_modules` and `dispatch/node_modules`; the kermit harness lists only `.env`. Lock files seen by `ls`: `frontend/package-lock.json` in kermit-pa, kermit-v3 and keystone; `package-lock.json` at SQRL's root; `package-lock.json` and `yarn.lock` both in `SQRL/server`; only `package.json` in `SQRL/dispatch`. dev-platform's own manifest has no live entries (`grep -v '^\s*#' .claude/worktree-deps | grep -v '^\s*$' | wc -l` printed 0), so it stays silent here.

Single Phase, single PR: one new script, one new test suite, one command-file edit, three doc touches.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/check-dep-install-needed.sh` | Bash | Thin glue over `git diff-tree` and a manifest read; sibling report scripts (`check-concurrent-sessions.sh`, `check-phase-milestones.sh`) are Bash. Not network, compute or AI work, so the matrix does not apply. |
| `tests/dep-install-notice/run.sh` | Bash | Matches every other `tests/<suite>/run.sh`. |

## Overview

Phase 1: Dependency install notice

1. Change 1: `scripts/check-dep-install-needed.sh`
2. Change 2: Tests, with mutation proof
3. Change 3: Wire into `/merge` Step 6 and update docs

---

## Phase 1: Dependency install notice

### Change 1: The notice script

**Problem:** Nothing tells a person that a merge left the shared `node_modules` out of date.

**File:** `scripts/check-dep-install-needed.sh` (new, executable bit set like its siblings; verified with `ls -l scripts/check-concurrent-sessions.sh` showing `-rwxrwxr-x`)

**Implementation:**

1. Header comment in the style of `scripts/check-concurrent-sessions.sh:1-43`: what it reports, that it is read-only and never installs or restarts anything, that it is a report and not a gate check (so it is NOT wired into `gate_fast.sh`; only its test suite is gate-discovered), usage, and exit codes.
2. Usage: `bash /home/rich/dev/scripts/check-dep-install-needed.sh [commit]`. `commit` defaults to `HEAD`. `--help` prints usage and exits 0. More than one argument, or an unknown `-` option, prints usage to stderr and exits 2. Everything else exits 0.
3. Resolve the project: `git rev-parse --show-toplevel` from the current directory. If that fails (not a git repo), exit 0 silently. Then `source` `scripts/lib/main_checkout.sh` (resolve the lib path from the script's own location, `$(dirname "${BASH_SOURCE[0]}")/lib/main_checkout.sh`, the way `scripts/check_env_leak.sh` does; confirm with `grep -n "main_checkout.sh" scripts/check_env_leak.sh`) and call `resolve_main_checkout "<toplevel>"` to get `MAIN`, the main checkout root, so the printed install command points at the checkout that owns `node_modules` even when run from a worktree. Do not write a fifth inline copy of the common-dir derivation (Derivation Sweep rule in `CLAUDE.md`; `scripts/lib/main_checkout.sh:36-53` explains why four others must stay inline and this one can share).
4. Read the manifest `<toplevel>/.claude/worktree-deps`. Missing -> exit 0 silently. Parse with the same rules as `shell/worktree/link-deps.sh:99-103`: strip from the first `#`, trim leading and trailing whitespace, skip empty lines. Do NOT drop a trailing `/`: `link-deps.sh` does not, and an entry written `frontend/node_modules/` fails to link there (verified by running it: `ln: failed to create symbolic link ... No such file or directory`, while it still printed `linked`), so such an entry names a directory that was never linked. This is a deliberate inline copy: `link-deps.sh` runs from the deployed `~/.claude/worktree/` path where `scripts/lib/` does not exist, so it cannot share. Say that in a comment, name `link-deps.sh` as the source of truth, and pin the two together with the parity test in Change 2.
5. Keep entries whose last path segment is exactly `node_modules`. Their directory is the entry minus that segment, with `.` for an entry that is just `node_modules`.
6. List the files changed by the commit: `git diff-tree --no-commit-id --name-only -r --root <commit>` (verified to list files for a one-commit diff; `--root` makes a first commit work). For each dependency directory, the changed dependency files are those of `package.json`, `package-lock.json`, `npm-shrinkwrap.json`, `yarn.lock`, `pnpm-lock.yaml` that appear in that list at `<dir>/<file>` (or `<file>` for `.`). An invalid `commit` makes `git diff-tree` fail: print nothing and exit 0.
7. If no dependency directory has a changed dependency file, print nothing and exit 0.
8. Otherwise print, each line prefixed `[dep-notice] `:
   - `This merge changed dependency files beside a linked node_modules:`
   - one line per directory: `  <dir>/: <changed files, comma separated>` (`.` shown as `(repo root)`).
   - `Worktrees share the main checkout's node_modules, so nothing is installed until you run, in the main checkout:`
   - one line per directory with the install command and the absolute path `${MAIN}/<dir>` (`${MAIN}` for the root): `npm --prefix <path> install` when `package-lock.json` or `npm-shrinkwrap.json` exists in that directory in `MAIN`; else `pnpm --dir <path> install` when `pnpm-lock.yaml` exists; else `yarn --cwd <path> install` when `yarn.lock` exists; else `npm --prefix <path> install`. (`SQRL/server` has both `package-lock.json` and `yarn.lock`; npm wins by this order. Whether SQRL actually uses npm there is unverified.)
   - `Then restart the dev server. Installing under a running server swaps packages beneath it (kermit-v3, 2026-11-01: Next.js was replaced on disk while the server ran and every page returned 500 until restart).`
9. Never run `npm`, `pnpm`, `yarn`, or any install; never write a file; never signal a process.

**Acceptance Test:** the Change 2 checks pass; `bash -n scripts/check-dep-install-needed.sh` is clean; `bash scripts/check-dep-install-needed.sh` in this worktree prints nothing (dev-platform's manifest has no live entries).

---

### Change 2: Tests, with mutation proof

**Problem:** Every silent case is a wrong answer if broken, and the parser has a twin in `link-deps.sh` that can drift.

**File:** `tests/dep-install-notice/run.sh` (new, executable; auto-discovered by `scripts/gate_fast.sh`, which runs every executable `tests/<suite>/*.sh`). Follow `tests/worktree/run.sh` for structure: source `tests/helpers/assert.sh`, use `record_pass`/`record_fail`/`record_skip`, never `exit`, own temp dir removed at the end.

Fixture builder: a function that creates a temp git repo (`git init`, local `user.email`/`user.name`), writes `.claude/worktree-deps`, commits a baseline, then makes a second commit changing named files. All checks call the script from inside the fixture repo with `bash "${REPO}/scripts/check-dep-install-needed.sh"` and capture stdout, stderr and the exit code.

Checks (all exit 0 unless stated):

1. Manifest `frontend/node_modules`; second commit changes `frontend/package-lock.json` -> notice names `frontend/`, the file, `npm --prefix <abs path of the fixture>/frontend install`, and the word `restart`.
2. Same manifest; only `frontend/package.json` changes -> notice.
3. Same manifest; only `frontend/src/app.ts` changes -> output empty.
4. No `.claude/worktree-deps` file; `package-lock.json` changes -> output empty.
5. Comment-only manifest -> output empty.
6. Manifest lists only `.env`; `package-lock.json` changes -> output empty (a non-`node_modules` entry is not a dependency directory).
7. SQRL shape: manifest `node_modules`, `server/node_modules`, `dispatch/node_modules`; change only `server/package-lock.json` -> only `server/` named; change root `package-lock.json` and `dispatch/package.json` -> `(repo root)` and `dispatch/` named, `server/` not.
8. Install command choice: `pnpm-lock.yaml` only -> `pnpm --dir`; `yarn.lock` only -> `yarn --cwd`; both `package-lock.json` and `yarn.lock` -> `npm --prefix`; `package.json` with no lock file -> `npm --prefix`.
9. Messy manifest (comment line, inline trailing comment, indented entry, blank lines) -> the directories are still recognised. An entry written with a trailing slash (`dispatch/node_modules/`) is NOT recognised, matching `link-deps.sh`.
10. Parity with `link-deps.sh`: run `bash shell/worktree/link-deps.sh <fixture-as-main> <empty-worktree-dir>` on the messy manifest (create the listed directories first so nothing is skipped as missing) and assert that the set of `node_modules` symlinks that actually exist afterwards equals the set of directories the notice script recognised for the same manifest (include the trailing-slash entry: neither side may have it). This fails if either parser changes alone.
11. Commit argument: pass the SHA of the dependency commit when `HEAD` is a later unrelated commit -> notice; with no argument -> output empty.
12. First commit (no parent): script exits 0 without error output.
13. Not a git repo (run from a plain temp dir): output empty, exit 0.
14. Run from a linked worktree of the fixture (`git worktree add`): the printed install path is the main checkout's, not the worktree's.
15. Never installs: put a fake `npm`, `pnpm` and `yarn` first in `PATH` that append their name to a log file; after a run that printed a notice, the log is absent or empty.
16. Usage: `--help` exits 0 with text; an unknown option and two arguments each exit 2.

**Mutation proof (mandatory):** in the scratchpad, mutate the real script one change at a time, run `bash tests/dep-install-notice/run.sh`, show the named checks fail, restore from a saved copy, and finish with a `diff` against the original. Run mutations one per tool call, never in parallel (they share the file; see `tasks/lessons/2026-11-03-run-mutation-proofs-one-at-a-time.md`). Mutations: (a) drop the `node_modules` filter -> check 6 fails; (b) print the notice unconditionally -> checks 3, 4, 5 fail; (c) drop comment stripping -> checks 9 and 10 fail; (d) use the toplevel instead of `MAIN` for the path -> check 14 fails; (e) actually call `npm` -> check 15 fails; (f) ignore the `commit` argument -> check 11 fails. Record results in the shipped file.

**Acceptance Test:** `bash tests/dep-install-notice/run.sh` all PASS; `./scripts/gate_fast.sh` PASS.

---

### Change 3: Wire into `/merge` and update docs

**Files:**

- `commands/merge.md` Step 6 (`## Step 6: Report the merge`, currently line 171): add a fourth item to the list under "Print:" telling the agent to run `bash /home/rich/dev/scripts/check-dep-install-needed.sh` (a plain single command, no arguments, no variables) and include its output verbatim in the report when it prints anything, and to say nothing about it when it prints nothing. State that it only reports and never installs or restarts anything, and that it covers this merge's commit only (a `git pull` that brought in several commits is not scanned back further). Put it in Step 6, not Step 7, so it runs on every merge without renumbering the sub-steps other text refers to by number. Do not touch Steps 1-5 or Step 7.
- `docs/CONCURRENT-DEV.md`: a short subsection after the "Make the gate take turns" section: dependencies are shared too, what the notice looks like, that it only reports, and that a project wanting a hard failure when its lock file is newer than `node_modules` adds that to its own `gate_fast.sh` (the issue's second ask, deliberately not done here).
- `shell/worktree/README.md`: one sentence in the `link-deps.sh` entry that an entry named `node_modules` is also what `/merge` watches for dependency-file changes.
- `tests/README.md` suite layout block: add `dep-install-notice/run.sh`.
- `/code`'s doc step: new `tasks/shipped/<date>-v1.48-dependency-install-notice.md`, a `ROADMAP.md` entry for v1.48 (list form, matching v1.47's shape), and a lesson file only if one is earned. Do not edit anything under `projects/`.

**Acceptance Test:** `grep -n "check-dep-install-needed" commands/merge.md docs/CONCURRENT-DEV.md tests/README.md` shows all three; `tests/commands/frontmatter.sh` passes (it validates the live `commands/*.md`); `./scripts/gate_fast.sh` PASS. `~/.claude/commands/merge.md` is a symlink to `/home/rich/dev/commands/merge.md` (verified with `ls -l`), so the new step is live at merge with no install step.

---

## What NOT to Do

- Do not run `npm install`, `pnpm`, `yarn` or any restart from the script or from `/merge`. Notice only; that was the decision, and the install-under-a-live-server step is what caused the incident.
- Do not add a gate check or a "lock file newer than node_modules" script. That is the issue's second ask and is out of scope.
- Do not put detection logic in `commands/merge.md`. One plain command line only.
- Do not add a fifth inline copy of the main-checkout derivation; source `scripts/lib/main_checkout.sh`.
- Do not hard-code project names, directories or package managers beyond the five dependency file names; read the manifest.
- Do not renumber Step 7's sub-steps.
- Do not edit `projects/` or comment on kermit-v3's side from this session. After merge, reply on issue #151 only.
- Do not make the script exit non-zero for anything but a usage error; a notice must never fail a merge.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/check-dep-install-needed.sh` | New | Read-only notice script |
| `tests/dep-install-notice/run.sh` | New | 16 checks, mutation-proven |
| `commands/merge.md` | Modify | Step 6 runs the script and prints its output |
| `docs/CONCURRENT-DEV.md` | Modify | Shared dependencies subsection |
| `shell/worktree/README.md` | Modify | One sentence on `node_modules` entries |
| `tests/README.md` | Modify | Suite layout line |
| `ROADMAP.md` | Modify | v1.48 entry |
| `tasks/shipped/<date>-v1.48-dependency-install-notice.md` | New | Shipped record (written by `/code`) |

## Implementation Order

1. Change 1 (script).
2. Change 2 (tests, then mutation proof, one mutation per call).
3. Change 3 (wiring and docs).

## Verification Checklist

- [ ] A changed lock file or `package.json` beside a listed `node_modules` prints the notice with the right directory, files, install command and restart line
- [ ] Unrelated changes, no manifest, comment-only manifest, and non-`node_modules` entries print nothing
- [ ] The install path is the main checkout's even when run from a linked worktree
- [ ] The script never installs, restarts, writes or signals anything (fake package managers log nothing)
- [ ] Manifest parsing agrees with `link-deps.sh` on a messy manifest
- [ ] Exit 0 in every case except a usage error (2)
- [ ] Each new check shown failing under a mutated copy; script diffed identical afterwards
- [ ] `./scripts/gate_fast.sh` PASS
- [ ] Not exercised: a real `/merge` on a consumer project with a dependency change. The script is tested against fixture repos only.

## Scope honesty (for the shipped file)

- Whether kermit-pa, keystone or SQRL have drifted the way kermit-v3 did was not checked (the issue says the same). They list a `node_modules` in their manifests, so they now get the notice.
- The notice covers the merge commit only. Dependency changes that reached `main` through other merges, or through a `git pull` of several commits, are not scanned; detecting that is the out-of-scope drift check.
- `SQRL/server` has both `package-lock.json` and `yarn.lock`; the script prints the npm command by its lock-file order. Which one SQRL actually uses there is unverified.
- Python, Go and other dependency layouts are not detected; only the JavaScript file names above.
- Found while implementing: `shell/worktree/link-deps.sh` silently fails to link a manifest entry written with a trailing slash (`ln` errors, then the script still prints `linked` and counts it). It is a separate defect and is not fixed here; the notice script agrees with what `link-deps.sh` actually links.
