# Roadmap Path Input

## Coding Specification for Implementation

## Design Philosophy

`ROADMAP_PATH` was added in v1.13 so a project whose Roadmap Phase entries do not live at root `ROADMAP.md` could point the checks at the real file. `check_spec_taxonomy.sh`, `check_version_collision.py`, `claim_roadmap_version.py` and `check-phase-tags.sh` all read it. **No consumer can reach it through CI**, because the reusable workflow does not accept it:

```bash
$ grep -n "inputs" .github/workflows/taxonomy-check.yml
20:  workflow_call:
21:    inputs:
22:      ref:          # the only input; env: on both run steps sets GH_TOKEN and nothing else
```

**The documentation is the worse half of this.** `docs/CI-INTEGRATION.md` → "Non-default roadmap location" tells consumers to "set it as an `env:` entry on the calling step/job in your `dev-platform-gate.yml`". A consumer's `dev-platform-gate.yml` has exactly one job, and that job is a reusable-workflow call — `uses:`, not `steps:`. A job calling a reusable workflow accepts a restricted key set (`name`, `needs`, `if`, `permissions`, `uses`, `with`, `secrets`, `strategy`, `concurrency`); `env` is not in it, and caller-level `env` does not propagate into a called workflow's jobs regardless. So the instruction cannot be followed as written. **Change 1 verifies this against live GitHub rather than trusting the reasoning** — the whole phase rests on it.

Keystone is the live case and demonstrates the cost. Its real roadmap is `docs/roadmap.md` (1063 lines). It maintains a **hand-written root `ROADMAP.md` index** of version headers, plus a bespoke `CT-ROADMAP-INDEX` gate check to stop the two drifting, purely so dev-platform's shared CI can parse anything at all. Its first attempt was a symlink, which produced false `COLLISION` failures against its own milestone history (`teelr/keystone#508` → `#509`) because `git show origin/main:ROADMAP.md` returns the raw symlink target string as file content. A consumer built and debugged a workaround for a feature we had already shipped and told them to use.

**An input, not auto-discovery.** Auto-discovery (fall back to a candidate list when root `ROADMAP.md` is absent) needs only a pin bump rather than a workflow edit, which is genuinely cheaper for consumers. It is still wrong here, and keystone is the proof: **keystone has a root `ROADMAP.md`**, so discovery finds it, stops, and changes nothing for the one project that needs this. Discovery helps only repos with no root file at all, guesses silently when it does fire, and cannot be overridden. The explicit input is what the docs already promise and the only thing that serves the motivating case.

**The empty-string trap is the real implementation hazard, and it is asymmetric.** The two readers disagree about `ROADMAP_PATH=""`:

```bash
$ ROADMAP_PATH= bash -c 'echo "${ROADMAP_PATH:-ROADMAP.md}"'
ROADMAP.md                       # bash :- treats empty as unset — correct
$ python3 -c "import os; os.environ['ROADMAP_PATH']=''; print(repr(os.environ.get('ROADMAP_PATH','ROADMAP.md')))"
''                               # Python .get() treats empty as a VALUE — wrong
```

`Path(root) / ""` is `root` itself, a directory. `.exists()` returns True, so the "no roadmap — nothing to check" guard is skipped and `read_text()` raises. Probed on a real fixture repo:

```text
$ ROADMAP_PATH= python3 scripts/check_version_collision.py .
IsADirectoryError: [Errno 21] Is a directory: '.'
rc=1
```

Exit 1 is what the workflow maps to `::error::version collision detected`. So an input declared with an empty default would hand **every consumer that does not set it** a false collision failure on a repo with no collision. The input therefore defaults to `ROADMAP.md`, *and* the Python readers are hardened to treat empty as unset — belt and braces, because the env var is also exported by hand for local `/plan` runs where nothing validates it.

**The reusable workflow has no test and no validation.** Nothing in `tests/` asserts anything about `taxonomy-check.yml`'s structure — every hit is a fixture pin string. `gate_fast.sh` validates JSON (`settings/`, `scaffolding/`) and never YAML. The file every consumer's CI depends on is the least-checked file in the repo. Adding an input to it without fixing that would be the same shape as v1.30 adding a seventh field to an unvalidated registry.

