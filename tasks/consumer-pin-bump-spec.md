# v1.27: Consumer Pin Bump

## Coding Specification for Implementation

## Design Philosophy

The ask was "bump the seven consumers off `@v0.7`." No consumer is on `@v0.7`, and
none was on 2026-09-03 when v1.26 wrote that claim into `CLAUDE.md`, `docs/CI-INTEGRATION.md`,
`scripts/check-phase-tags.sh`, the ROADMAP entry, the shipped record, and the
titles of seven issues filed on other people's repos. The live pins, read from
each repo's default branch on GitHub:

| Repo | Live pin | Has `check_version_collision.py`? | Issue |
| ---- | -------- | --------------------------------- | ----- |
| `teelr/kermit-harness` | `v1.26` | yes | #377 closed — already bumped |
| `teelr/kermit-pa` | `v1.12` | **yes** | #178 open |
| `teelr/keystone` | `v1.12` | **yes** | #515 open |
| `teelr/kermit-v3` | `v1.13` | **yes** | #740 open |
| `teelr/OPIE` | `v1.2` | no | #9 open |
| `teelr/keystone_prototype` | `v1.0` | no | #2 open |
| `Osigin-LLC/SQRL` | unverifiable — `gh` 404s on the repo | unknown | #1, unverifiable |

Verified with `gh api repos/<slug>/contents/.github/workflows/dev-platform-gate.yml`
per repo, and `git show <tag>:.github/workflows/taxonomy-check.yml | grep -c check_version_collision`
per tag (`v0.7` → 0, `v1.0` → 0, `v1.11` → 1, `v1.12` → 1, `v1.13` → 1, `v1.26` → 1).

So the sharpest claim v1.26 made — the collision guard "has never run for a single
consumer" — is false for three of the six reachable consumers. It runs on
`kermit-pa`, `keystone`, and `kermit-v3` today and has since their `@v1.12`/`@v1.13`
bumps. It is genuinely absent on `OPIE` and `keystone_prototype`. That is a
materially different problem, with a different fix, than the one the issues describe.

**How a wrong claim survived a whole Roadmap Phase is the transferable part.**
`scripts/fleet-pins.sh` exists precisely to answer "what is each consumer pinned
to," and it was not run — the `@v0.7` number came from an example line in
`docs/CI-INTEGRATION.md:26`. Worse, running it would not have caught the error
either, because `monitoring/fleet_pins.py` reads the **local working-tree copy**
under `projects/<name>/`, not the file GitHub Actions actually runs. Those differ
right now: OPIE's local copy reads `@v1.12` while its live workflow reads `@v1.2`,
because OPIE's working tree carries an **uncommitted** template overwrite from a
past `fleet-install-template.sh --apply --force` that nobody ever committed. The
inspector reports a pin that no CI run has ever used. That is the
"Verify Against Source of Truth, Not Derived State" rule, and the inspector itself
is the thing violating it.

Two more gaps fall out of the same investigation. `keystone_prototype` is a real
consumer — it has the template, it has an issue — and it is **not in
`monitoring/projects.json`**, so no fleet tool has ever seen it; it is also the
one repo whose pin genuinely predates the guard. And `Osigin-LLC/SQRL` sits on a
different GitHub account behind the `github-teelr129` SSH host alias, so `gh api`
404s on it: any GitHub-truth inspector has to report it as unverifiable rather
than silently falling back to the local copy and calling that an answer.

**What this phase does not do: bump the consumers.** dev-platform cannot. The
Scope rule forbids writing to `projects/`, and the one carve-out
(`fleet-install-template.sh`) writes the whole template file — which would clobber
each consumer's local edits, since their files have already diverged from the
template (the `uses:` line sits at line 44 in kermit-pa, 35 in SQRL, 26 in
keystone_prototype). Each project's own session opens its own one-line PR, as
`kermit-harness` already did in its PR #380. This phase's deliverable is that the
ask reaching those sessions is **accurate**, that dev-platform can **tell whether
it happened** without trusting a local checkout, and that the next release bumps
consumers without an issue at all — three consumers already have Dependabot's
`github-actions` block and it has opened bump PRs for them before; the reason they
stalled at `v1.12`/`v1.13` is that those were the newest tags in existence until
`v1.26` was cut yesterday.

**Branching strategy:** single branch, single PR. The three Phases are not
independently shippable — correcting the record (Phase 2) states facts that only
Phase 1's inspector can re-verify, and the post-merge issue updates depend on both.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `monitoring/fleet_pins.py` changes | Python | Existing file; the fleet inspectors are Python by v0.8 convention, and this is `gh` orchestration plus text parsing, not a service. |
| `tests/fleet-pins/` additions | Bash | Existing per-suite runner contract (`tests/README.md`). |
| Rules, docs, lesson, ROADMAP | Markdown | Instruction and reference files. |

No new services or components — the Language Architecture Decision Matrix is not
in play.

## Overview

**Phase 1: Read the pin from GitHub, not from a local working copy**

1. Change 1 — `fleet_pins.py` reads each consumer's live pin from its default branch, and flags local-vs-live drift.
2. Change 2 — add `keystone_prototype` to `monitoring/projects.json`.
3. Change 3 — extend `tests/fleet-pins/run.sh` with a mock `gh` covering the live path, drift, and the unreachable repo.

