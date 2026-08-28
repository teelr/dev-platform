# v1.20: Concurrent Session Awareness

## Coding Specification for Implementation

## Design Philosophy

`cc --new` (v1.19) made running two, three, or four Claude Code sessions on one
project routine. Nothing in `commands/` or `skills/` knows that. `commands/dev.md`
has no step that looks for other sessions and no mention of the take-turns gate
lock — which is documented only in `docs/CONCURRENT-DEV.md`,
`shell/worktree/README.md`, and the projects' own `scripts/gate_fast.sh`.

The result showed up immediately. A `/dev` run in `kermit-v3` found a second live
session, improvised a warning from raw `ps` output, and got it wrong: it told the
user not to run `./scripts/gate_fast.sh` while the other session was building. But
kermit-v3 wires the lock at `scripts/gate_fast.sh:163` — a concurrent
`/gate fast` blocks on `flock` and takes its turn, which is exactly the case the
lock exists for. The advice turned a solved problem back into a scary one, and
because it was improvised rather than instructed, the next run would improvise
something different.

So the fix is not a correction to a wrong instruction — there is no instruction to
correct. It is a missing capability, and the right shape for it is the one this
repo already uses twice for exactly this class of problem: a standalone,
mechanical detector script with an offline fixture suite
(`scripts/check-phase-milestones.sh` + `tests/phase-milestones/` from v1.10,
`scripts/check_duplicate_numbering.sh` + `tests/duplicate-numbering/` from v1.17).
Prose in a command file is advice a model may follow; a script that prints the
same four lines every time is a fact. `/dev` runs it and reports what it says.

The detector answers the three questions the improvised warning got wrong, and
draws the line the existing docs already draw: **files and branch are isolated**
per worktree, **the running app and its database are not** (`docs/CONCURRENT-DEV.md`
calls this "the honest limit"), and **the gate is safe if the lock is wired**.
The last one is the one that must be measured rather than assumed.

The detector is deliberately NOT wired into `gate_fast.sh`. It is a diagnostic,
not a gate check — the same call v1.10 made for `check-phase-milestones.sh` and
v1.5 for `check-comms-delivery.sh`. It always exits 0.

**Branching strategy:** single branch and single PR for the whole spec, per the
per-Spec-Phase branching rule in `/home/rich/dev/CLAUDE.md`. The two Spec Phases
are not independently shippable — Phase 1 alone ships a script nothing calls, and
Phase 2 alone points `/dev` at a script that does not exist.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/check-concurrent-sessions.sh` | Bash | Reads `/proc`, `git worktree list`, and the filesystem. Pure shell glue, matching every other `scripts/check-*.sh` in this repo. No new service or component. |
| `tests/concurrent-sessions/run.sh` | Bash | Matches the existing per-suite runner contract (`record_pass`/`record_fail` from `tests/helpers/assert.sh`, never `exit`s). |
| `commands/dev.md`, `docs/CONCURRENT-DEV.md` | Markdown | Instruction and documentation files. |

The Language Architecture Decision Matrix governs new services and components
(network → Go, compute → Rust, AI → Python, UI → TypeScript). This spec adds
neither — it is environment tooling, the same class as every other file in
`scripts/`.

## Overview

**Phase 1: The detector**

1. Change 1: `scripts/check-concurrent-sessions.sh` — enumerate this repo's live sessions, isolation mode, and gate-lock status
2. Change 2: `tests/concurrent-sessions/run.sh` — offline fixture suite with a mocked `/proc`

**Phase 2: Wire it into `/dev`**

3. Change 3: `commands/dev.md` — run the detector, report it verbatim, and stop improvising
4. Change 4: `docs/CONCURRENT-DEV.md` — document the detector and what `/dev` does with it

---

## Phase 1: The detector

### Change 1: `scripts/check-concurrent-sessions.sh`

**Problem:** Nothing can answer "is another session working in this project, and
what is safe to do?" without improvising from raw `ps` output. The three facts
that matter — who else is live, what is isolated, whether the gate takes turns —
are each derivable mechanically, and each was gotten wrong by hand.

**File:** `scripts/check-concurrent-sessions.sh` (new file, executable)

**Implementation:**

A read-only diagnostic. Operates on `$PWD`'s repo, not on dev-platform's — it is
invoked by absolute path from any project, the same way `/plan` Step 2 calls
`python3 /home/rich/dev/scripts/claim_roadmap_version.py`. **Always exits 0**
except on a usage error; it is a report, not a gate check.

Header comment must state: read-only, always exits 0, not wired into
`gate_fast.sh` (diagnostic like `check-phase-milestones.sh`), and Linux-only
because it reads `/proc`.

Four parts:

**1. Resolve this repo's worktree roots.**

```bash
mapfile -t ROOTS < <(git worktree list --porcelain 2>/dev/null \
    | awk '/^worktree /{print substr($0, 10)}')
