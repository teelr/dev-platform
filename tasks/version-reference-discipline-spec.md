# v1.26: Version Reference Discipline

## Coding Specification for Implementation

## Design Philosophy

Three different identifiers get used to reference shipped work, and nothing says
which to use when. `v1.25` is a **Roadmap Phase** — a unit of planned work
matching a GitHub Milestone, claimed atomically at `/plan`. `#92` is a **GitHub
PR number** — sequential across the repo, sharing a number space with issues, no
semantic meaning. `v1.13` as a **git tag** is a third thing again: the only one
consumers can actually pin. Prose jumps between them because each was written by
whatever felt natural that day, and a reader cannot tell whether two references
point at the same thing.

Chasing that inconsistency surfaced a functional gap underneath it. **Tagging
stopped at v1.13** — twelve phases ago — so v1.14 through v1.25 are unpinnable.
Meanwhile **all seven consumer projects pin `@v0.7`**, whose
`taxonomy-check.yml` runs only `check_spec_taxonomy.sh` and does **not** include
`check_version_collision.py`. Verified with `git show v0.7:...`. So the
version-collision guard shipped in v1.11, fixed in v1.12 and again in v1.13, has
**never run for a single consumer** — despite v1.11's ROADMAP entry stating every
consumer would get it "without any local wiring." That claim was true of the
workflow on `main` and false of every tag anyone was pinning.

Why it died silently is the useful part. The practice was documented — `docs/GLOSSARY.md`'s
"Cut release" entry says to tag at the merge commit closing a Roadmap Phase — but
it lived in a **reference doc nobody executes from**, not in the post-merge
runbook `/merge` actually runs. Closing the milestone is a mechanical post-merge
sub-step and has happened every single time; cutting the tag was a thing to
remember, and stopped. This repo already learned that lesson once, in v1.10,
which paired the milestone-close step with `check-phase-milestones.sh` as a
backstop. This phase applies the same pair to tags: a mechanical step plus a
detector, so it cannot quietly die again.

**Scope decision, recorded so it does not read as an oversight.** The twelve
missing tags (v1.14–v1.25) are deliberately NOT backfilled. Consumers need one
recent tag to pin, not an exact historical phase, and retroactively tagging
twelve merge commits risks mis-tagging — a wrong tag is worse than a missing
one. Historical ROADMAP entries are likewise left alone: entries reading
"Released `v1.11`" are accurate history, not stale text. The rule applies going
forward.

**Branching strategy:** single branch and single PR. The Phases are not
independently shippable — a rule with no mechanical step is what already failed,
and tagging `main` before the step exists leaves nothing to prevent the next gap.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/check-phase-tags.sh` | Bash | A `git tag` + `ROADMAP.md` comparison, matching `check-phase-milestones.sh` (v1.10), the detector this one is modelled on. |
| `tests/phase-tags/run.sh` | Bash | Existing per-suite runner contract. |
| Rule and glossary text | Markdown | Instruction and reference files. |

No new services or components — the Language Architecture Decision Matrix is not
in play.

## Overview

**Phase 1: Say which identifier to use**

1. Change 1: `CLAUDE.md` — the citation rule
2. Change 2: `docs/GLOSSARY.md` — three entries that distinguish the three identifiers

**Phase 2: Make tagging mechanical, not remembered**

3. Change 3: `CLAUDE.md` + `commands/merge.md` — cut the tag as a standard post-merge sub-step
4. Change 4: `scripts/check-phase-tags.sh` — the backstop detector
5. Change 5: `tests/phase-tags/run.sh`

**Phase 3: Catch up**

6. Change 6: tag `main`, bump the consumer template default

---

## Phase 1: Say which identifier to use

### Change 1: `CLAUDE.md` — the citation rule

**Problem:** Nothing states which identifier to cite, so prose alternates between
a phase version, a PR number, and occasionally a tag, with no way for a reader to
tell whether two references mean the same thing.

**File:** `/home/rich/dev/CLAUDE.md` (existing — add near the Development
Terminology section, which already defines the taxonomy levels this builds on)

**Implementation:**

A short rule in the file's existing terse voice. It must establish:

- **The Roadmap Phase version (`v1.25`) is what you cite** in prose, reports, and
  anything a human reads. It is stable, meaningful, and maps 1:1 to a milestone.
- **A PR number (`#92`) is provenance, never the primary reference.** Put it in
  parentheses after the phase where the exact commit matters. It shares a number
  space with issues, so `#325` alone is ambiguous about what it even refers to.