**Phase 2: Correct the record**

4. Change 4 — fix the `@v0.7` claims in `CLAUDE.md`, `check-phase-tags.sh`, and `docs/CI-INTEGRATION.md`.
5. Change 5 — append correction notes to the v1.26 ROADMAP entry and the v1.26 shipped file.
6. Change 6 — lesson: a claim about another repo's state gets verified against that repo.

**Phase 3: Make the ask durable**

7. Change 7 — `docs/CI-INTEGRATION.md` gains "Keeping the pin current", with Dependabot as the standing fix.
8. Change 8 — `docs/CROSS-REPO-COMMS.md` records the SQRL account boundary and the pin-ask procedure.

**Phase 4: Fleet paths resolve to the main checkout** *(added during implementation
— see the note below)*

9. Change 9 — one shared main-checkout resolver; five fleet scripts stop resolving `projects/` against a worktree.
10. Change 10 — `tests/fleet-worktree/` proves the resolution from both locations.

**Post-merge (deferred, spec'd at the end of this file):** correct the six open
consumer issues, then re-run `fleet-pins.sh` to confirm.

### Note: Phase 4 was added mid-implementation

Change 1's own acceptance test (`./scripts/fleet-pins.sh` shows OPIE's drift)
could not run. From a worktree the inspector reports `— not adopted` for all
seven consumers, because `projects/` is gitignored and exists only in the main
checkout, while every fleet script derives its root from its own file location.
It is a pre-existing bug — five scripts, one wrong derivation copied five times —
and it is the same silent-wrong-answer failure this phase exists to correct, so
shipping "the inspector now tells the truth" while leaving it would be
inconsistent. Approved as scope at implementation time; the Derivation Sweep rule
in `CLAUDE.md` mandates fixing all copies together rather than the one that
happened to surface.

---

## Phase 1: Read the Pin From GitHub, Not From a Local Working Copy

### Change 1: `fleet_pins.py` reads the live pin and flags drift

**Problem:** `monitoring/fleet_pins.py:184` (`query_project`) reads
`<project>/.github/workflows/dev-platform-gate.yml` off local disk. CI runs the
copy on the repo's default branch. Those disagree today for OPIE (local `@v1.12`,
live `@v1.2`) because of an uncommitted overwrite in OPIE's working tree, and the
report has no way to say so. Every consumer-pin claim dev-platform has made rests
on the wrong file.

**File:** `monitoring/fleet_pins.py` (existing file — changes at the module header,
the `ProjectPin` dataclass at line 55, a new fetch helper after
`fetch_latest_release` at line 85, `query_project` at line 184, the three
`format_*` helpers at lines 233–251, `render_markdown` at 275, `render_json` at
301, and the argparse block at 318)

**Implementation:**

1. **Import the shared slug parser.** Below the existing imports, use the same
   idiom as `scripts/check_version_collision.py:47-50` — comment included, since
   the reason (resolve off `__file__`, not cwd) is identical:

   ```python
   sys.path.insert(0, str(REPO / "scripts" / "lib"))
   from repo_slug import parse_repo_slug  # noqa: E402
   ```

   Do **not** write a fourth copy of the owner/repo rule — that is the exact
   Derivation Sweep failure `scripts/lib/repo_slug.py` was extracted to end (v1.21).

2. **Add a module constant** next to `QUERY_TIMEOUT_S` (line 38):

   ```python
   TEMPLATE_REL_PATH = ".github/workflows/dev-platform-gate.yml"
   ```

   Use it for both the local `Path` join in `query_project` and the `gh api`
   contents path, so the two can never drift apart.

3. **Extend `ProjectPin`** (line 55). Keep the existing `pin` field as the
   *authoritative* pin — live when available, local otherwise — so nothing that
   already reads it breaks. Add:

   ```python
   repo: Optional[str]        # owner/repo slug, or None when it can't be derived
   local_pin: Optional[str]   # what's on this machine's disk (previous behaviour)
   live_pin: Optional[str]    # what's on the repo's default branch
   live_state: str            # "ok" | "absent" | "unreachable" | "skipped"
   drift: bool                # local_pin and live_pin both known and unequal
   ```

4. **Add `fetch_live_pin(slug)`** after `fetch_latest_release` (line 85+),
   returning `(pin, live_state)`:

   - `gh api repos/<slug> --jq .full_name` first. Non-zero → `(None, "unreachable")`.
     This probe is what separates "the file isn't there" from "this `gh` account
     cannot see this repo" — without it, SQRL's 404 is indistinguishable from a
     consumer that never adopted the template, and the report would call an
     unknown a fact.
   - Then `gh api repos/<slug>/contents/<TEMPLATE_REL_PATH> --jq .content`.
     Non-zero → `(None, "absent")`.
   - Decode with `base64.b64decode(out)` (the API returns base64 with embedded
     newlines; `b64decode` ignores them) and `.decode("utf-8", "replace")`. Search
     the decoded text with the existing `USES_RE` — the same anchored regex the
     local path uses, so a `# uses:` comment can't shadow the real directive on
     either path. No match → `("", "ok")`, which `classify` already renders as
     `unparseable`.
   - Reuse the existing `_run` helper (line 68) — it already carries the 10s
     timeout and the `FileNotFoundError` guard for a missing `gh`.

