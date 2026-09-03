# v1.22: Gate Lock Visibility

## Coding Specification for Implementation

## Design Philosophy

Running three or four sessions on one project makes `/gate fast` feel broken. The
gate lock does its job — it stops two gate runs fighting over the same port — but
it does it in total silence. `flock 9` blocks with no output, so a session queued
behind another is indistinguishable from a session that has hung. That
uncertainty, not the waiting, is the actual cost.

**The obvious fix is wrong, and this spec deliberately does not do it.** The
instinct is to narrow the lock so gates overlap. But kermit-v3 and Keystone each
hold it across the whole stop→pytest→restart window for a real reason: the gate
*stops the backend* so pytest can bind the ports itself
(`kermit-v3/scripts/gate_fast.sh:172-194` frees 7000/7002;
`keystone/scripts/gate_fast.sh:108-120` does the same for 8400/8402). The
exclusive resource is the port, held for the entire test run. Narrowing the lock
there would let two pytest runs bind the same port and fail in a far more
confusing way than waiting does. Genuinely removing the serialization needs
per-session ports and per-session databases, which `docs/CONCURRENT-DEV.md`
already names as out of scope.

So the fix is visibility, not scope: say who holds the lock, say when the wait
starts, and say how long it took. A queued gate that announces itself is a queued
gate; the same gate in silence is a bug report.

The second finding is the one that shapes the API. **Both projects that wire the
lock bypass its only public function.** `with_gate_lock` wraps a single command,
which cannot express "hold this across the next 40 lines," so kermit-v3 and
Keystone each reached for the private `_gate_lockfile` and hand-rolled
`exec 9>… ; flock 9 … ; exec 9>&-`. The two blocks are byte-for-byte identical
down to the comments — copy-pasted between projects. That is the same shape
v1.21 promoted to the **Derivation Sweep** rule in `CLAUDE.md`: one rule
duplicated across places because no shared helper expressed it. Shipping
`gate_lock_acquire` / `gate_lock_release` gives them the thing they actually
needed, and gives every future adopter the visibility for free instead of
requiring each to reinvent it.

**Branching strategy:** single branch and single PR. Two small Spec Phases, and
the documentation Phase describes the API the first Phase adds, so they are not
independently shippable.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `shell/worktree/gate-lock.sh` | Bash | Extends the existing sourced helper. It must be `source`-able by each project's `gate_fast.sh`, which is Bash, and it manipulates file descriptors in the caller's shell — nothing else can do that. |
| `tests/worktree/run.sh` | Bash | Matches the existing per-suite runner contract. |

The Language Architecture Decision Matrix governs new services and components.
This spec adds neither — it is shell tooling for the development environment,
the same class as every other file under `shell/`.

## Overview

**Phase 1: The helper**

1. Change 1: `gate-lock.sh` — public `gate_lock_acquire`/`gate_lock_release`, holder stamping, and wait announcement
2. Change 2: `tests/worktree/run.sh` — assertions for contention messaging and the new API

**Phase 2: Documentation**

3. Change 3: document the API, why a wide lock is correct here, and the truncation trap

---

## Phase 1: The helper

### Change 1: `gate-lock.sh` — acquire/release, holder stamping, wait announcement

**Problem:** `flock 9` blocks silently, so a queued gate looks hung. And the only
public API (`with_gate_lock`, wrapping one command) cannot express the
hold-across-a-region shape both consumers actually need, so both bypassed it and
hand-rolled the same block.

**File:** `shell/worktree/gate-lock.sh` (existing file — `_gate_lockfile()` at
lines 13-19, `with_gate_lock()` at lines 21-31)

**Implementation:**

Keep `_gate_lockfile()` exactly as-is; both consumers call it today and the path
must not move. Keep `with_gate_lock` working, including its `flock`-absent
warning path. Add on top:

**1. A holder file, beside the lockfile — never the lockfile itself.**

