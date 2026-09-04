# v1.29: Identifier Descriptors

## Coding Specification for Implementation

## Design Philosophy

A real `/merge` report, quoted back by the reader who could not parse it:

> Release cut — `make release VERSION=4.141.0`; tag `v4.141.0` pushed. Milestone **#157** closed — v4.141: Retry Policy Hook. **#383** reply posted, after the Release existed. Left open for Kermit v3 to close, matching how **#365/#366/#367/#369** were handled.

Six numbering systems in three sentences, and nothing says which is which. Verified against the live repo:

| In the report | What it actually is | How you could tell |
| ------------- | ------------------- | ------------------ |
| `v4.141: Retry Policy Hook` | Roadmap Phase | it reads like one |
| `#384` | a **PR** | you could not |
| `#383` | an **issue** | you could not |
| milestone `#157` | GitHub's sequential counter, holding `v4.141` | only from the word before it |
| `4.141.0` / `v4.141.0` | `__api_version__` and release tag | two spellings of one phase |
| `a2551bb1` | commit SHA | shape |
| `2282` | a test count | not an identifier at all |

Three of these are ambiguous *by construction*, not by carelessness. **GitHub issues and PRs share one number space**, so `#383` and `#384` are adjacent integers naming different kinds of object. **Milestone numbers are a separate sequential counter** — `#157` holds `v4.141`, and the two numbers have no relationship whatsoever, so citing the milestone number communicates nothing a reader can use. And dev-platform is at `v1.29` while the harness is at `v4.141`: **independent counters wearing the same `v<n>.<n>` shape**, with nothing in a report saying which project you are reading about.

**The fix the reader asked for is a descriptor in front of every number.** `issue #383`, `PR #384`, `milestone v4.141`. It is small, it is mechanical to apply while writing, and it removes the ambiguity at the only place it matters — the moment of reading.

`CLAUDE.md` already has a **Which Identifier To Cite** rule from v1.26. It covers three identifiers (Roadmap Phase version, PR number, release tag) and has two holes this phase closes: it never mentions **milestone numbers**, which is the worst offender in the example above, and it governs "prose, reports, commit bodies" in the abstract while none of the actual report templates in `commands/` or `settings/claude-global.md` carry the convention.

**A detector would be vacuous here, and this spec deliberately does not build one.** The measurement says so. Scanning every `#N` reference in `CLAUDE.md`, `commands/`, `docs/` and `settings/` finds **20 references, of which 5 lack a descriptor** — and four of those five are the `owner/repo#N` form (`teelr/dev-platform#68`), which is already unambiguous because it names the repo, while the fifth is `Ask #51`, which has a descriptor. **The tracked markdown is already fine.** A file-scanning check would go green on day one and stay green while the actual problem — what gets written into chat reports — continued unchecked. This repo has a rule about that (a green gate whose output proves nothing is worse than no gate), and shipping a check that cannot see the surface it claims to guard would be an instance of it. The enforcement here is the rule plus the templates that shape what gets written; the honest thing is to say that rather than manufacture symmetry with v1.26's `check-phase-tags.sh`.

*(That measurement is itself a correction: a first grep reported "99 references, 73 with descriptors, ~26 bare." It piped `-o` match fragments into a second `grep`, so the descriptor test ran against the fragment `#92` with its line context already stripped. The number in this spec comes from a line-context scan.)*

**Branching strategy:** single branch, single PR. Three small Phases, none independently useful — the rule without the templates changes nothing about what gets written, and the templates without the rule have nothing to point at.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `CLAUDE.md`, `settings/claude-global.md`, `commands/*.md`, `docs/*.md` | Markdown | Rules, report templates and reference docs. No code ships in this phase. |

No new components, no new scripts. The Language Architecture Decision Matrix is not in play.

## Overview

**Phase 1: The rule**

1. Change 1 — extend `CLAUDE.md`'s **Which Identifier To Cite** with the descriptor mandate, a milestone-number row, and cross-project qualification.
2. Change 2 — `docs/GLOSSARY.md` entries a confused reader can actually look up.

**Phase 2: The report templates, where it bites**

