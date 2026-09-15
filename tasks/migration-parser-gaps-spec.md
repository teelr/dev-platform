# v1.37: Migration Parser Gaps

## Coding Specification for Implementation

## Design Philosophy

`v1.36`'s shipped record and both its PR bodies wrote "kermit's `lessons.md`/`planning.md` fail to
parse" and filed it as a `teelr/kermit-harness` problem, out of scope for dev-platform. **That
characterization was investigated and found wrong before this spec was written** — verified by
reading the actual files (`/home/rich/dev/projects/kermit/tasks/lessons.md`,
`/home/rich/dev/projects/kermit/planning.md`), not by re-running the same check and trusting its
message a second time. Both "failures" are dev-platform's own detector misclassifying an
**already-fully-migrated** file as one that still needs migrating, because of a residual,
intentionally-kept non-lesson section neither script's `detect()` function anticipated:

- **`tasks/lessons.md`**: all 152 real lessons are already split into `tasks/lessons/` (175 files
  exist there now — more have landed since). What's left is a permanent lookup table
  (`## Renumbering note — 2026-08-31`, mapping old L-numbers to new ones so an archived spec's
  citation still resolves) — explicitly documented in the file itself as "kept because it is a live
  lookup table, not history." `migrate-lessons.sh`'s `detect()` finds zero `## L<N>` headings (all
  migrated out) and falls back to counting `| `-prefixed lines anywhere in the file toward "table
  format" — which the renumbering table's rows satisfy, so it misdetects `table`, tries to parse
  them as `| Date | Lesson | Project | Status |` rows, and aborts on all 21 (verified:
  `LESSONS_FILE=.../tasks/lessons.md LESSONS_DIR=/tmp/probe bash scripts/migrate-lessons.sh
  --date-from git --ignore-heading '^## Renumbering note'` — the exact command `teelr/kermit-harness#395`
  itself recommended — still aborts with "21 row(s) unparseable", all of them the renumbering table).
- **`planning.md`**: its `## Recently shipped` section held a real table until 2026-09-07, when
  `migrate-shipped.sh` extracted all 14 entries into `tasks/shipped/` (30 files exist there now).
  What's left under that heading is explanatory prose ("Per-phase records now live in
  `tasks/shipped/`... The 14 entries that were in this table were migrated there"). `detect()` finds
  no table rows in that section and falls back to `'bullets'`, whose parser allows exactly one
  non-bullet "preamble" line before aborting — and the residual prose is 8 lines, not 1 (verified:
  `PLANNING_FILE=.../planning.md SHIPPED_DIR=/tmp/probe bash scripts/migrate-shipped.sh` aborts with
  "9 problem(s)", every one a prose line, none a real entry).

**The "157 entries in a different bullet format" story in `planning.md`'s own prose is a real,
separate, already-tracked gap — but it is NOT what's failing today**, and this spec does not touch
it. `migrate-shipped.sh` only ever reads the `## Recently shipped` section; the 157 legacy entries
live under a *different* heading, `## Where work stands`, which the tool has never read and isn't
being asked to here. That gap is `teelr/kermit-harness#396` (closed) and stays exactly where it is —
teaching the tool a whole new section/format is a real design decision, not a detector bug, and
conflating the two is exactly the mistake `v1.36` already made once.

**Both real bugs share one root cause and one fix shape**: neither `detect()` distinguishes "a file
with zero parseable entries because it's already fully migrated, leaving an intentional residual
section" from "a file with zero parseable entries because it's the wrong format or genuinely empty."
The fix in both scripts is the same shape: recognize the already-migrated case and report it via the
EXISTING `"nothing to migrate"` message convention (both scripts already use this exact phrase for
their other "no content" cases — `migrate-lessons.sh`'s missing-file check, `migrate-shipped.sh`'s
missing-section check) rather than inventing a new status. `check-migration-coverage.sh` already
handles that phrase generically (`probe()`: `if echo "${out}" | grep -q "nothing to migrate"` →
`MIGRATED (N files)` when the target directory has content, `NO SECTION` otherwise) — **verified,
not assumed**: reading `probe()`'s source confirms this branch runs before the failure-classification
branch, so no change to `check-migration-coverage.sh` itself is needed. This is why the fix is
narrowly scoped to the two `detect()` functions.

