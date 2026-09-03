# v1.23: Lessons Directory

## Coding Specification for Implementation

## Design Philosophy

`tasks/lessons.md` is a single append-only table that every `/code` turn adds a
row to. With one session that is fine. With three or four it is a standing merge
conflict: each session appends at the same place, so git either conflicts or —
worse — merges cleanly at different line offsets and leaves a silent duplicate.
This session hit the conflicting variant during a `git stash pop` while shipping
v1.21, and `tasks/lessons.md` is one of the three files v1.11's ROADMAP entry
already deferred as "the `planning.md`/`ROADMAP.md`/`tasks/lessons.md`
doc-merge-collision redesign".

The fix is structural rather than procedural: **one file per lesson**, named
`tasks/lessons/<date>-<slug>.md`. Two sessions never touch the same file, so the
conflict class stops existing instead of being detected and resolved. v1.17
shipped `check_duplicate_numbering.sh`, a *detector* for the numbering half of
this problem; this removes the cause for dev-platform and gives consumers a
pattern to port for theirs.

**Scope is deliberately one file, not three.** `ROADMAP.md` is read by six
scripts and four commands — `claim_roadmap_version.py` and
`check_version_collision.py` parse version headers out of
`git show origin/main:ROADMAP.md` — so splitting it would put the atomic
version-claim guard, the most load-bearing mechanism in this repo, at risk to fix
its least frequent conflict (one line per Roadmap Phase). `planning.md` sits in
between. `tasks/lessons.md` has the highest append frequency and the lightest
coupling: nothing in dev-platform machine-reads it, and
`check_duplicate_numbering.sh` already no-ops cleanly when it is absent (verified:
prints `no tasks/lessons.md — skipping lessons-L# check`, exits 0). It is the
right place to prove the pattern.

Two decisions worth stating because they are not obvious. **No generated
`lessons.md`** — nothing machine-reads it, and regenerating a combined file would
reintroduce exactly the merge conflict this removes. And the **"capped at ~30
entries" rule becomes a read limit, not a storage limit**: the cap existed to keep
one file readable, which one-file-per-lesson already solves. It is also already
violated — 46 rows against a stated ~30 — which is what an unenforceable cap
looks like. The separate rule about consolidating 2-3 similar lessons into a
`CLAUDE.md` rule is about signal, not size, and stays exactly as-is.

**Branching strategy:** single branch and single PR. The Phases are not
independently shippable — Phase 1 without Phase 2 leaves every command still
writing to a file that no longer exists.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/migrate-lessons.sh` | Bash | A one-shot text transform over a markdown table, matching `scripts/migrate-workflow-chain.sh` (v0.9), the repo's existing migration-tool precedent. It is committed rather than run-and-discarded so consumers can port their own `L#`-numbered lessons later. |
| `tests/lessons-dir/run.sh` | Bash | Matches the existing per-suite runner contract. |
| The lesson files | Markdown | Prose read by humans and agents at session start. |

The Language Architecture Decision Matrix governs new services and components.
This spec adds neither.

## Overview

**Phase 1: The directory**

1. Change 1: `.gitignore` — re-include `tasks/lessons/` **before** anything writes there
2. Change 2: `scripts/migrate-lessons.sh` — a pipe-safe, text-preserving table→files migration
3. Change 3: Run it — 46 lesson files in, `tasks/lessons.md` out
4. Change 4: `tests/lessons-dir/run.sh` — migration correctness, including the pipe-bearing rows

**Phase 2: Rewire the consumers**

5. Change 5: `commands/code.md`, `commands/docs.md`, `commands/dev.md`
6. Change 6: the rule text and the project templates

---

## Phase 1: The directory

### Change 1: `.gitignore` — re-include `tasks/lessons/` first

**Problem:** `.gitignore:39` is `tasks/**` and `:61` is `!tasks/*.md`, which does
**not** reach subdirectories. Every generated lesson file would be silently
untracked. Verified by probe: `touch tasks/lessons/probe.md` then
`git status --porcelain tasks/lessons/` prints **nothing**.

