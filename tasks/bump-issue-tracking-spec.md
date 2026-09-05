# Bump Issue Tracking

## Coding Specification for Implementation

## Design Philosophy

`fleet-pins.sh` tells you a consumer is 19 minor versions behind. It does not tell you whether anyone is *doing something about it*. Today every active consumer has an open tracking issue — `teelr/keystone#515`, `teelr/kermit-v3#740`, `Osigin-LLC/SQRL#156`, `teelr/kermit-harness#391` — and none of them appears in the report. A row that is tracked and a row that has been forgotten render identically:

```text
| keystone  | ✓ | v1.12 | v1.12 | ⚠ 19 minor behind · PR #512 open → v1.13 |
| SQRL      | ✓ | v1.12 | v1.12 | ⚠ 19 minor behind                        |
```

Both are tracked. Only one looks it, and only because a Dependabot *PR* happens to exist. v1.31's own report had to assemble the tracking column by hand.

**The useful signal is the absence, not the presence.** Adding `· issue #515 open` to rows that have one is half the value; the half that changes behaviour is marking the rows that have *nothing* — no bump PR and no tracking issue — as **untracked**. That is the row nobody will act on, and it is currently invisible.

**This must never guess at absence.** "Untracked" is a claim that a lookup completed and found nothing. If the API call failed, or the response was truncated, the honest output is that we could not tell — the same rule v1.30 applied when `unverifiable` was kept from being masked by `frozen`. A false "untracked" would send someone to file a duplicate of an issue that already exists; a false "tracked" would let a real gap sit. Both are worse than saying nothing.

**One endpoint, not two.** `fetch_open_bump` currently lists `/pulls`. GitHub's `/issues` endpoint returns **both** issues and pull requests, with `.pull_request` non-null on the PRs — so one call yields both objects this phase needs. Verified against two repos rather than assumed:

```console
$ gh api "repos/teelr/keystone/pulls?state=open&per_page=100" --jq 'length'          → 1
$ gh api "repos/teelr/keystone/issues?...' --jq '[.[]|select(.pull_request!=null)]|length'  → 1
$ gh api "repos/teelr/kermit-harness/pulls?..." --jq 'length'                         → 3
$ gh api "repos/teelr/kermit-harness/issues?...' --jq '[…select(.pull_request!=null)]|length' → 3
```

So the consolidation removes a call rather than adding one — seven fewer HTTP round-trips per full sweep.

**The `.pull_request` filter is load-bearing, and the failure case is already live.** Of the 7 items `/issues` returns for keystone, exactly one is a PR — and it is `PR #512`, the Dependabot bump, whose title matches the bump regex. Without the filter the same object would be reported twice on one row: once as a PR, once as an "issue". That is not a hypothetical; it is what the unfiltered query returns today.

**The existing regexes already work on issue titles** — checked before designing around them:

| Title | `BUMP_TITLE_RE` | target |
| ----- | --------------- | ------ |
| `[dev-platform] Bump dev-platform-gate pin @v1.26 → @v1.31 — and Dependabot didn't propose it` | match | 1.31 |
| `[dev-platform] Bump dev-platform-gate pin @v1.12 → @v1.31 (+ add dependabot.yml)` | match | 1.31 |
| `chore(deps): Bump …taxonomy-check.yml from 1.12 to 1.13` | match | 1.13 |
| `[dev-platform] Migrate tasks/lessons.md → tasks/lessons/ (30 lessons…)` | skip | — |
| `Port gate-fast docs-only-diff skip pattern from dev-platform` | skip | — |
| `[dev-platform v1.22] Adopt gate_lock_acquire/release…` | skip | — |

The near-misses matter as much as the matches: three real open issues mention dev-platform without being bump asks, and none of them matches. No regex change is needed, so this phase does not touch one.

**Branching strategy:** single branch, single PR. Small, and the Changes are not independently shippable — the consolidated fetch with no rendering shows nothing, and the rendering without the fetch has nothing to show.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `monitoring/fleet_pins.py` | Python | Existing file; the fleet inspectors are Python by v0.8 convention. |
| `tests/fleet-pins/fixtures/mock-bin/gh` | Bash | Existing mock; extended, not replaced. |
| `tests/fleet-pins/run.sh` | Bash | Existing suite. |

No new components. The Language Architecture Decision Matrix is not in play.

## Overview

**Phase 1: One call, both object types**