**Why this couldn't have been caught before now**: `check-migration-coverage.sh`'s own registry
fixtures (`tests/migration-coverage/run.sh`) test "dir exists, source deleted" (`done-1`) and "dir +
source with a real backlog" (`split-1`), but never "dir exists, source still exists but holds
nothing left to migrate" — the specific shape a consumer reaches only by keeping the emptied-out
source file rather than deleting it. `kermit-v3` reached "fully migrated" by deleting
`tasks/lessons.md` outright, which takes the OTHER short-circuit path in `probe()`
(`[[ ! -f "${src}" ]]`) and never exercises `detect()` at all — kermit-harness is the first (and
so far only) consumer to reach "fully migrated" while keeping the source file, which is exactly why
nobody hit this until now.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/migrate-lessons.sh`, `scripts/migrate-shipped.sh` (Python block edits) | Bash + Python | Both scripts already embed their parsing logic as a Python heredoc (`python3 - <<'PY' ... PY`) — matching the existing pattern, not introducing a new one. |
| `tests/migration-formats/run.sh`, `tests/migration-coverage/run.sh` | Bash | Matches every existing test suite in this repo. |

## Overview

1. **Phase 1: Fix the two detector misclassifications** — `migrate-lessons.sh`'s `detect()` stops
   counting `| ` rows found after the first `## ` heading toward "table format"; `migrate-shipped.sh`'s
   `detect()` stops forcing `'bullets'` parsing on a `## Recently shipped` section with zero real
   entries (Changes 1–2)
2. **Phase 2: Regression coverage** — two new fixtures in `tests/migration-formats/run.sh` (one per
   script) proving the exact kermit shape now reports cleanly instead of aborting; one new
   end-to-end fixture project in `tests/migration-coverage/run.sh` proving `check-migration-coverage.sh`
   classifies it `MIGRATED`, not `FAILS` (Changes 3–4)
3. **Phase 3: Correct the record** — `ROADMAP.md`'s `v1.36` entry gets a `**Corrected in v1.37:**`
   note, matching the existing precedent set by `v1.26`'s entry (Change 5)

**Demo:** `bash scripts/check-migration-coverage.sh --project kermit` today reports `FAILS` for both
columns. After this spec, the same command against the same real files reports `MIGRATED (175 files)`
and `MIGRATED (30 files)` — verified against the live `projects/kermit` checkout as this spec's own
acceptance test, not just the new offline fixtures.

---

## Phase 1: Fix the Two Detector Misclassifications

### Change 1: `scripts/migrate-lessons.sh` — `detect()` ignores post-heading table rows, reports cleanly when nothing is left

**Problem:** `detect()` (line 178) counts every `| `-prefixed, non-header/separator line in the WHOLE
file toward "table format" whenever zero `## L<N>`/`## Title (date)` headings are found — including
rows that sit inside a `## `-headed section that isn't a lesson at all (kermit's kept renumbering
table). A fully-migrated file with such a residual section gets misdetected as table format and
aborts trying to parse those rows as `| Date | Lesson | Project | Status |` entries.

**File:** `scripts/migrate-lessons.sh`, lines 189–209 (inside the Python heredoc)

**Implementation:**

Current code (lines 189–209):

```python
    numbered = sum(1 for l in lines if NUMBERED.match(l))
    dated    = sum(1 for l in lines if DATED.match(l))
    table    = sum(1 for l in lines
                   if l.startswith('| ')
                   and not re.match(r'^\|\s*(Date|-+)\s*\|', l))

    if numbered or dated:
        # Both heading shapes present in quantity is genuine ambiguity — that is
        # when a human chooses, not a heuristic.
        if numbered and dated and min(numbered, dated) > max(numbered, dated) // 4:
            print(f"migrate-lessons: ambiguous format — numbered={numbered}, "
                  f"dated={dated}. Pass --format numbered|dated.", file=sys.stderr)
            sys.exit(1)
        return 'numbered' if numbered >= dated else 'dated'

    if table:
        return 'table'

    print("migrate-lessons: no lessons found in any known format "
          f"(table/numbered/dated) in {src}", file=sys.stderr)
    sys.exit(1)
```