**Branching strategy:** single branch, single PR. The Changes are not independently shippable — the input without the doc fix leaves the wrong instruction standing, and the doc fix without the input documents something that does not exist. Total diff is small.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `.github/workflows/taxonomy-check.yml` | YAML | Existing reusable workflow; GitHub Actions has no alternative. |
| `extensions/github-actions/dev-platform-gate.yml` | YAML | Existing consumer template. |
| `scripts/check_version_collision.py`, `claim_roadmap_version.py` | Python | Existing files; the empty-string hardening goes where the bug is. |
| `tests/reusable-workflow/run.sh` | Bash | Existing per-suite runner contract; parses YAML via a short `python3` block. |
| `scripts/gate_fast.sh` | Bash | Existing orchestrator. |
| `docs/CI-INTEGRATION.md` | Markdown | Where the wrong instruction lives. |

No new services. The Language Architecture Decision Matrix is not in play.

## Overview

**Phase 1: Prove the gap, then close it**

1. Change 1 — verify on live GitHub that `env:` on a reusable-call job is rejected, and record the evidence.
2. Change 2 — add the `roadmap_path` input to `taxonomy-check.yml` and wire it into both jobs.
3. Change 3 — harden the Python readers so an empty `ROADMAP_PATH` means unset.

**Phase 2: Make it reachable**

4. Change 4 — consumer template gains a commented `with:` block and its pin moves to `@v1.31`.
5. Change 5 — `docs/CI-INTEGRATION.md`: replace the instruction that cannot be followed.

**Phase 3: Stop shipping this file untested**

6. Change 6 — `tests/reusable-workflow/` suite.
7. Change 7 — YAML validity in `gate_fast.sh`.

---

## Phase 1: Prove the Gap, Then Close It

### Change 1: Verify the premise on live GitHub

**Problem:** The whole phase rests on "a consumer cannot pass `ROADMAP_PATH` through the reusable workflow." That is reasoned from GitHub's documented key set for `uses:` jobs, not observed. If it is wrong — if `env:` on a reusable-call job silently works — the fix is a two-line doc correction, not this spec.

**File:** none in this repo; a scratch branch on **dev-platform itself**, deleted after.

**Implementation:**

Push a throwaway branch carrying a workflow whose job both `uses:` the reusable workflow and declares `env: ROADMAP_PATH: docs/roadmap.md`. Observe what GitHub does. Expect a workflow-level validation error naming `env` as unexpected; the run will not start.

Then confirm the positive half: the same job with `with: roadmap_path: ...` against a ref that does not yet declare the input must fail with an *invalid input* error. That is what a consumer sees if they adopt the `with:` syntax before bumping their pin, and Change 5's doc text has to say so.

Record both outcomes verbatim in the shipped record. **Delete the scratch branch.** If either observation contradicts the Design Philosophy, STOP and re-plan rather than proceeding.

**Acceptance Test:**

```bash
gh run list --branch <scratch-branch> --limit 5   # shows the startup_failure / validation error
gh api repos/teelr/dev-platform/git/refs/heads/<scratch-branch> -X DELETE
```

---

### Change 2: Add the `roadmap_path` input and wire it to both jobs

**Problem:** The input does not exist, so `ROADMAP_PATH` is unreachable from CI.

**File:** `.github/workflows/taxonomy-check.yml` (existing — `inputs:` block ~line 21, both `run:` steps ~lines 56 and 84)

**Implementation:**

Add beneath the existing `ref` input:

```yaml
      roadmap_path:
        description: 'Path to the roadmap file, relative to the caller repo root (default ROADMAP.md)'
        type: string
        required: false
        default: 'ROADMAP.md'
```

**The default is `ROADMAP.md`, never `''`** — see the Design Philosophy probe. An empty default would give every consumer that omits the input a false `COLLISION` failure.

Wire it into **both** jobs, because both scripts read it and a consumer setting it once expects both to honour it:

- `taxonomy` job's run step → add `env: ROADMAP_PATH: ${{ inputs.roadmap_path }}`.
- `version-collision` job's run step → add `ROADMAP_PATH: ${{ inputs.roadmap_path }}` alongside the existing `GH_TOKEN`.

Wiring one and not the other is the most likely defect here and the one Change 6 asserts against specifically: the two jobs would then disagree about which file is the roadmap, and the taxonomy job would silently scan nothing while the collision job worked.

Update the header comment's example `uses:` line to `@v1.31` and show the `with:` form.

**Acceptance Test:**