```bash
_gate_lock_holderfile() { printf '%s.holder' "$(_gate_lockfile)"; }
```

This separation is load-bearing and needs a comment saying so: the lockfile is
opened with `9>`, and **the redirection truncates before `flock` is called**, so
a waiter opening the lockfile would erase the holder's own stamp before it ever
blocked. Holder metadata therefore lives in a sibling file that nothing opens
for writing until it already holds the lock.

**2. Stamp on acquire, clear on release.**

After the lock is held, write one line: the pid, the ISO timestamp, and an
optional caller-supplied label. On release, remove the file (best-effort, `|| true`).

A stale holder file is possible — `flock` releases automatically when a holder
dies, and the file outlives it. It is **advisory only**: the reader below must
never trust it as proof anything is running, and must degrade gracefully when
the recorded pid is gone.

**3. Announce contention, and only contention.**

The common single-session case must stay completely silent — a message on every
gate run is noise that trains people to ignore it. So: try non-blocking first,
and only if that fails say something.

```bash
_gate_lock_wait() {   # called with the lock fd already open as 9
    if flock -n 9; then
        return 0                       # uncontended — say nothing
    fi
    <read the holder file, best-effort>
    <print to stderr: waiting for another session's gate, naming the holder
     pid and when it started; if the holder file is missing or its pid is
     gone, say "held by another session" without inventing detail>
    <record start time>
    flock 9                            # now block
    <print to stderr: acquired after Ns>
}
```

All messages go to **stderr**, prefixed `[gate-lock]`, matching the existing
`flock`-absent warning at line 28.

**4. The public acquire/release pair** — the shape both consumers need:

```bash
gate_lock_acquire [label]   # opens fd 9 on the lockfile, waits (announcing), stamps
gate_lock_release           # clears the stamp, closes fd 9
```

`gate_lock_acquire` must use `exec 9>` so the descriptor persists in the caller's
shell after the function returns — that is the whole point, and it is why this
cannot be a subshell like `with_gate_lock`. Document fd **9** as reserved by this
helper; both consumers already hardcode it, so it must not change.

`gate_lock_release` must be safe to call when the lock was never acquired
(consumers call it from an early-exit path — see `keystone/scripts/gate_fast.sh:155`),
and safe to call twice.

**5. Route `with_gate_lock` through the same announcement** so its users get the
messaging too. It keeps its subshell form (`( ... ) 9>"${lf}"`), calling
`_gate_lock_wait` in place of its current bare `flock 9`.

**Acceptance Test:**

```bash
bash -n shell/worktree/gate-lock.sh

# Uncontended acquire must be silent.
out=$( . shell/worktree/gate-lock.sh; gate_lock_acquire test; gate_lock_release ) 2>&1
[ -z "${out}" ] && echo "silent when uncontended: OK"

# Contended acquire must announce and still serialize.
( . shell/worktree/gate-lock.sh; gate_lock_acquire holder; sleep 2; gate_lock_release ) &
sleep 0.3
( . shell/worktree/gate-lock.sh; gate_lock_acquire waiter; gate_lock_release ) 2>&1 \
    | grep -q "waiting" && echo "announces the wait: OK"
wait
```

---

### Change 2: `tests/worktree/run.sh` — cover contention and the new API

**Problem:** The suite proves `with_gate_lock` serializes (test 6, lines 87-108)
but nothing covers the new API or any of the messaging, and the silent-when-
uncontended property is exactly the kind of thing a later change breaks without
noticing.

**File:** `tests/worktree/run.sh` (existing — add after test 6 at line 108,
before the install-integration test at line 117)

**Implementation:**

Follow the existing contract: `set -uo pipefail`, `record_pass`/`record_fail`/
`record_skip` only, never `exit`. Reuse the suite's existing `flock`-absent
`record_skip` guard (line 110) for every new contention assertion — they all
need real `flock`. Run against a temp `GIT_COMMON_DIR`-backed lockfile the way
tests 5 and 6 already do, so the real repo's lockfile is never touched.