Replace with:

```python
    numbered = sum(1 for l in lines if NUMBERED.match(l))
    dated    = sum(1 for l in lines if DATED.match(l))

    if numbered or dated:
        # Both heading shapes present in quantity is genuine ambiguity — that is
        # when a human chooses, not a heuristic.
        if numbered and dated and min(numbered, dated) > max(numbered, dated) // 4:
            print(f"migrate-lessons: ambiguous format — numbered={numbered}, "
                  f"dated={dated}. Pass --format numbered|dated.", file=sys.stderr)
            sys.exit(1)
        return 'numbered' if numbered >= dated else 'dated'

    # No heading-format entries. Only count `| ` rows that appear BEFORE the
    # first `## ` heading toward the table-format guess — a genuine
    # table-format file (dev-platform's own convention) is a flat table under
    # one H1, never mixed with `## ` subsections. A `| ` row appearing AFTER a
    # `## ` heading belongs to THAT heading's own content: a real lesson body
    # quoting a table (already handled — see the numbered-format L1 fixture),
    # or — this is the new case — a permanently-kept, non-lesson reference
    # section in an otherwise fully-migrated file (kermit's `## Renumbering
    # note`, a lookup table for resolving archived citations, verified: it
    # sits at line 22, the table rows at lines 37+, all after it).
    first_heading = next((i for i, l in enumerate(lines) if l.startswith('## ')), None)
    scan_upto = first_heading if first_heading is not None else len(lines)
    table = sum(1 for l in lines[:scan_upto]
                if l.startswith('| ')
                and not re.match(r'^\|\s*(Date|-+)\s*\|', l))

    if table:
        return 'table'

    # Genuinely nothing left: no numbered/dated entries, and if any `## `
    # heading exists its content didn't register as a table either. This is
    # the fully-migrated case — report it the same way the missing-file case
    # above does, so check-migration-coverage.sh's existing "nothing to
    # migrate" handling (probe(), scripts/check-migration-coverage.sh) reports
    # MIGRATED (if LESSONS_DIR already has files) or NO SECTION, instead of
    # this being read as a parse failure.
    if first_heading is not None:
        print(f"migrate-lessons: no numbered/dated/table entries found in {src} "
              "— nothing to migrate", file=sys.stderr)
        sys.exit(1)

    print("migrate-lessons: no lessons found in any known format "
          f"(table/numbered/dated) in {src}", file=sys.stderr)
    sys.exit(1)
```

**Acceptance Test:**

```bash
bash -n scripts/migrate-lessons.sh

# The exact real-world case, against the actual kermit checkout — not a
# fixture stand-in. Confirms the fix against the file that motivated it.
LESSONS_FILE=/home/rich/dev/projects/kermit/tasks/lessons.md \
LESSONS_DIR=/tmp/v1.37-lessons-probe \
    bash scripts/migrate-lessons.sh --date-from git
# BEFORE this Change: "migrate-lessons: aborting, 21 row(s) unparseable — nothing written", exit 1
# AFTER:  "migrate-lessons: no numbered/dated/table entries found in
#          /home/rich/dev/projects/kermit/tasks/lessons.md — nothing to migrate", exit 1
rm -rf /tmp/v1.37-lessons-probe

# Existing fixtures still pass unchanged — this change only widens what
# counts as "nothing to migrate"; it must not touch any currently-parsing shape.
bash tests/migration-formats/run.sh
bash tests/migration-coverage/run.sh
```

### Change 2: `scripts/migrate-shipped.sh` — `detect()` requires at least one real entry before choosing `'bullets'`

**Problem:** `detect()` (line 120) falls back to `'bullets'` whenever the `## Recently shipped`
section has no table rows, with no check that the section actually holds anything bullet-shaped. A
fully-migrated section whose table was extracted, leaving only explanatory prose, gets forced through
the bullets parser, which allows exactly one non-bullet "preamble" line before aborting on every line
after it.