5. **Add `repo_slug_for(project_dir)`** beside it: `_run(["git", "remote",
   "get-url", "origin"], cwd=project_dir)`, then `parse_repo_slug(out)`; return
   `None` on non-zero rc, empty output, or an unparseable URL. A missing local
   checkout therefore yields `live_state="skipped"`, not a crash.

6. **Rework `query_project`** (line 184). Keep the `dev-platform` short-circuit
   exactly as it is. Then:

   - Read the local pin as today (`extract_pin`) into `local_pin`.
   - When `source` includes GitHub, derive the slug and call `fetch_live_pin`.
     When it does not, set `live_pin=None`, `live_state="skipped"`.
   - `pin = live_pin if live_state == "ok" else local_pin`.
   - `drift = live_state == "ok" and local_pin not in (None, "") and live_pin != local_pin`.
   - `adopted` stays `True` when *either* copy exists.
   - Call the existing `classify(pin, latest)` unchanged — the staleness maths
     doesn't change, only which pin feeds it.

7. **Statuses.** `classify` keeps its six values. Add exactly one new status,
   assigned in `query_project` *after* `classify` returns, and only when
   `live_state == "unreachable"`: `"unverifiable"`. Report it in `format_status`
   as `? unverifiable (no gh access)`. It must never be silently downgraded to a
   local-file answer — reporting SQRL's local copy as if it were live is the
   failure this Change exists to fix.

8. **`--source` flag** in `main` (line 318): `choices=("local", "github", "both")`,
   `default="both"`. `both` reads the local copy and the live copy (this is what
   surfaces drift); `local` is the pre-v1.27 behaviour and is what the offline
   test suite and any no-network run should use; `github` skips the local read
   entirely. Thread the value into `query_project` — it already runs under
   `ThreadPoolExecutor`, so the extra `gh` calls stay parallel across projects.
   Document the flag in the module docstring's Usage block and in
   `scripts/fleet-pins.sh`'s header comment (lines 4-10), which lists the same
   options.

9. **Markdown table** (`render_markdown`, line 275): columns become
   `Project | Adopted | Pin (live) | Pin (local) | Status`. Under `--source local`
   the "Pin (live)" column reads `—` for every row; under `--source github` the
   local column does. A drifting row gets `⚠ local ≠ live` appended to its status
   cell, naming both values. Add a footnote line under the table whenever any row
   drifts: the local copy is not what CI runs, and an uncommitted local edit is
   the usual cause.

10. **JSON** (`render_json`, line 301): emit the new fields via the existing
    `asdict`. Keep `pin` in place with its new authoritative meaning.

**Acceptance Test:**

```bash
# Live read against the real fleet (needs gh auth):
./scripts/fleet-pins.sh
#   → OPIE row shows Pin (live) v1.2, Pin (local) v1.12, status "⚠ local ≠ live"
#   → SQRL row shows "? unverifiable (no gh access)"
#   → keystone_prototype appears (Change 2) at v1.0

# Offline behaviour is unchanged:
./scripts/fleet-pins.sh --source local --latest v1.26   # pre-v1.27 output shape

# JSON carries both pins:
./scripts/fleet-pins.sh --format json | python3 -c \
  'import json,sys; [print(p["name"], p["local_pin"], p["live_pin"], p["drift"]) for p in json.load(sys.stdin)["projects"]]'
```

---

### Change 2: Add `keystone_prototype` to the fleet registry

**Problem:** `projects/keystone_prototype/.github/workflows/dev-platform-gate.yml`
pins `@v1.0` — a tag whose `taxonomy-check.yml` does not contain
`check_version_collision.py`. It is one of only two consumers where v1.26's
"the guard has never run here" claim is actually true, and it is invisible to
every fleet tool because it is not in `monitoring/projects.json`. Issue #2 was
filed against it, so it is a known consumer; only the registry disagrees.

**File:** `monitoring/projects.json` (existing file — append one object before the
closing `]`)

**Implementation:**

Add an entry matching the existing schema. `gate_cmd` must be a command that
actually exists in that repo — check for `scripts/gate_fast.sh`, then `Makefile`,
then `package.json` scripts, in that order, and if none exists set `enabled` to
`false` with a `notes` field saying so rather than inventing a command. An entry
with a wrong `gate_cmd` breaks `scripts/fleet-gate.sh` for the whole fleet, which
is a worse outcome than the project staying out of the sweep.

```json
{
  "name": "keystone_prototype",
  "path": "projects/keystone_prototype",
  "gate_cmd": "<verified command>",
  "primary_language": "<verified from the repo>",
  "enabled": true,
  "notes": "consumer since v1.0; added to the registry in v1.27 — was pinning @v1.0, predating check_version_collision.py"
}
```

**Acceptance Test:**

```bash
python3 -c 'import json; json.load(open("monitoring/projects.json"))'   # parses
./scripts/fleet-pins.sh --source local | grep keystone_prototype        # row appears
./scripts/fleet-status.sh | grep keystone_prototype                     # dashboard sees it too
```