3. Change 3 — `settings/claude-global.md` end-of-step report format.
4. Change 4 — `commands/merge.md`: post-merge report and Change Summary.
5. Change 5 — `commands/plan.md`: the claimed-version line.
6. Change 6 — `commands/pr.md`: milestone reporting.

**Phase 3: The worked example**

7. Change 7 — the decoded real report in `docs/RULE_RATIONALE.md`, plus the recorded decision not to build a detector.

---

## Phase 1: The Rule

### Change 1: Descriptors, milestones, and cross-project qualification

**Problem:** The v1.26 rule ranks three identifiers but never says to label them, and omits milestone numbers entirely — the one identifier in the motivating example that carries no recoverable meaning.

**File:** `CLAUDE.md` — the `## Which Identifier To Cite` section (currently ~7 lines plus a 3-row table, immediately before `## Workflow Principles`)

**Implementation:**

Keep the existing three rows; their ranking guidance is unchanged and correct. Add, in this order:

1. **The descriptor rule, stated first, because it applies to every row.** Every `#<number>` in anything a human reads carries a type word immediately before it: `PR #384`, `issue #383`, `milestone #157`. Never a bare `#384`. The one exempt form is `owner/repo#N` (`teelr/kermit-harness#200`), which is already unambiguous — GitHub renders it as a cross-repo link and the repo name supplies the context. This is a writing rule, applied while writing; there is no checker (see Change 7).

2. **A fourth table row — Milestone number.** What it is: GitHub's own sequential counter, assigned across the repo's entire history and bearing **no relation** to the version the milestone holds — `milestone #157` holds `v4.141`, `milestone #40` holds `v1.29`. When to cite it: **essentially never in prose.** Cite the milestone by its title (`milestone v4.141: Retry Policy Hook`). The number is an API argument — it belongs in a `gh api ... /milestones/157` command, not in a sentence, because a reader cannot map it to anything.

3. **Cross-project qualification.** Roadmap Phase versions are per-project counters that all wear `v<n>.<n>`: dev-platform is on `v1.29`, kermit-harness on `v4.141`, kermit-v3 on `v0.197`. In any report that mentions more than one project, or in any cross-repo comm, name the project with the version — `kermit-harness v4.141`, not `v4.141`. Within a single project's own session, bare `v1.29` is fine.

Add one worked line showing the before/after of the motivating report, so the rule carries its own example.

**Acceptance Test:**

```bash
grep -n "milestone #157" CLAUDE.md          # the milestone row exists and names the real example
grep -c "owner/repo#N" CLAUDE.md            # the exempt form is stated
bash scripts/check_spec_taxonomy.sh          # CLAUDE.md still parses
```

---

### Change 2: Glossary entries a confused reader can look up

**Problem:** `docs/GLOSSARY.md` has entries for **PR number** and **Release tag** (added v1.26) and for **GitHub Milestone**, but nothing that answers "what is `#157` and why does it not match `v4.141`", which is the question the reader actually had.

**File:** `docs/GLOSSARY.md` — the `### GitHub Milestone` entry (line ~59) and the `### PR number` entry (line ~97)

**Implementation:**

Extend `### GitHub Milestone` with the number-vs-title distinction: the milestone's *title* is 1:1 with the Roadmap Phase and is what to cite; its *number* is an unrelated sequential counter used only as an API argument. Name a live pair (`milestone #40` ↔ `v1.29: Identifier Descriptors`) so the mismatch is concrete rather than abstract.

Extend `### PR number` with the shared-number-space fact stated as a reader problem, not a trivia item: an issue and a PR can be adjacent integers, so a bare `#N` does not even reveal which kind it is — hence the descriptor. Cross-link both entries to the `CLAUDE.md` rule.

**Acceptance Test:**

```bash
grep -n "sequential counter" docs/GLOSSARY.md
grep -n "adjacent" docs/GLOSSARY.md
./scripts/gate_fast.sh    # markdown/link checks
```

---

## Phase 2: The Report Templates, Where It Bites

### Change 3: The end-of-step report format

**Problem:** `settings/claude-global.md` defines the required end-of-step format (the `{results}` + `Ready for /{next-step}` shape at lines ~24-34). Every workflow report a human reads is emitted under it, and it says nothing about identifiers — which is why the rule existed since v1.26 and the motivating report still shipped bare numbers.