**File:** `scripts/migrate-shipped.sh`, lines 120–137 (inside the Python heredoc)

**Implementation:**

Current code (lines 120–137):

```python
def detect():
    """bullets | table (both inside `## Recently shipped`) | sections."""
    if fmt_arg:
        return fmt_arg
    if any(GROUND_TRUTH.match(l) for l in lines):
        return 'sections'
    try:
        s = next(i for i, l in enumerate(lines) if l.strip() == '## Recently shipped')
    except StopIteration:
        print(f"migrate-shipped: no '## Recently shipped' section in {src} — nothing to migrate",
              file=sys.stderr)
        sys.exit(1)
    e = next((i for i in range(s + 1, len(lines)) if lines[i].startswith('## ')), len(lines))
    body = lines[s + 1:e]
    if any(SHIPPED_ROW.match(l) for l in body):
        return 'table'
    return 'bullets'
```

Replace with:

```python
def detect():
    """bullets | table (both inside `## Recently shipped`) | sections."""
    if fmt_arg:
        return fmt_arg
    if any(GROUND_TRUTH.match(l) for l in lines):
        return 'sections'
    try:
        s = next(i for i, l in enumerate(lines) if l.strip() == '## Recently shipped')
    except StopIteration:
        print(f"migrate-shipped: no '## Recently shipped' section in {src} — nothing to migrate",
              file=sys.stderr)
        sys.exit(1)
    e = next((i for i in range(s + 1, len(lines)) if lines[i].startswith('## ')), len(lines))
    body = lines[s + 1:e]
    if any(SHIPPED_ROW.match(l) for l in body):
        return 'table'
    # No table rows either. Only call this 'bullets' if the body actually
    # holds at least one real entry (PHASE and BULLET are defined below, at
    # module scope, so both are already in reach here) — otherwise this is a
    # fully-migrated section whose table was already extracted, leaving a
    # residual pointer paragraph (verified: kermit's `## Recently shipped`
    # reads "Per-phase records now live in tasks/shipped/... The 14 entries
    # that were in this table were migrated there"). Forcing the bullets
    # parser onto ordinary prose aborts on its own one-preamble-line
    # allowance, not because anything needs migrating.
    if not any(PHASE.match(l) or BULLET.match(l) for l in body):
        print(f"migrate-shipped: no shippable entries in the '## Recently shipped' "
              f"section of {src} — nothing to migrate", file=sys.stderr)
        sys.exit(1)
    return 'bullets'
```

`PHASE` and `BULLET` are defined at lines 101–102, above `detect()` — both already in scope; this
Change does not move or redefine them.

**Acceptance Test:**

```bash
bash -n scripts/migrate-shipped.sh

# The exact real-world case, against the actual kermit checkout.
PLANNING_FILE=/home/rich/dev/projects/kermit/planning.md \
SHIPPED_DIR=/tmp/v1.37-shipped-probe \
    bash scripts/migrate-shipped.sh
# BEFORE this Change: "migrate-shipped: aborting, 9 problem(s) — nothing written", exit 1
# AFTER:  "migrate-shipped: no shippable entries in the '## Recently shipped' section of
#          /home/rich/dev/projects/kermit/planning.md — nothing to migrate", exit 1
rm -rf /tmp/v1.37-shipped-probe