1. Change 1 — `fetch_open_bump` reads `/issues`, splitting PRs from issues on `.pull_request`.
2. Change 2 — truncation and failure are reported, never rendered as absence.
3. Change 3 — `ProjectPin` carries the tracking issue and the lookup's own state.

**Phase 2: Make the row say what it means**

4. Change 4 — render `issue #N` distinctly from `PR #N`, and mark genuinely untracked rows.
5. Change 5 — correct the stale `(v1.31)` citation in the mock.

**Phase 3: Test the new branch points**

6. Change 6 — mock `gh` grows `/issues`; suite asserts the split, the untracked case, and the two failure cases.

---

## Phase 1: One Call, Both Object Types

### Change 1: `fetch_open_bump` reads `/issues` and splits on `.pull_request`

**Problem:** The function lists `/pulls`, so it can only ever find PRs. Tracking issues are invisible to it, and a second call would be wasteful when one endpoint returns both.

**File:** `monitoring/fleet_pins.py` — `fetch_open_bump`, ~line 252

**Implementation:**

Change the endpoint to `repos/{slug}/issues?state=open&per_page=100` and the `--jq` to emit three fields per line — number, whether it is a PR, and title:

```text
--jq '.[] | "\(.number)|\(.pull_request != null)|\(.title)"'
```

Split the results into the first matching PR and the first matching issue, keeping the existing `BUMP_TITLE_RE` / `BUMP_TARGET_RE` filtering unchanged. Return both, plus the lookup state from Change 2.

Rename to `fetch_bump_refs` — it no longer fetches only a bump PR, and a name that still says `open_bump` would misdescribe it at every call site. Keep the existing docstring's reasoning about why listing beats the search API (rate limits, eventual consistency); it applies identically here.

**Do not change the regexes.** They already match every real bump-issue title and skip every real near-miss — see the Design Philosophy table.

**Acceptance Test:**

```bash
./scripts/fleet-pins.sh --project keystone
#   → keystone row shows BOTH: PR #512 (Dependabot) and issue #515 (tracking)
#   → PR #512 appears exactly once, not also as an "issue"
```

---

### Change 2: A failed or truncated lookup is never rendered as absence

**Problem:** "No tracking issue" and "we could not find out" are different facts, and only the first justifies telling someone to file one. Two ways the second arises: the `gh` call fails (rc != 0), and the response fills the page — with `per_page=100` returning both issues *and* PRs, truncation is likelier than it was for PRs alone.

**File:** `monitoring/fleet_pins.py` — `fetch_bump_refs`

**Implementation:**

Return a third value: the lookup state, one of `"ok"`, `"failed"`, `"truncated"`.

- `rc != 0` or empty output where the repo is known reachable → `"failed"`.
- Number of returned lines `== 100` (the `per_page` ceiling) → `"truncated"`. A full page means a later item may exist that was never seen, so absence cannot be claimed. Today's largest consumer returns 11 items (kermit-harness: 8 issues + 3 PRs), so this is a guard, not a live condition — assert it with a fixture rather than waiting for it.
- Otherwise `"ok"`.

Only `"ok"` licenses the "untracked" rendering in Change 4.

**Acceptance Test:**

```bash
# Fixture-driven, in the suite: a 100-line fixture must yield "truncated",
# and a failing gh call must yield "failed" — neither may render as untracked.
bash tests/fleet-pins/run.sh
```

---

### Change 3: `ProjectPin` carries the tracking issue and the lookup state

**Problem:** The renderer needs both the issue number and whether the lookup was trustworthy.

**File:** `monitoring/fleet_pins.py` — `ProjectPin`, ~line 90; `query_project`, ~line 397

**Implementation:**

Add two defaulted fields after the existing `open_bump_to` (defaulted fields cannot precede non-defaulted ones — the dataclass already documents this constraint at `via_account`):

```python
    tracking_issue: Optional[int] = None
    bump_lookup: str = "skipped"
```

`"skipped"` is the correct default and matches `live_state`'s vocabulary: when `--source local` is used, or the repo was unreachable, no lookup happened at all. Populate both in `query_project` at the existing `fetch_open_bump` call site, which already runs only when `live_state in ("ok", "absent")`.

A frozen project still gets its lookup — v1.30 established that an open bump PR on a frozen repo is exactly the stale-PR case worth seeing, and the same holds for a tracking issue that should probably be closed.

**Acceptance Test:**

```bash
python3 monitoring/fleet_pins.py --format json --project keystone \
  | jq '.projects[0] | {open_bump_pr, tracking_issue, bump_lookup}'
#   → {"open_bump_pr": 512, "tracking_issue": 515, "bump_lookup": "ok"}
```

