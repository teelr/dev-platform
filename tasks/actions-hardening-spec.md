# Actions Hardening

## Coding Specification for Implementation

Roadmap Phase: `v1.42: Actions Hardening` (milestone claimed by `/plan`).
Branch: `worktree-v1.42+phase-1-actions-hardening`. One branch, one PR. Closes the GitHub
Actions and Dependabot items of `issue #131` (items 1 to 3 of its checklist).

## Design Philosophy

The 2026-10-30 security review left three low-risk findings on this public repo's CI: the
GitHub Actions it uses are pinned to moving tags, not commit SHAs; Dependabot is off, so
nothing ever proposes an update; and `taxonomy-check.yml` puts `${{ github.job_workflow_ref }}`
straight into a shell script. Pinning to a SHA stops a moved or hijacked tag from changing what
runs, but a SHA pin never updates by itself, so the pins and Dependabot have to land together:
Dependabot's `github-actions` ecosystem is what keeps a SHA pin current.

One constraint shapes the order of work. `taxonomy-check.yml` is the workflow every consumer
repo calls, and this repo's own CI never runs it, so a mistake there only shows up in a
consumer's pull request after they bump to the next tag. The edits to it are therefore kept
behaviour-neutral (the same commits pinned by SHA, an `env:` indirection, a permission the
sibling job already needs), the existing structural suite is kept green, and the shell logic
that changes is run by hand against a sample value (Change 2). The repo setting that makes the
pinning mandatory (`sha_pinning_required`) is turned on only after the pins are merged,
because turning it on first would fail every run that still uses a tag, including the CI that
must pass to merge the fix. That setting, and enabling Dependabot alerts, change the repo's
GitHub configuration, so they are a post-merge step that asks the user first.

## Verified state

| Claim | Verified by |
| ----- | ----------- |
| Five actions are pinned by tag, ten `uses:` lines: `actions/checkout@v4` (gate.yml:30, pages.yml:30, taxonomy-check.yml:61, :77, :95, :106), `configure-pages@v4` (pages.yml:32), `jekyll-build-pages@v1` (pages.yml:35), `upload-pages-artifact@v3` (pages.yml:40), `deploy-pages@v4` (pages.yml:46) | `grep -rn "uses:" .github/workflows` |
| `gate.yml` already has `permissions: contents: read` (added in `PR #129`); `pages.yml` has `contents: read, pages: write, id-token: write`; `taxonomy-check.yml` has permissions only on the `version-collision` job (`contents: read, issues: read`), not on the `taxonomy` job | `grep -n permissions -A1 .github/workflows/*.yml` |
| `${{ github.job_workflow_ref }}` is interpolated into a shell `echo` at taxonomy-check.yml:74 and :103 (`issue #131` said ~57-59 and ~94-96; those numbers were wrong) | `grep -n job_workflow_ref .github/workflows/taxonomy-check.yml` |
| Dependabot alerts are disabled (404) and automated security fixes are `{"enabled":false}` | `gh api repos/teelr/dev-platform/vulnerability-alerts -i`; `gh api repos/teelr/dev-platform/automated-security-fixes` |
| The repo's actions permission is `{"allowed_actions":"all","enabled":true,"sha_pinning_required":false}` | `gh api repos/teelr/dev-platform/actions/permissions` |
| There is no `.github/dependabot.yml`; the consumer template says "dev-platform itself does not run it" | `ls .github`; `extensions/github-actions/dependabot-consumer-template.yml:15-17` |
| `.gitignore` re-includes `.github/**/*.yml`, so `.github/dependabot.yml` will be tracked | `grep -n github .gitignore` (lines 55-57); re-probe at `/code` time |
| The YAML-validity check in `gate_fast.sh` scans only `.github/workflows` and `extensions/github-actions`, so a new `.github/dependabot.yml` would be unchecked | `sed -n 163,180p scripts/gate_fast.sh` |
| `tests/reusable-workflow/run.sh` test 4 requires the literal `${{ github.job_workflow_ref }}` to still appear in both jobs, with no `workflow_sha` | `sed -n 100,125p tests/reusable-workflow/run.sh` |
| Commit SHAs at planning time: checkout `11d5960a326750d5838078e36cf38b85af677262` (v4.4.0), configure-pages `1f0c5cde4bc74cd7e1254d0cb4de8d49e9068c7d` (v4.0.0), jekyll-build-pages `44a6e6beabd48582f863aeeb6cb2151cc1716697` (v1.0.13), upload-pages-artifact `56afc609e74202658d3ffba0e8f6dda462b719fa` (v3.0.1), deploy-pages `d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e` (v4.0.5) | a script that dereferences each tag through the GitHub API and finds the most specific version tag at that commit; **re-run it at `/code` time**, tags move |

