# v1.11: Roadmap-Version Claim Guard

## Coding Specification for Implementation

## Design Philosophy

kermit-v3 already built and merged (its own v0.75) two scripts that close a real race condition: two Claude Code sessions working the same repo in separate git worktrees can both read "the next free Roadmap Phase version number" as the same value, both act on it, and only find out they collided when GitHub rejects a duplicate milestone or a human untangles a merge conflict by hand. `scripts/claim_roadmap_version.py` (atomic claim: compute next-free, create the milestone, retry forward on a create-race) and `scripts/check_version_collision.py` (gate-time backstop: compare a branch's `ROADMAP.md` against `origin/main` and live GitHub milestones, fail on a real collision) both already derive `owner/repo` dynamically from `git remote get-url origin` — they were written portable, they just shipped in the wrong repo. Every other project scaffolded from dev-platform (Keystone, kermit-pa, SQRL, OPIE, kermit-v3's own siblings) has the identical exposure, completely unpatched, because the fix lives in kermit-v3's `scripts/`, not dev-platform's.

This spec promotes both scripts into dev-platform as the single source of truth, then wires them into the two places dev-platform actually owns: `/plan`'s branch/version-creation step (Step 2) and the reusable `taxonomy-check.yml` CI workflow every consumer's `dev-platform-gate.yml` already pulls in. Per the Scope rule (`/home/rich/dev/CLAUDE.md`), dev-platform does not write into `projects/kermit-v3/` or any other project directory — the two source scripts are read once for reference and reproduced as new files under dev-platform's own `scripts/`, with one small addition (an env-var test hook, see Change 1) and one message tweak (dropping a kermit-v3-specific file reference), not a byte-for-byte copy.