bash tests/migration-formats/run.sh
bash tests/migration-coverage/run.sh
```

---

## Phase 2: Regression Coverage

### Change 3: `tests/migration-formats/run.sh` — two new fixtures, one per script

**Problem:** Both fixes in Changes 1–2 are proven live against `projects/kermit`'s real files as an
acceptance test, but that checkout is outside this repo, gitignored, and absent on a CI runner or a
fresh clone. Without a committed fixture, the fix has zero regression coverage the gate can ever run.

**File:** `tests/migration-formats/run.sh` (existing — two new fixtures + two new checks, following
the file's own established pattern: a `cat > "${FIX}/<name>.md" <<'EOF'` fixture block, then a
`record_pass`/`record_fail` check)

**Implementation:**

Add a fixture reproducing kermit's real `lessons.md` shape (zero lesson headings, one kept reference
table) — place alongside the other `cat > "${FIX}/...` blocks, before the checks section:

```bash
cat > "${FIX}/already-migrated-lessons.md" <<'EOF'
# Lessons

**The lessons moved to tasks/lessons/.** No new L-numbers are issued.

The renumbering note below is kept because it is a live lookup table, not
history: archived citations were deliberately never rewritten.

## Renumbering note — 2026-08-31

Use this table to resolve an old citation:

| Old | New | The entry that MOVED |
| --- | --- | -------------------- |
| L77 | L178 | Milvus VARCHAR max_length is bytes, not chars |
| L78 | L179 | bound a streaming generate by inter-pull time |
EOF
```

Add a fixture reproducing kermit's real `planning.md` `## Recently shipped` shape (table already
extracted, only pointer prose remains):

```bash
cat > "${FIX}/already-migrated-shipped.md" <<'EOF'
# Planning

## Recently shipped

Per-phase records now live in tasks/shipped/ — one file per phase, so
concurrent worktree sessions cannot collide appending to a shared table. The
entries that were in this table were migrated there already.

**Not yet migrated:** a separate legacy section elsewhere uses a bullet
format this tool does not read from here.
EOF
```

Add two checks, near the other `migrate-lessons`/`migrate-shipped` format checks (after the existing
numbered/dated/categorised checks, following the file's own ordering: lessons fixtures grouped
together, shipped fixtures grouped together):

```bash
# Check: already-fully-migrated lessons.md (residual reference table, zero
# lesson headings) reports "nothing to migrate", not a parse abort.
out="$(LESSONS_FILE="${FIX}/already-migrated-lessons.md" LESSONS_DIR="${TMP}/o11" \
        bash "${LESSONS}" 2>&1)"; rc=$?
if [[ ${rc} -ne 0 ]] && echo "${out}" | grep -q "nothing to migrate"; then
    record_pass "migration-formats: fully-migrated lessons.md with a kept reference table reports cleanly"
else
    record_fail "migration-formats: fully-migrated lessons.md mis-detected — rc=${rc}: ${out:0:200}"
fi

# Check: already-fully-migrated '## Recently shipped' (pointer prose, zero
# real entries) reports "nothing to migrate", not a bullets-parse abort.
out="$(PLANNING_FILE="${FIX}/already-migrated-shipped.md" SHIPPED_DIR="${TMP}/o12" \
        bash "${SHIPPED}" 2>&1)"; rc=$?
if [[ ${rc} -ne 0 ]] && echo "${out}" | grep -q "nothing to migrate"; then
    record_pass "migration-formats: fully-migrated '## Recently shipped' with pointer prose reports cleanly"
else
    record_fail "migration-formats: fully-migrated shipped section mis-detected — rc=${rc}: ${out:0:200}"
fi
```

**Acceptance Test:**

```bash
bash -n tests/migration-formats/run.sh
bash tests/migration-formats/run.sh
# expect: 22 PASS, 0 FAIL (20 existing + 2 new)
```

### Change 4: `tests/migration-coverage/run.sh` — end-to-end fixture proving `MIGRATED`, not `FAILS`

**Problem:** Change 3 proves the two `migrate-*.sh` scripts individually report cleanly. Nothing
proves `check-migration-coverage.sh` — the tool that actually produced the wrong `FAILS` verdict —
classifies this exact shape as `MIGRATED` end to end, through its own `probe()` logic.

**File:** `tests/migration-coverage/run.sh` (existing — one new fixture project + one new check)

**Implementation:**