**Assumptions (unverified):** Dependabot can bump a SHA-pinned action when the line carries a
`# vX.Y.Z` comment; the `sha_pinning_required` field is writable through
`PUT /repos/{owner}/{repo}/actions/permissions` (it is returned by the GET). Both are checked by
read-back in the post-merge step.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| Workflow edits, `dependabot.yml` | YAML | GitHub's own config formats. |
| `tests/actions-pinning/run.sh` | Bash (with a small Python/PyYAML probe) | Matches `tests/reusable-workflow/run.sh`, which this suite mirrors. |

## Overview

Phase 1: Harden the workflows and turn on Dependabot

1. Change 1: Pin the five actions to commit SHAs
2. Change 2: Keep `job_workflow_ref` out of the shell, add the missing job permission
3. Change 3: Add `.github/dependabot.yml`
4. Change 4: Tests, and put `dependabot.yml` under the YAML check
5. Change 5: Documentation
6. Post-merge step (asks the user first)

---

## Phase 1: Harden the workflows and turn on Dependabot

### Change 1: Pin the five actions to commit SHAs

**Problem:** A tag such as `actions/checkout@v4` can be moved to different code. The repo's
CI, its Pages deploy, and the reusable workflow every consumer calls all run those tags.

**File:** `.github/workflows/gate.yml` (line 30), `.github/workflows/pages.yml` (lines 30, 32,
35, 40, 46), `.github/workflows/taxonomy-check.yml` (lines 61, 77, 95, 106)

**Implementation:** First re-resolve each tag to its commit SHA and the most specific version
tag at that commit (the script used while planning: for each `owner/repo@tag`, read
`git/ref/tags/<tag>` through `gh api`, dereference an annotated tag object to its commit, then
walk `git/matching-refs/tags/<major>.` for the newest `vX.Y.Z` that points at the same commit).
Use the SHAs from the "Verified state" table only if the re-run prints the same values;
otherwise use what it prints and note the difference in the shipped record. Replace every
`uses: actions/<name>@<tag>` with `uses: actions/<name>@<40-hex-sha> # <vX.Y.Z>` (two spaces
before `#`, so Dependabot reads the comment as the version). Do not pin
`teelr/dev-platform/...` references (those are this repo's own tags, and they appear only in
comments and the consumer template). Do not change any `with:` block, name or order.

**Acceptance Test:** `grep -rnE "uses: actions/[a-z-]+@" .github/workflows` shows only 40-hex
refs each followed by a `# v...` comment; `python3 -c "import yaml; [yaml.safe_load(open(f)) for f in
__import__('glob').glob('.github/workflows/*.yml')]"` succeeds; `bash tests/reusable-workflow/run.sh`
all PASS.

---

### Change 2: Keep `job_workflow_ref` out of the shell, add the missing job permission

**Problem:** `echo "ref=$(echo '${{ github.job_workflow_ref }}' | cut -d@ -f2)"` expands an
expression inside the script body. The value comes from the caller's `uses:` ref, so the risk
is very low, but the standard pattern is an `env:` variable. Separately, the `taxonomy` job has
no `permissions:` block.

**File:** `.github/workflows/taxonomy-check.yml` (the two "Extract dev-platform ref" steps at
lines 66 to 74 and 100 to 103; the `taxonomy` job header at line 56)

**Implementation:**

- In both "Extract dev-platform ref from job_workflow_ref" steps add `env: JOB_WORKFLOW_REF:
  ${{ github.job_workflow_ref }}` (write the expression exactly like that, single spaces) and
  change the script to `echo "ref=$(echo "${JOB_WORKFLOW_REF}" | cut -d@ -f2)" >> "$GITHUB_OUTPUT"`.
  Keep the explanatory comment block in the first step; it must not contain `${{`, which
  Actions would expand inside a comment.
- Add `permissions: contents: read` to the `taxonomy` job. This is exactly what the
  `version-collision` job in the same workflow already requests, so any caller that works today
  grants it. Do NOT add a top-level `permissions:` block (it would change what the
  `version-collision` job inherits).
- Keep everything `tests/reusable-workflow/run.sh` asserts: the literal `${{ github.job_workflow_ref }}`
  still present in both jobs (now in `env:`), no `workflow_sha`, both jobs still check out the
  caller, `version-collision` still has `contents: read, issues: read`, `GH_TOKEN` and
  `ROADMAP_PATH` wiring unchanged.