```

If `git worktree list` fails (not a git repo), print `not a git repository` and
exit 0. The main checkout is always the first entry.

**2. Find live Claude Code sessions inside those roots.**

Scan `${CCS_PROC_ROOT}/[0-9]*` for processes whose `comm` is exactly `claude`,
read each one's `cwd` symlink, and keep those whose cwd is inside one of `ROOTS`.

```bash
CCS_PROC_ROOT="${CCS_PROC_ROOT:-/proc}"
```

The override exists so Change 2 can test against a fixture tree offline; default
behavior is unchanged.

Three details that are each load-bearing:

- **Match the LONGEST root, not the first.** The main checkout
  (`/home/rich/dev/projects/kermit-v3`) is a string prefix of every worktree
  under it (`.../.claude/worktrees/v0.166+phase-1-git-layer`). Matching the first
  root would report every worktree session as being in the main checkout — the
  exact distinction the report exists to make. A cwd belongs to a root if it
  equals the root or begins with `${root}/`.
- **Identify the calling session** by walking up from `$$` to the nearest
  ancestor whose `comm` is `claude`. Read the parent PID from
  `${CCS_PROC_ROOT}/<pid>/status` (`PPid:` line), NOT from field 4 of
  `/proc/<pid>/stat` — `stat`'s second field is the comm in parentheses and may
  contain spaces, which shifts every later field. Mark that pid `(this session)`.
- **`/proc` unavailable** (missing directory, or a non-Linux host): print
  `sessions: unknown — /proc not available on this platform` and skip to part 4.
  Never print a session count of 1 when detection did not actually run — a false
  "you are alone" is the dangerous failure here, not an unhelpful one.

For each session print the pid, whether its root is the main checkout or a
worktree, the root path relative to the main checkout (`.` for the main
checkout), and elapsed runtime from `ps -p <pid> -o etime=` (blank if `ps` has
no answer).

**3. Report the isolation mode.** `test -f <main-checkout>/.claude/worktree-deps`
— present means worktree mode is on for this project and `/plan` will give each
session its own copy of the repo; absent means every session shares one working
tree and one branch.

**4. Report gate-lock status.** Look for the project's gate entry point in this
order: `scripts/gate_fast.sh`, then `scripts/gate.sh`. Then check two independent
conditions:

- the gate script references the lock:
  `grep -qE 'gate-lock\.sh|with_gate_lock|_gate_lockfile' "${gate}"`
- the helper is deployed: `test -f "${HOME}/.claude/worktree/gate-lock.sh"`

**The pattern must match all three shapes in the fleet today** — verified live
while writing this spec:

| Project | Shape at | Matches on |
| ------- | -------- | ---------- |
| dev-platform | `scripts/gate_fast.sh:27,119` | `gate-lock.sh` path + `with_gate_lock` call |
| keystone | `scripts/gate_fast.sh:112,114` | `gate-lock.sh` path |
| kermit-v3 | `scripts/gate_fast.sh:163-170` | `gate-lock.sh` path + `_gate_lockfile`, and **no `with_gate_lock` call at all** — it opens fd 9 and calls `flock` directly |

Grepping only for `with_gate_lock` would report kermit-v3 as unlocked, which is
the precise false negative that produced the wrong advice this spec exists to fix.

Four distinct outcomes, each a different line — never collapse the last two into
"not wired":

- wired and helper deployed → concurrent gate runs take turns
- wired but helper missing → say to run `./scripts/install.sh worktree`
- gate script found, no lock reference → concurrent gate runs will fight over the backend
- no gate script found → status unknown, do NOT report "not wired"

**Output format.** Stable, one fact per line, safe to reproduce verbatim:

```text
sessions: 2 (this one + 1 other)
  pid 1687039  worktree  .claude/worktrees/v0.166+phase-1-git-layer  69:10
  pid 2358072  main      .                                          (this session)