Add a new fixture project after the existing `mk ...` calls and before the `categories-1` block
(around where `nothing-1` is set up) — `residual-1` mirrors kermit exactly: the source file exists
and holds the SAME already-migrated-lessons shape as Change 3's fixture, AND the target directory
already has files:

```bash
mkdir -p "${TMP}/projects/residual-1/tasks/lessons"
printf '# Already migrated\n\nBody.\n' \
    > "${TMP}/projects/residual-1/tasks/lessons/2026-01-01-already-migrated.md"
cat > "${TMP}/projects/residual-1/tasks/lessons.md" <<'EOF'
# Lessons

**The lessons moved to tasks/lessons/.**

## Renumbering note — 2026-08-31

| Old | New | The entry that MOVED |
| --- | --- | -------------------- |
| L77 | L178 | Milvus VARCHAR max_length is bytes, not chars |
EOF
```

Add `"residual-1"` to the registry-building `rows` list (the `python3 - <<'PY'` block's tuple of
project names) alongside the existing six.

Add a check after check 4 (`nothing-1` → `NO SOURCE`), before the `categories-1` section:

```bash
# ─── 4b: source exists but holds nothing left (kept reference table) + dir
# already populated → MIGRATED, not the FAILS this shipped as before v1.37 ───
residual_row="$(row residual-1)"
if echo "${residual_row}" | grep -q "MIGRATED (1 files)"; then
    record_pass "migration-coverage: fully-migrated source with a kept reference table → MIGRATED"
else
    record_fail "migration-coverage: residual-reference-table case wrong — ${residual_row}"
fi
```

**Acceptance Test:**

```bash
bash -n tests/migration-coverage/run.sh
bash tests/migration-coverage/run.sh
# expect: 12 PASS, 0 FAIL (11 existing + 1 new)
```

---

## Phase 3: Correct the Record

### Change 5: `ROADMAP.md` — correct `v1.36`'s mischaracterization

**Problem:** `v1.36`'s entry states "A real, already-verified finding surfaced but not fixed:
`check-migration-coverage.sh` fails today — kermit... fixing kermit's files is out of scope (Scope
rule)." That framing is wrong — the fix belongs to dev-platform, not kermit, and this spec ships it.
Leaving the original entry unexamined would let a wrong claim stand as the permanent record of what
was actually true. `v1.26`'s entry already set the precedent for this exact situation: append a
`**Corrected in vX.Y:**` note rather than rewriting history.

**File:** `ROADMAP.md` (existing — append one sentence to the `v1.36` entry, do not rewrite it)

**Implementation:**

Find the `v1.36: Gate Release Tier` entry. Append, immediately before its closing "Full record:"
sentence:

```markdown
**Corrected in v1.37:** the "fixing kermit's files is out of scope" framing in this entry is wrong
— the two `check-migration-coverage.sh` findings against kermit were dev-platform's own detector
misclassifying an already-fully-migrated file, not a kermit-harness problem. Fixed in
`tasks/migration-parser-gaps-spec.md`; see `tasks/shipped/<date>-v1.37-migration-parser-gaps.md`.
```

**Acceptance Test:**

```bash
grep -q "Corrected in v1.37" ROADMAP.md
grep -A2 "v1.36: Gate Release Tier" ROADMAP.md | grep -q "Corrected in v1.37"
```

---

## What NOT to Do

- **Do not teach `migrate-shipped.sh` the "Where work stands" bullet format.** That is
  `teelr/kermit-harness#396`'s still-open, separate decision (a real new parser capability, verified
  against a section this tool has never read) — not the detection bug this spec fixes. Conflating the
  two is the exact mistake `v1.36` already made.
- **Do not hardcode kermit's exact heading text ("Renumbering note", "Recently shipped" pointer
  wording) into the fix.** The fix is structural (post-heading table rows don't count; a bullets
  section needs at least one real bullet), not a string match against this one consumer's prose —
  a different consumer reaching the same "fully migrated, kept a reference section" state must be
  covered by the same code path without a new special case.