**Acceptance Test:** `bash tests/reusable-workflow/run.sh` all PASS. Then run the new shell
logic by hand against a sample: `JOB_WORKFLOW_REF='teelr/dev-platform/.github/workflows/taxonomy-check.yml@refs/tags/v1.31'
bash -c 'echo "ref=$(echo "${JOB_WORKFLOW_REF}" | cut -d@ -f2)"'` prints `ref=refs/tags/v1.31`.
Note in the shipped record that this workflow is not exercised by this repo's own CI, so the
real proof is the first consumer run after the next tag.

---

### Change 3: Add `.github/dependabot.yml`

**Problem:** SHA pins never update on their own, and Dependabot is not configured here.

**File:** `.github/dependabot.yml` (new)

**Implementation:** `version: 2`, one `updates:` entry: `package-ecosystem: "github-actions"`,
`directory: "/"`, `schedule.interval: "weekly"`, `open-pull-requests-limit: 5`,
`commit-message.prefix: "ci"`. No `labels:` (a label that does not exist can make Dependabot
log an error; the consumer template's `dependencies` label has not been checked to exist on
this repo). Add a header comment saying why it exists (keeps the SHA pins in Change 1 current)
and that a Dependabot PR still needs merging. Consumer Audit for a new file in a
glob-managed directory: probe that it is tracked with `touch .github/probe.yml && git status
--porcelain .github/` and delete the probe.

**Acceptance Test:** the file parses (`python3 -c "import yaml; print(yaml.safe_load(open('.github/dependabot.yml')))"`),
`git status --porcelain .github/` lists it, and it contains the `github-actions` ecosystem.

---

### Change 4: Tests, and put `dependabot.yml` under the YAML check

**Problem:** Nothing stops a later edit from reintroducing a tag pin, and `gate_fast.sh` would
not notice a malformed `dependabot.yml`.

**File:** `tests/actions-pinning/run.sh` (new, auto-discovered); `scripts/gate_fast.sh`
(the `find` list at about lines 173-176); `tests/README.md`

**Implementation:**

- `scripts/gate_fast.sh`: add `"${REPO}/.github/dependabot.yml"` to the YAML-validity `find`
  as an extra path, keeping the file-count reporting and the "0 files matched" guard. The
  `find` already ignores a missing path (`2>/dev/null`).
- `tests/actions-pinning/run.sh` (PyYAML-guarded like `tests/reusable-workflow/run.sh`: SKIP
  loudly if PyYAML is missing, never pass by validating nothing). Assertions: (a) every `uses:`
  in `.github/workflows/*.yml` that is not a local `./` path and not `teelr/dev-platform/...` is
  pinned to a 40-hex SHA and its line carries a `# v` comment; (b) `.github/dependabot.yml`
  exists and lists the `github-actions` ecosystem; (c) no `run:` block in `.github/workflows/*.yml`
  contains `${{ github.` (expressions belong in `env:`), which also covers any new workflow;
  (d) each workflow has a top-level `permissions:` or per-job `permissions:` on every job.
  Mind the interaction with `tests/reusable-workflow/run.sh`: that suite wants the
  `${{ github.job_workflow_ref }}` expression present in the job's dumped YAML (it will be, in
  `env:`); assertion (c) only forbids it inside `run:` scripts.
- `tests/README.md`: list the new suite.

**Acceptance Test:** `bash tests/actions-pinning/run.sh` all PASS; reverting one pin to a tag
makes it FAIL (check by hand once, then restore); `./scripts/gate_fast.sh` PASS and its YAML
count goes up by one.

---

### Change 5: Documentation

**Problem:** The consumer template says dev-platform does not run Dependabot, and the Dependabot
and pinning behaviour needs a home.