isolation: worktree mode ON — /plan gives each session its own copy of the repo
shared: the running app and its database — one backend, one DB across all sessions
gate: lock wired (scripts/gate_fast.sh) + helper deployed — concurrent /gate fast takes turns
```

Alone, the first line is `sessions: 1 (this one only)` and the per-session lines
still print.

**Acceptance Test:**

```bash
chmod +x scripts/check-concurrent-sessions.sh
bash -n scripts/check-concurrent-sessions.sh

# In dev-platform (branch mode, lock wired):
./scripts/check-concurrent-sessions.sh; echo "rc=$?"   # rc=0

# In a project with a live second session:
cd /home/rich/dev/projects/kermit-v3 \
    && bash /home/rich/dev/scripts/check-concurrent-sessions.sh
# expect: worktree session listed separately from the main-checkout one,
#         isolation ON, gate lock wired
```

---

### Change 2: `tests/concurrent-sessions/run.sh`

**Problem:** The detector's three subtle behaviors — longest-root matching,
kermit-v3's `_gate_lockfile`-only lock shape, and the `/proc`-unavailable path —
are all invisible when they break. Each returns a plausible-looking answer that
is simply wrong, which is how the original bug shipped.

**File:** `tests/concurrent-sessions/run.sh` (new file, executable)

**Implementation:**

Follow the existing per-suite contract exactly: `set -uo pipefail`, resolve
`REPO` from `BASH_SOURCE`, source `tests/helpers/assert.sh`, use only
`record_pass`/`record_fail`/`record_skip`, and **never `exit`** — the
orchestrator (`scripts/gate_fast.sh:136`) owns the exit code. `tests/shell/run.sh`
is the closest model. Suites are auto-discovered, so no orchestrator change is
needed.

Everything runs offline against fixtures — no real `claude` process is ever
spawned or inspected. Build a fake proc tree per case:

```bash
mkproc() {   # mkproc <procroot> <pid> <comm> <cwd> <ppid>
    mkdir -p "$1/$2"
    echo "$3"                > "$1/$2/comm"
    printf 'PPid:\t%s\n' "$5" > "$1/$2/status"
    ln -sfn "$4" "$1/$2/cwd"
}
```

and a fixture repo made with a real `git init` plus `git worktree add` (the same
approach `tests/version-collision/` uses for its local remote), so
`git worktree list --porcelain` returns genuine output rather than a stub.

Assertions:

1. `bash -n scripts/check-concurrent-sessions.sh` — syntax clean.
2. Exit code is 0 in every case below (assert per case, or once at the end over a
   recorded set — never let a non-zero slip through as a "failure to report").
3. Alone: one `claude` process, cwd = main checkout → `sessions: 1 (this one only)`.
4. Two sessions, one in the main checkout and one in a worktree → both listed,
   the worktree one labeled `worktree`.
5. **Longest-root regression:** the worktree session must NOT be labeled `main`.
   This is the assertion that catches first-match-wins.
6. A `claude` process whose cwd is in an unrelated directory is excluded from the
   count.
7. A non-`claude` process inside the repo (comm `bash`) is excluded.
8. Self-identification: exactly one line carries `(this session)`, and it is the
   pid reachable by the `PPid` walk.
9. **Lock-shape regression:** a fixture gate script containing only
   `source ~/.claude/worktree/gate-lock.sh` and `_gate_lockfile` (kermit-v3's
   shape, no `with_gate_lock` call) is reported as wired.
10. Lock referenced but `${HOME}/.claude/worktree/gate-lock.sh` absent (point
    `HOME` at a temp dir) → the "helper missing" line, not the "not wired" line.
11. No gate script at all → the `unknown` line, not "not wired".
12. `CCS_PROC_ROOT` pointed at a nonexistent path → the `/proc not available`
    line, and the output does NOT claim a session count.

**Acceptance Test:**

```bash
bash tests/concurrent-sessions/run.sh    # all PASS, no FAIL
./scripts/gate_fast.sh                   # 273 PASS today; expect ~285
```

---

## Phase 2: Wire it into `/dev`

### Change 3: `commands/dev.md` — run the detector and report it

**Problem:** `/dev` has no concurrent-session step, so it improvises one from
`ps` output — which is how the wrong gate advice was generated. It also has no
rule preventing that improvisation from recurring.

**File:** `commands/dev.md` (existing file — Step 4 at line 36, Step 5 report
template at line 46, Rules at the end)

**Implementation:**

1. **New step, inserted after the current Step 4 ("Check the running stack"),
   renumbering the current Step 5 to Step 6.** Title it
   `## Step 5: Check for other live sessions`. It runs one command and reports
   what it prints:

   ```bash
   bash /home/rich/dev/scripts/check-concurrent-sessions.sh
   ```

   The step must state plainly: report the detector's lines as facts; do NOT
   re-derive any of this from `ps`, `git worktree list`, or process inspection of
   your own, and do NOT add caveats the detector did not print.