```bash
python3 -c "
import yaml; w=yaml.safe_load(open('.github/workflows/taxonomy-check.yml'))
ins=w['on']['workflow_call']['inputs']
assert ins['roadmap_path']['default']=='ROADMAP.md', ins['roadmap_path']
for j in ('taxonomy','version-collision'):
    envs=[s.get('env',{}) for s in w['jobs'][j]['steps']]
    assert any('ROADMAP_PATH' in e for e in envs), j
print('roadmap_path declared and wired into both jobs')"
```

---

### Change 3: An empty `ROADMAP_PATH` means unset, in Python too

**Problem:** `os.environ.get("ROADMAP_PATH", "ROADMAP.md")` returns `""` for an empty env var, and `Path(root) / ""` is the root directory — which `.exists()` accepts and `read_text()` cannot read. Verified: `IsADirectoryError`, exit 1, which the workflow renders as a false collision error. Bash's `${ROADMAP_PATH:-ROADMAP.md}` already handles this correctly, so the two reader families disagree about the same environment.

**Files:** `scripts/check_version_collision.py:99`, `scripts/claim_roadmap_version.py:68`

**Implementation:**

In both, replace the bare `.get()` with a read that treats empty-or-whitespace as absent — matching what bash's `:-` already does. One small module-level helper used by both is preferable to two copies (Derivation Sweep); `scripts/lib/` already exists and is on the import path for `check_version_collision.py` via the `repo_slug` precedent.

Change 2's default makes this unreachable *from CI*, which is exactly why it belongs here anyway: the env var is also exported by hand for local `/plan` and `gate_fast.sh` runs, where nothing validates it and a stray `export ROADMAP_PATH=` is a plausible mistake.

Do **not** change `check_spec_taxonomy.sh` or `check-phase-tags.sh` — both already use `${VAR:-default}` and are correct.

**Acceptance Test:**

```bash
cd "$(mktemp -d)" && git init -q -b main && printf '# R\n\n## v1.0: T\n' > ROADMAP.md
ROADMAP_PATH= python3 /path/to/scripts/check_version_collision.py .
#   → clean "SKIP" or normal output, exit 0 or 2 — never an IsADirectoryError traceback
```

---

## Phase 2: Make It Reachable

### Change 4: Consumer template shows the input, pinned to a tag that has it

**Problem:** Consumers copy `extensions/github-actions/dev-platform-gate.yml`. It pins `@v1.26` and shows no `with:` block, so nobody discovers the input. Worse, a consumer who adds `with: roadmap_path:` while pinned below v1.31 gets an *invalid input* error — Change 1 captures exactly what that looks like.

**File:** `extensions/github-actions/dev-platform-gate.yml` (existing)

**Implementation:**

Bump the `uses:` pin to `@v1.31` and add the input **commented out**, with a one-line note that it is only needed when the roadmap is not at root `ROADMAP.md`, and that it requires `@v1.31` or newer:

```yaml
jobs:
  taxonomy:
    uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@v1.31
    # Only if your roadmap is NOT at the repo root. Requires @v1.31+ —
    # passing this to an older pin fails with an invalid-input error.
    # with:
    #   roadmap_path: docs/roadmap.md
```

Commented, not active: the default is correct for every consumer but keystone, and an active `with:` block invites copy-paste of a path that does not exist in the copying repo.

**This line is load-bearing beyond the template.** `fleet-install-template.sh` derives `DEFAULT_PIN` by parsing the template's own `uses:` line (v1.26), so bumping it moves the fleet installer's default in the same edit. `tests/fleet-install` asserts on that derivation — expect it to need updating, and check `tests/fleet-pins` for hardcoded `v1.26` strings too.

**Acceptance Test:**

```bash
grep -n "taxonomy-check.yml@v1.31" extensions/github-actions/dev-platform-gate.yml
./scripts/fleet-install-template.sh --project keystone   # dry-run: "Pin:    @v1.31"
bash tests/fleet-install/run.sh
```

---

### Change 5: Replace the instruction that cannot be followed

**Problem:** `docs/CI-INTEGRATION.md` → "Non-default roadmap location" says to set `ROADMAP_PATH` "as an `env:` entry on the calling step/job in your `dev-platform-gate.yml`". That job is a `uses:` call with no steps and no permitted `env`. A consumer following it either gets a validation error or, if they put `env` at workflow level, a silent no-op — the shape keystone hit before building its index workaround.

**File:** `docs/CI-INTEGRATION.md` (the "Non-default roadmap location" section ~line 125, and the troubleshooting row ~line 159)

