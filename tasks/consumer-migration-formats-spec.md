# v1.28: Consumer Migration Formats

## Coding Specification for Implementation

## Design Philosophy

`scripts/migrate-lessons.sh` and `scripts/migrate-shipped.sh` both say, in their own headers, that they are committed rather than run-and-discarded **"so consumer projects can port their own."** Neither one can parse any consumer's file. That claim has been in the tree since v1.23 and v1.24 and was never tested against a consumer.

Surveyed across all seven consumers, read from their working checkouts:

| Consumer | `tasks/lessons.md` | `migrate-lessons.sh` | `planning.md` | `migrate-shipped.sh` |
| -------- | ------------------ | -------------------- | ------------- | -------------------- |
| kermit | migrated (`tasks/lessons/`, 4 files) | n/a | 3,788 lines, `## Recently shipped` is a **table** | aborts (15) |
| kermit-pa | 132 × `## L<N>` | aborts | 1,659 lines, no section | no-ops |
| keystone | 316 × `## L<N>` | aborts | none | n/a |
| OPIE | 5 × `## L<N>` | aborts | 297 lines, no section | no-ops |
| SQRL | 30 × `## L<N>` + 8 category headings | aborts | none | n/a |
| kermit-v3 | 205 × `## L<N>` | aborts | 9,240 lines, 182 `## Ground Truth` | no-ops |
| keystone_prototype | 6 × `## Title (YYYY-MM-DD)` | aborts | 2,174 lines, no section | no-ops |

**694 lessons across six consumers, and the tool parses zero of them. `migrate-shipped.sh` fits zero consumers too.**

That second number is a correction to this spec's own first draft, and it is worth recording how it was found. The draft said `migrate-shipped.sh` "works" for kermit, because kermit has a `## Recently shipped` section. Nobody had run it. Building the detector first (Change 9, deliberately ordered ahead of every parser) reported `FAILS (aborting, 15 problems)` on the first run: kermit's section is a **table** (`| Version | Date | Summary |`), not the bullet list the parser expects. One consumer's worth of scope appeared out of an unverified word.

The cause is the shape both scripts were written against: dev-platform's own `lessons.md` was a **table**, one row per lesson, and its `planning.md` had a `## Recently shipped` **bullet list**. Every consumer instead uses **heading-per-entry**. The parsers encode dev-platform's format as if it were the format. This is the Derivation Sweep failure in a new costume — not two scripts deriving one value differently, but two scripts each hardcoding the one input shape their author happened to have.

**The fix is a seam, not a rewrite.** Read either script and the format-specific part is small: a regex and a loop that yields `(date, text)` pairs. Everything after that — `slugify`, `titleize`, collision-safe filename assignment, abort-on-unparseable, dry-run reporting, the write — is *near*-duplicate logic across both files, and would be triplicated the moment a third format arrives. Near, not exact: `slugify`'s empty-slug fallback is `'lesson'` in one and `'entry'` in the other, and the two emit loops differ in shape because shipped keeps phases and chores in separate lists. Both differences are real and must survive the extraction, which is what Changes 2 and 3's byte-for-byte proof is for.

**Two contracts carry forward unchanged, because they are what make these scripts safe to point at 694 irreplaceable entries.** First, an unparseable entry **aborts the whole run and names the line** — a silently skipped lesson is undetectable once the source file is deleted. Second, the derived title is cosmetic; **the original entry text is always written to the body verbatim**, so a bad title split can never lose content.

**SQRL is the constraint that shapes the parser.** Its file groups lessons under 8 category headings (`## Sails 0.12 and Waterline`, `## Billing and domain invariants`, …) that sit at the same `##` level as the lessons themselves. A parser that splits on bare `^## ` manufactures 8 junk lesson files. So each format matches a *specific* heading pattern, and a `^## ` line matching none of them aborts — with an explicit `--ignore-heading` escape so an operator can name SQRL's eight deliberately rather than the tool guessing.