2. **Report template gains a conditional section**, placed immediately after the
   `**Last commit:**` block so it is seen first:

   ```text
   ## Other sessions
   - <the detector's session lines>
   - <its isolation, shared, and gate lines>
   ```

   Only include the section when the detector reports more than one session, or
   when it reports `unknown`. A single-session run must not grow the report —
   the existing "keep it under ~40 lines" rule still binds.

3. **The "To bring the stack up" section** gains one conditional sentence when
   another session is live: the app and database are shared, so starting or
   restarting the stack affects the other session too.

4. **Two new Rules**, in the existing terse style:

   - Never tell the user to avoid `/gate fast` because another session is
     running. The gate lock is what makes that safe, and the detector reports
     whether it is wired — report that, don't guess. (This is the exact defect
     v1.20 exists to fix.)
   - Another session's worktree is off-limits: don't read into it, don't touch
     its stashes, don't `git worktree remove` it. Being unable to work in *that*
     worktree is not a reason to tell the user they can't work at all — in a
     worktree-mode project, `/plan` gives this session its own.

Frontmatter is unchanged: `allowed-tools` already includes `Bash`, and the
`description` stays as-is (`tests/commands/frontmatter.sh` enforces a 200-char
limit on it).

**Acceptance Test:**

```bash
bash tests/commands/frontmatter.sh 2>&1 | grep "dev.md"     # still valid
grep -n "check-concurrent-sessions" commands/dev.md          # step wired
grep -c "^## Step" commands/dev.md                           # 6 steps, was 5
```