**File:** `settings/claude-global.md` — the "Required end-of-step format" block

**Implementation:**

Add a short clause to that section: in `{results}`, every `#<number>` carries its type word, and a milestone is named by title. Point at `CLAUDE.md`'s rule for the full table rather than restating it — this file is the deployed global behaviour spec and should stay short.

Note this file deploys to `~/.claude/CLAUDE.md` as a real file via `scripts/install.sh`, so the change reaches every session in every project, which is the point: the harness report that prompted this was not a dev-platform report.

**Acceptance Test:**

```bash
grep -n "type word" settings/claude-global.md
bash tests/install/run.sh     # deployment contract unchanged
```

---

### Change 4: `/merge`'s post-merge report and Change Summary

**Problem:** `commands/merge.md` is where the motivating report came from. Step 7's Roadmap-Phase-completion sub-step (line ~201) instructs closing the milestone via `gh api ... /milestones/<n>`, and its reporting sub-step says to print what post-merge did — with no guidance on how to name any of it.

**File:** `commands/merge.md` — Step 7 sub-steps 5 and 7, and Step 6 ("Report the merge")

**Implementation:**

Leave the `gh api ... /milestones/<n>` command exactly as it is — the number is the correct API argument. Change only the *reporting*: the report says `milestone v<X.Y>: <Title> closed`, not `milestone #<n> closed`. Add to Step 6 and sub-step 7 that the merge commit is cited as `PR #<n>` with its type word, and that a linked issue in another repo is cited as `<owner>/<repo>#<n>` — the exempt form — because a cross-repo bare number is the worst case of all.

**Acceptance Test:**

```bash
grep -n "milestone v<X.Y>" commands/merge.md
bash tests/commands/frontmatter.sh    # command file still valid
```

---

### Change 5: `/plan`'s claimed-version line

**Problem:** `commands/plan.md:38` tells the agent to parse and report `Claimed v<X.Y> — milestone #<N>: <title>`, which is `claim_roadmap_version.py`'s own output. That line is where a bare milestone number first enters a report, at the very start of every phase.

**File:** `commands/plan.md` — Step 2 sub-step 3

**Implementation:**

The script's output is what it is and is not changing here (it prints the number because the number is what the API returned). Change the *instruction*: parse `v<X.Y>` from it, and when reporting the claim to the user, name the milestone by title — `claimed v1.29: Identifier Descriptors` — rather than echoing the raw `milestone #40`. Say the number may be kept if a subsequent `gh api` call in the same report needs it.

**Acceptance Test:**

```bash
grep -n "name the milestone by title" commands/plan.md
bash tests/commands/frontmatter.sh
```

---

### Change 6: `/pr`'s milestone reporting

**Problem:** `commands/pr.md` Step 3 auto-detects the milestone by title (correctly — it queries `startswith("v<X.Y>:")`), but its Step 6 report says only to print the PR URL, leaving the milestone unnamed in the report.

**File:** `commands/pr.md` — Step 6

**Implementation:**

The report names the milestone by its title, which Step 3 already has in hand, and labels the PR number with its type word. This is the smallest change in the phase; it is included because `/pr` and `/merge` are the two commands whose reports a human reads most often, and leaving one inconsistent is how a convention erodes.

**Acceptance Test:**

```bash
grep -n "milestone" commands/pr.md | tail -3
bash tests/commands/frontmatter.sh
```

---

## Phase 3: The Worked Example

### Change 7: The decoded report, and why there is no detector

**Problem:** Two things need somewhere to live. The decode table at the top of this spec is the most useful artifact in the phase and specs are not where people look. And the decision *not* to build a checker needs recording, or the next phase to touch this will add one for symmetry and it will pass vacuously forever.

**File:** `docs/RULE_RATIONALE.md` — a new section

**Implementation:**

A section carrying (a) the real six-system report and its decode table, as the concrete illustration of why the rule exists, and (b) the measurement and the reasoning behind having no detector: 20 `#N` references in the tracked rules/commands/docs, 5 without a descriptor, 4 of those the already-unambiguous `owner/repo#N` form. The tracked markdown was never the problem; chat reports are, and a file scan cannot see them. State plainly that a green check over files would be an instance of the failure this repo already recorded — a gate whose output proves nothing.