**Distribution model — a deliberate correction to the "template" framing.** The initial ask described this as "a template — same distribution pattern as `dev-platform-gate.yml` today." That pattern (a `.yml` file consumers copy-paste into their own `.github/workflows/`) exists ONLY because GitHub Actions requires a *trigger* workflow file to physically live in the consumer's own repo — the reusable logic behind it (`taxonomy-check.yml`) is never copied; it's checked out fresh from dev-platform on every run via `uses:` + a pinned tag. `check_spec_taxonomy.sh` already proves this: it lives once in dev-platform's `scripts/`, and every consumer's CI checks out dev-platform live to run it (see `taxonomy-check.yml`'s "Checkout dev-platform" step). `claim_roadmap_version.py`/`check_version_collision.py` need no `.yml`-style copy-paste step at all: locally, `/plan` is itself a globally-deployed, Rich-machine-only command file (already referencing `/home/rich/dev/CLAUDE.md` and `/home/rich/dev/projects/<name>` as absolute paths — see `commands/plan.md:89`, `commands/gate.md:58`), so it can call the promoted scripts by their canonical dev-platform path directly; in CI, the same "checkout dev-platform, invoke its script" pattern `taxonomy-check.yml` already uses for `check_spec_taxonomy.sh` extends cleanly to the new scripts. Promoting them as N per-consumer copies would recreate exactly the "the fix landed in the wrong repo, only one project got it" problem this spec exists to close, just N times over instead of once. `docs/CI-INTEGRATION.md` is updated (Change 7) to describe this correctly.

**Branching:** single branch, single PR for the whole spec (deviation from the default one-branch-per-Spec-Phase rule, criterion (b) — Phase 1 alone has zero standalone value: promoted-but-unwired scripts fix nothing. Phase 2 and Phase 3 each depend on Phase 1's promoted files existing, though not on each other. Splitting into 3 PRs would mean shipping "scripts that exist but nothing calls them" as its own merge, which isn't independently demoable — same shape as v1.10's single-PR precedent.).

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/claim_roadmap_version.py`, `scripts/check_version_collision.py` | Python | Already-proven code being promoted, not written fresh. Matches dev-platform's existing convention for `gh api`-calling, JSON-parsing scripts (`fleet_pins.py`, `comms_delivery.py`, `check-phase-milestones.sh`'s sibling scripts) — AI-intensive matrix doesn't apply; this is API/JSON glue, and Python is what every comparable dev-platform script already uses for that shape of work. |
| `commands/plan.md` edits | Markdown (agent instructions) | Not a language choice — editing an existing instruction file. |
| `.github/workflows/taxonomy-check.yml` addition | YAML | GitHub Actions' native format; extends the existing reusable workflow in place. |
| `tests/version-collision/run.sh` | Bash | Matches every existing `tests/<suite>/run.sh` — sources `tests/helpers/assert.sh`, uses the `fixtures/mock-bin/<binary>` mock pattern already established in `tests/phase-milestones/`. |

## Overview

1. **Phase 1 — Promote the scripts** (Changes 1–2): copy both scripts into `scripts/`, add a git+mock-gh fixture test suite.
2. **Phase 2 — Wire the atomic claim into `/plan`** (Changes 3–4): replace `commands/plan.md` Step 2's "read and hope" with an atomic claim; simplify Step 6 to a fallback that routes through the same claim script instead of an unguarded `gh api` POST.
3. **Phase 3 — CI enforcement for every consumer** (Changes 5–8): add a `version-collision` job to the shared `taxonomy-check.yml`, update the consumer template's doc comment and the adoption guide.

---

## Phase 1: Promote the Scripts

### Change 1: Add `scripts/claim_roadmap_version.py` and `scripts/check_version_collision.py`

**Problem:** These two scripts exist only in `/home/rich/dev/projects/kermit-v3/scripts/` — read-only reference for this dev-platform session, per the Scope rule (dev-platform never writes into `projects/`). Every other consumer project has the identical version-collision exposure with no fix available.

**Files:**

- `scripts/claim_roadmap_version.py` (new)
- `scripts/check_version_collision.py` (new)

**Implementation:**

Reproduce both files from `/home/rich/dev/projects/kermit-v3/scripts/claim_roadmap_version.py` and `/home/rich/dev/projects/kermit-v3/scripts/check_version_collision.py` verbatim, with exactly these three deviations:

1. **`check_version_collision.py`, the collision message** (source lines 149–152): drop the kermit-v3-specific spec-file pointer. Change:

   ```python
   print(
       "Renumber this branch's ROADMAP.md/planning.md/milestone to a free version "
       "before committing — see tasks/roadmap-version-collision-guard-spec.md."
   )
   ```

   to:

   ```python
   print(
       "Renumber this branch's ROADMAP.md/planning.md/milestone to a free version "
       "before committing."
   )
   ```

   (Every consumer project has a different spec-file layout; a hardcoded path to a file that only exists in kermit-v3 would be actively misleading elsewhere.)

2. **Add a test-only repo-slug override to BOTH scripts**, so the fixture suite (Change 2) can exercise the `gh`-dependent code paths against a local-filesystem git remote (needed for a real `git fetch`/`git show` in a hermetic test) while still driving a mock `gh` binary (which needs a non-`None` slug to be invoked at all — a local file-path remote fails the `github.com` URL regex and short-circuits straight to the "could not determine owner/repo" SKIP path, never touching `gh`). In `check_version_collision.py`'s `_repo_slug()` (source lines 60–65) and `claim_roadmap_version.py`'s `_repo_slug()` (source lines 37–43), add an env-var check before the `git remote get-url` call:

   ```python
   import os
   # ... inside _repo_slug():
   override = os.environ.get("VERSION_GUARD_REPO_SLUG")
   if override:
       return override
   ```

   (`import os` goes in each file's existing import block.) This is the same "state-file/env-var override for testability" pattern the project's own lessons file documents (`tasks/lessons.md`, the v0.6 "Mock-binary pattern for testability" entry) — production behavior is unchanged (the env var is never set outside tests), and it lets the fixture keep `origin`'s URL as a real local path for git operations while independently controlling what `gh api` sees.

3. Update each script's module docstring header comment minimally if it references kermit-v3 by name (neither currently does — both docstrings are already generic; verify this holds and leave as-is otherwise).

No other logic changes. Both files keep their existing `if __name__ == "__main__":` entry points, argument parsing, exit codes (`claim_roadmap_version.py`: 0 success / 1 failure; `check_version_collision.py`: 0 clean / 1 collision / 2 degraded-SKIP), and retry semantics exactly as proven in kermit-v3.

**Acceptance Test:**

```bash
python3 -c "import ast; ast.parse(open('scripts/claim_roadmap_version.py').read())"
python3 -c "import ast; ast.parse(open('scripts/check_version_collision.py').read())"
# Dogfood against dev-platform's own repo — should be clean (no new version headers on main itself)
python3 scripts/check_version_collision.py .
```

---

### Change 2: `tests/version-collision/run.sh` — offline fixture suite

**Problem:** No test coverage exists yet for either promoted script. Per the Consumer Audit rule (`CLAUDE.md`), a new file type/suite under `tests/` needs its own runner; per `docs/RULE_RATIONALE.md`'s general standard, mechanical checks need mechanical tests, not conversation-derived trust.

**File:** `tests/version-collision/run.sh` (new) + `tests/version-collision/fixtures/mock-bin/gh` (new)

**Implementation:**

Follow `tests/phase-milestones/run.sh` and its `fixtures/mock-bin/gh` exactly as the template (source both — `tests/phase-milestones/run.sh:1-20` for the sourcing/`HERE`/`REPO` boilerplate, `tests/phase-milestones/fixtures/mock-bin/gh` for the mock-binary shape). Key differences this suite needs that `phase-milestones` doesn't:

- **A real local git remote**, because both promoted scripts run actual `git fetch origin main` / `git show origin/main:ROADMAP.md` — this can't be mocked away without changing the scripts. Build it once per test run in a `mktemp -d`:

  ```bash
  ORIGIN="${TMP}/origin.git"
  git init -q --bare "${ORIGIN}"

  SEED="${TMP}/seed"
  git init -q "${SEED}" && cd "${SEED}"
  git checkout -q -b main
  printf '## v0.1: Foundation\n' > ROADMAP.md
  git add ROADMAP.md
  git -c user.email=t@t -c user.name=t commit -q -m seed
  git remote add origin "${ORIGIN}"
  git push -q origin main
  cd - >/dev/null

  WORK="${TMP}/work"
  git clone -q "${ORIGIN}" "${WORK}"
  cd "${WORK}" && git checkout -q -b feature && cd - >/dev/null
  ```

  Each test case edits `${WORK}/ROADMAP.md` (add a new version header, or reuse `v0.1` under a different title) before invoking the script under test with `cd "${WORK}"` (the git commands run relative to CWD, not the `project_root` argument — this is load-bearing, not optional: passing `project_root` alone without also `cd`-ing into it will silently run `git fetch`/`git show` against whatever repo happens to be at the test runner's own CWD instead).

- **`VERSION_GUARD_REPO_SLUG=owner/repo`** exported before invoking either script, so the mock `gh` gets called (see Change 1, deviation 2). The mock `gh` binary itself follows `tests/phase-milestones/fixtures/mock-bin/gh`'s exact shape: a `MOCK_MILESTONES_FILE` env var supplies canned `gh api ... milestones` JSON, `MOCK_FAIL` (if set) makes the mock exit 1 to test degraded/SKIP handling. Also support the milestone-CREATE call `claim_roadmap_version.py` makes (`gh api repos/... --method POST -f title=... -f description=...`) — the mock's `api` case needs a sub-branch for `--method POST` that either succeeds (prints a canned JSON `{"number": N, "html_url": "..."}`) or, for the race-retry test, exits 1 with a message containing `already_exists` on the first call and succeeds on the second (drive this via a counter file the mock increments, same pattern as `MOCK_FAIL`).

Required assertions (minimum — use `record_pass`/`record_fail` from `tests/helpers/assert.sh`, matching the existing suites' style):

**`check_version_collision.py`:**
1. No new version headers vs. `origin/main` → exit 0, "OK: no new Roadmap Phase version headers introduced".
2. A `v0.1` reused under a different local title than `origin/main`'s → exit 1, "COLLISION" output naming both titles (Layer 1, no `gh` needed).
3. A genuinely new version header (e.g. `v0.2`), mock `gh` returns no matching milestone → exit 0, "OK: 1 new version header(s), no collision detected".
4. A genuinely new version header, mock `gh` returns a milestone for that same number under a *different* title → exit 1, "COLLISION" (Layer 2).
5. `VERSION_GUARD_REPO_SLUG` unset (or `MOCK_FAIL` on the `gh api` call) with a new version header present → exit 2, "SKIP" — not treated as a failure.
6. `git fetch` failure (point `origin` at a nonexistent path) → exit 2, "SKIP: could not fetch origin/main".

**`claim_roadmap_version.py`:**
7. `origin/main`'s `ROADMAP.md` highest is `v0.1`, no milestones exist → claims `v0.2`, mock `gh` receives the POST, output contains `Claimed v0.2`.
8. Milestones (via mock) show a higher minor than `ROADMAP.md` (e.g. `v0.3` milestone exists, `ROADMAP.md` only shows `v0.1`) → claims `v0.4` (proves `max(roadmap_high, milestone_high) + 1`, not `ROADMAP.md`-only).
9. Mock `gh` POST fails with `already_exists` on the first attempt, succeeds on the second → claims the bumped number, output shows the retry succeeded (not a hard failure).
10. Mock `gh` POST fails with `already_exists` on every attempt (exhausts `_MAX_CLAIM_ATTEMPTS`) → exit 1, error message names the attempt count.

Wire the new suite into `scripts/gate_fast.sh`'s auto-discovery — no orchestrator change needed (per `tests/README.md`, any `tests/<suite>/run.sh` is picked up automatically); just confirm it fires:

**Acceptance Test:**

```bash
bash tests/version-collision/run.sh
./scripts/gate_fast.sh 2>&1 | tail -3   # count increases by the new suite's assertions, 0 FAIL
```

---

## Phase 2: Wire the Atomic Claim into `/plan`

### Change 3: `commands/plan.md` Step 2 — atomic claim replaces "read and hope"

**Problem:** Step 2 sub-step 3 (`commands/plan.md:32`) reads `planning.md`'s stated active version and assumes the next number is free — exactly the pattern that let three concurrent kermit-v3 sessions all claim `v0.71`/`v0.72` today. This is the earliest point in the whole chain a new Roadmap Phase's version number gets decided; claiming it atomically here is the only place that actually closes the race (by `/pr` time, as today's incident showed, the number is already baked into commits, ROADMAP.md text, and the branch name).

**File:** `commands/plan.md`, lines 30–39 (Step 2, sub-steps 1–4)

**Implementation:**

Replace sub-step 3 (currently: `3. If on \`main\`, read the active Roadmap Phase version from \`planning.md\` (e.g. \`v0.9\`). A brand-new spec always starts at Phase 1, so the branch name is \`v<X.Y>/phase-1-<slug>\`.`) with:

```markdown
3. If on `main`, this is a new Roadmap Phase — claim its version number atomically instead of reading one and hoping it's free (two concurrent `/plan` sessions can otherwise both read the same "next" number, as happened twice in one afternoon on kermit-v3). First derive a short Title-Cased feature title from the same feature description used for the slug in sub-step 1 (e.g. slug `image-generation` → title "Image Generation") — this exact title is reused verbatim as the milestone title AND, later in Step 5, as the ROADMAP.md `## v<X.Y>: <Title>` header, so the two never drift apart (a title mismatch between them is precisely what `check_version_collision.py` flags as a collision). Then derive the major version from `planning.md`'s stated Active Roadmap Phase line (e.g. `**Active Roadmap Phase:** **v1.10 SHIPPED**` → major `1`), or the highest `## v<N>.<M>:` header in `ROADMAP.md` if `planning.md` has none. Run:

   ```bash
   python3 /home/rich/dev/scripts/claim_roadmap_version.py "<Title-Cased feature title>" --major <N>
   ```

   This fetches `origin/main`'s `ROADMAP.md` AND every GitHub milestone (open + closed) to find the true highest-claimed minor version, creates the milestone for the next one, and retries forward if another session's milestone appears mid-claim. On success it prints `Claimed v<X.Y> — milestone #<N>: <title>` — parse `v<X.Y>` from that line and use it for the rest of this Step, the branch name, and the spec. **If the script exits non-zero** (no `gh` auth, repo detection failed, or 5 consecutive collisions), STOP and report the error verbatim — do NOT fall back to guessing a version number; that defeats the entire point of claiming it here. A brand-new spec always starts at Phase 1, so the branch name is `v<X.Y>/phase-1-<slug>` using the claimed version.
```

Sub-step 4 (the branch-mode/worktree-mode `git checkout -b v<X.Y>/phase-1-<slug>` / `EnterWorktree` block) needs no textual change — its `v<X.Y>` placeholder already resolves from whatever Step 2 established; it now resolves from the claimed version instead of a guessed one.

**Acceptance Test:**

Manually dry-run the new sub-step 3 against dev-platform's own repo (already on a feature branch for this spec, so this exercises the "on main" branch of the logic in isolation, without actually re-claiming):

```bash
python3 scripts/claim_roadmap_version.py "Test Dry Run Claim" --major 99
# Expect: "Claimed v99.1 — milestone #<N>: ..." — a real milestone gets created; delete it after:
gh api repos/teelr/dev-platform/milestones/<N> -X DELETE
```

---

### Change 4: `commands/plan.md` Step 6 — fallback only, routes through the same claim script

**Problem:** Step 6 (`commands/plan.md:158-180`, "Ensure GitHub Milestone Exists") creates milestones via a raw `gh api ... --method POST` with zero collision protection — the exact bug class this spec fixes, still present as a second, un-guarded code path even after Change 3 fixes the primary one. Once Change 3 ships, Step 6 should only ever fire for the cases Step 2 doesn't cover: a hand-authored spec added without going through `/plan`'s branch creation, or a later Spec Phase of the SAME Roadmap Phase added via a fresh `/plan` on an already-existing feature branch (Step 2 sub-step 2 already skips branch/version creation for that case, per its "If it's already something other than `main` ... skip straight to Step 3" rule).

**File:** `commands/plan.md`, lines 158–180 (all of Step 6)

**Implementation:**

Replace the entire Step 6 section with:

```markdown
## Step 6: Verify the Milestone (fallback only)

If Step 2 already claimed a version via `claim_roadmap_version.py` (the normal path for any brand-new Roadmap Phase), its milestone already exists — skip this step entirely.

This step only fires for the two cases Step 2 doesn't cover: (a) a hand-authored spec added to `tasks/` without going through `/plan`'s branch-creation flow, or (b) a later Spec Phase of the SAME Roadmap Phase added via a fresh `/plan` invocation on an EXISTING feature branch. Case (b) should almost never actually find a missing milestone — Change 3's Step 2 already created it when Phase 1 of the same Roadmap Phase ran — so hitting the "no milestone exists" branch below in case (b) is a signal something already drifted, not a normal occurrence.

Derive the version prefix from the spec filename or branch name, then check:

​```bash
PREFIX="v<X.Y>"   # substitute actual major.minor
gh api repos/{owner}/{repo}/milestones?state=all \
    --jq ".[] | select(.title | startswith(\"${PREFIX}:\")) | .title"
​```

Derive `{owner}/{repo}` from `git remote get-url origin`.

- **If the milestone exists:** note its title and move on.
- **If no milestone exists:** claim one the same race-safe way Step 2 does — do NOT create it directly via `gh api ... POST` (that path has no collision protection, which is the exact bug this spec exists to fix):

​```bash
python3 /home/rich/dev/scripts/claim_roadmap_version.py "<Title from spec or ROADMAP.md>" --major <N>
​```

`claim_roadmap_version.py` always claims the NEXT free minor version — it does not accept a specific target number. If the branch/spec already commits to an exact `v<X.Y>` that turns out to be missing its milestone, and the script would claim a DIFFERENT number, STOP and report to the user rather than silently claiming a mismatched number under the hood — that mismatch is itself worth a human looking at.

This prevents the "No vX.Y milestone exists" warning that surfaces later at `/pr` time.
```

(Use literal triple-backtick fences in the actual file — shown here escaped only so this spec's own fence doesn't terminate early.)

**Acceptance Test:**

```bash
grep -n "gh api repos/{owner}/{repo}/milestones --method POST" commands/plan.md && echo "FAIL: unguarded create still present" || echo "PASS: no direct unguarded milestone creation left in plan.md"
grep -n "claim_roadmap_version.py" commands/plan.md | wc -l   # expect 2 (Step 2 and Step 6)
```

---

## Phase 3: CI Enforcement for Every Consumer

### Change 5: `version-collision` job in `.github/workflows/taxonomy-check.yml`

**Problem:** `check_version_collision.py` has no local-service or harness dependency (pure `git` + `gh`), so — unlike most `gate_fast.sh` checks — it can run in hosted CI today without any per-project wiring. Folding it into the ALREADY-consumed `taxonomy-check.yml` reusable workflow means every consumer with `dev-platform-gate.yml` installed gets this protection automatically the next time they bump their pin, with zero new adoption steps.

**File:** `.github/workflows/taxonomy-check.yml` (existing — add a second job after the existing `taxonomy:` job)

**Implementation:**

Add as a sibling to the existing `taxonomy:` job (a separate job, not extra steps in the same job, so the two checks report independently in the PR Checks UI and a version-collision failure never masks/gets masked by a taxonomy failure):

```yaml
  version-collision:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: read
    steps:
      - name: Checkout caller's repo
        uses: actions/checkout@v4
        with:
          ref: ${{ inputs.ref }}
          path: caller

      - name: Extract dev-platform ref from job_workflow_ref
        id: wf-ref
        run: |
          echo "ref=$(echo '${{ github.job_workflow_ref }}' | cut -d@ -f2)" >> "$GITHUB_OUTPUT"

      - name: Checkout dev-platform (for the check script)
        uses: actions/checkout@v4
        with:
          repository: teelr/dev-platform
          ref: ${{ steps.wf-ref.outputs.ref }}
          path: dev-platform

      - name: Run version-collision check against caller's repo
        working-directory: caller
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          set +e
          python3 "${GITHUB_WORKSPACE}/dev-platform/scripts/check_version_collision.py" .
          status=$?
          set -e
          if [ "$status" -eq 1 ]; then
            echo "::error::version collision detected — see output above"
            exit 1
          elif [ "$status" -eq 2 ]; then
            echo "::warning::version-collision check degraded to partial coverage (see output above) — not treated as a failure"
          fi
          exit 0
```

Notes on the non-obvious parts:

- **`set +e` / `set -e` around the python3 call is load-bearing, not stylistic.** GitHub Actions `run:` steps default to `bash -eo pipefail`; without `set +e`, a nonzero exit from `python3` would abort the step immediately at that line, and `status=$?` would never execute — the SKIP/warn branch for exit code 2 would never be reachable, and every SKIP would incorrectly hard-fail the job.
- **`working-directory: caller`** is required for the same reason the test fixture (Change 2) needs an explicit `cd` — the script's `git fetch`/`git show` calls run relative to the process CWD, not the `project_root` CLI argument. `actions/checkout` already configures `caller`'s `origin` remote to point at the real caller repo, so this "just works" once CWD is right.
- **`GH_TOKEN: ${{ github.token }}`** — `gh` does not read Actions' ambient checkout credentials the way plain `git` does; without this env var, `gh auth status` fails and the check silently degrades to SKIP on every run (self-defeating, and quietly so). `github.token` in a `workflow_call` context is scoped to the CALLING repo, matching what `check_version_collision.py` needs to query.
- **Exit-code handling: 1 fails the job, 2 warns and passes, 0 passes silently.** This mirrors the script's own documented semantics (`check_version_collision.py`'s docstring) — a degraded/partial check must never be indistinguishable from a clean PASS in its own script output, but it also must never hard-fail a PR over something outside the PR's control (a `gh` rate limit, a transient network blip).

**Acceptance Test:**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/taxonomy-check.yml'))" && echo "PASS: valid YAML"
grep -n "version-collision:" .github/workflows/taxonomy-check.yml
```

Full functional proof only happens on a live PR (GitHub Actions has no reliable local emulator in this environment) — covered by the Verification Checklist's live-fire item.

---

### Change 6: Update `extensions/github-actions/dev-platform-gate.yml`'s header comment

**Problem:** The consumer-facing template's header comment (lines 1–13) describes only the taxonomy check. Once `taxonomy-check.yml` also runs version-collision detection, consumers copy-pasting this template should know what they're adopting.

**File:** `extensions/github-actions/dev-platform-gate.yml`, lines 1–13

**Implementation:**

Extend the header comment's second sentence. Current:

```yaml
# What it does: runs check_spec_taxonomy.sh against your repo's
# tasks/*-spec.md, ROADMAP.md, and planning.md on every PR targeting
# main and every push to main. Fails the build if any header uses a
# killed prefix (R<N>:, Sprint X:, Stage Y:, Q<N>-<YYYY>:, etc.) or
# any Spec Phase header uses a killed Change-level synonym.
```

New:

```yaml
# What it does: runs two independent checks on every PR targeting
# main and every push to main. (1) check_spec_taxonomy.sh — fails
# the build if any header in tasks/*-spec.md, ROADMAP.md, or
# planning.md uses a killed prefix (R<N>:, Sprint X:, Stage Y:,
# Q<N>-<YYYY>:, etc.) or a killed Change-level synonym. (2)
# check_version_collision.py — fails the build if this branch's
# ROADMAP.md claims a Roadmap Phase version number that origin/main
# or a live GitHub milestone already uses under a different title
# (best-effort: degrades to a non-blocking warning, never a false
# failure, if gh/network access is unavailable).
```

No change to the `uses:` line or job structure — one `uses:` call already fans out to both jobs since they live in the same reusable workflow file.

**Acceptance Test:**

```bash
grep -n "check_version_collision.py" extensions/github-actions/dev-platform-gate.yml
```

---

### Change 7: Update `docs/CI-INTEGRATION.md`

**Problem:** The adoption guide describes only the taxonomy check and doesn't mention the distribution-model reasoning (why these scripts are checked-out-live rather than copy-pasted, unlike the `.yml` trigger file).

**File:** `docs/CI-INTEGRATION.md`

**Implementation:**

1. In the "What this gives you" bullet list (lines 5–9), add a bullet after the taxonomy-enforcement one:

   ```markdown
   - **Roadmap-version collision detection on every PR.** If two branches independently claim the same `v<MAJOR>.<MINOR>` Roadmap Phase number — the exact race that happens when two sessions run `/plan` around the same time in separate worktrees — the PR that would introduce the collision fails with the specific colliding version and both titles named. Degrades to a non-blocking warning (never a silent false pass, never a hard fail) if `gh`/network access isn't available to the runner.
   ```

2. In the Troubleshooting table (lines 107–112), add a row:

   | Symptom | Likely cause | Fix |
   | ------- | ------------ | --- |
   | `version-collision` check fails with "COLLISION" | Your branch's `ROADMAP.md` claims a `v<X.Y>` that `origin/main` or a live GitHub milestone already uses under a different title | Renumber to a free version (see the check's own output for the specific collision), or if you're intentionally updating an existing Phase's title, make sure `ROADMAP.md` and the milestone agree |