Then run `/dev` in `/home/rich/dev` (single session expected: no
`## Other sessions` section) and in a project with two live sessions (section
present, gate line matching the detector's).

---

### Change 4: `docs/CONCURRENT-DEV.md` — document the detector

**Problem:** `docs/CONCURRENT-DEV.md` is the user-facing doc for running more
than one chat on a project. It explains the worktree layer, the take-turns lock,
and the honest limit, but has nothing on finding out what is currently running —
which is the first question anyone actually has.

**File:** `docs/CONCURRENT-DEV.md` (existing file — add a section before
"How it's wired"; also one line in the "How it's wired" list)

**Implementation:**

Add a short section, `## Seeing what's running`, in the file's existing plain
voice (short sentences, no marketing adjectives — the CLAUDE.md Plain Language
rule applies, and this file already follows it):

- `bash /home/rich/dev/scripts/check-concurrent-sessions.sh` from any project
  prints the live sessions for that repo, whether worktree mode is on, what is
  shared, and whether the gate takes turns.
- `/dev` runs it automatically at session start and reports it.
- Include one short sample of the output — reuse the block from Change 1 rather
  than inventing a second format.
- State plainly that a concurrent `/gate fast` is safe when the lock is wired,
  and that this is the fact `/dev` used to get wrong.

Then add one line to the existing "How it's wired" list naming
`scripts/check-concurrent-sessions.sh` alongside `link-deps.sh` and
`gate-lock.sh`.

Do NOT restate the worktree setup instructions — they are already in this file
and in `shell/worktree/README.md`.

**Acceptance Test:**

```bash
grep -n "check-concurrent-sessions" docs/CONCURRENT-DEV.md   # 2 matches
./scripts/gate_fast.sh                                       # PASS
```

---

## What NOT to Do

- **Do not grep only for `with_gate_lock`** when detecting the lock. kermit-v3
  sources `gate-lock.sh` and calls `_gate_lockfile` + `flock 9` directly, with no
  `with_gate_lock` call anywhere — verified at
  `projects/kermit-v3/scripts/gate_fast.sh:163-170`. That false negative is the
  original bug.
- **Do not report "no other sessions" when detection failed.** A missing `/proc`
  must print `unknown`. Silently reporting a count of 1 tells the user they are
  alone when they may not be.
- **Do not match a cwd against the first worktree root that prefixes it.** Take
  the longest match, or every worktree session is mislabeled as the main checkout.
- **Do not read the parent PID from `/proc/<pid>/stat` field 4.** The comm field
  is parenthesized and may contain spaces, shifting every later field. Use the
  `PPid:` line in `/proc/<pid>/status`.
- **Do not wire the detector into `scripts/gate_fast.sh`.** It is a diagnostic,
  not a gate check — same call as `check-phase-milestones.sh` (v1.10) and
  `check-comms-delivery.sh`. It must never fail a commit.
- **Do not make `/dev` inspect processes itself.** The whole point is that the
  detector is the single source of these facts. A second, hand-rolled derivation
  in the command file recreates the bug.
- **Do not have `/dev` add caveats the detector did not print.** "The gate might
  still be risky" is exactly the improvisation being removed.
- **Do not spawn real `claude` processes in the test suite.** Use the
  `CCS_PROC_ROOT` fixture tree. The suite runs on every gate and must not depend
  on what the user happens to have open.
- **Do not touch another session's worktree** from the detector or from `/dev` —
  no reads into it beyond the path, no `git worktree remove`, no stash
  inspection.
- **Do not extend this to `/code` or `/gate`** in this spec. `/dev` is the
  orientation command; wiring the detector elsewhere is a separate decision.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/check-concurrent-sessions.sh` | New | Read-only detector: live sessions per worktree, isolation mode, gate-lock status. Always exits 0 |
| `tests/concurrent-sessions/run.sh` | New | ~12 offline assertions against a mocked `/proc` and a real fixture repo |
| `commands/dev.md` | Modify | New Step 5 running the detector, conditional report section, 2 new rules, Step 5 → Step 6 |
| `docs/CONCURRENT-DEV.md` | Modify | New "Seeing what's running" section + one line in "How it's wired" |
| `ROADMAP.md` | Modify | v1.20 entry (handled by `/code`'s doc step) |
| `planning.md` | Modify | Active-phase + recently-shipped update (handled by `/code`'s doc step) |

No `.gitignore`, `install.sh`, or `verify.sh` changes are needed — verified
during planning: `.gitignore:63` (`!scripts/*.sh`) already allows the new script,
`install.sh` has no `scripts` deploy category (scripts run from the repo by
absolute path, the same as `claim_roadmap_version.py`), and `gate_fast.sh:81`
already walks `scripts/` and `tests/` for the bash-syntax check and
auto-discovers new test suites.

## Implementation Order

1. **Change 1** — the detector. Everything else depends on it existing.
2. **Change 2** — the test suite. Written against Change 1; run
   `./scripts/gate_fast.sh` here and confirm the count moved from 273.
3. **Change 3** — `commands/dev.md`. Only once the script it calls is proven.
4. **Change 4** — `docs/CONCURRENT-DEV.md`. Last, so it documents shipped
   behavior and can reuse Change 1's real output.

## Verification Checklist

- [ ] `./scripts/check-concurrent-sessions.sh` exits 0 in dev-platform and prints all four lines
- [ ] Run from `projects/kermit-v3` with a second session live: the worktree session and the main-checkout session are listed separately, and the worktree one is not labeled `main`
- [ ] kermit-v3's `_gate_lockfile`-only gate script is reported as wired
- [ ] Lock referenced but helper absent → "helper missing" line, distinct from "not wired"
- [ ] No gate script → `unknown`, not "not wired"
- [ ] `CCS_PROC_ROOT` pointed at a missing path → `unknown`, no session count claimed
- [ ] Exactly one session line is marked `(this session)`
- [ ] Unrelated `claude` processes and non-`claude` processes inside the repo are excluded
- [ ] `/dev` in dev-platform (single session) produces NO `## Other sessions` section and stays under ~40 lines
- [ ] `/dev` in a two-session project produces the section, and its gate line matches the detector's verbatim
- [ ] `bash tests/concurrent-sessions/run.sh` — all PASS
- [ ] `bash tests/commands/frontmatter.sh` — `dev.md` still valid
- [ ] `./scripts/gate_fast.sh` — PASS, count up from 273 by the number of new assertions
- [ ] Detector is NOT referenced anywhere in `scripts/gate_fast.sh`
- [ ] Markdown: blank line after headings, fenced blocks tagged with a language