- **A git tag (`v1.13`) means one specific thing: what consumers pin.** Same
  string as the phase version, different object — the phase is the work, the tag
  is the artifact. Cite it only when talking about what a consumer can depend on.
- A one-line note that all three may share the string `v1.25` and still be
  different things, which is precisely why the rule exists.

Keep it to a short section. This is a rule file, not an essay.

**Acceptance Test:**

```bash
grep -n "provenance" CLAUDE.md          # the PR-number clause is present
./scripts/check_spec_taxonomy.sh        # no killed terms introduced
```

---

### Change 2: `docs/GLOSSARY.md` — distinguish the three

**Problem:** The Glossary defines "Cut release" and "Roadmap Phase" separately
but never says how a phase version, a PR number and a tag relate — which is the
actual confusion.

**File:** `docs/GLOSSARY.md` (existing — `### Cut release` at line 29; entries are
alphabetical `###` headings under `## Terms`)

**Implementation:**

Add or amend three entries, keeping alphabetical order and the file's one-paragraph
style:

- **A new entry for the PR number** — what it is, that it is assigned by GitHub,
  that it shares a number space with issues, and that it is provenance rather
  than a reference. Cross-link to Roadmap Phase.
- **A new entry for the release tag** — a git tag at the merge commit closing a
  Roadmap Phase; the only identifier consumers can pin
  (`taxonomy-check.yml@v1.26`); same string as the phase version but a different
  object.
- **Amend `### Cut release`** — it currently describes the practice as a thing
  someone does. Point it at the now-mechanical post-merge sub-step (Change 3) and
  the detector (Change 4), so a reader learns it is automatic rather than
  discretionary. Keep the existing v0.7 example sentence; it is accurate history.

**Acceptance Test:**

```bash
grep -c "^### " docs/GLOSSARY.md                 # two more than before
grep -n "provenance\|consumers pin" docs/GLOSSARY.md
```

---

## Phase 2: Make tagging mechanical, not remembered

### Change 3: cut the tag as a standard post-merge sub-step

**Problem:** Closing the milestone is a mechanical post-merge sub-step and has
happened every time. Cutting the tag was documented only in a reference doc and
stopped after v1.13. The fix is to move it to where the milestone close already
lives.

**File:** `/home/rich/dev/CLAUDE.md` (existing — the post-merge bullet at line
126, whose Roadmap-Phase-completion sub-step already lists marking the phase
complete and closing the milestone), `commands/merge.md` (existing — Step 7
sub-step 5, the same actions in the runbook `/merge` executes)

**Implementation:**

Extend the existing Roadmap-Phase-completion sub-step in both files with a third
action, alongside "mark the phase complete" and "close the milestone":

**(3) cut the release tag** at the squash-merge commit that completed the phase,
named exactly as the phase version (`v1.26`), via `gh release create` or
`git tag` + push. State that this is what consumers pin, and that skipping it
leaves the phase unpinnable — the failure that produced a twelve-phase gap.

Both files must say the same thing; `commands/merge.md` is the executable copy
and `CLAUDE.md` is the rule. Word the `merge.md` version as a concrete command
with the version and target commit substituted, matching how the milestone-close
line reads there.

Add the verification pointer to Change 4's detector, exactly as the milestone
line points at `check-phase-milestones.sh`.

**Acceptance Test:**

```bash
grep -c "cut the release tag\|release tag" CLAUDE.md commands/merge.md   # >0 each
bash tests/commands/frontmatter.sh 2>&1 | grep "merge.md"                 # still valid
```

---

### Change 4: `scripts/check-phase-tags.sh` — the backstop

**Problem:** A step in a runbook is still a step someone can skip. v1.10 paired
its milestone-close step with `check-phase-milestones.sh` for exactly this
reason, and that pairing is why milestones have never drifted. Tags need the same
backstop — and running it today must report the real twelve-phase gap.

**File:** `scripts/check-phase-tags.sh` (new file, executable)

**Implementation:**

Model it directly on `scripts/check-phase-milestones.sh` — read that file first
and match its shape: header comment stating what it catches and what it
explicitly cannot, `--help`, documented exit codes, and **not wired into
`gate_fast.sh`** (it is a diagnostic like its sibling; only its offline test
suite is gate-discovered).

Behavior: for every Roadmap Phase in `ROADMAP.md` marked complete, check whether
a git tag of the same name exists. Report any that are missing.

Details that matter:

- **Parse both ROADMAP forms** — `- **v<N>.<M>: <Title>**` (list, dev-platform's
  own) and `## v<N>.<M>: <Title>` (heading, kermit-v3's). This is the exact bug
  v1.12 had to come back and fix; do not repeat it.
- Honour `ROADMAP_PATH` (v1.13) rather than hardcoding `ROADMAP.md`, for the same
  reason its siblings do.
- "Complete" means the entry carries the `*(complete — ...)*` marker; a planned
  or in-flight phase with no tag is correct, not a finding.
- Read tags with `git tag --list`, comparing exact names.
- Exit 0 when every complete phase has a tag; exit 1 when any are missing (this
  is an actionable finding, matching `check-phase-milestones.sh`'s convention);
  exit 2 on a setup error.
- Output must name each missing tag and the phase title, and state plainly that a
  missing tag means consumers cannot pin that phase.

**Running it on this branch must report v1.14–v1.25 as missing** — twelve
findings. That is the point of the detector and confirms it works against the
real gap rather than only against fixtures.

**Acceptance Test:**

```bash
bash -n scripts/check-phase-tags.sh
./scripts/check-phase-tags.sh; echo "rc=$?"     # rc=1, names v1.14..v1.25 (12 findings)
./scripts/check-phase-tags.sh --help; echo "rc=$?"   # rc=0
grep -c "check-phase-tags" scripts/gate_fast.sh      # 0 — diagnostic, not a gate check
```

---

### Change 5: `tests/phase-tags/run.sh`

**Problem:** The detector's failure modes are silent: a ROADMAP form it does not
parse reports zero findings and looks clean — the precise shape of the v1.12 bug.

**File:** `tests/phase-tags/run.sh` (new file, executable)

**Implementation:**

Standard suite contract (`record_pass`/`record_fail`/`record_skip`, never `exit`,
auto-discovered). Offline: build fixture repos with `git init` + `git tag`, and
fixture `ROADMAP.md` files, driving the script with `ROADMAP_PATH` and a fixture
cwd. Never inspect dev-platform's own tags — the suite must not change result
when a real tag is cut.

Assertions (~8):

- `bash -n` clean; `--help` exits 0.
- Every complete phase tagged → exit 0, no findings.
- A complete phase with no tag → exit 1, output names the version and title.
- **Dual-form regression:** the same missing tag is found in BOTH the list form
  and the heading form. This is the v1.12 bug; without it a whole project's
  convention goes unchecked while the script reports clean.
- A phase NOT marked complete and untagged → not a finding (exit 0).
- `ROADMAP_PATH` override reads a custom path; the default path is unaffected.
- Missing `ROADMAP.md` → a clean skip, not a crash or a false pass.

**Acceptance Test:**

```bash
bash tests/phase-tags/run.sh    # all PASS
./scripts/gate_fast.sh          # 351 PASS today; expect ~359
```

---

## Phase 3: Catch up

### Change 6: tag `main`, bump the consumer template default

**Problem:** Even with the step and the detector in place, consumers are pinned
to `@v0.7` and the newest pinnable tag is `v1.13`. Nothing changes for them until
a current tag exists and the template points at it.

**File:** `extensions/github-actions/dev-platform-gate.yml` (existing — the
`uses:` line at 44, currently `@v1.12`, and the comment at 16)

**Implementation:**

1. **Bump the template default** from `@v1.12` to `@v1.26`. Update the comment at
   line 16 if it names a specific version.
2. **Cutting the actual `v1.26` tag is a post-merge action, not a Change** — the
   tag must point at this phase's squash-merge commit on `main`, which does not
   exist until the PR merges. It is the first execution of Change 3's new
   sub-step, which is the right way to prove that step works.

Do NOT edit any file under `projects/` to change a consumer's pin. Cross-project
writes are forbidden; consumers bump from their own sessions, prompted by the
post-merge issues below.

**Acceptance Test:**

```bash
grep -n "@v1.26" extensions/github-actions/dev-platform-gate.yml   # the uses: line
grep -rn "@v1.12" extensions/ || echo "no stale default remains"
```

---

## Post-merge step

1. **Cut the `v1.26` tag** at this PR's squash-merge commit — the first run of
   Change 3's new sub-step. Then `./scripts/check-phase-tags.sh` should report
   v1.26 as tagged and v1.14–v1.25 as still missing (expected: deliberately not
   backfilled).
2. **File one issue per consumer project** — kermit, kermit-pa, kermit-v3,
   keystone, keystone_prototype, OPIE, SQRL — asking them to bump
   `.github/workflows/dev-platform-gate.yml` from `@v0.7` to `@v1.26` from their
   own sessions. Each issue must state the concrete consequence rather than just
   "please update": on `@v0.7` the reusable workflow runs only
   `check_spec_taxonomy.sh`, so `check_version_collision.py` has never run on
   their PRs, and the v1.12/v1.13 fixes to it have never reached them. Same shape
   as the v1.22 handoff issues.

## What NOT to Do

- **Do not backfill v1.14–v1.25 tags.** Explicit scope decision: consumers need a
  recent tag, not an exact historical phase, and mis-tagging twelve merge commits
  is worse than leaving them untagged. The detector will keep reporting them,
  which is honest.
- **Do not rewrite historical ROADMAP entries.** "Released `v1.11`" is accurate
  history. The rule applies going forward; rewriting the record to look
  consistent would make it less true.
- **Do not edit any consumer's `dev-platform-gate.yml`.** Cross-project writes are
  forbidden — bump the template default and file issues.
- **Do not wire `check-phase-tags.sh` into `gate_fast.sh`.** It is a diagnostic,
  matching `check-phase-milestones.sh` and `check-comms-delivery.sh`. Only its
  test suite is gate-discovered.
- **Do not parse only one ROADMAP form.** List AND heading. This is the exact v1.12
  bug — a single-form regex reports clean while checking nothing.
- **Do not let the test suite read dev-platform's real tags.** Fixtures only, or
  the suite's result changes the moment a real tag is cut.
- **Do not put the tagging rule only in the Glossary.** That is where it already
  was, and it is why it stopped happening. The mechanical step in
  `commands/merge.md` is the load-bearing half.
- **Do not treat an untagged in-flight phase as a finding.** Only phases marked
  complete are expected to have tags.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `CLAUDE.md` | Modify | Citation rule; tag-cutting added to the post-merge sub-step |
| `docs/GLOSSARY.md` | Modify | PR-number and release-tag entries; "Cut release" points at the mechanical step |
| `commands/merge.md` | Modify | Step 7 sub-step 5 gains the tag-cut action |
| `scripts/check-phase-tags.sh` | New | Complete-phase-without-a-tag detector; dual-form, `ROADMAP_PATH`-aware; not in gate_fast |
| `tests/phase-tags/run.sh` | New | ~8 offline assertions incl. the dual-form regression |
| `extensions/github-actions/dev-platform-gate.yml` | Modify | Default pin `@v1.12` → `@v1.26` |
| `ROADMAP.md`, `tasks/shipped/`, `tasks/lessons/` | Modify/New | v1.26 entry via `/code`'s doc step |

No `.gitignore` change: `scripts/*.sh` and `tests/` are already allowed —
confirm with a probe anyway, per the Consumer Audit rule.

## Implementation Order

1. **Change 1** then **Change 2** — the rule and its reference entries.
2. **Change 3** — the mechanical step, which the rule points at.
3. **Change 4** — the detector; run it and confirm it reports the real twelve-phase gap.
4. **Change 5** — its tests, on fixtures.
5. **Change 6** — the template bump. Gate; confirm the count moved from 351.

## Verification Checklist

- [ ] `CLAUDE.md` states the phase version is canonical and the PR number is provenance
- [ ] Glossary distinguishes phase version / PR number / release tag, and "Cut release" points at the mechanical step
- [ ] Tag-cutting appears in BOTH `CLAUDE.md` and `commands/merge.md`, worded consistently
- [ ] `check-phase-tags.sh` run on this branch reports exactly v1.14–v1.25 missing (12 findings, exit 1)
- [ ] It finds a missing tag in the heading form as well as the list form
- [ ] An in-flight (not complete) untagged phase is not reported
- [ ] `ROADMAP_PATH` override honoured; missing ROADMAP is a clean skip
- [ ] `check-phase-tags.sh` is NOT referenced in `gate_fast.sh`
- [ ] Test suite reads only fixtures — cutting a real tag does not change its result
- [ ] Template default is `@v1.26`; no `@v1.12` remains under `extensions/`
- [ ] No file under `projects/` modified
- [ ] `bash tests/commands/frontmatter.sh` — `merge.md` still valid
- [ ] `./scripts/gate_fast.sh` — PASS from BOTH the main checkout and a worktree, count up from 351
- [ ] Markdown: blank line after headings, fenced blocks tagged with a language