---

### Change 3: `tests/fleet-pins/` covers the live path, drift, and the unreachable repo

**Problem:** The existing 299-line suite exercises every local-file branch and
would keep passing with the live read entirely broken.

**File:** `tests/fleet-pins/run.sh` (existing), plus new
`tests/fleet-pins/fixtures/mock-bin/gh` (new file)

**Implementation:**

Follow the mock-`gh` pattern already used by `tests/phase-milestones/run.sh` (see
its header comment, lines 5-10): an executable stub at `fixtures/mock-bin/gh`
driven by an env var, prepended to `PATH` for the assertions that need it. Two
contract details that suite already learned the hard way, and this one must match:
the mock lives under `fixtures/` so `gate_fast.sh`'s auto-discovery never runs it
as a test, and it must handle the argument shapes it is given rather than
pattern-matching loosely.

The mock reads `MOCK_GH_FIXTURE` — a directory holding one file per slug
(`owner__repo.yml`) whose presence means "repo reachable, template present with
this content", plus an optional `owner__repo.unreachable` marker meaning the repo
probe itself fails. It must base64-encode the file content for the `contents`
call, because that is what the real API returns and what the decode path under
test consumes.

Existing assertions get `--source local` added so they keep testing what they were
written to test. New assertions:

1. `--source github` against a fixture pinned `@v1.26` with `--latest v1.26` → `up-to-date`.
2. Local `@v1.12` + live `@v1.2` → status reports drift, and both values appear in the row (the OPIE case).
3. Repo probe fails → `unverifiable`, and the local pin is **not** reported as the answer (the SQRL case). Assert the local value does not appear in the status cell.
4. Repo reachable, template absent → `not-adopted`, distinct from case 3.
5. Live content with a `# uses: ...@v0.5` comment above the real `uses: ...@v1.26` → extracts `v1.26`, proving the live path uses the same anchored `USES_RE` as the local path (the v0.8 regression, re-run on the new path).
6. Live template with no `uses:` line → `unparseable`.
7. No git remote in the project dir → `live_state` is `skipped`, no crash, local pin still reported.
8. `--source local` makes zero `gh` calls — assert with a mock that appends its argv to a file and check the file stays empty. This is what keeps the suite runnable with no network.
9. `--format json` carries `local_pin`, `live_pin`, `repo`, and `drift` for a drifting fixture.

**Acceptance Test:**

```bash
bash tests/fleet-pins/run.sh          # all assertions pass, no network required
./scripts/gate_fast.sh                # suite auto-discovered; PASS count rises by 9
```

---

## Phase 2: Correct the Record

### Change 4: Fix the `@v0.7` claims in the rules and the CI guide

**Problem:** Three files state, as fact, that every consumer pins `@v0.7` and that
the collision guard has never run for any of them. Both halves are false, and the
first is where the wrong number came from in the first place.

**Files:**

- `CLAUDE.md:180` — "...stopped after v1.13 while every consumer stayed pinned to `@v0.7`."
- `scripts/check-phase-tags.sh:11` — "...unpinnable while all seven consumer projects sat on @v0.7."
- `docs/CI-INTEGRATION.md:26` — the `curl` example URL pinned at `/v0.7/`.
- `docs/CI-INTEGRATION.md:40` — the "staying on an old pin costs you checks" paragraph.
- `docs/CI-INTEGRATION.md:65` — the `--pin v0.7` example.

**Implementation:**

For `CLAUDE.md:180` and `check-phase-tags.sh:11`, the point being made — a missing
tag leaves a phase unpinnable — survives intact; only the supporting number is
wrong. Replace it with the true one: the tag gap froze consumers at `v1.12` and
`v1.13`, the newest tags that existed, for twelve phases. That is a *better*
illustration of the rule than the invented `@v0.7`, because it is what actually
happened.

For `docs/CI-INTEGRATION.md:40`, rewrite the paragraph around the verified tag
data rather than around `v0.7`: `check_version_collision.py` landed in `v1.11`;
any pin older than that has no collision detection at all, and `v1.0` and `v0.7`
are both in that bucket. Keep the paragraph's shape — old pins cost you checks
silently — and state the boundary version instead of a single example repo's pin.

For lines 26 and 65, bump the stale example pins to `v1.26`. Line 26 is a `curl`
a reader copies verbatim, so a `v0.7` there hands them a template that is nineteen
phases old — this is how the wrong number entered circulation. Prefer wording
that points at the releases page for "latest" where the example does not need a
literal tag.

Then grep the whole repo for any remaining `@v0.7` assertion about consumer state
and fix it in the same pass — Derivation Sweep, applied to a claim rather than a
value:

```bash
grep -rn "v0\.7" --include='*.md' --include='*.sh' --include='*.py' . \
  | grep -v tasks/shipped/ | grep -v '^\./tasks/.*-spec\.md'
```

Historical spec files under `tasks/*-spec.md` are left alone — they are the record
of what a past phase believed, and Change 5 handles the correction properly.

**Acceptance Test:**

