# v1.24: Shipped Directory

## Coding Specification for Implementation

## Design Philosophy

`planning.md` is the last per-phase append collision in dev-platform's own docs.
Every `/code` turn prepends a bullet to its "Recently shipped" section AND
rewrites the "Active spec" / "Active Roadmap Phase" lines in Current state —
two concurrent sessions collide on both, the same way they collided on
`tasks/lessons.md` before v1.23. The file also shows what unenforceable
hand-maintenance looks like: its "In flight" section still opens with "v1.17
shipped", six phases stale, flagged twice in past sessions and never fixed
because nothing owns it.

The fix is the v1.23 pattern applied to the shipped record, plus one step
further: **`/code` stops editing `planning.md` entirely.** Each shipped phase
becomes its own file, `tasks/shipped/<date>-v<X.Y>-<slug>.md`, carrying the
narrative that today lands in the Recently-shipped bullet and the Active-line
prose. Phase filenames can never collide because version numbers are claimed
atomically (v1.11). `planning.md` shrinks to a short, static orientation doc —
zero per-phase writes, so zero collisions and zero staleness-by-neglect. The
"In flight" section is deleted outright: it exists only because something had
to be hand-rewritten every phase, and it wasn't.

**This is safe fleet-wide because it is convention-detected**, the same way
worktree mode is: `/code` and `/merge` check for a `tasks/shipped/` directory
and keep their current `planning.md` behavior when it is absent, so consumer
projects are untouched until they migrate from their own sessions. It is safe
for dev-platform's own machinery because the couplings were verified before
this spec was written: `/plan` Step 2 already falls back to `ROADMAP.md`'s
highest version entry when `planning.md` has no Active line; `docs_only_diff.sh`
matches with bash `[[ == ]]` globs where `*` crosses slashes, so its existing
`tasks/*` pattern already covers the new directory; no fleet script reads
`planning.md`; and `check_spec_taxonomy.sh` scans it only for killed-term
headers, which the static rewrite keeps clean. **`ROADMAP.md` still gets its
per-phase entry** — deliberately, again: the atomic version-claim guard parses
it from `origin/main`, and that mechanism stays untouched.