3. No change needed to the "Zero vendored code" bullet — it's already accurate for the newly-added check too (same checkout-live pattern, no consumer-side script copy).

**Acceptance Test:**

```bash
grep -n "collision" docs/CI-INTEGRATION.md
```

---

### Change 8: `tests/README.md` suite listing

**Problem:** `tests/README.md`'s "Suite layout" tree (lines 13–40) enumerates every existing suite; `tests/version-collision/` needs to appear there per the file's own stated contract ("Create `tests/<suite>/run.sh`... re-run `scripts/gate_fast.sh`" doesn't require a README edit for discovery, but every prior suite is listed for humans reading the tree).

**File:** `tests/README.md`, lines 36–39 (append after the `phase-milestones` entry)

**Implementation:**

```text
└── phase-milestones/
    ├── run.sh                      check-phase-milestones.sh detector (offline mock-gh)
    └── fixtures/mock-bin/gh        mock gh CLI for canned milestone responses
└── version-collision/
    ├── run.sh                      claim_roadmap_version.py + check_version_collision.py (offline mock-gh + real local git fixture)
    └── fixtures/mock-bin/gh        mock gh CLI for canned milestone responses + create-race injection
```

(Fix the tree's box-drawing so `version-collision` isn't a second top-level `└──` sibling of the tree root — it should read as a sibling of `phase-milestones` under the same parent, matching the existing tree's indentation.)

**Acceptance Test:**

```bash
grep -n "version-collision" tests/README.md
```

---

## What NOT to Do

- **Do not copy-paste the Python scripts into each consumer project's own `scripts/` directory.** That recreates the exact "N divergent copies, one gets the fix" problem this spec closes. Only the thin `.yml` trigger file is ever copy-pasted (a GitHub Actions technical requirement, not a general pattern) — the enforcement logic stays single-sourced in dev-platform and is checked out live.
- **Do not remove the `set +e`/`set -e` guard in Change 5's workflow step** to "simplify" it. Without it, every degraded/SKIP result (exit 2) becomes an unreachable branch and the job hard-fails on transient `gh` issues instead of warning.
- **Do not let `commands/plan.md` Step 6 fall back to a raw `gh api ... POST`** for its "no milestone exists" branch. That reintroduces the exact unguarded-creation bug this spec fixes, just in a second location instead of the first.
- **Do not extend `check_version_collision.py`'s job into `scripts/gate_fast.sh`.** It needs `gh` + network, same rationale that already excludes `check-phase-milestones.sh` and `check-comms-delivery.sh` from `gate_fast.sh` — CI is the correct and sufficient enforcement point per this spec's own scope.
- **Do not invent a "does this specific vX.Y already have a milestone, and if not create exactly that one" mode for `claim_roadmap_version.py`.** It only ever claims the next free number by design (that's what makes the race-safety work) — Change 4's Step 6 explicitly SURFACES the mismatch to a human instead of pretending to reconcile it silently.
- **Do not attempt to fix the doc-merge collision (`planning.md`/`ROADMAP.md`/`tasks/lessons.md` insertion patterns) or the lesson-number reservation gap in this spec.** Both are explicitly out of scope — deferred to their own specs per the user's confirmed scoping decision, because the doc-insertion redesign has an unresolved design choice (append-at-bottom vs. split-file-per-entry) that isn't this spec's call to make.
- **Do not investigate the CI-dispatch-miss issue (PR #328/#331's zero-runs-until-second-push symptom) as part of this spec.** Root cause is unconfirmed; it's an investigation task, not implementation work, and conflating it here would stall the mechanical fixes on an open-ended question.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/claim_roadmap_version.py` | New | Promoted from kermit-v3, + test-hook env var |
| `scripts/check_version_collision.py` | New | Promoted from kermit-v3, + test-hook env var, genericized collision message |
| `tests/version-collision/run.sh` | New | Fixture suite: real local git remote + mock `gh` |
| `tests/version-collision/fixtures/mock-bin/gh` | New | Mock `gh` binary, milestone list + create + race injection |
| `commands/plan.md` | Modify | Step 2 sub-step 3: atomic claim replaces "read and hope". Step 6: fallback-only, routes through the claim script. |
| `.github/workflows/taxonomy-check.yml` | Modify | New `version-collision` job |
| `extensions/github-actions/dev-platform-gate.yml` | Modify | Header comment describes both checks |
| `docs/CI-INTEGRATION.md` | Modify | New bullet + troubleshooting row |
| `tests/README.md` | Modify | Suite tree lists `version-collision/` |

## Implementation Order

1. Change 1 (promote scripts) — everything else depends on these files existing.
2. Change 2 (test suite) — verify the promoted scripts actually work correctly before wiring anything to them.
3. Change 3 (`/plan` Step 2 atomic claim) — the primary fix.
4. Change 4 (`/plan` Step 6 fallback) — depends on Change 3 existing so the "normal path already claimed it" framing is accurate.
5. Change 5 (CI job) — independent of Changes 3–4, can run in parallel with them in principle, sequenced after for a cleaner single-PR diff review.
6. Change 6 (consumer template comment) — depends on Change 5 shipping the behavior it describes.
7. Change 7 (CI-INTEGRATION.md) — depends on Change 5/6.
8. Change 8 (tests/README.md) — depends on Change 2's suite existing.

## Verification Checklist

- [ ] `scripts/claim_roadmap_version.py` and `scripts/check_version_collision.py` exist, parse cleanly, and dogfood-check clean against dev-platform's own repo
- [ ] `tests/version-collision/run.sh` passes all 10 assertions (6 for `check_version_collision.py`, 4 for `claim_roadmap_version.py`)
- [ ] `./scripts/gate_fast.sh` passes with the new suite auto-discovered (count increases, 0 FAIL)
- [ ] `commands/plan.md` Step 2 no longer reads `planning.md`'s version and assumes it's free — it calls `claim_roadmap_version.py`
- [ ] `commands/plan.md` Step 6 no longer contains an unguarded `gh api ... --method POST` for milestone creation
- [ ] `.github/workflows/taxonomy-check.yml` is valid YAML with a `version-collision:` job present
- [ ] `extensions/github-actions/dev-platform-gate.yml` and `docs/CI-INTEGRATION.md` describe both checks
- [ ] No hardcoded settings — `--major` is always derived, never assumed to be 0 for a non-dev-platform consumer
- [ ] Language architecture matrix followed (Python for the API/JSON glue scripts, Bash for the test runner, YAML for the workflow — no new component contradicts the matrix)
- [ ] **Live-fire check (post-merge, not blocking this PR):** after this spec ships and at least one consumer bumps its `dev-platform-gate.yml` pin to `@v1.11`, open a real test PR on that consumer with a deliberately colliding `ROADMAP.md` version header and confirm the `version-collision` check actually fails with the expected message — the local YAML-validity check in Change 5 cannot prove the live GitHub Actions behavior end-to-end.

## Post-merge

Standard Roadmap-Phase-completion post-merge step (this spec's Roadmap Phase, v1.11, is complete once this PR merges — single-PR spec, no further Phases planned): mark v1.11 complete in `ROADMAP.md` + `planning.md`, close its GitHub milestone. Then, per the existing consumer-pin-bump convention (a separate chore PR "after tag exists", same as every prior Roadmap Phase): `gh release create v1.11`, bump `extensions/github-actions/dev-platform-gate.yml`'s `uses: ...@v1.10` → `@v1.11` and `scripts/fleet-install-template.sh`'s `DEFAULT_PIN="v1.10"` → `"v1.11"`. Actual per-consumer pin bumps (kermit-v3, keystone, kermit-pa, SQRL, OPIE) happen from each project's own session, not from dev-platform.

Deferred to future specs (explicitly out of scope here, per the confirmed scoping decision):
- Redesigning `planning.md`/`ROADMAP.md`/`tasks/lessons.md`'s insertion patterns to reduce doc-merge collisions.
- A matching claim/reservation mechanism for `tasks/lessons.md`'s hand-incremented `L<NN>` numbering.
- Investigating the CI-dispatch-miss symptom (PR #328/#331).