**File:** `extensions/github-actions/dependabot-consumer-template.yml` (the note at lines 15-17),
`docs/CI-INTEGRATION.md` (the "Keeping the pin current" section, line 95), `tasks/shipped/<date>-v1.42-actions-hardening.md`
and `ROADMAP.md` (by `/code`'s doc step)

**Implementation:** Change the template note to say dev-platform now runs its own
`.github/dependabot.yml` (github-actions only) and that the template is still the copy-paste
source for consumers. In `docs/CI-INTEGRATION.md` add one short paragraph: this repo pins its
own actions to commit SHAs with a version comment and Dependabot bumps them, and a consumer
that wants the same does the same. Do not touch any consumer-facing `@v1.31` pin or the
`pins-agree` assertion.

**Acceptance Test:** `grep -n "does not run it" extensions/github-actions/dependabot-consumer-template.yml`
returns nothing; `bash tests/reusable-workflow/run.sh` still PASS (it compares the template pin
with the workflow header).

---

## Post-merge step

Run by `/merge`. **Stop and ask the user before each action below:** they change this repo's
GitHub configuration, and the last can break CI if anything is still pinned by tag.

1. Enable Dependabot alerts and security updates: `gh api -X PUT repos/teelr/dev-platform/vulnerability-alerts`
   and `gh api -X PUT repos/teelr/dev-platform/automated-security-fixes`. Read back both
   (`gh api repos/teelr/dev-platform/vulnerability-alerts -i` returns 204; the second returns
   `{"enabled":true,...}`). Undo with `-X DELETE` on the same paths.
2. Confirm Dependabot version updates are live: the repo's Dependabot page lists a
   `github-actions` run (assumption: reachable through the web UI only; if the CLI cannot show it,
   report that and ask the user to look).
3. Exercise the pinned Pages actions, which only `workflow_dispatch` or a docs push can run:
   `gh workflow run deploy-pages` then `gh run watch` until it completes; report the result. It
   republishes the docs site from `main`, which is harmless.
4. Only after step 3 succeeds and no workflow still uses a tag: enable mandatory pinning with
   `gh api -X PUT repos/teelr/dev-platform/actions/permissions -F enabled=true -f allowed_actions=all -F sha_pinning_required=true`
   (assumption: the call shape is untested; if it is rejected, report the error and stop, do not
   retry with other fields). Read back with `gh api repos/teelr/dev-platform/actions/permissions`.
   Undo by setting `sha_pinning_required=false`.
5. Update `issue #131`: tick the Dependabot, Actions-pinning and `taxonomy-check.yml` items, and
   correct the line numbers it quotes (they are 74 and 103, not ~57-59 and ~94-96).

---

## What NOT to Do

- Do not enable `sha_pinning_required` before every workflow is pinned and merged; it would
  fail the CI needed to merge the fix.
- Do not pin `teelr/dev-platform/...` refs, and do not change the consumer template's `@v1.31`
  pin or any `with:` input of the reusable workflow.
- Do not add a top-level `permissions:` block to `taxonomy-check.yml`.
- Do not add `labels:` to `dependabot.yml` without confirming the label exists.
- Do not put `${{ ... }}` inside a `run:` script or a comment within one (Actions expands it).
- Do not claim `taxonomy-check.yml` was tested end to end; this repo's CI does not run it.
- Do not touch any consumer repo or anything under `projects/`.
- Do not add other hardening (for example `persist-credentials: false`) in this phase; each
  checkout's behaviour is not exercised for the reusable workflow here.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `.github/workflows/gate.yml` | Modify | Pin `checkout` |
| `.github/workflows/pages.yml` | Modify | Pin five actions |
| `.github/workflows/taxonomy-check.yml` | Modify | Pin four checkouts; `env:` for `job_workflow_ref`; `permissions` on the `taxonomy` job |
| `.github/dependabot.yml` | New | `github-actions`, weekly |
| `scripts/gate_fast.sh` | Modify | YAML check also covers `.github/dependabot.yml` |
| `tests/actions-pinning/run.sh` | New | Pinning, Dependabot, no expressions in `run:`, permissions |
| `tests/README.md` | Modify | List the suite |
| `extensions/github-actions/dependabot-consumer-template.yml` | Modify | Fix the "does not run it" note |
| `docs/CI-INTEGRATION.md` | Modify | Short paragraph on SHA pins and Dependabot |
| `tasks/shipped/<date>-v1.42-actions-hardening.md`, `ROADMAP.md` | New / Modify | Written by `/code`'s doc step |

## Implementation Order

1. Change 1 (pins), then Change 2 (same file for taxonomy-check.yml), then Change 3.
2. Change 4 after 1 to 3 (the tests assert their end state).
3. Change 5 last.
4. The post-merge step only after the PR is merged and CI on `main` is green.

## Verification Checklist

- [ ] `bash tests/reusable-workflow/run.sh` and `bash tests/actions-pinning/run.sh` PASS
- [ ] `./scripts/gate_fast.sh` PASS; the YAML count includes `.github/dependabot.yml`
- [ ] Every `uses: actions/...` is a 40-hex SHA with a `# v...` comment
- [ ] The `job_workflow_ref` shell snippet prints `ref=refs/tags/v1.31` for the sample value
- [ ] `gate-fast` on the PR is green (it runs the pinned `checkout`)
- [ ] After merge: `deploy-pages` dispatch succeeds before `sha_pinning_required` is enabled
- [ ] `bash scripts/check_spec_taxonomy.sh` passes
- [ ] No file under `projects/` modified