**Branching strategy:** single branch, single PR. The Phases are not independently shippable — Phase 1 is a pure refactor that delivers nothing on its own, and Phase 4 is what proves Phases 2 and 3 actually work. If scope needs trimming, Phase 3 (shipped) is the clean cut line: lessons are where the 694 entries and the one confirmed corruption (kermit-v3#744) are.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/lib/entry_split.py` | Python | Both scripts already drop into `python3` for parsing — bash regex cannot express the anchored, greedy-middle patterns without mangling pipe-bearing content. This extracts what is already Python. |
| `migrate-lessons.sh` / `migrate-shipped.sh` parsers | Python (inside the existing bash wrappers) | Same file, same idiom; the bash wrapper stays as the CLI surface. |
| `scripts/check-migration-coverage.sh` | Bash | A dry-run sweep over the registry, matching `check-phase-tags.sh` and `check-phase-milestones.sh`, the detectors it is modelled on. |
| `tests/migration-formats/run.sh` | Bash | Existing per-suite runner contract. |

No new services. The Language Architecture Decision Matrix is not in play.

## Overview

**Phase 1: One splitter, two callers**

1. Change 1 — extract `scripts/lib/entry_split.py` from the duplicated halves of both scripts.
2. Change 2 — `migrate-lessons.sh` calls it, table parser unchanged.
3. Change 3 — `migrate-shipped.sh` calls it, bullet parser unchanged.

**Phase 2: The formats consumers actually have**

4. Change 4 — numbered-heading parser (`## L<N> — title`), the 688-lesson case.
5. Change 5 — dated-heading parser (`## Title (YYYY-MM-DD)`), keystone_prototype.
6. Change 6 — `--date-from` and `--ignore-heading`, the two decisions a heading format forces.

**Phase 3: Section-per-phase planning files**

7. Change 7 — section parser for `## Ground Truth (<date>, v<X.Y> <Title> — <status>)`, **and** a table parser for kermit's `| Version | Date | Summary |` shape.
8. Change 8 — `--format` override + auto-detection across all parsers.

**Phase 4: Prove it against every consumer**

9. Change 9 — `scripts/check-migration-coverage.sh`, the fleet dry-run detector.
10. Change 10 — `tests/migration-formats/` fixture suite.

---

## Phase 1: One Splitter, Two Callers

### Change 1: Extract `scripts/lib/entry_split.py`

**Problem:** `migrate-lessons.sh` (153 lines) and `migrate-shipped.sh` (180 lines) each carry their own `slugify`, `titleize`, collision-resolving filename assignment, abort-on-unparseable reporting, and dry-run/apply emit. Only the parser differs. Adding three parsers without extracting this first triplicates it.

**File:** `scripts/lib/entry_split.py` (new)

**Implementation:**

Move, verbatim where possible, from `scripts/migrate-lessons.sh:84-153` and `scripts/migrate-shipped.sh:84-180`:

- `slugify(text, words=8, fallback="entry")` — strips code spans (they make poor slugs), NFKD-normalises, takes the first 8 alphanumeric words, caps at 50 chars. **The two copies are not identical:** `migrate-lessons.sh` returns `'lesson'` when the slug comes out empty, `migrate-shipped.sh` returns `'entry'`. Merging them without a parameter silently renames files for one caller. Pass the fallback in and keep each caller's current value, or the byte-for-byte proof in Changes 2 and 3 will fail — which is the point of doing that proof.
- `titleize(text, words=12)` — cosmetic title derivation with an ellipsis past 12 words.
- `assign_filenames(entries)` — takes `(date, slug_source, body)` and returns `(filename, body)` pairs, appending `-2`, `-3`, … on collision rather than overwriting. Return the collision count so callers can report it.
- `report_and_abort(errors, tool_name)` — prints each `(lineno, line)` with the line truncated to 160 chars, then `"<tool>: aborting, N problem(s) — nothing written"`, and exits 1.
- `emit(planned, out_dir, apply_, tool_name, summary)` — dry-run prints the count and the re-run hint; apply creates the directory and writes each file.

An `Entry` dataclass (`date: str | None`, `title_source: str`, `body: str`, `version: str | None`) is the contract between a parser and the emitter. `version` is `None` for lessons and set for shipped phases, which is what selects the `<date>-v<X.Y>-<slug>.md` vs `<date>-<slug>.md` filename shape.

Import it the same way as the other two shared libs — `sys.path.insert(0, str(REPO / "scripts" / "lib"))`, matching `check_version_collision.py:47-50` and `fleet_pins.py`.

**Acceptance Test:**

```bash
python3 -c "import ast; ast.parse(open('scripts/lib/entry_split.py').read())"
bash tests/lessons-dir/run.sh    # unchanged, still green
bash tests/shipped-dir/run.sh    # unchanged, still green
```

---

### Change 2: `migrate-lessons.sh` calls the shared splitter

**Problem:** Its Python block owns both parsing and emitting.

**File:** `scripts/migrate-lessons.sh` (existing — the `python3 - <<'PY'` block at lines 72-153)

**Implementation:**

Keep the `ROW` regex and its loop exactly as they are — that parser is correct for dev-platform's own historical file and for any consumer that shares it. Replace everything after `rows.append(...)` with a call into `entry_split`. The script's observable behaviour must not change: same messages, same exit codes, same filenames.

**This is a pure refactor. Prove it byte-for-byte** rather than trusting the test suite alone: run the pre-change script and the post-change script against the same fixture into two directories and `diff -r` them.

**Acceptance Test:**

```bash
git stash list   # verify nothing of yours is stashed first (shared stack)
# Capture pre-change output from git, run both, compare:
LESSONS_FILE=tests/lessons-dir/fixtures/table.md LESSONS_DIR=/tmp/pre bash <(git show HEAD:scripts/migrate-lessons.sh) --apply
LESSONS_FILE=tests/lessons-dir/fixtures/table.md LESSONS_DIR=/tmp/post bash scripts/migrate-lessons.sh --apply
diff -r /tmp/pre /tmp/post && echo "IDENTICAL"
bash tests/lessons-dir/run.sh
```

---

### Change 3: `migrate-shipped.sh` calls the shared splitter

**Problem:** Same duplication, plus the `version`-bearing filename shape that `Entry.version` now carries.

**File:** `scripts/migrate-shipped.sh` (existing — the Python block from line ~80)

**Implementation:**

Keep `PHASE` / `BULLET` / `DATE` and their loop. Route both bullet shapes through `Entry`: a phase bullet sets `version`, a chore bullet leaves it `None`. Same byte-for-byte proof as Change 2.

**Acceptance Test:**

```bash
PLANNING_FILE=tests/shipped-dir/fixtures/planning.md SHIPPED_DIR=/tmp/pre-s bash <(git show HEAD:scripts/migrate-shipped.sh) --apply
PLANNING_FILE=tests/shipped-dir/fixtures/planning.md SHIPPED_DIR=/tmp/post-s bash scripts/migrate-shipped.sh --apply
diff -r /tmp/pre-s /tmp/post-s && echo "IDENTICAL"
bash tests/shipped-dir/run.sh
```

---

## Phase 2: The Formats Consumers Actually Have

### Change 4: Numbered-heading lesson parser

**Problem:** 688 of the 694 consumer lessons live in `## L<N> — title` sections — kermit-pa (132), keystone (316), OPIE (5), SQRL (30), kermit-v3 (205). The current parser skips every line not starting with `| `, so it reads these files as containing zero lessons and then aborts on any markdown table that happens to sit inside a lesson body.

**File:** `scripts/migrate-lessons.sh` (add a parser alongside the existing table parser)

**Implementation:**

Match `^## L(?P<num>\d+)\s*[—–-]\s*(?P<title>.+)$`. Accept em dash, en dash and hyphen — kermit-v3 and SQRL both use `—`, but do not assume it. The body runs from the heading to the line before the next `^## ` (of any kind) or EOF, and is written verbatim including the original heading line, so the `L<N>` number survives as history inside the file.

Duplicate `L<N>` numbers are **expected, not an error** — kermit-v3 has six pairs (L92, L93, L113–L116), which is the corruption that motivated kermit-v3#744. The number is not the filename key; `<date>-<slug>` is, and `assign_filenames` already de-duplicates. Report the duplicate numbers in the dry-run summary as information, since seeing them is half the value of migrating.

A `^## ` line matching neither this pattern nor a configured `--ignore-heading` aborts, naming the line. That is what stops SQRL's 8 category headings from becoming lessons.

**Acceptance Test:**

```bash
# Real consumer files, dry-run, nothing written:
LESSONS_FILE=~/dev/projects/kermit-v3/tasks/lessons.md LESSONS_DIR=/tmp/x bash scripts/migrate-lessons.sh
#   → "205 entries would become 205 files", reports 6 duplicate L-numbers
LESSONS_FILE=~/dev/projects/keystone/tasks/lessons.md LESSONS_DIR=/tmp/x bash scripts/migrate-lessons.sh
#   → 316 entries
LESSONS_FILE=~/dev/projects/SQRL/tasks/lessons.md LESSONS_DIR=/tmp/x bash scripts/migrate-lessons.sh
#   → aborts, naming all 8 category headings (Change 6 adds the escape)
```

---

### Change 5: Dated-heading lesson parser

**Problem:** keystone_prototype's 6 lessons use `## Title (YYYY-MM-DD)` — a title with a trailing parenthesised date, no number.

**File:** `scripts/migrate-lessons.sh`

**Implementation:**

Match `^## (?P<title>.+?)\s*\((?P<date>\d{4}-\d{2}-\d{2})\)\s*$`. Body extraction identical to Change 4. This format is the easy case: the date is already in the heading, so `--date-from` (Change 6) does not apply.

Order matters in detection — try the numbered pattern first, then the dated one, because a heading could in principle satisfy both.

**Acceptance Test:**

```bash
LESSONS_FILE=~/dev/projects/keystone_prototype/tasks/lessons.md LESSONS_DIR=/tmp/x bash scripts/migrate-lessons.sh
#   → 6 entries, each dated from its own heading
```

---

### Change 6: `--date-from` and `--ignore-heading`

**Problem:** Two decisions the heading formats force, neither of which the tool may make silently.

**File:** `scripts/migrate-lessons.sh` (argument parsing + the emit call)

**Implementation:**

`--date-from <mode>`, required when the detected format carries no date (the numbered variant), refused otherwise:

- `git` — for each entry, `git log --diff-filter=A -S'<heading line>' --reverse --format=%ad --date=short -- <file> | head -1`, the commit that introduced it. Accurate; slow on 316 entries, so report progress. An entry whose heading yields no commit falls back to `today` **with a warning naming it** — never silently.
- `today` — stamp every entry with the migration date. Fast, and honest as long as the choice is recorded; ordering within the batch is then arbitrary.
- `<YYYY-MM-DD>` — an explicit literal, for a project that knows its own cutover date.

`--ignore-heading <regex>` (repeatable) — a `^## ` line matching any of these is treated as a structural container, not an entry, and its text is skipped. Required for SQRL's 8 category headings. Every ignored heading is **listed in the dry-run output**, so the operator sees exactly what was dropped rather than trusting a silent filter.

Both flags appear in `--help` with the SQRL and kermit-v3 cases named as the worked examples.

**Acceptance Test:**

```bash
LESSONS_FILE=~/dev/projects/SQRL/tasks/lessons.md LESSONS_DIR=/tmp/x \
  bash scripts/migrate-lessons.sh --date-from today \
  --ignore-heading '^## (Sails|Schema|Billing|Data|Verification|Frontend|Infrastructure|Retired)'
#   → 30 entries, 8 ignored headings listed by name
LESSONS_FILE=~/dev/projects/OPIE/tasks/lessons.md LESSONS_DIR=/tmp/x \
  bash scripts/migrate-lessons.sh --date-from git
#   → 5 entries with real introduction dates
```

---

## Phase 3: Section-Per-Phase Planning Files

### Change 7: `## Ground Truth (...)` section parser, and kermit's shipped table

**Problem:** `migrate-shipped.sh` looks for a `## Recently shipped` bullet list. Only kermit has one. kermit-v3 has 182 `## Ground Truth (<date>, v<X.Y> <Title> — <status>, milestone #N)` sections in a 9,240-line file; kermit-pa (1,659), keystone_prototype (2,174) and OPIE (297) have `planning.md` files with neither shape.

**File:** `scripts/migrate-shipped.sh`

**Implementation:**

Match `^## Ground Truth \((?P<date>\d{4}-\d{2}-\d{2}),\s*(?P<rest>.+)\)\s*$`, then pull an optional `v<X.Y>` off the front of `rest` to set `Entry.version`. Body runs to the next `^## ` or EOF, written verbatim.

**Multiple sections per version are normal and must not be treated as damage.** kermit-v3 has 139 versioned sections across 114 distinct versions: v0.175 alone has seven, one per Spec Phase, plus a final COMPLETE. `assign_filenames` already resolves these to `-2`, `-3`, … but a bare version key would read as corruption. Include the heading's qualifier text (`Spec Phase 6`, `follow-up`, `quality`) in the slug so the files are self-describing, and say in the dry-run summary that repeats are expected.

Sections whose `rest` carries no version are chores (`## Ground Truth (2026-09-03, chores: exact harness pin, … — ✅ COMPLETE, no milestone)`) and take the `<date>-<slug>.md` shape.

**Also add a shipped-table parser for kermit's shape.** Its `## Recently shipped` section holds `| Version | Date | Summary |` rows — same section heading as dev-platform's bullets, different content. Match `^\|\s*(?P<version>v[\d.]+)\s*\|\s*(?P<date>\d{4}-\d{2}-\d{2})\s*\|\s*(?P<summary>.*?)\s*\|?$`, skipping the header and separator rows the way the lessons table parser already does. `version` sets `Entry.version`, so these take the `<date>-v<X.Y>-<slug>.md` shape.

Before spending effort on the other three `planning.md` files: **look at them first.** This Change is scoped to the two shapes with confirmed instances — `Ground Truth` (182 sections, kermit-v3#745) and kermit's table. If kermit-pa / OPIE / keystone_prototype turn out to use a fifth shape, note it in the shipped record and leave it — do not invent a parser for a format no one has asked to migrate.

**Acceptance Test:**

```bash
PLANNING_FILE=~/dev/projects/kermit-v3/planning.md SHIPPED_DIR=/tmp/x bash scripts/migrate-shipped.sh
#   → 182 sections; 139 versioned + 43 chores; notes v0.175 ×7 as expected repeats
PLANNING_FILE=~/dev/projects/kermit/planning.md SHIPPED_DIR=/tmp/x bash scripts/migrate-shipped.sh
#   → still parses the bullet-list shape (Change 3 regression)
```

---

### Change 8: `--format` override and auto-detection

**Problem:** With four parsers across two scripts, guessing wrong on a 316-entry file is expensive.

**Files:** `scripts/migrate-lessons.sh`, `scripts/migrate-shipped.sh`

**Implementation:**

Auto-detect by counting matches for each parser's heading pattern and choosing the highest, requiring a clear winner. **Ambiguity aborts** — a file matching two patterns roughly equally is exactly when a human should choose. `--format table|numbered|dated` (lessons) and `--format bullets|sections` (shipped) force the choice.

The detected format is always printed, in dry-run and apply alike, so the operator can catch a wrong guess before writing.

**Acceptance Test:**

```bash
LESSONS_FILE=~/dev/projects/kermit-pa/tasks/lessons.md LESSONS_DIR=/tmp/x bash scripts/migrate-lessons.sh --date-from today
#   → prints "format: numbered (132 headings)" before the count
LESSONS_FILE=~/dev/projects/kermit-pa/tasks/lessons.md LESSONS_DIR=/tmp/x bash scripts/migrate-lessons.sh --format table
#   → aborts: no table rows found
```

---

## Phase 4: Prove It Against Every Consumer

### Change 9: `scripts/check-migration-coverage.sh`

**Problem:** The claim "consumer projects can port their own" went unchallenged for two Roadmap Phases because nothing ran the scripts against a consumer. A rule with no detector is the failure this repo has now recorded three times (v1.10 milestones, v1.26 tags, and this).

**File:** `scripts/check-migration-coverage.sh` (new)

**Implementation:**

Walk `monitoring/projects.json`. For each enabled consumer, dry-run both scripts against its real `tasks/lessons.md` and `planning.md` and report one row each: `MIGRATED` (already on the directory convention), `PARSES (N entries)`, `NO SOURCE`, or `FAILS (<reason>)`. Exit non-zero when any consumer with a source file fails to parse — that is the condition the phase exists to eliminate.

Read-only and side-effect free: dry-run only, never `--apply`, and write nothing under `projects/`. Resolve project paths through `FLEET_ROOT` (`scripts/lib/main_checkout.sh`, v1.27), not the script's own location, or it reports `NO SOURCE` for every project when run from a worktree.

Not wired into `gate_fast.sh` — it depends on consumer checkouts being present, which a CI runner's fresh clone does not have. It is a fleet report, like `fleet-pins.sh`.

**Acceptance Test:**

```bash
./scripts/check-migration-coverage.sh
#   → every consumer row PARSES or MIGRATED; exit 0
#   → before Phase 2, the same command exits 1 with six FAILS — run it first to see that
./scripts/check-migration-coverage.sh    # from a worktree: identical output (v1.27 lesson)
```

---

### Change 10: `tests/migration-formats/` fixture suite

**Problem:** The real consumer files are not fixtures — they live outside the repo, they change, and CI cannot see them. The coverage check needs a committed counterpart that runs offline.

**File:** `tests/migration-formats/run.sh` (new), with fixtures under `tests/migration-formats/fixtures/`

**Implementation:**

Fixtures small enough to read, each a reduced copy of a real shape:

1. `numbered.md` — three `## L<N> —` lessons, one body containing a markdown table (the kermit-v3 abort), one pair sharing a number (the L113 case).
2. `dated.md` — two `## Title (YYYY-MM-DD)` lessons.
3. `categorised.md` — numbered lessons under two category headings (the SQRL case).
4. `sections.md` — four `## Ground Truth (...)` sections: two sharing a version, one chore with no version.

Assertions:

1. Numbered format detected and parsed; a table inside a body does not abort.
2. Duplicate `L<N>` produces two files, both bodies verbatim, and the duplicate is reported.
3. Dated format detected; date comes from the heading.
4. Category heading without `--ignore-heading` **aborts** and names the heading.
5. With `--ignore-heading`, parses, and the ignored headings are listed.
6. `--date-from today` stamps the migration date; `--date-from` refused on a dated format.
7. Ambiguous file aborts rather than guessing.
8. `--format` override forces a parser and aborts when it finds nothing.
9. Sections format: version parsed, chore section takes the version-less filename.
10. Two sections sharing a version produce two distinct self-describing filenames.
11. Dry-run writes nothing (snapshot the fixture dir before/after — the path-guard contract `tests/fleet-pins/run.sh` already uses).
12. Every entry body appears verbatim in its output file — the no-content-loss contract, asserted mechanically rather than trusted.

**Acceptance Test:**

```bash
bash tests/migration-formats/run.sh   # offline, no consumer checkouts needed
./scripts/gate_fast.sh                # auto-discovered; PASS count rises by 12
```

---

## What NOT to Do

- **Do not migrate any consumer's files.** Not with `--apply`, not by hand. The Scope rule forbids writing under `projects/`, and these scripts are run by each project's own session. This phase makes the tool work; kermit-v3#744 and #745 track the actual migrations.
- **Do not weaken abort-on-unparseable into a skip.** It is the contract that makes the tool safe to point at 694 irreplaceable entries. A skipped lesson is undetectable once the source is deleted.
- **Do not let auto-detection guess through ambiguity.** A file matching two patterns equally is exactly when a human decides.
- **Do not treat repeated `L<N>` numbers or repeated versions as errors.** The first are real corruption to surface (kermit-v3 has six); the second are deliberate per-Spec-Phase journaling. Neither should abort.
- **Do not split on bare `^## `.** SQRL's 8 category headings sit at the same level as its lessons; a naive split invents 8 lessons that do not exist.
- **Do not build a parser for a format no consumer has.** Change 7 is scoped to `Ground Truth` because that is the shape with 182 real sections and an open issue. Look before extending.
- **Do not wire `check-migration-coverage.sh` into `gate_fast.sh`.** It depends on consumer checkouts a CI runner does not have.
- **Do not rewrite any consumer's `planning.md` prose.** The target is bespoke — a transform cannot write it, and `migrate-shipped.sh` already documents that as a by-hand step.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/lib/entry_split.py` | New | Shared slugify / titleize / filename assignment / abort / emit + the `Entry` contract |
| `scripts/migrate-lessons.sh` | Modify | Calls the shared splitter; adds numbered + dated parsers, `--date-from`, `--ignore-heading`, `--format` |
| `scripts/migrate-shipped.sh` | Modify | Calls the shared splitter; adds the `Ground Truth` section parser and `--format` |
| `scripts/check-migration-coverage.sh` | New | Fleet dry-run detector over `monitoring/projects.json` |
| `tests/migration-formats/run.sh` + `fixtures/` | New | 12-assertion offline suite covering all four formats |
| `tests/lessons-dir/run.sh`, `tests/shipped-dir/run.sh` | Modify | Only if the refactor changes an interface they assert on; behaviour must not change |
| `README.md`, `ROADMAP.md`, `tasks/shipped/`, `tasks/lessons/` | Modify/New | `/code`'s doc step |

## Implementation Order

1. **Change 9 first, before any parser work** — run `check-migration-coverage.sh` against the fleet and capture the failing baseline. It is the before-picture that proves the phase did something, and writing the detector first stops it being shaped to fit whatever the parsers happen to do.
2. **Changes 1-3** (extract, then both callers) — pure refactor, proven byte-for-byte identical.
3. **Change 4**, then **Change 5** — the two lesson parsers.
4. **Change 6** — the flags both formats need; Change 4's SQRL acceptance test only passes after this.
5. **Change 8** — detection, once there are three lesson parsers to detect between.
6. **Change 7** — the shipped section parser.
7. **Change 10** — the fixture suite.
8. Re-run Change 9's detector and put the before/after in the shipped record. **Regenerate it — do not paste the table from this spec.** That is the unverified-claim failure v1.27 was about, one phase later.

## Verification Checklist

- [ ] `./scripts/check-migration-coverage.sh` exits 0 with every consumer `PARSES` or `MIGRATED`
- [ ] Baseline captured first: the same command's failing output before Phase 2
- [ ] kermit-v3's 205 lessons parse, and the 6 duplicate `L<N>` numbers are reported, not fatal
- [ ] keystone's 316 lessons parse
- [ ] SQRL parses with `--ignore-heading` and aborts without it, naming all 8 category headings
- [ ] keystone_prototype's 6 dated lessons parse with dates from their headings
- [ ] kermit-v3's 182 `Ground Truth` sections parse; v0.175's seven get distinct self-describing filenames
- [ ] kermit's bullet-list `planning.md` still parses (Change 3 regression)
- [ ] Changes 2 and 3 proven byte-for-byte identical to the pre-refactor scripts on the existing fixtures
- [ ] Every entry body appears verbatim in its output file (asserted in the suite, not assumed)
- [ ] No file under `projects/` modified — `git status` in each consumer unchanged from its pre-phase state
- [ ] `bash tests/migration-formats/run.sh` passes offline
- [ ] `./scripts/gate_fast.sh` passes from the worktree **and** from the main checkout
- [ ] `./scripts/verify.sh` clean

`/security-review` is not required — no auth, credentials, external input, or new endpoints. The scripts read local files and write only under a directory the operator names.

## Post-merge

1. **Roadmap-Phase completion** (standard): mark v1.28 complete in `ROADMAP.md`, close milestone #39, cut the `v1.28` release tag at the squash-merge commit, verify with `check-phase-milestones.sh` and `check-phase-tags.sh`.
2. **Comment on kermit-v3#744 and #745** that the blocker named in both — "the dev-platform migration script does not fit this repo's format" — is resolved, with the exact command for each, including the `--date-from` decision each will need to make. This is the sanctioned cross-repo comm; no files are written to that repo.
3. **Tell the other four consumers their format is now supported** — kermit-pa (132), keystone (316), OPIE (5), SQRL (30, needs `--ignore-heading`). File an issue per repo only where one does not already exist, and put that consumer's **verified** entry count in it, read at filing time rather than copied from this spec.
4. **Record the fourth-format finding** if kermit-pa / OPIE / keystone_prototype `planning.md` files turn out to need a parser this phase did not build — as a follow-on, not as silent scope.