```bash
grep -n "v0.7" CLAUDE.md scripts/check-phase-tags.sh docs/CI-INTEGRATION.md
#   → no remaining claim that consumers pin @v0.7
bash tests/phase-tags/run.sh    # comment-only edit to the script; suite still green
./scripts/gate_fast.sh
```

---

### Change 5: Correct the v1.26 ROADMAP entry and shipped record

**Problem:** `ROADMAP.md:45` and
`tasks/shipped/2026-09-03-v1.26-version-reference-discipline.md` both assert the
`@v0.7` claim. v1.26 set the precedent that historical entries are left alone as
accurate history — but that applies to entries that were *accurate*. A false
statement left in the record keeps being cited; the `@v0.7` number has already
propagated into seven issues on other repos.

**Files:** `ROADMAP.md` (line 45, the v1.26 entry) and
`tasks/shipped/2026-09-03-v1.26-version-reference-discipline.md`

**Implementation:**

Do not rewrite either narrative. Append a short, clearly-marked correction:

- ROADMAP.md, at the end of the v1.26 entry: one sentence stating that the
  "all seven consumers pin `@v0.7`" claim was wrong, that the real pins were
  `v1.0`–`v1.13`, and that v1.27 carries the verified table.
- The shipped file, as a `## Correction (2026-09-03, v1.27)` section at the end:
  the same fact with the per-repo numbers and the verification commands, plus the
  reason it went unnoticed — `fleet-pins.sh` was never run, and would have given a
  local-disk answer if it had been.