This is the **third** time this exact trap has appeared — v1.18
(`shell/profile.d/`), v1.21 (`scripts/lib/*.py`), now `tasks/lessons/`. It goes
first in the implementation order for that reason: a migration that writes 46
untracked files looks like it worked.

**File:** `.gitignore` (existing — the `tasks/` block at lines 61-62)

**Implementation:**

Add both rules, directory re-include first, mirroring the `scripts/lib/` block at
lines 66-70 whose comment already explains the ordering ("Re-include must precede
file patterns — files in an ignored dir can't be unignored by a file-pattern rule
alone"):

```gitignore
# v1.23: tasks/lessons/ — one file per lesson, so concurrent sessions never
# append to the same file. !tasks/*.md does not reach subdirectories.
!tasks/lessons/
!tasks/lessons/*.md
```

**Acceptance Test:**

Use a probe file and `git status`, **not** `git check-ignore -v` — that command
exits 0 when the last matching pattern is a negation, so its exit code cannot
distinguish "ignored" from "explicitly re-included". This is the v1.18 lesson.

```bash
mkdir -p tasks/lessons && touch tasks/lessons/probe.md
git status --porcelain tasks/lessons/    # must print: ?? tasks/lessons/probe.md
rm tasks/lessons/probe.md
```

---

### Change 2: `scripts/migrate-lessons.sh`

**Problem:** The 46 existing rows must become 46 files without losing or
corrupting text. **Seven of them contain a literal `|` inside the lesson body** —
backticked things like `|| true`, `cmd | head`, `` `owner/repo#N` `` — so a naive
`awk -F'|'` column split mangles them. Confirmed by running one: the "project"
and "status" columns for those rows come back as fragments of the lesson prose.

**File:** `scripts/migrate-lessons.sh` (new file, executable)

**Implementation:**

Follow `scripts/migrate-workflow-chain.sh` (v0.9) for shape: **dry-run by
default**, `--apply` to write, idempotent, and a header comment stating what it
transforms and why it is committed rather than discarded.

Read the table from `${LESSONS_FILE:-tasks/lessons.md}` and write to
`${LESSONS_DIR:-tasks/lessons}`. Both overridable so the test suite can drive it
against fixtures.

**Row parsing — the load-bearing part.** Anchor at both ends and let the lesson
field be greedy; only the outer columns are pipe-free:

```text
^\|\s*(?P<date>[^|]+?)\s*\|\s*(?P<lesson>.*?)\s*\|\s*(?P<project>[^|]+?)\s*\|\s*(?P<status>[^|]+?)\s*\|\s*$
```

Verified against all 46 rows: 46 parsed, 0 failed, and the 7 pipe-bearing lessons
keep their pipes. Any row that does not match this pattern **must abort the
migration with the offending line**, never be silently skipped — a dropped lesson
is invisible afterwards.

Discard the `project` and `status` columns. Both are constant across all 46 rows
(`dev-platform` / `active`), so they carry no information: each project's lessons
live in its own repo, and nothing has ever been marked non-active.

**Output file per row:**

```markdown
# <title>

<the full original lesson text, verbatim>
```

Filename: `<date>-<slug>.md`, where `<slug>` comes from the first several words of
the lesson, lowercased, non-alphanumerics collapsed to `-`, trimmed to ~50 chars.
On a filename collision, append `-2`, `-3`, … — do not overwrite.

**The title is cosmetic; the body is authoritative.** Derive the title from the
lesson's opening clause, but **always write the complete original lesson text into
the body regardless of what the title says**. That way a bad title split is a
cosmetic wart, never data loss. Do not attempt clever sentence-boundary detection
— these lessons are full of `e.g.`, `v0.7`, and `.sh` — a first-N-words title is
fine and cannot corrupt anything.

Print a summary on completion: rows read, files written, collisions renamed.

**Acceptance Test:**

```bash
bash -n scripts/migrate-lessons.sh
./scripts/migrate-lessons.sh            # dry run: reports 46 rows, writes nothing
ls tasks/lessons/ 2>/dev/null | wc -l   # still 0

./scripts/migrate-lessons.sh --apply
ls tasks/lessons/*.md | wc -l           # 46

# Text preservation: every original lesson body must appear verbatim exactly once.
# This is the check that matters — run it, do not assume.
```

---

### Change 3: Run the migration and retire `tasks/lessons.md`

**Problem:** The generated files and the deletion have to land in the same commit
as the rewiring, or a session between the two states has no lessons at all.

**File:** `tasks/lessons/*.md` (46 new files), `tasks/lessons.md` (delete)

**Implementation:**

Run `./scripts/migrate-lessons.sh --apply`, then `git rm tasks/lessons.md`.

Before deleting, **verify text preservation mechanically**: for each of the 46
original lesson bodies, assert it appears verbatim in exactly one file under
`tasks/lessons/`. Do not eyeball it — 46 rows with embedded backticks, pipes and
em-dashes is exactly where a spot check misses the one that broke.

`tasks/lessons.md`'s two-line preamble ("Patterns from corrections. Reviewed at
session start. Consolidated into CLAUDE.md rules when 2-3 similar entries
emerge.") is real content and must not be lost — move it to
`tasks/lessons/README.md`, along with the naming convention and a note that the
directory is read newest-first.

**Acceptance Test:**

```bash
test ! -e tasks/lessons.md
ls tasks/lessons/*.md | wc -l                 # 46 + README
ls -1 tasks/lessons/ | sort -r | head -3      # newest-first ordering works
./scripts/gate_fast.sh                        # duplicate-numbering check still clean
```

---

### Change 4: `tests/lessons-dir/run.sh`

**Problem:** The migration's two failure modes are both silent — a mangled
pipe-bearing row, and a row dropped for not matching the pattern. Neither is
visible after `tasks/lessons.md` is deleted.

**File:** `tests/lessons-dir/run.sh` (new file, executable)

**Implementation:**

Standard per-suite contract: `set -uo pipefail`, resolve `REPO` from
`BASH_SOURCE`, source `tests/helpers/assert.sh`, `record_pass`/`record_fail` only,
never `exit`. Auto-discovered by `scripts/gate_fast.sh:136`, so no orchestrator
change. Drive the script against a fixture table via `LESSONS_FILE` /
`LESSONS_DIR` — never against the repo's real `tasks/lessons/`.

Assertions:

- `bash -n` clean.
- Dry run (no `--apply`) writes nothing and reports the row count.
- `--apply` writes one file per row.
- **Pipe-bearing regression:** a fixture row whose lesson contains `` `|| true` ``
  and `` `cmd | head` `` round-trips with both pipes intact. This is the assertion
  that catches a naive column split.
- Text preservation: each fixture lesson body appears verbatim in exactly one
  output file.
- A malformed row (too few columns) **aborts** with the offending line and writes
  no files — not a silent skip.
- Filename collision (two same-date rows with the same opening words) produces two
  distinct files, neither overwritten.
- Idempotence: a second `--apply` over the same input does not duplicate or
  corrupt files.

**Acceptance Test:**

```bash
bash tests/lessons-dir/run.sh    # all PASS
./scripts/gate_fast.sh           # 320 PASS today; expect ~328
```

---

## Phase 2: Rewire the consumers

### Change 5: the three commands that read and write lessons

**Problem:** `/code` and `/docs` append a row to a file that will no longer exist,
and `/dev` reads it at session start.

**File:** `commands/code.md` (existing — `### tasks/lessons.md` at line 154, the
`git add` at line 167), `commands/docs.md` (existing — lines 36, 65, 98),
`commands/dev.md` (existing — lines 18, 34, 97)

**Implementation:**

- **`commands/code.md` and `commands/docs.md`** — the doc step writes a **new
  file** `tasks/lessons/<today>-<slug>.md` instead of appending a row. State the
  filename convention and that the body is prose with a `#` title. The staging
  lines (`git add planning.md ROADMAP.md README.md tasks/lessons.md`) become
  `git add planning.md ROADMAP.md README.md tasks/lessons/` — note that a *new*
  file needs staging by path, so `tasks/lessons/` (the directory) is correct here
  and `git add -A` remains forbidden.
- **`commands/dev.md:18`** — read the newest few files instead of the single file:
  `ls -1 tasks/lessons/*.md 2>/dev/null | sort -r | head -5`. Sorting by filename
  works because the date leads the name; do not use `ls -t`, which sorts by mtime
  and would reorder every file a checkout touches.
- **`commands/dev.md:34`** — the spec-listing step excludes `lessons.md` by name;
  that exclusion is now unnecessary for lessons (it lives in a subdirectory) but
  the `HARNESS_HANDOFF_QUEUE.md` exclusion stays. Update the sentence rather than
  deleting the line.
- **`commands/dev.md:97`** — the report template's "Recent lessons" bullet
  wording, if it names the file.

Frontmatter in all three is unchanged; `tests/commands/frontmatter.sh` enforces a
200-char `description` limit and none of these descriptions change.

**Acceptance Test:**

```bash
bash tests/commands/frontmatter.sh 2>&1 | grep -E "code.md|docs.md|dev.md"
grep -rn "tasks/lessons\.md" commands/     # no hits
grep -rn "tasks/lessons/" commands/        # code.md, docs.md, dev.md
```

---

### Change 6: the rule text and the project templates

**Problem:** `settings/claude-global.md:58` states the "~30 entries" cap that no
longer means anything, and five template/doc files describe a `tasks/` tree
containing `lessons.md`.

**File:** `settings/claude-global.md` (existing — line 58),
`scaffolding/{python-agent,go-service,next-frontend}/CLAUDE.md` (existing — the
`tasks/` tree comment), `docs/PROJECT_CLAUDE_TEMPLATE.md:69`,
`docs/GLOSSARY.md`, `docs/RULE_RATIONALE.md`

**Implementation:**

- **`settings/claude-global.md:58`** — "Specific bugs → project
  `tasks/lessons.md` (capped at ~30 entries)" becomes a pointer to
  `tasks/lessons/`, one file per lesson, with the cap restated as a **read**
  limit: session start reads the newest handful, storage is unbounded because the
  files do not conflict. Leave the neighbouring consolidation rule (lines 59-63)
  untouched.
- **The four `tasks/` tree comments** — `lessons.md` → `lessons/`.
- **`docs/GLOSSARY.md` and `docs/RULE_RATIONALE.md`** — update the references
  that name the file as a path. Leave historical incident narrative alone;
  RULE_RATIONALE describes what happened at the time and rewriting history is
  forbidden elsewhere in this repo for the same reason.
- **One-line fix to the Consumer Audit rule in `CLAUDE.md`** (the rule this spec's
  Change 1 exists because of): its step 1 tells you to run `git check-ignore -v
  <newfile>`, but that command **exits 0 when the last matching pattern is a
  negation**, so its status cannot distinguish ignored from re-included — the
  v1.18 lesson. Replace it with the probe-and-`git status --porcelain` check that
  actually works. This is in scope: the rule names an unreliable check, and this
  phase is the third time the trap it guards has fired.

**Acceptance Test:**

```bash
grep -rn "tasks/lessons\.md" settings/ scaffolding/ docs/ CLAUDE.md   # only historical narrative
grep -n "check-ignore" CLAUDE.md                                       # rule now names the probe check
./scripts/gate_fast.sh
```

---

## What NOT to Do

- **Do not write any lesson file before Change 1 lands.** `tasks/**` swallows the
  subdirectory, and 46 silently-untracked files look exactly like success. Third
  occurrence of this trap; it goes first in the order for that reason.
- **Do not split rows on `|`.** Seven of the 46 lessons contain literal pipes
  inside backticks. Use the both-ends-anchored pattern with a greedy middle field.
- **Do not silently skip an unparseable row.** Abort and name the line. A dropped
  lesson is undetectable once `lessons.md` is gone.
- **Do not let the title derivation lose text.** The full original lesson goes in
  the body no matter what the title ends up being. Do not attempt sentence-boundary
  splitting — these lessons are full of `e.g.`, `v0.7` and `.sh`.
- **Do not generate a combined `lessons.md`.** Nothing machine-reads it, and a
  generated file reintroduces the exact merge conflict being removed.
- **Do not touch `ROADMAP.md` or `planning.md`** beyond this phase's own entries.
  Splitting those is explicitly out of scope — `ROADMAP.md` especially, since
  `claim_roadmap_version.py` reads it from `origin/main`.
- **Do not use `ls -t`** to order lessons. Filename order is date order; mtime
  order is checkout order, which reshuffles on every clone.
- **Do not change `check_duplicate_numbering.sh`.** It already no-ops cleanly on a
  missing lessons file (verified), and its `L#` pass still serves consumers whose
  own lessons files keep that convention.
- **Do not delete `tasks/lessons.md`'s preamble.** Move it to
  `tasks/lessons/README.md`; it states what the lessons are for.
- **Do not port this to consumer projects from this session.** Cross-project
  writes are forbidden. Post-merge may file issues if desired.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `.gitignore` | Modify | Re-include `tasks/lessons/` and `tasks/lessons/*.md`, directory rule first |
| `scripts/migrate-lessons.sh` | New | Pipe-safe, text-preserving table→files migration; dry-run default, `--apply` to write |
| `tasks/lessons/*.md` | New | 46 migrated lesson files, one per former row |
| `tasks/lessons/README.md` | New | The old preamble plus the naming convention |
| `tasks/lessons.md` | Delete | Superseded by the directory |
| `tests/lessons-dir/run.sh` | New | ~8 assertions incl. the pipe-bearing regression and text preservation |
| `commands/code.md`, `commands/docs.md`, `commands/dev.md` | Modify | Write a new file / read newest-N instead of one shared file |
| `settings/claude-global.md` | Modify | Cap becomes a read limit; path updated |
| `CLAUDE.md` | Modify | Consumer Audit step 1 names the probe check, not `check-ignore -v` |
| `scaffolding/*/CLAUDE.md` ×3, `docs/PROJECT_CLAUDE_TEMPLATE.md`, `docs/GLOSSARY.md`, `docs/RULE_RATIONALE.md` | Modify | `tasks/` tree comments and path references |
| `ROADMAP.md`, `planning.md` | Modify | v1.23 entry (handled by `/code`'s doc step — which now writes a lesson *file*) |

No `install.sh` or `verify.sh` changes: `tasks/` has no deploy category, and
`gate_fast.sh` already walks `scripts/` for bash syntax and auto-discovers new
test suites.

## Implementation Order

1. **Change 1** — `.gitignore`, before anything writes to the directory.
2. **Change 2** — the migration script.
3. **Change 4** — its tests, against fixtures, before running it for real.
4. **Change 3** — run the migration, verify preservation, delete the old file.
5. **Change 5** — the three commands.
6. **Change 6** — rule text and templates. Run `./scripts/gate_fast.sh` and confirm
   the count moved from 320.

Note that Change 4 is implemented before Change 3 despite the numbering: proving
the migration on fixtures before running it on the only copy of 46 real lessons is
the whole point.

## Verification Checklist

- [ ] A probe file under `tasks/lessons/` shows as untracked in `git status --porcelain` (not ignored)
- [ ] Dry run reports 46 rows and writes nothing
- [ ] `--apply` produces 46 files plus README
- [ ] All 7 pipe-bearing lessons keep their `|` characters intact
- [ ] Every one of the 46 original lesson bodies appears verbatim in exactly one file
- [ ] A malformed fixture row aborts the migration and names the line; no partial output
- [ ] Same-date same-opening-words rows produce two distinct files
- [ ] Re-running `--apply` is idempotent
- [ ] `tasks/lessons.md` is gone; its preamble survives in `tasks/lessons/README.md`
- [ ] `ls -1 tasks/lessons/*.md | sort -r` gives newest-first
- [ ] No `tasks/lessons.md` reference remains in `commands/`, `settings/`, `scaffolding/`, or the templates
- [ ] `check_duplicate_numbering.sh` still reports clean (its lessons pass no-ops)
- [ ] `bash tests/commands/frontmatter.sh` — all three edited commands still valid
- [ ] `./scripts/gate_fast.sh` — PASS, count up from 320
- [ ] No file under `projects/` modified
- [ ] Markdown: blank line after headings, fenced blocks tagged with a language