---

## Phase 2: Make the Row Say What It Means

### Change 4: Render `issue #N` distinctly, and mark untracked rows

**Problem:** The status cell currently appends only `· PR #N open`. It needs to show a tracking issue too, and — the point of the phase — say when a behind row has neither.

**File:** `monitoring/fleet_pins.py` — `render_markdown`, ~line 572 (the append chain at ~595)

**Implementation:**

Extend the existing append chain:

- Bump PR present → `· PR #512 open → v1.13` (unchanged).
- Tracking issue present → `· issue #515 open`.
- **Both absent, `status == "behind"`, and `bump_lookup == "ok"`** → `· untracked`.

**Every number carries its type word** — `PR #512`, `issue #515`, never a bare `#512`. Issues and PRs share one number space, which is precisely why one row may legitimately show both; `CLAUDE.md` → "Which Identifier To Cite".

`· untracked` is gated on all three conditions:

- `status == "behind"` — a frozen or up-to-date row needs no tracking issue, and marking it untracked would be noise inviting someone to file a pointless one.
- `bump_lookup == "ok"` — never claim absence from a failed or truncated read (Change 2).
- Both refs absent — an open bump PR *is* tracking, even without an issue.

Add a footnote when any row is untracked, in the same style as the existing drift and second-account notes, saying what it means and what to do. Do not add one when nothing is untracked — a footnote explaining an absent state is clutter.

**Acceptance Test:**

```bash
./scripts/fleet-pins.sh
#   → every behind row shows either a PR, an issue, or "untracked" — never blank
#   → frozen rows unchanged; up-to-date rows unchanged
```

---

### Change 5: Correct the stale `(v1.31)` citation

**Problem:** `tests/fleet-pins/fixtures/mock-bin/gh` line ~56 comments the `/pulls` branch as "open bump PRs (v1.31)". That feature shipped as `PR #105`, a chore with no phase version, and `v1.31` turned out to be Roadmap Path Input. The citation was written as a *forward guess* when v1.29 was newest — confirmed by reading the commit that introduced it (`git show 208d4ee`), so it was wrong the day it landed, not merely overtaken.

**File:** `tests/fleet-pins/fixtures/mock-bin/gh` (~line 56)

**Implementation:**

Cite `PR #105`. Change 1 rewrites this branch to `/issues` anyway, so the comment is being touched regardless.

This is the eighth instance of the pattern `tasks/lessons/2026-09-04-version-numbers-are-claims-not-predictions.md` records, and it survived that lesson's own sweep because the sweep grepped for `v1.30` — the version then being claimed — and this said `v1.31`. **Sharpen the lesson while fixing the instance:** the sweep must look for any dev-platform version at or beyond the newest tag, not only the one being claimed. Add that to the lesson file.

**Acceptance Test:**

```bash
grep -rn "v1\.3[2-9]\|v1\.[4-9][0-9]" scripts/ monitoring/ tests/ commands/ docs/ CLAUDE.md \
  | grep -v "kermit\|keystone\|harness\|v4\."
#   → no dev-platform version beyond the newest tag appears anywhere
```

---

## Phase 3: Test the New Branch Points

### Change 6: Mock `gh` grows `/issues`; suite asserts every branch

**Problem:** The mock only serves `/pulls`, and the suite has no fixture that produces an issue, a truncated page, or a failed lookup. Every new branch point in Changes 1-4 is untested until it does.

**Files:** `tests/fleet-pins/fixtures/mock-bin/gh`, `tests/fleet-pins/run.sh`

**Implementation:**

Replace the mock's `/pulls` branch with `/issues`, reading a `<owner>__<repo>.issues` fixture whose lines are `number|is_pr|title` — exactly what the real `--jq` emits, keeping the existing fixture contract that the mock returns what the real call would.

Assertions to add:

1. A repo with **both** a bump PR and a tracking issue reports both, on one row.
2. **A PR is never counted as an issue** — the keystone shape, where the only PR in the `/issues` response is itself a bump PR. This is the regression that the `.pull_request` filter exists to prevent.
3. A repo with a tracking issue and **no** PR reports `issue #N` and no PR.
4. A behind repo with neither reports `untracked`.
5. A **frozen** repo with neither does NOT report untracked (status gating).
6. An **up-to-date** repo with neither does NOT report untracked.
7. A **truncated** page (100 lines) does NOT report untracked.
8. A **failed** lookup does NOT report untracked.
9. `--source local` performs no lookup at all — assert via the existing `MOCK_GH_ARGS_FILE` mechanism that no `issues` call was made, the same way the suite already proves `--source local` makes zero `gh` calls.
10. The existing open-bump-PR assertions still pass against the new endpoint.