Both corrections point at this spec and at
`tasks/shipped/<date>-v1.27-consumer-pin-bump.md` (written by `/code`'s doc step).
Do not touch any other historical ROADMAP entry.

**Acceptance Test:**

```bash
bash scripts/check_spec_taxonomy.sh    # ROADMAP.md still parses; no killed terms
python3 scripts/check_version_collision.py   # entry edit doesn't disturb the claim guard
./scripts/gate_fast.sh
```

---

### Change 6: Lesson — verify a claim about another repo against that repo

**Problem:** The whole phase exists because a number from a doc example was
written into six places, one rule file, and seven issues on repos dev-platform
does not own, without one command run against the repos it described.

**File:** `tasks/lessons/2026-09-03-verify-consumer-state-against-the-consumer.md` (new file)

**Implementation:**

One lesson, following the existing format in `tasks/lessons/` (title as an H1
sentence, then prose — see the 2026-09-03 entries for length and tone). It must
carry three specifics, because a generic "verify your claims" lesson prevents
nothing:

1. The claim ("all seven consumers pin `@v0.7`") and where it actually came from
   (an example `curl` URL in `docs/CI-INTEGRATION.md:26`), versus the live pins.
2. That `scripts/fleet-pins.sh` — the tool built for exactly this question in
   v0.8 — was never run; and that it would have answered wrong anyway, because it
   read local working copies. A tool existing is not the same as a fact being
   checked, and a tool answering is not the same as it answering about the right
   file.
3. That the wrong number reached seven issues on other people's repos. A claim
   about another repo's state is outbound the moment it is written down; correct
   it there too, not only in the source file.

Name the check to run instead: `gh api repos/<slug>/contents/<path>` per repo, or
`./scripts/fleet-pins.sh` once Change 1 lands.

**Acceptance Test:**

```bash
ls tasks/lessons/2026-09-03-verify-consumer-state-against-the-consumer.md
git status --porcelain tasks/lessons/   # tracked, not ignored (the .gitignore trap, 5 prior hits)
./scripts/gate_fast.sh
```

---

## Phase 3: Make the Ask Durable

### Change 7: "Keeping the pin current" in the CI integration guide

**Problem:** Every pin bump so far has been a hand-filed issue answered by a
hand-written PR, and the guide never says there is another way. Three consumers
(`kermit-pa`, `keystone`, `kermit-v3`) already have Dependabot's `github-actions`
block and it has opened `uses:`-bump PRs for them before — `kermit-v3`'s PR #362
and `kermit-pa`'s PR #130 are both Dependabot's work. They stalled at `v1.12`/`v1.13`
not because Dependabot failed but because those were the newest tags in existence
until `v1.26` was cut. Now that tagging is mechanical (v1.26), Dependabot is the
standing fix; the issue-per-bump is the fallback for the repos without it.

**File:** `docs/CI-INTEGRATION.md` (existing — new section after "Rollout", around
line 80)

**Implementation:**

A short section covering, in order:

1. **The durable path:** copy
   `extensions/github-actions/dependabot-consumer-template.yml`'s
   `github-actions` block into the repo's `.github/dependabot.yml`. That block
   alone is what bumps the `uses:` pin; the pip/npm/gomod blocks are independent
   and optional. Note which of Rich's consumers already have it and which do not
   (`OPIE`, `SQRL`, `keystone_prototype`, `kermit-harness` do not, as of
   2026-09-03), so the gap is visible rather than implied.
2. **Why a Dependabot PR can sit unmerged and still leave you stale** — it opens
   the PR; a human merges it.
3. **The manual bump:** edit the one `uses:` line, commit, PR. Point at
   `kermit-harness` PR #380 as the worked example.
4. **Checking where you stand:** `./scripts/fleet-pins.sh` from the dev-platform
   repo, and what "⚠ local ≠ live" means — an uncommitted local edit to the
   workflow file, which OPIE has right now.
5. **Do not** use `fleet-install-template.sh --force` to bump a pin. It rewrites
   the entire template, and consumer files have diverged from it. Bumping a pin is
   a one-line edit in the consumer's own session; the fleet helper is for first-time
   adoption only.

**Acceptance Test:**

```bash
grep -n "dependabot" docs/CI-INTEGRATION.md    # section present, links the template
./scripts/gate_fast.sh                          # markdown/link checks pass
```

---

### Change 8: Record the SQRL account boundary and the pin-ask procedure

**Problem:** `Osigin-LLC/SQRL` is on a different GitHub account, reached through
the `github-teelr129` SSH host alias. `gh api repos/Osigin-LLC/SQRL` returns 404
under the authenticated account, so its pin cannot be read, its issue #1 cannot be
verified, and `scripts/check-comms-delivery.sh` cannot confirm delivery of any ask
filed against it. Nothing in the comms doc says this, so the next session will
either re-discover it or, worse, read SQRL's local checkout and report that as
live.

**File:** `docs/CROSS-REPO-COMMS.md` (existing — add to the section covering ask
delivery and verification)

**Implementation:**

Two short additions:

1. **Account boundary.** `Osigin-LLC/SQRL` is not reachable by the `gh` account
   this machine authenticates as. `scripts/lib/repo_slug.py` parses its alias
   remote correctly — the slug is right, the *access* is not, and those are
   different failures. Any tool that queries it must report `unverifiable`, never
   fall back to the local checkout, and never treat an unverifiable repo as
   compliant. State how to verify it instead: from a session authenticated to that
   account, or by asking in SQRL's own session.
2. **Pin asks specifically.** A dev-platform release does not need an issue per
   consumer when the consumer has Dependabot's `github-actions` block — the
   release tag is the notification, which is the outbound half this doc already
   prescribes. File a pin-bump issue only for consumers without it, and put the
   consumer's **verified current pin** in the title, not an assumed one.

**Acceptance Test:**

```bash
bash scripts/check-comms-delivery.sh       # unchanged behaviour, still green
grep -n "Osigin-LLC" docs/CROSS-REPO-COMMS.md
./scripts/gate_fast.sh
```

---

## Phase 4: Fleet Paths Resolve to the Main Checkout

### Change 9: One main-checkout resolver, five call sites

**Problem:** `monitoring/fleet_pins.py:49`, `monitoring/fleet_dashboard.py:34`,
`scripts/fleet-gate.sh:25`, `scripts/fleet-status.sh:14`, and
`scripts/fleet-install-template.sh:28` each derive their root from their own file
location, then join the registry's relative `projects/<name>` paths onto it.
`projects/` is gitignored (`.gitignore:183`) and exists only in the main checkout,
so from a worktree every one of them points at a path that does not exist. None
of them errors — `fleet-pins.sh` reports `— not adopted` for all seven consumers,
`fleet-gate.sh` sweeps nothing, `fleet-install-template.sh` would write a template
into a directory it just created under the worktree. Five copies of one wrong
derivation, which is precisely the Derivation Sweep rule's case.

v1.25 already fixed this exact bug for `install.sh` and `verify.sh` using
`git rev-parse --git-common-dir` (see `scripts/install.sh:33-39`), and swept those
two together for the same reason. This Change extracts that resolution once and
points every script that *can* share it at the one definition. Four scripts
cannot, for reasons the helper's header records: two run from the deployed
`~/.claude/worktree/` path, and two are bootstrap scripts a test suite copies in
isolation.

**Files:**

- `scripts/lib/main_checkout.sh` (new) — sourced bash helper.
- `scripts/lib/main_checkout.py` (new) — the same rule for the Python callers.
- `monitoring/fleet_pins.py`, `monitoring/fleet_dashboard.py` (modify)
- `scripts/fleet-gate.sh`, `scripts/fleet-status.sh`, `scripts/fleet-install-template.sh` (modify)
- `scripts/install.sh`, `scripts/verify.sh` — **attempted and reverted.** Pointing
  them at the helper cost five failures in `tests/worktree-default`: that suite
  copies `install.sh`, `verify.sh` and `uninstall.sh` into a fixture worktree *by
  themselves*, deliberately, to test the working-tree versions rather than HEAD's.
  A sourced sibling is not there. They are bootstrap scripts that must run
  standalone, so they keep their inline copy — as do `shell/worktree/gate-lock.sh`
  and `scripts/check-concurrent-sessions.sh`, which run from the deployed
  `~/.claude/worktree/` path where `scripts/lib/` does not exist. The helper's
  header names all four and says why, so the next sweep does not re-try it.

**Implementation:**

The rule, stated once: run `git rev-parse --git-common-dir` from the candidate
root; on success, the main checkout is that directory's parent (it resolves to
`<main>/.git` from a worktree and from the main checkout alike). On any failure —
not a git repo, no `git` on PATH — fall back to the candidate unchanged, so a
tarball checkout keeps working.

Keep the two values distinct and name them so:

- `REPO` / `REPO_ROOT` — where *this* script and its sibling repo files live.
  Unchanged. A worktree's `monitoring/projects.json` is the registry that worktree
  is editing, and that is correct.
- `FLEET_ROOT` — the main checkout, and the only base for resolving a registry
  entry's relative `path`. Absolute registry paths (which the test suites use via
  `mktemp`) keep bypassing it entirely.

In `fleet_pins.py` this means `target = FLEET_ROOT / path_raw` for relative paths
rather than `REPO / path_raw`; `path_raw == "."` still means dev-platform itself,
which short-circuits before any path use. Apply the same substitution at each of
the other four call sites, changing only the base of a relative project path —
not registry loading, not template sources, not test-fixture handling.

Say it out loud when the two differ, matching `install.sh:45-49`'s precedent: one
line on stderr noting the fleet root is the main checkout, so a worktree user is
never silently reading another directory's state.

**Acceptance Test:**

```bash
# From the worktree — the case that was broken:
./scripts/fleet-pins.sh --source local --latest v1.26   # real rows, not 7× "not adopted"
./scripts/fleet-status.sh | head -20                    # same project set as from main

# From the main checkout — unchanged behaviour:
cd /home/rich/dev && ./scripts/fleet-pins.sh --source local --latest v1.26

# Absolute registry paths still bypass FLEET_ROOT:
bash tests/fleet-pins/run.sh && bash tests/fleet-gate/run.sh && bash tests/fleet-install/run.sh
```

---

### Change 10: `tests/fleet-worktree/` proves it from both locations

**Problem:** Nothing catches this class of bug. The v1.25 lesson
(`tasks/lessons/2026-09-03-run-the-gate-from-where-users-will-run-it.md`) is
exactly it: every gate run was from the main checkout, so four suites asserting
against their own `${REPO}` passed while being wrong from a worktree.

**File:** `tests/fleet-worktree/run.sh` (new)

**Implementation:**

Build a throwaway git repo under `mktemp` with a `projects/<name>` tree and a
registry, add a real worktree to it with `git worktree add`, then assert the
resolver returns the main checkout's root from *both* locations — for the bash
helper and the Python helper alike. Assertions:

1. `main_checkout.sh` from the main checkout → that checkout.
2. `main_checkout.sh` from a worktree of it → the main checkout, not the worktree.
3. `main_checkout.py` — same two.
4. Non-git directory → returns the input unchanged (no crash, no empty string).
5. `git` absent from `PATH` → same graceful fallback.
6. A relative registry path resolves under the main checkout from a worktree.
7. An absolute registry path is untouched by the resolver.

Use the existing `tests/helpers/assert.sh` contract and keep it offline. Do not
read dev-platform's own worktrees — the suite must not depend on whether one
exists.

**Acceptance Test:**

```bash
bash tests/fleet-worktree/run.sh    # passes from the main checkout AND from a worktree
./scripts/gate_fast.sh              # both locations
```

---

## What NOT to Do

- **Do not bump any consumer's pin from this session.** Not by editing
  `projects/<name>/.github/workflows/dev-platform-gate.yml`, and not by running
  `fleet-install-template.sh --apply --force`. The Scope rule forbids the first;
  the second clobbers diverged consumer files and is for first-time adoption only.
  OPIE's working tree already carries an uncommitted overwrite from exactly that
  mistake — leave it alone and report it (post-merge, below).
- **Do not "fix" OPIE's dirty working tree.** Not `git checkout --`, not `git stash`,
  not a commit. It is another repo's uncommitted state; discarding it destroys work
  this session cannot see the origin of. It goes in OPIE's issue comment.
- **Do not backfill the missing v1.14–v1.25 tags.** v1.26 made that call
  deliberately and nothing here changes it.
- **Do not rewrite the v1.26 narrative** in ROADMAP.md or its shipped file. Append
  a marked correction; the record of what a phase believed is worth keeping intact.
- **Do not write a fourth owner/repo parser.** Import `scripts/lib/repo_slug.py`.
- **Do not let `unverifiable` degrade into a local-file answer.** An unknown
  reported as a fact is the defect this whole phase is correcting.
- **Do not make the live `gh` read mandatory.** `--source local` must keep working
  with no network and no `gh`, and the test suite must run offline.
- **Do not add the new pin check to `gate_fast.sh`.** It depends on network, on
  `gh` auth, and on other repos' state — none of which belong in a commit gate.
  It is a fleet report, like `fleet-status.sh`.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `monitoring/fleet_pins.py` | Modify | Live pin read via `gh`, slug derivation, drift + `unverifiable` states, `--source` flag, new columns and JSON fields |
