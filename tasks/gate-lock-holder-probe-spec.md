# v1.47: Gate Lock Holder Probe

## Coding Specification for Implementation

## Design Philosophy

Issue #140 (consumer: kermit-v3) asks for a public, read-only function in `shell/worktree/gate-lock.sh` that answers "is a gate running right now", so a consumer does not parse `gate.lock.holder` itself. kermit-v3's backend health check needs it: on 2026-10-31 at 20:49:51 two `/gate fast` runs taking turns stopped the dev backend on purpose and the check raised a false alert (per the issue). kermit-v3 currently carries its own copy, `gate_holder()` at `projects/kermit-v3/scripts/check_backend_health.sh:55-71` (read-only look; verified with `sed -n 36,80p`). It repeats the "is the pid alive" rule that `_gate_lock_describe_holder` (`shell/worktree/gate-lock.sh:63-74`) already has, and it depends on a note format that is private to this helper. Two copies of that parsing can drift apart; the point of this phase is one copy, owned here.

The function is `gate_lock_holder_alive [repo-dir] [max-age-minutes]`. It prints `pid=N label=L started=S` and returns 0 when the holder note names a live pid and is not older than the limit; it returns 1 otherwise. It never opens, takes or probes `gate.lock`: it only reads `gate.lock.holder`. A caller that only wants to know must never delay a gate, and a gate must never delay the caller. It takes the repo directory as an argument because a systemd unit has no git working directory, which the existing private `_gate_lockfile` assumes (it runs `git rev-parse --git-common-dir` in the current directory, line 28).

Per the Derivation Sweep rule in `CLAUDE.md`, the note-parsing is extracted into one shared helper that both `_gate_lock_describe_holder` and the new function call, instead of adding a third copy of the `sed` patterns. `_gate_lock_describe_holder`'s behavior does not change (it still degrades to "another session" and still reports `unknown` for a missing `started=`); existing checks 6d, 6e and 6h pin that.

No change to how gates take or release the lock, and nothing in `projects/` is edited from this session (cross-project rule). kermit-v3 switches to the helper in its own session after this ships; until then its copy stays. `~/.claude/worktree/gate-lock.sh` is a symlink to the main checkout's file (verified: `ls -l ~/.claude/worktree/` shows `gate-lock.sh -> /home/rich/dev/shell/worktree/gate-lock.sh`), so the function is live to consumers at merge with no `install.sh` step.

Single Phase, single PR: one shell file, one test block, three doc touches.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `shell/worktree/gate-lock.sh` additions | Bash | The file is a sourced Bash helper and the function must be callable from consumers' Bash scripts (including a systemd-run check). Not network, compute or AI work, so the matrix does not apply. |
| `tests/worktree/run.sh` additions | Bash | Extends the existing suite in its established language. |

## Overview

Phase 1: Read-only holder probe

1. Change 1: Shared holder-note parser, repo-dir-aware lockfile path, and `gate_lock_holder_alive`
2. Change 2: Tests, with mutation proof
3. Change 3: Docs (file header, `shell/worktree/README.md`, `docs/CONCURRENT-DEV.md`)

---

## Phase 1: Read-only holder probe

### Change 1: `gate_lock_holder_alive` and the shared parser

**Problem:** There is no public way to ask "is a gate running" without parsing a private file format, and `_gate_lockfile` only works from inside a git working directory.

**File:** `shell/worktree/gate-lock.sh` (existing, 142 lines; `_gate_lockfile` at 26-32, `_gate_lock_holderfile` at 34-36, `_gate_lock_describe_holder` at 63-74)

**Implementation:**