**Implementation:**

Rewrite the section to distinguish the two contexts, which the current text conflates:

- **In CI** — pass `with: roadmap_path:` to the reusable workflow. Requires `@v1.31` or newer; show what an older pin produces, quoting Change 1's observed error.
- **Locally** (`/plan`, `gate_fast.sh`, `check-phase-tags.sh`) — export `ROADMAP_PATH`. This is where the env var was always the right mechanism.

Keep the symlink warning verbatim; it is correct, hard-won, and cites a real incident.

Add a line stating plainly that `env:` on a reusable-workflow-call job is not valid, so a reader who remembers the old advice learns why it changed instead of assuming the docs drifted.

Update the troubleshooting row for "no ROADMAP.md — nothing to check" to point at the input for CI and the export for local.

**Acceptance Test:**

```bash
grep -n "roadmap_path" docs/CI-INTEGRATION.md      # the with: form is documented
grep -n "env:" docs/CI-INTEGRATION.md              # no surviving "set env: on the calling job"
./scripts/gate_fast.sh
```

---

## Phase 3: Stop Shipping This File Untested

### Change 6: `tests/reusable-workflow/`

**Problem:** Nothing asserts anything about `taxonomy-check.yml`. Every consumer's CI calls it; a typo in an input name or a step-name change breaks the whole fleet silently, and this phase is about to edit it.

**File:** `tests/reusable-workflow/run.sh` (new)

**Implementation:**

Parses the real workflow with `python3`/`pyyaml` and asserts:

1. `workflow_call.inputs` declares `roadmap_path`, type `string`, **default exactly `ROADMAP.md`** — the empty-default regression, named explicitly.
2. `ROADMAP_PATH` is wired into **both** the `taxonomy` and `version-collision` jobs, from `inputs.roadmap_path`. Asserted per job, not "at least one" — one-job wiring is the likely defect.
3. `GH_TOKEN` survives on the `version-collision` step (adding an env key must not displace the existing one).
4. Both jobs still check out the caller and derive the dev-platform ref from `github.job_workflow_ref` — the mechanism the header comment says must not regress to `workflow_sha`.
5. The `version-collision` job keeps `permissions: contents: read, issues: read` — the cross-org startup_failure found on SQRL.
6. The consumer template's `uses:` pin and the workflow's own header example name the same tag.
7. Empty `ROADMAP_PATH` does not crash `check_version_collision.py` (Change 3's regression, asserted against the script directly).

If `pyyaml` is unavailable, **`record_skip` with a message naming the missing module** — never a silent pass. The gate treats SKIP distinctly, per the `check_env_leak` precedent.

**Acceptance Test:**

```bash
bash tests/reusable-workflow/run.sh
./scripts/gate_fast.sh                 # auto-discovered
```

---

### Change 7: YAML validity in the gate

**Problem:** `gate_fast.sh` validates every tracked JSON file and no YAML file. A malformed `taxonomy-check.yml` or consumer template would reach `main`, and the reusable workflow's blast radius is every consumer's CI.

**File:** `scripts/gate_fast.sh` (beside the existing JSON-validity check ~line 130)

**Implementation:**

Mirror the JSON check's shape over `.github/workflows/*.yml`, `extensions/github-actions/*.yml`, and `scaffolding/**/*.yml`, using `python3 -c "import yaml; yaml.safe_load(...)"`. Report the file count in the PASS line, as the JSON check does, so a glob that matches nothing is visible rather than a silent pass.

If `pyyaml` is missing, record SKIP naming it — not PASS. A validity check that validated nothing is the exact failure this repo keeps rediscovering.

**Acceptance Test:**

```bash
./scripts/gate_fast.sh | grep -i "YAML validity"      # names a non-zero file count
printf 'a:\n  - b\n c\n' > /tmp/bad.yml               # then temporarily copy into a scanned dir
./scripts/gate_fast.sh                                # must FAIL; remove the file afterwards
```

---

## What NOT to Do

- **Do not default `roadmap_path` to `''`.** It hands every consumer that omits the input a false `COLLISION` failure via `IsADirectoryError` → exit 1. This is the single most likely way to ship this phase broken, and it fails on *other people's* repos.
- **Do not wire `ROADMAP_PATH` into only one job.** The two jobs would disagree about which file is the roadmap; the taxonomy job would scan nothing and still pass.
- **Do not implement auto-discovery instead.** keystone has a root `ROADMAP.md`, so discovery finds it and helps the motivating case not at all.
- **Do not delete or edit keystone's index file or its `CT-ROADMAP-INDEX` check.** Another repo, another session — the Scope rule. Whether they retire the workaround is their call once the input exists.
- **Do not remove the symlink warning** from `docs/CI-INTEGRATION.md`. It is correct and cites a real incident (`teelr/keystone#508` → `#509`).
- **Do not skip Change 1.** The premise is reasoned, not observed. Everything else follows from it.
- **Do not leave the scratch branch from Change 1 on the remote.**
- **Do not change `check_spec_taxonomy.sh` or `check-phase-tags.sh`** — their `${VAR:-default}` reads are already correct.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `.github/workflows/taxonomy-check.yml` | Modify | `roadmap_path` input; wired into both jobs |
| `scripts/check_version_collision.py` | Modify | Empty `ROADMAP_PATH` treated as unset |
| `scripts/claim_roadmap_version.py` | Modify | Same |
| `scripts/lib/roadmap_path.py` | New | The shared reader both import |
| `extensions/github-actions/dev-platform-gate.yml` | Modify | Pin `@v1.31`; commented `with:` block |
| `docs/CI-INTEGRATION.md` | Modify | CI vs local split; the invalid `env:` advice removed |
| `scripts/gate_fast.sh` | Modify | YAML validity check |
| `tests/reusable-workflow/run.sh` | New | 7-assertion suite |
| `tests/fleet-install/run.sh`, `tests/fleet-pins/run.sh` | Modify | Pin-string updates from Change 4 |
| `README.md`, `ROADMAP.md`, `tasks/shipped/`, `tasks/lessons/` | Modify/New | `/code`'s doc step |

## Implementation Order

1. **Change 1 first, before any code.** It can invalidate the spec. Record the observed errors; delete the scratch branch.
2. **Change 6's assertions 1-5 next, against the CURRENT workflow** — they should fail on `roadmap_path` and pass on the rest, proving the suite detects the absence before Change 2 fills it.
3. **Change 2**, then re-run Change 6 — assertions flip to green.
4. **Change 3**, with the empty-env probe as its own regression test.
5. **Changes 4 and 5** — template and docs together; they describe the same mechanism.
6. **Change 7**, then the full suite.
7. Re-run `fleet-install-template.sh --project keystone` (dry-run) and confirm the derived pin reads `@v1.31`.

## Verification Checklist

- [ ] Change 1's observed GitHub errors recorded verbatim; scratch branch deleted
- [ ] `roadmap_path` default is exactly `ROADMAP.md`, never empty
- [ ] `ROADMAP_PATH` wired into **both** jobs, asserted per job
- [ ] `GH_TOKEN` still present on the `version-collision` step
- [ ] `ROADMAP_PATH=` (empty) no longer crashes either Python script
- [ ] `permissions:` and the `job_workflow_ref` derivation unchanged
- [ ] Consumer template pins `@v1.31`; `fleet-install-template.sh` derives `@v1.31`
- [ ] `docs/CI-INTEGRATION.md` no longer tells anyone to set `env:` on a `uses:` job
- [ ] YAML validity check reports a non-zero file count, and fails on a malformed file
- [ ] No file under `projects/` modified
- [ ] `./scripts/gate_fast.sh` passes from the worktree **and** the main checkout
- [ ] `./scripts/verify.sh` clean

`/security-review` is not required — CI configuration and reporting only. No auth logic, credentials, or new endpoints; `GH_TOKEN` handling is unchanged and explicitly asserted so.

## Post-merge

1. **Roadmap-Phase completion** (standard): mark v1.31 complete in `ROADMAP.md`, close its milestone, cut the `v1.31` release tag at the squash-merge commit, verify with `check-phase-milestones.sh` and `check-phase-tags.sh`. **The tag matters more than usual here** — the input does not exist for any consumer until a tag carries it, and Change 4's template already points at `@v1.31`.
2. **Tell keystone.** Comment on `teelr/keystone#515` that the input now exists at `@v1.31`, with the exact `with:` block, and that it makes the root `ROADMAP.md` index and its `CT-ROADMAP-INDEX` check retirable — their decision, from their own session. That issue is currently the record of a bump with little to offer; this gives it a concrete payoff.
3. **No other consumer action.** Every other consumer's roadmap is at the default path; the input is opt-in and the default preserves today's behaviour exactly.