| `monitoring/projects.json` | Modify | Add `keystone_prototype` |
| `tests/fleet-pins/run.sh` | Modify | `--source local` on existing assertions; 9 new assertions |
| `tests/fleet-pins/fixtures/mock-bin/gh` | New | Mock `gh` driven by `MOCK_GH_FIXTURE` |
| `scripts/fleet-pins.sh` | Modify | Header comment documents `--source` |
| `CLAUDE.md` | Modify | Line 180 — correct the `@v0.7` claim |
| `scripts/check-phase-tags.sh` | Modify | Line 11 — correct the same claim in the header comment |
| `docs/CI-INTEGRATION.md` | Modify | Lines 26, 40, 65 corrected; new "Keeping the pin current" section |
| `docs/CROSS-REPO-COMMS.md` | Modify | SQRL account boundary; pin-ask procedure |
| `ROADMAP.md` | Modify | Correction sentence on the v1.26 entry; v1.27 entry (added by `/code`'s doc step) |
| `tasks/shipped/2026-09-03-v1.26-version-reference-discipline.md` | Modify | Appended correction section |
| `tasks/lessons/2026-09-03-verify-consumer-state-against-the-consumer.md` | New | The lesson |
| `tasks/shipped/<date>-v1.27-consumer-pin-bump.md` | New | Shipped record (`/code`'s doc step) |

## Implementation Order

1. **Change 2** (registry) — one line, and Change 1's live read has a seventh
   project to exercise the moment it lands.
2. **Change 1** (`fleet_pins.py`) — the substantive one; everything downstream
   quotes its output.
3. **Change 3** (tests) — written against Change 1, run offline.
4. **Change 4** (rules + CI guide corrections) — depends on nothing, but is worded
   from the table Change 1 can now regenerate.
5. **Change 5** (ROADMAP + shipped correction) — after Change 4, same facts.
6. **Change 6** (lesson) — last of Phase 2; it describes what Changes 1–5 fixed.
7. **Change 7**, then **Change 8** (docs) — independent of each other; both quote
   the verified state.

Re-run `./scripts/fleet-pins.sh` after Change 1 and paste the real table into the
shipped record. Do not paste the table from this spec — regenerate it, or it is
the same unverified-claim failure one phase later.

## Verification Checklist

- [ ] `./scripts/fleet-pins.sh` reports live pins for all six reachable consumers, `unverifiable` for SQRL
- [ ] OPIE's row shows local `v1.12` vs live `v1.2` and flags the drift
- [ ] `keystone_prototype` appears in the report at `v1.0`
- [ ] `./scripts/fleet-pins.sh --source local` runs with no network and no `gh`, output shape unchanged from v1.26
- [ ] `bash tests/fleet-pins/run.sh` passes offline; 9 new assertions
- [ ] No remaining claim in `CLAUDE.md`, `docs/`, or `scripts/` that consumers pin `@v0.7`
- [ ] v1.26 ROADMAP entry and shipped file carry an appended correction, narratives otherwise intact
- [ ] Lesson file exists and is tracked by git (probe with `git status --porcelain tasks/lessons/`)
- [ ] `docs/CI-INTEGRATION.md` documents Dependabot as the standing fix and names which consumers lack it
- [ ] `docs/CROSS-REPO-COMMS.md` records the SQRL account boundary
- [ ] No file under `projects/` modified by this branch (`git status` in each consumer repo unchanged from its pre-phase state)
- [ ] `./scripts/gate_fast.sh` passes from the worktree **and** from the main checkout (the v1.25 lesson: run the gate from every location it will be run from)
- [ ] `./scripts/verify.sh` clean
- [ ] Language architecture matrix followed for all new components

`/security-review` is not required — no auth, credentials, external input, or new
endpoints. The new `gh` calls are read-only GETs against repos the account already
has access to.

## Post-merge

Deferred to post-merge because these write to repos dev-platform does not own, and
because the issue text should cite the merged, verified state rather than a
pre-merge draft. All of it is issue comments and titles — the sanctioned cross-repo
transport — with no file writes to any consumer repo.

1. **Correct the six open issues.** For each of `kermit-pa#178`, `keystone#515`,
   `kermit-v3#740`, `OPIE#9`, `keystone_prototype#2`: retitle to name that repo's
   **verified current pin** instead of `@v0.7`, and comment with the correction —
   what the real pin is, whether `check_version_collision.py` is actually running
   there (yes for kermit-pa, keystone, kermit-v3; no for OPIE and
   keystone_prototype), and the one-line bump. Where the repo lacks Dependabot's
   `github-actions` block, say so and link the template.
2. **OPIE gets one extra paragraph:** its working tree at
   `projects/OPIE/.github/workflows/dev-platform-gate.yml` has an uncommitted
   overwrite from a past `fleet-install-template.sh --force`, so the local file
   reads `@v1.12` while its CI runs `@v1.2`. OPIE's own session decides whether to
   commit or discard it. dev-platform must not touch it.
3. **SQRL:** issue #1 cannot be read from this account. Report that to the user
   rather than guessing at its state, and note it needs handling from a session
   authenticated to `Osigin-LLC`.
4. **Roadmap-Phase completion** (standard): mark v1.27 complete in `ROADMAP.md`,
   close milestone #38, cut the `v1.27` release tag at the squash-merge commit,
   then verify with `scripts/check-phase-milestones.sh` and
   `scripts/check-phase-tags.sh`.
5. **Re-run `./scripts/fleet-pins.sh`** and record the resulting table — that is
   the standing measure of whether the consumers actually bumped, and the first
   time dev-platform has had a trustworthy one.

Each consumer's own bump PR is **not** part of this phase and does not gate its
completion. That work belongs to each project's session, per the Scope rule.