Assertions:

- `gate_lock_acquire` then `gate_lock_release` succeeds and produces **no output**
  when uncontended. This is the anti-noise guard.
- A second acquirer, while the first holds, prints `waiting` on stderr and names
  the holder's pid.
- The second acquirer still serializes — reuse test 6's existing no-interleave
  ordering technique rather than inventing a second one.
- On acquire after a wait, the "acquired after" line appears.
- The holder file exists while held, names the holder pid, and is gone after
  `gate_lock_release`.
- `gate_lock_release` without a prior acquire exits 0 (the early-exit path
  consumers rely on), and a second `gate_lock_release` is also a no-op.
- A stale holder file — one naming a pid that does not exist — still lets a
  waiter acquire, and its message does not claim a live holder.
- `with_gate_lock` still runs its command and still serializes (existing tests 5
  and 6 must keep passing unchanged — do not rewrite them).

**Acceptance Test:**

```bash
bash tests/worktree/run.sh     # all PASS, existing assertions unchanged
./scripts/gate_fast.sh         # 312 PASS today; expect ~320
```

---

## Phase 2: Documentation

### Change 3: document the API, the wide-lock rationale, and the truncation trap

**Problem:** Both consumers hand-rolled the acquire/release block because nothing
documented one, and `docs/CONCURRENT-DEV.md`'s setup section still shows only
`with_gate_lock`. Worse, the next person to look at a slow concurrent gate will
have the same instinct this spec started with — narrow the lock — and that is
actively wrong here.

**File:** `shell/worktree/README.md` (existing), `docs/CONCURRENT-DEV.md`
(existing — the "Make the gate take turns" step and the "How it's wired" list)

**Implementation:**

In `docs/CONCURRENT-DEV.md`'s "3. Make the gate take turns", show both shapes and
say when each applies: `with_gate_lock <cmd>` for a single command, and
`gate_lock_acquire` / `gate_lock_release` for holding across a region — which is
what a gate that stops a backend and runs tests against its ports needs.

Add a short paragraph, in the file's existing plain voice, stating plainly:

- A gate that stops the shared backend so its tests can bind the ports **must**
  hold the lock across the whole test run. That is not a mistake to be optimised
  away; shrinking it lets two test runs bind the same port.
- The way to reduce waiting is to run the parts that need nothing shared —
  syntax, taxonomy, fixture suites — *before* acquiring, so concurrent sessions
  overlap on those.
- Genuinely concurrent gates need per-session ports and databases, which this
  file already lists under "The honest limit". Nothing here changes that.
- Contention is now announced, so a waiting gate says so rather than looking hung.

In `shell/worktree/README.md`, document the three public functions
(`with_gate_lock`, `gate_lock_acquire`, `gate_lock_release`), that **fd 9 is
reserved**, that the holder file is advisory and may be stale, and the
truncation trap — the lockfile must never carry the holder metadata, because
`9>` truncates before `flock` runs.

Keep the markdown conventions both files already follow: blank line after every
heading, fenced blocks tagged with a language.

**Acceptance Test:**

```bash
grep -c "gate_lock_acquire" docs/CONCURRENT-DEV.md shell/worktree/README.md   # >0 each
grep -q "fd 9" shell/worktree/README.md
./scripts/gate_fast.sh
```

---

## Post-merge step

Both consumer projects carry the hand-rolled block this spec replaces, and
**neither may be edited from this session** — cross-project writes are forbidden
by `/home/rich/dev/CLAUDE.md`. File one GitHub issue per project so each adopts
the public API from its own session:

- `kermit-v3` — `scripts/gate_fast.sh:162-170` and the two release sites at
  lines 200 and 216.
- `keystone` — `scripts/gate_fast.sh:111-120` and the release sites at lines 155
  and 170.