1. `_gate_lockfile [dir]` and `_gate_lock_holderfile [dir]` take an optional directory. With no argument they behave exactly as today (current directory's git). With one, run git as `git -C "${dir}" rev-parse --git-common-dir`. A relative result is relative to `dir`, not the caller's cwd, so resolve it with `cd "${dir}"` first (the current code does `cd "${common}"` against the caller's cwd, line 31, which is wrong once `dir` is given). Keep the `/tmp` fallback when `dir` is not in a git repo, so the probe and the acquire agree on the path in every case. Do not use `--path-format=absolute` (needs a newer git than the file otherwise assumes; this host has git 2.43.0 but the file's other consumers are not known).
2. Add `_gate_lock_holder_field <holderfile> <pid|started|label>` that prints one field, using the exact `sed` patterns now in `_gate_lock_describe_holder` and in kermit-v3's copy: `pid` from `^pid=\([0-9]*\).*`, `started` from `.*started=\([^ ]*\).*`, `label` from `.*label=\(.*\)$` (label is last on the line and may contain spaces; `_gate_lock_stamp` writes `pid=%s started=%s label=%s`, line 42). Prints nothing when the file is unreadable or the field is absent.
3. Rewrite `_gate_lock_describe_holder` (lines 63-74) to call `_gate_lock_holder_field` for `pid` and `started`. Same output in every case: `pid N (since S)` for a live pid (`unknown` when `started` is empty), `another session` otherwise.
4. Add the public function, placed after `_gate_lock_describe_holder`:

   `gate_lock_holder_alive [repo-dir] [max-age-minutes]`
   - `repo-dir` defaults to the current directory. `max-age-minutes` defaults to 120 (kermit-v3's value; its `/gate full` browser tier takes about 45 minutes, per the issue). An empty-string argument counts as omitted.
   - A `max-age-minutes` that is not a non-negative integer prints `gate_lock_holder_alive: max-age-minutes must be a whole number` to stderr and returns 2. (A caller treating any nonzero as "no gate" fails safe: the alert fires rather than being silenced.)
   - Read only `_gate_lock_holderfile "${repo_dir}"`. Return 1 when it is missing or unreadable.
   - Return 1 when `pid` is empty or `kill -0 "${pid}"` fails (a killed gate leaves the note behind; flock released when it died).
   - Return 1 when `started` is empty. Required explicitly: `date -d ""` means midnight today, so an empty value would count as recent between 00:00 and 02:00 (verified on this host: `date -d "" +%F' '%T` prints today at `00:00:00`).
   - Return 1 when `date -d "${started}" +%s` fails (verified: `date -d garbage` exits non-zero with `invalid date`).
   - Return 1 when `now - started_epoch` is greater than `max-age-minutes * 60`. A note stamped in the future (negative age) is not older than the limit and passes, matching kermit-v3's copy; this is deliberate and covered by a test.
   - Otherwise print `pid=N label=L started=S` (label `unknown` when empty) on stdout and return 0.
   - Must not: open `gate.lock` (no `exec 9>`, no `: >>"${lf}"`, no `flock`), create any file, or write to the holder file. Use `local` for every variable and do not touch fd 9, `_GATE_LOCK_HELD` or any other state, so calling it from inside a gate that holds the lock is harmless.
   - Document in a comment: the pid check is a hint, not proof (a reused pid after a gate died would look alive until the age limit expires), the same limit `_gate_lock_describe_holder` already documents at lines 21-24; and `kill -0` fails for a pid owned by another user, so this reports "no gate" for another user's gate (dev-platform's box is single-user).

**Acceptance Test:** the Change 2 checks pass; `bash -n shell/worktree/gate-lock.sh` is clean; the 6b-6j checks that already exist pass unmodified.

---

### Change 2: Tests, with mutation proof

**Problem:** The function's value is its edge cases, each of which is a silent wrong answer if broken.

**File:** `tests/worktree/run.sh` (existing). Add a new block after the existing `flock` block (the block starting near line 215 that ends after check 6j; read the file to find the closing `fi` rather than trusting this number). Use `record_pass`/`record_fail`/`record_skip` like the neighbours, number the checks continuing the file's existing sequence (read the last one first), and register the new tmp dir in the existing `trap ... EXIT` line. The holder note is written by hand with `printf`, in the exact format `_gate_lock_stamp` writes.

Setup: `git init` a scratch repo; `HOLDER` is `<repo>/.git/gate.lock.holder`; start `sleep 60 &` for a live pid and clean it up; use `999999` for a dead pid; compute timestamps with `date -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S` etc. Call the function from `/` (a non-git cwd) with the repo path as an argument, via `bash -c 'source ...; gate_lock_holder_alive ...'` so no test state leaks.

Checks:

1. Live pid, recent `started`, label `gate fast` (with a space) -> exit 0, stdout is exactly `pid=<pid> label=gate fast started=<ts>`.
2. Dead pid -> exit 1, no stdout.
3. Missing holder file -> exit 1.
4. Empty `started=` (`pid=<live> started= label=x`) -> exit 1. Run it with a `now` that makes the bug visible: this must pass at any time of day, so assert via the function's result, not the clock.
5. Unparseable `started=garbage` -> exit 1.
6. `started` older than the limit (3 hours ago, default 120) -> exit 1; the same note with `max-age-minutes` 240 -> exit 0.
7. `started` in the future (1 hour ahead) -> exit 0.
8. Non-numeric `max-age-minutes` (`abc`, `-5`, `1.5`) -> exit 2 and a stderr message; stdout empty.
9. Does not touch the lock: with no `gate.lock` present, a successful probe leaves `gate.lock` absent (`[[ ! -e ... ]]`). With a real `gate_lock_acquire` held in a background job (reuse the 6c technique), the probe returns exit 0 naming that pid in under 2 seconds (measure with `SECONDS`; a probe that waited for the lock would take as long as the hold) and the lock is still held afterward (a second `flock -n` on the file fails).
10. Linked worktree: `git worktree add` a second worktree of the scratch repo, pass the worktree path as `repo-dir` -> same answer as the main path (shared common dir).
11. No argument, run from inside the scratch repo -> same answer as passing its path.
12. `repo-dir` that is not a git repo -> exit 1 and nothing created under it.
13. Regression: `_gate_lock_describe_holder` still prints `pid N (since S)` for a live holder and `another session` for a dead one (calls the private helper directly; checks 6d/6e/6h cover the end-to-end path).

**Mutation proof (mandatory):** in the scratchpad, copy `gate-lock.sh`, apply each mutation, point `GATE_LOCK` at the copy, and show the named checks fail; restore after each. Mutations: (a) drop the `kill -0` test -> check 2 fails; (b) drop the empty-`started` guard -> check 4 fails (note: on this host before 02:00 only; so make check 4 independent of clock time by also asserting the guard through the function's code path, e.g. by a `date` shim earlier in `PATH` that returns a fixed epoch, and show that check failing under the mutation); (c) drop the age comparison -> check 6 fails; (d) make the probe do `: >>"${lf}"` -> check 9 fails; (e) make it ignore `repo-dir` (use cwd) -> checks 10 and 12 fail. Record the results in the shipped file.

**Acceptance Test:** `bash tests/worktree/run.sh` all PASS or SKIP; `./scripts/gate_fast.sh` PASS.

---

### Change 3: Docs

**Files:**

- `shell/worktree/gate-lock.sh` header (lines 1-25): add the probe as a third public shape, one short paragraph, and note it is read-only and never touches `gate.lock`.
- `shell/worktree/README.md` (the "Three public functions" table near line 44): add the row and change "Three" to "Four". Add the arguments, the default limit of 120 minutes, the exit codes (0 alive, 1 not, 2 bad argument), and one line on the three ignored-note cases (dead pid, empty or unparseable `started`, older than the limit).
- `docs/CONCURRENT-DEV.md` (section 3, "Make the gate take turns", lines 48-62): a short paragraph for a monitor or cron job that must not alert during a gate, with a three-line `source ~/.claude/worktree/gate-lock.sh; gate_lock_holder_alive <repo> <minutes>` example and the sentence that it never waits on the lock.
- `/code`'s doc step: new `tasks/shipped/<date>-v1.47-gate-lock-holder-probe.md`, ROADMAP entry for v1.47 (list form, matching v1.46's shape). Do not edit `projects/kermit-v3`.

**Acceptance Test:** `grep -n "gate_lock_holder_alive" shell/worktree/README.md docs/CONCURRENT-DEV.md shell/worktree/gate-lock.sh` shows all three; markdown lint clean; `./scripts/gate_fast.sh` PASS.

---

## What NOT to Do

- Do not open, truncate, create or lock `gate.lock` from the probe, even to "check it is writable" the way `gate_lock_acquire` does (lines 94-99). That probe is what makes acquire safe; here it would make the check able to delay a gate, or create the file.
- Do not add a third copy of the `sed` patterns. Both `_gate_lock_describe_holder` and the new function go through `_gate_lock_holder_field`.
- Do not change `_gate_lockfile`'s no-argument behavior. Acquire, release and `with_gate_lock` all depend on it.
- Do not use fd 9, `_GATE_LOCK_HELD`, `exec`, or global variables in the probe.
- Do not treat an empty or unparseable `started=` as recent.
- Do not edit `projects/kermit-v3` or comment on its PRs from this session. After merge, reply on issue #140 only.
- Do not change how gates take or release the lock (explicitly not requested in the issue).

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `shell/worktree/gate-lock.sh` | Modify | Optional dir argument on the path helpers, shared field parser, `gate_lock_holder_alive` |
| `tests/worktree/run.sh` | Modify | 13 new checks, mutation-proven |
| `shell/worktree/README.md` | Modify | Function table and contract |
| `docs/CONCURRENT-DEV.md` | Modify | Monitor example |
| `ROADMAP.md` | Modify | v1.47 entry |
| `tasks/shipped/<date>-v1.47-gate-lock-holder-probe.md` | New | Shipped record (written by `/code`) |

## Implementation Order

1. Change 1 (the library).
2. Change 2 (tests, then mutation proof).
3. Change 3 (docs).

## Verification Checklist

- [ ] Live, recent holder -> exit 0 and the exact `pid=N label=L started=S` line
- [ ] Dead pid, missing note, empty `started`, unparseable `started`, too old -> exit 1
- [ ] Bad `max-age-minutes` -> exit 2
- [ ] The probe never creates or waits on `gate.lock`, including while a real gate holds it
- [ ] Works from a non-git cwd and from a linked worktree via `repo-dir`
- [ ] `_gate_lock_describe_holder` output unchanged; existing worktree checks pass untouched
- [ ] Each new check shown failing under a mutated copy
- [ ] `./scripts/gate_fast.sh` PASS
- [ ] Not exercised: sourcing the file from an actual systemd unit. The file defines only functions (verified: no top-level statements outside function bodies), so sourcing has no side effects, but no unit was run.

## Scope honesty (for the shipped file)

- kermit-v3 still carries its own `gate_holder()` until its session switches to this helper; nothing here changes that.
- The pid check is a hint: a gate killed uncleanly whose pid is reused by an unrelated process reads as alive until the age limit passes.
- `kill -0` returns false for another user's pid, so a gate run by a different user reads as "no gate".