- **Do not modify anything under `projects/kermit/`.** This session verifies against the real files
  read-only (the Scope rule permits read-only cross-project operations); the fix ships entirely in
  `scripts/migrate-lessons.sh` and `scripts/migrate-shipped.sh`.
- **Do not weaken `report_and_abort`'s "an unparseable row aborts the run" guarantee.** The fix adds
  a new clean-exit path for the specific "nothing real is here" case; it does not make a genuine
  parse failure (a malformed heading, an ambiguous format) silently pass.
- **Do not rewrite `v1.36`'s ROADMAP entry.** Append the correction note per Change 5's exact
  precedent (`v1.26`'s entry); the original text stays, wrong framing and all, exactly as `v1.26`'s
  did after its own correction.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/migrate-lessons.sh` | Modify | `detect()`: ignore post-heading `\| ` rows; report "nothing to migrate" when fully migrated |
| `scripts/migrate-shipped.sh` | Modify | `detect()`: require ≥1 real entry before choosing `'bullets'`; report "nothing to migrate" otherwise |
| `tests/migration-formats/run.sh` | Modify | 2 new fixtures + checks (one per script) |
| `tests/migration-coverage/run.sh` | Modify | 1 new fixture project (`residual-1`) + check, end-to-end |
| `ROADMAP.md` | Modify | Correction note appended to `v1.36`'s entry |
| `tasks/migration-parser-gaps-spec.md` | (this file) | Spec |

## Implementation Order

1. **Phase 1 (Changes 1–2)** — the two `detect()` fixes. Independent of each other; either order works.
2. **Phase 2 (Changes 3–4)** — regression fixtures, once both fixes exist to test against.
3. **Phase 3 (Change 5)** — the ROADMAP correction, last, once the fix is proven.

All 5 Changes fit in one `/code` session — two small, independent function edits plus their tests
and one doc correction. Single feature branch/worktree → single PR.

## Verification Checklist

- [ ] `bash -n scripts/migrate-lessons.sh` and `bash -n scripts/migrate-shipped.sh` pass
- [ ] Against the REAL `projects/kermit` checkout: `migrate-lessons.sh` now reports "nothing to migrate" (not "21 row(s) unparseable") for `tasks/lessons.md`
- [ ] Against the REAL `projects/kermit` checkout: `migrate-shipped.sh` now reports "nothing to migrate" (not "9 problem(s)") for `planning.md`
- [ ] `bash scripts/check-migration-coverage.sh --project kermit` reports `MIGRATED (175 files)` and `MIGRATED (30 files)` — re-run fresh, numbers may have grown further since this spec was written; verify the STATUS is `MIGRATED`, not the exact count
- [ ] `bash scripts/check-migration-coverage.sh` (full fleet) exits 0 — the one real failure this spec exists to fix is gone, and no other consumer's verdict changed
- [ ] `tests/migration-formats/run.sh`: 22 PASS, 0 FAIL
- [ ] `tests/migration-coverage/run.sh`: 12 PASS, 0 FAIL
- [ ] `bash scripts/gate_fast.sh`: grows from 488 → 491 PASS (+3: 2 in migration-formats, 1 in migration-coverage)
- [ ] `ROADMAP.md`'s `v1.36` entry carries the `**Corrected in v1.37:**` note
- [ ] No file under `projects/` modified
- [ ] `scripts/check_spec_taxonomy.sh` passes
- [ ] Spec deviations (if any) explicitly flagged at `/code` time

## Out of Scope (Future Specs)

- **Teaching `migrate-shipped.sh` the "Where work stands" bullet format** — `teelr/kermit-harness#396`'s
  own open decision; a real new capability, not a bug fix.
- **Any other consumer's migration state** — this spec fixes the detector, not any specific consumer's
  files; re-running `check-migration-coverage.sh` fleet-wide (part of this spec's own verification) is
  the confirmation that no one else's verdict regresses, not a broader audit.
- **Filing anything against `teelr/kermit-harness`** — there is nothing to file; both findings were
  dev-platform's own bug.