Each issue should note that the swap is mechanical (`exec 9>"$(_gate_lockfile)"; flock 9`
→ `gate_lock_acquire "gate-fast"`; `exec 9>&-` → `gate_lock_release`), that it
buys them the contention messaging, and that the old code keeps working
untouched — nothing breaks if they do not adopt it. Same shape as the v1.14 and
v1.17 post-merge handoff issues.

## What NOT to Do

- **Do not narrow the lock in any consumer's gate**, and do not advise it in the
  docs. Both hold it across the test run because they stopped the backend so
  pytest could bind its ports. Shrinking it swaps a visible wait for two runs
  racing on one port.
- **Do not put holder metadata in the lockfile.** `9>` truncates at open, before
  `flock`, so a waiter would erase the holder's stamp. Use the sibling
  `.holder` file.
- **Do not print anything on an uncontended acquire.** A message on every gate
  run is noise, and noise on the common path is how a real warning gets ignored.
- **Do not treat the holder file as authoritative.** `flock` releases on process
  death and the file survives; a message must degrade to "another session" when
  the pid is gone rather than inventing a live holder.
- **Do not change `_gate_lockfile()`'s path or fd 9.** Two consumers hardcode
  both today, and this spec must not break their existing gates before they
  adopt the new API.
- **Do not remove or rewrite `with_gate_lock`.** It stays, and its existing
  tests stay unchanged.
- **Do not edit any file under `projects/`.** The consumer swap is a post-merge
  issue, not a change here.
- **Do not add a session registry, lockfile lease, or timeout-and-steal.**
  `flock` already releases on death; anything cleverer is a new failure mode for
  a problem that does not exist.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `shell/worktree/gate-lock.sh` | Modify | Holder stamping in a sibling file, contention announcement, public `gate_lock_acquire`/`gate_lock_release`; `with_gate_lock` routed through the same wait |
| `tests/worktree/run.sh` | Modify | ~8 assertions: silence when uncontended, announcement + holder pid when contended, serialization via the new API, holder-file lifecycle, release-without-acquire, stale holder |
| `docs/CONCURRENT-DEV.md` | Modify | Both lock shapes, why the wide lock is correct, how to reduce waiting without shrinking it |
| `shell/worktree/README.md` | Modify | Public function contract, fd 9 reserved, advisory holder file, truncation trap |
| `ROADMAP.md`, `planning.md`, `tasks/lessons.md` | Modify | v1.22 entry (handled by `/code`'s doc step) |

No `.gitignore`, `install.sh`, or `verify.sh` changes: `gate-lock.sh` already
exists and already deploys via `install.sh worktree`, and `.gitignore:133`
(`!shell/worktree/*`) already covers the directory. No new files are added.

## Implementation Order

1. **Change 1** — the helper. Everything depends on it.
2. **Change 2** — tests. Run `./scripts/gate_fast.sh` here and confirm the count
   moved from 312.
3. **Change 3** — docs, last, so they describe shipped behavior.

## Verification Checklist

- [ ] Uncontended `gate_lock_acquire`/`gate_lock_release` produces no output at all
- [ ] A contended acquire prints a `waiting` line naming the holder's pid, then an "acquired after Ns" line
- [ ] The new API serializes two concurrent holders (no interleave)
- [ ] Holder file exists while held, names the holder pid, and is removed on release
- [ ] `gate_lock_release` with no prior acquire exits 0; calling it twice is a no-op
- [ ] A stale holder file (dead pid) does not block acquisition and is not reported as a live holder
- [ ] `_gate_lockfile()` returns the same path as before, and fd 9 is still the descriptor used
- [ ] `with_gate_lock` still runs its command and still serializes — existing tests 5 and 6 unchanged and passing
- [ ] The `flock`-absent path still warns and still runs the command unserialized
- [ ] `./scripts/install.sh worktree && ./scripts/verify.sh` — no drift
- [ ] `./scripts/gate_fast.sh` — PASS, count up from 312
- [ ] No file under `projects/` modified
- [ ] Markdown: blank line after headings, fenced blocks tagged with a language