Record the counting error honestly too: the first measurement said "~26 bare" because it piped `grep -o` fragments into a second `grep`, testing the descriptor against text whose line context had already been stripped. It is a good small example of a measurement that looks like evidence and is not.

**Acceptance Test:**

```bash
grep -n "Identifier Descriptors" docs/RULE_RATIONALE.md
./scripts/gate_fast.sh
```

---

## What NOT to Do

- **Do not build a file-scanning checker for bare `#N`.** The measurement says the tracked markdown is already compliant; such a check would go green immediately and stay green while the real surface — chat reports — drifted. Change 7 records this decision so it is not re-litigated.
- **Do not change `gh api ... /milestones/<n>` calls.** The number is the correct API argument. Only prose and reports change.
- **Do not change `claim_roadmap_version.py`'s output.** It prints what the API returned; the instruction that consumes it changes instead.
- **Do not flag `owner/repo#N` as a violation.** It is the exempt form — the repo name already supplies the context a descriptor would.
- **Do not restate the full rule in `settings/claude-global.md`.** That file is the deployed global behaviour spec and stays short; it points at `CLAUDE.md`.
- **Do not rewrite historical records** in `tasks/shipped/` to add descriptors. They are the record of what was written at the time, and this phase is about what gets written next.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `CLAUDE.md` | Modify | Descriptor mandate, milestone-number row, cross-project qualification |
| `docs/GLOSSARY.md` | Modify | Milestone number-vs-title; issue/PR shared number space |
| `settings/claude-global.md` | Modify | End-of-step report format carries the descriptor clause |
| `commands/merge.md` | Modify | Post-merge report and Change Summary name the milestone by title |
| `commands/plan.md` | Modify | Claimed-version line reports the title, not the raw number |
| `commands/pr.md` | Modify | Report names the milestone and labels the PR number |
| `docs/RULE_RATIONALE.md` | Modify | Worked decode + the recorded no-detector decision |
| `README.md`, `ROADMAP.md`, `tasks/shipped/`, `tasks/lessons/` | Modify/New | `/code`'s doc step |

## Implementation Order

1. **Change 1**, then **Change 2** — the rule and its lookup, so Phase 2 has something to point at.
2. **Change 3** — the global report format, the broadest-reach change.
3. **Changes 4, 5, 6** — the three command templates, in that order (`/merge` is where the motivating report came from).
4. **Change 7** — the rationale, written last so it can describe what actually shipped.

## Verification Checklist

- [ ] `CLAUDE.md` states the descriptor rule, the `owner/repo#N` exemption, and the milestone row naming a real pair (`milestone #40` ↔ `v1.29`)
- [ ] Cross-project qualification covered — `kermit-harness v4.141` vs bare `v4.141`
- [ ] `docs/GLOSSARY.md` answers "why does `#157` not match `v4.141`"
- [ ] `settings/claude-global.md` carries the clause and still points at `CLAUDE.md` for the table
- [ ] `/merge`, `/plan`, `/pr` report templates name milestones by title; no `gh api` call changed
- [ ] `docs/RULE_RATIONALE.md` carries the decode table, the 20/5/4 measurement, and the no-detector decision
- [ ] No `owner/repo#N` reference altered anywhere
- [ ] No file under `tasks/shipped/` rewritten
- [ ] `./scripts/gate_fast.sh` passes from the worktree **and** from the main checkout
- [ ] `./scripts/verify.sh` clean — `settings/claude-global.md` deploys correctly

`/security-review` is not required — documentation and instruction text only, no code, no auth, no external input.

## Post-merge

1. **Roadmap-Phase completion** (standard): mark v1.29 complete in `ROADMAP.md`, close its milestone, cut the `v1.29` release tag at the squash-merge commit, verify with `check-phase-milestones.sh` and `check-phase-tags.sh`.
2. **Re-run `scripts/install.sh settings`** so the amended `settings/claude-global.md` reaches `~/.claude/CLAUDE.md` — this phase's whole point is that the convention applies in *every* project's sessions, and until that install runs it applies in none of them. Verify with `scripts/verify.sh`.
3. **No consumer communication.** This is a dev-platform convention that reaches other projects through the deployed global rules file, not through anything a consumer repo installs or pins. Nothing to file.