Assertions 5-8 are the ones worth the most: each is a way to render a confident "untracked" that is not true.

**Acceptance Test:**

```bash
bash tests/fleet-pins/run.sh
./scripts/gate_fast.sh
```

---

## What NOT to Do

- **Do not render `untracked` from a failed or truncated lookup.** It sends someone to file a duplicate of an issue that already exists. Absence must be observed, not assumed — the same rule that keeps `unverifiable` from being masked.
- **Do not drop the `.pull_request` filter.** `/issues` returns PRs, and keystone's only open PR is itself a bump PR: unfiltered, one object is reported twice on one row.
- **Do not mark a frozen or up-to-date row untracked.** Nobody should file a bump issue for either, and the noise would invite exactly that.
- **Do not change `BUMP_TITLE_RE` or `BUMP_TARGET_RE`.** They already match every real bump-issue title and skip every real near-miss; a "while we're here" widening risks matching the lessons-migration and docs-only-skip issues that legitimately mention dev-platform.
- **Do not add a second API call.** One `/issues` call replaces the `/pulls` call and serves both needs.
- **Do not file, close, or edit any consumer issue from this phase.** It reports on them; it does not touch them.
- **Do not keep the name `fetch_open_bump`.** It would misdescribe a function that returns two kinds of reference.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `monitoring/fleet_pins.py` | Modify | `/issues` fetch, PR/issue split, lookup state, two new fields, rendering |
| `tests/fleet-pins/fixtures/mock-bin/gh` | Modify | `/issues` branch + `.issues` fixture form; `(v1.31)` → `PR #105` |
| `tests/fleet-pins/run.sh` | Modify | 10 assertions |
| `tasks/lessons/2026-09-04-version-numbers-are-claims-not-predictions.md` | Modify | Sweep any version ≥ newest tag, not just the one being claimed |
| `README.md`, `ROADMAP.md`, `tasks/shipped/`, `tasks/lessons/` | Modify/New | `/code`'s doc step |

## Implementation Order

1. **Change 6's assertions 1-4 first, against the current code** — they must fail on the issue lookup and pass on the existing PR behaviour, proving the suite detects the absence before Change 1 fills it.
2. **Change 1**, then re-run — the PR assertions must stay green across the endpoint switch, which is the regression that matters.
3. **Changes 2 and 3** — lookup state and the dataclass fields.
4. **Change 4** — rendering, then assertions 5-8, each of which is a false-`untracked` guard.
5. **Change 5** with the lesson update.
6. Re-run `./scripts/fleet-pins.sh` against the **real** fleet and paste the actual output into the shipped record. Regenerate it; do not copy the table from this spec.

## Verification Checklist

- [ ] keystone's row shows `PR #512` **and** `issue #515`, with `PR #512` appearing once
- [ ] Every active consumer's row names its tracking issue: keystone `#515`, kermit-v3 `#740`, SQRL `#156`, kermit-harness `#391`
- [ ] SQRL's row resolves via the second account, as it does today
- [ ] No row reads `untracked` while a tracking issue exists
- [ ] A truncated page and a failed lookup both refuse to render `untracked`
- [ ] Frozen and up-to-date rows are unchanged
- [ ] `--source local` makes no `issues` call
- [ ] One API call per project, not two
- [ ] No dev-platform version beyond the newest tag appears anywhere in the repo
- [ ] No consumer repo touched
- [ ] `./scripts/gate_fast.sh` passes from the worktree **and** the main checkout
- [ ] `./scripts/verify.sh` clean

`/security-review` is not required — read-only reporting over the GitHub API. Token handling is unchanged (the existing per-subprocess `GH_TOKEN`), and no new credential path is introduced.

## Post-merge

1. **Roadmap-Phase completion** (standard): mark v1.32 complete in `ROADMAP.md`, close its milestone, cut the `v1.32` release tag at the squash-merge commit, verify with `check-phase-milestones.sh` and `check-phase-tags.sh`.
2. **No consumer communication.** This changes how dev-platform reports on consumer issues; nothing in any consumer repo changes, and no consumer pins anything affected.
3. **Re-run `./scripts/fleet-pins.sh`** and record the output — the standing measure that every tracked row is now visibly tracked.