**Branching strategy:** single branch and single PR. The Phases are not
independently shippable — migrating the content without rewiring the commands
leaves `/code` appending to a section that no longer exists.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/migrate-shipped.sh` | Bash | One-shot text transform over a markdown section, matching `scripts/migrate-lessons.sh` (v1.23) and `migrate-workflow-chain.sh` (v0.9). Committed so consumer projects can port their own `planning.md` later. |
| `tests/shipped-dir/run.sh` | Bash | Existing per-suite runner contract. |
| The shipped files | Markdown | Prose read by humans, `/dev`, and `/merge`'s Change Summary. |

No new services or components — the Language Architecture Decision Matrix is
not in play.

## Overview

**Phase 1: The directory**

1. Change 1: `.gitignore` — re-include `tasks/shipped/` before anything writes there
2. Change 2: `scripts/migrate-shipped.sh` — section→files migration
3. Change 3: `tests/shipped-dir/run.sh`
4. Change 4: run the migration; rewrite `planning.md` as a static orientation doc

**Phase 2: Rewire the consumers**

5. Change 5: `commands/code.md`, `commands/docs.md`, `commands/merge.md`, `commands/dev.md`, `commands/plan.md`
6. Change 6: the rule text — `CLAUDE.md`, `settings/claude-global.md`

---

## Phase 1: The directory

### Change 1: `.gitignore` — re-include `tasks/shipped/` first

**Problem:** `.gitignore:39` (`tasks/**`) silently swallows any new
subdirectory; `!tasks/*.md` does not reach it. This is the FOURTH occurrence
(v1.18 `shell/profile.d/`, v1.21 `scripts/lib/*.py`, v1.23 `tasks/lessons/`),
and the Consumer Audit rule in `CLAUDE.md` now spells out the exact procedure
because of the third.

**File:** `.gitignore` (existing — add directly below the v1.23
`tasks/lessons/` block)

**Implementation:** Two rules, directory re-include first, with a one-line
comment citing v1.24 and the one-file-per-shipped-phase rationale — mirror the
v1.23 block's shape exactly.

**Acceptance Test:**

Probe + `git status --porcelain` — NOT `git check-ignore -v` (exits 0 on a
negation match; the rule text says why):

```bash
mkdir -p tasks/shipped && touch tasks/shipped/probe.md
git status --porcelain tasks/shipped/    # must print: ?? tasks/shipped/probe.md
rm tasks/shipped/probe.md
```

---

### Change 2: `scripts/migrate-shipped.sh`

**Problem:** `planning.md`'s "Recently shipped" section holds 51 entries that
must become files without losing text: **36 phase bullets** (`- v<X.Y> <Title>,
...`), **14 chore bullets** (`- <description> (<date>, ...)` with no version),
and **1 preamble line** ("Hashes intentionally omitted — ..."). All bullets are
single-line (verified), so the parse is simpler than v1.23's four-column table —
but the two bullet shapes need different filenames.

**File:** `scripts/migrate-shipped.sh` (new file, executable)

**Implementation:**

Same shape as `scripts/migrate-lessons.sh`: dry-run by default, `--apply` to
write, env overrides `PLANNING_FILE` (default `planning.md`) and `SHIPPED_DIR`
(default `tasks/shipped`) for the tests, python3 inside for the parsing, and a
header comment saying why it is committed (consumers port their own
`planning.md` later).

Operate ONLY on the lines between `## Recently shipped` and the next `## `
heading. Per line:

- Blank → skip.
- The preamble ("Hashes intentionally omitted...") → goes into
  `tasks/shipped/README.md`'s content (Change 4 writes the README; the script
  just must not treat it as an error). Identify it as: a non-bullet, non-blank
  line — there is exactly one; if MORE than one non-bullet line appears, abort
  naming the line, same abort-not-skip contract as v1.23.
- `- v<MAJOR>.<MINOR> ...` → phase entry. Filename
  `<date>-v<MAJOR>.<MINOR>-<slug>.md` where `<date>` is the FIRST
  `\d{4}-\d{2}-\d{2}` found in the bullet (every phase bullet carries one in
  its parenthetical; if none is found, abort naming the line) and `<slug>` is
  slugified from the title text between the version and the first comma
  (reuse migrate-lessons.sh's slugify approach: strip code spans, keep
  `[A-Za-z0-9]`, ~50 chars).
- Any other `- ...` bullet → chore entry. Filename `<date>-<slug>.md`, date
  extracted the same way (every chore bullet carries one — verified; abort if
  not), slug from the bullet's opening words.
- Anything else → abort naming the line. A silently dropped entry is
  undetectable once the section is deleted.

File content: `# <title>` + blank + the FULL original bullet text verbatim
(minus the leading `- `). The title is cosmetic; the body is authoritative —
same contract as v1.23, and for the same reason.

Filename collisions get `-2`, `-3` suffixes, never overwritten. Print a
summary: phase entries, chore entries, files written.

The script only READS `planning.md` — the rewrite of the file itself is
Change 4, done by hand, because the target is bespoke prose, not a transform.

**Acceptance Test:**

```bash
bash -n scripts/migrate-shipped.sh
./scripts/migrate-shipped.sh              # dry run: 36 phase + 14 chore entries, writes nothing
./scripts/migrate-shipped.sh --apply
ls tasks/shipped/*.md | wc -l             # 50
ls tasks/shipped/ | grep -c "^....-..-..-v1\."   # phase files carry their version
```

---

### Change 3: `tests/shipped-dir/run.sh`

**Problem:** The migration's failure modes are silent once the section is
deleted: a dropped bullet, a mis-dated file, a phase bullet filed as a chore.

**File:** `tests/shipped-dir/run.sh` (new file, executable)

**Implementation:**

Standard suite contract (`record_pass`/`record_fail`, never `exit`,
auto-discovered). Fixture `planning.md` with a Recently-shipped section
containing: 2 phase bullets (one with backticked pipes in the prose — carry the
v1.23 pipe regression forward), 2 chore bullets, the preamble line, and
surrounding sections that must be ignored. Drive via `PLANNING_FILE`/
`SHIPPED_DIR`.

Assertions (~9):

- `bash -n` clean; dry run reports counts and writes nothing.
- `--apply`: one file per bullet; phase files named `<date>-v<X.Y>-<slug>.md`;
  chore files named `<date>-<slug>.md` with the date from the parenthetical.
- Pipe-bearing bullet round-trips verbatim.
- Every bullet body appears verbatim in exactly one file (bodies unique in the
  fixture — the v1.23 lesson).
- A non-bullet line other than the single preamble aborts with the line named,
  writing nothing.
- A bullet with no date aborts.
- Re-running `--apply` is idempotent.
- Lines OUTSIDE the Recently-shipped section are never migrated.

**Acceptance Test:**

```bash
bash tests/shipped-dir/run.sh    # all PASS
./scripts/gate_fast.sh           # 329 PASS today; expect ~338
```

---

### Change 4: run the migration; rewrite `planning.md` static

**Problem:** The generated files, the section deletion, and the rewiring must
land in one commit, or a session in between has no shipped record.

**File:** `tasks/shipped/*.md` (50 new files), `tasks/shipped/README.md` (new),
`planning.md` (rewrite)

**Implementation:**

1. `./scripts/migrate-shipped.sh --apply`, then verify preservation
   MECHANICALLY before touching `planning.md`: every one of the 50 bullet
   bodies appears verbatim in exactly one file (the v1.23 check, rerun here —
   do not eyeball 50 entries).
2. Additionally migrate the CURRENT phase narrative: the "Active spec" /
   "Active Roadmap Phase" lines' v1.23 prose is already in the v1.23 shipped
   file (it duplicates the Recently-shipped bullet); nothing extra to save.
   Verify that claim rather than assuming it — diff the Active-line prose
   against the v1.23 bullet before deleting.
3. `tasks/shipped/README.md`: the preamble line's content (hashes intentionally
   omitted, git log is authoritative), the two naming conventions
   (`<date>-v<X.Y>-<slug>.md` phases, `<date>-<slug>.md` chores), newest-first
   reading via `ls -1 tasks/shipped/*.md | sort -r` (filename order is date
   order; never `ls -t`), and why one file per phase (the collision rationale,
   two sentences).
4. Rewrite `planning.md` to a short static doc (~25 lines):
   - `# dev-platform Planning Snapshot` + intro sentence updated to say the
     file is static orientation, per-phase state lives elsewhere.
   - `## Current state` — the Name line (static), a line pointing at
     `tasks/shipped/` (newest first) for what shipped, and a line pointing at
     `ROADMAP.md` for the phase sequence and next version. NO Active-spec or
     Active-Roadmap-Phase lines — that is the point.
   - `## Taxonomy migration note (2026-05-11)` — keep verbatim (static
     history).
   - `## Pointer` — rewrite: drop the "future CHANGELOG.md" sentence (never
     happened); name `tasks/` (specs), `tasks/shipped/` (per-phase record),
     `tasks/lessons/` (corrections), `ROADMAP.md` (sequence).
   - DELETE `## Recently shipped` and `## In flight` entirely. In-flight state
     is visible from live branches/PRs/milestones, which cannot go stale.

**Acceptance Test:**

```bash
ls tasks/shipped/*.md | wc -l                          # 50 + README = 51
grep -c "Recently shipped\|In flight" planning.md      # 0
grep -c "Active Roadmap Phase" planning.md             # 0
wc -l planning.md                                      # ~25
./scripts/check_spec_taxonomy.sh                       # still conforms
python3 scripts/check_version_collision.py             # unaffected (reads ROADMAP.md)
```

---

## Phase 2: Rewire the consumers

### Change 5: the five commands

**Problem:** `/code` and `/docs` write sections that no longer exist; `/merge`'s
Change Summary Tier 1 diffs a file that no longer changes; `/dev` and `/plan`
read lines that are gone.

**File:** `commands/code.md` (the `### planning.md` block at ~line 136 and the
staging line at ~168), `commands/docs.md` (mirror sites), `commands/merge.md`
(Tier 1 at line 151), `commands/dev.md` (Step 1 read list, "Where work stands"
guidance), `commands/plan.md` (Step 2 sub-step 3 major-version derivation)

**Implementation:**

All five changes are **convention-detected**: the marker is
`test -d tasks/shipped`. Absent it, current behavior is unchanged — consumer
projects keep working until they migrate.

- **`commands/code.md`** — the `### planning.md` block becomes
  `### tasks/shipped/ (or planning.md)`: if `tasks/shipped/` exists, write a
  NEW file `tasks/shipped/<today>-v<X.Y>-<slug>.md` containing the phase
  narrative (problem → what shipped → key findings — the prose that used to be
  the Recently-shipped bullet), and do NOT edit `planning.md`; otherwise the
  existing planning.md instructions apply verbatim (keep them, indented under
  the legacy branch). Staging line gains `tasks/shipped/`.
- **`commands/docs.md`** — same treatment at its mirror sites (~lines 33, 43,
  99).
- **`commands/merge.md` Tier 1** — becomes: check
  `git diff HEAD~1 --name-only -- tasks/shipped/` first; if this merge added a
  shipped file, use its content as the Change Summary source. Fall back to the
  existing `planning.md` "Recently shipped" diff (keep that text as the legacy
  branch), then Tier 2/3 unchanged.
- **`commands/dev.md`** — Step 1: alongside `planning.md`, read the newest 1-2
  files from `tasks/shipped/` (`ls -1 tasks/shipped/*.md 2>/dev/null | sort -r
  | head -2`) — they are now where "where work stands" lives; the "Where work
  stands" template bullet references them.
- **`commands/plan.md`** — Step 2 sub-step 3's major-version derivation
  reorders: derive from the highest `v<N>.<M>:` entry in `ROADMAP.md` (both
  list and heading forms — keep that existing wording), with `planning.md`'s
  Active Roadmap Phase line as the legacy fallback for projects that still
  carry one. This inverts the current order; `ROADMAP.md` was already the more
  authoritative source (the claim script itself reads it from `origin/main`).

Frontmatter unchanged in all five (`tests/commands/frontmatter.sh` still
passes).

**Acceptance Test:**

```bash
bash tests/commands/frontmatter.sh 2>&1 | grep -cE "PASS"   # all 10 still valid
grep -n "tasks/shipped" commands/code.md commands/docs.md commands/merge.md commands/dev.md | wc -l   # >0 each
grep -n "Recently shipped" commands/merge.md   # present only as the legacy fallback
```

---

### Change 6: the rule text

**Problem:** `CLAUDE.md:126` (the post-merge Change Summary tiers) and
`settings/claude-global.md:52` ("Docs Ship With the Code") both describe
`planning.md` as the per-phase write target and Tier-1 source.

**File:** `/home/rich/dev/CLAUDE.md` (the post-merge bullet at ~line 126 and
the `/code` chain bullet that names planning.md), `settings/claude-global.md`
(line 52, and its own post-merge Change Summary paragraph)

**Implementation:** Update both to name the shipped-file source first with the
planning.md diff as the legacy fallback (same order as `commands/merge.md`),
and "Docs Ship With the Code" to say `/code` writes `tasks/shipped/` +
`tasks/lessons/` + `ROADMAP.md` + `README.md` where the convention exists,
`planning.md` where it does not. Keep both edits tight — these are rule files,
not essays.

**Acceptance Test:**

```bash
grep -c "tasks/shipped" CLAUDE.md settings/claude-global.md   # >0 each
./scripts/gate_fast.sh                                        # PASS
```

---

## What NOT to Do

- **Do not write any shipped file before Change 1 lands.** Fourth occurrence of
  the `tasks/**` trap; the Consumer Audit rule now exists because of it.
- **Do not touch `ROADMAP.md`'s per-phase entries or parsing.** The atomic
  version-claim guard reads it from `origin/main`; it is the one remaining
  per-phase append, kept deliberately.
- **Do not generate a combined `planning.md` from the directory.** Nothing
  machine-reads the shipped narrative; a generated file reintroduces the
  conflict (the v1.23 decision, same reasoning).
- **Do not keep an "Active Roadmap Phase" line that /code updates.** A small
  per-phase edit still conflicts on every concurrent pair — zero-touch is the
  point. `/plan`'s ROADMAP fallback makes it free.
- **Do not make the command changes unconditional.** Consumer projects'
  `planning.md` conventions differ; the `tasks/shipped/` directory is the
  opt-in marker, exactly like `.claude/worktree-deps`.
- **Do not silently skip an unparseable bullet, or guess a missing date.**
  Abort naming the line — v1.23's contract, same reason.
- **Do not use `ls -t`** for newest-first; filename order is date order.
- **Do not migrate consumer projects' planning.md from this session.**
  Cross-project writes are forbidden; the committed script is how they do it
  themselves.
- **Do not delete the Taxonomy migration note.** Static history, referenced by
  the R→v mapping.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `.gitignore` | Modify | `!tasks/shipped/` + `!tasks/shipped/*.md`, directory rule first |
| `scripts/migrate-shipped.sh` | New | Section→files migration: 36 phase + 14 chore bullets; dry-run default; abort-not-skip |
| `tests/shipped-dir/run.sh` | New | ~9 assertions incl. pipe regression, both filename shapes, abort paths |
| `tasks/shipped/*.md` + `README.md` | New | 50 migrated entries + conventions doc |
| `planning.md` | Rewrite | Static orientation doc; Recently shipped + In flight deleted |
| `commands/{code,docs,merge,dev,plan}.md` | Modify | Convention-detected on `tasks/shipped/`; legacy planning.md branch kept |
| `CLAUDE.md`, `settings/claude-global.md` | Modify | Tier-1 source + Docs-Ship wording |
| `ROADMAP.md` | Modify | v1.24 entry (handled by `/code` — which also writes this phase's own shipped file, dogfooding) |

No `install.sh`/`verify.sh`/`gate_fast.sh` changes: verified —
`docs_only_diff.sh`'s `tasks/*` glob crosses slashes under `[[ == ]]`, no fleet
script reads `planning.md`, and test suites auto-discover.

## Implementation Order

1. **Change 1** — `.gitignore`.
2. **Change 2** — the migration script.
3. **Change 3** — its tests, on fixtures, before the real run.
4. **Change 4** — migrate, verify preservation mechanically, rewrite
   `planning.md`.
5. **Change 5** — the five commands.
6. **Change 6** — rule text. Gate; confirm the count moved from 329.

## Verification Checklist

- [ ] Probe file under `tasks/shipped/` shows `??` in `git status --porcelain`
- [ ] Dry run reports 36 phase + 14 chore entries, writes nothing
- [ ] `--apply` → 50 files; phase files `<date>-v<X.Y>-<slug>.md`, chore files `<date>-<slug>.md`
- [ ] All 50 bullet bodies verbatim in exactly one file each (mechanical check)
- [ ] Active-line prose confirmed duplicated in the v1.23 shipped file before deletion
- [ ] Unparseable line and missing-date bullets abort, writing nothing
- [ ] `planning.md` ≤ ~25 lines; no Recently shipped, In flight, or Active lines; taxonomy check clean
- [ ] `/plan`'s major-version derivation prefers ROADMAP.md; legacy fallback documented
- [ ] All five commands convention-detect `tasks/shipped/`; legacy branches preserved verbatim
- [ ] `bash tests/commands/frontmatter.sh` — all 10 pass
- [ ] `python3 scripts/check_version_collision.py` — unaffected
- [ ] `./scripts/gate_fast.sh` — PASS, count up from 329
- [ ] No file under `projects/` modified
- [ ] Markdown: blank line after headings, fenced blocks tagged with a language
