# v1.30: Frozen Project State

## Coding Specification for Implementation

## Design Philosophy

`monitoring/projects.json` has one boolean, `enabled`, and it is doing two unrelated jobs: deciding whether the fleet **runs a project's tests**, and deciding whether the fleet **nags about the project's dev-platform pin**. For most projects those answers agree. For kermit-pa they are opposite.

kermit-pa is **deployed but frozen** — still running in production, no further development, superseded by kermit-v3 (2026-09-04). Disabling it would stop `fleet-gate.sh` sweeping its test suite, which is the one signal worth having on something in prod. Leaving it enabled means `fleet-pins.sh` reports it as 17 versions behind forever, next to projects where that number is a call to action. Neither is right, so v1.29's stopgap was a prose `notes` field explaining why the row never moves — a comment standing in for a missing state.

Three states exist in the registry today and only two are expressible:

| State | Example | Run its tests? | Chase its pin? | Expressible now |
| ----- | ------- | -------------- | -------------- | --------------- |
| Active | keystone, kermit-v3 | yes | yes | `enabled: true` |
| **Deployed, frozen** | **kermit-pa** | **yes** | **no** | **no** |
| Dormant / deprecated | OPIE, atlas | no | no | `enabled: false` |

**`frozen: true` is additive, not a replacement.** A tri-state `status: active|frozen|disabled` would read better on a blank page, but every one of the six consumers below parses `enabled` today and a rename touches all of them for no behavioural gain. An absent `frozen` means `false`, so every existing entry keeps working untouched.

**The flag is not one check — it is six decisions**, and the point of the phase is that they genuinely differ. The rule for each: *does this operation still mean anything on a repo nobody will open a PR against?*

| Consumer | On `frozen: true` | Why |
| -------- | ----------------- | --- |
| `scripts/fleet-gate.sh` | **still sweeps** | it is deployed; a broken test is the thing you want to hear about |
| `monitoring/fleet_dashboard.py` | **still shows**, marked frozen | its real state matters; hiding a deployed project is worse than listing it |
| `monitoring/fleet_pins.py` | **`frozen` status, no staleness delta** | `dev-platform-gate` fires only on PRs; a frozen repo raises none, so the pin gates nothing |
| `scripts/check-migration-coverage.sh` | **skip** | the lessons convention prevents *future* concurrent appends; there will be none |
| `scripts/audit-project-drift.sh` | **skip** | workflow-chain drift only matters to someone about to follow the chain |
| `scripts/fleet-install-template.sh` | **refuse**, distinct message | it mutates a consumer repo; writing a fresh template into a frozen one is pointless |

**`enabled: false` always wins.** `frozen` is a qualifier on an enabled project, so a disabled entry is skipped regardless. That combination is contradictory rather than dangerous, and Change 7 makes it a loud validation error rather than a silent precedence rule nobody remembers.

**The registry schema is currently documented nowhere.** `monitoring/README.md` covers telemetry and never describes `projects.json`, so `gate_cmd`, `enabled` and the ad-hoc `notes` field are defined only by the code that reads them. Adding a seventh field to an undocumented schema would compound that, so this phase writes the schema down.

**Branching strategy:** single branch, single PR. The Phases are not independently shippable — the flag with no consumers changes nothing, and a consumer honouring a field the schema does not define is worse than either.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `monitoring/fleet_pins.py`, `fleet_dashboard.py` | Python | Existing files; the fleet inspectors are Python by v0.8 convention. |
| `scripts/fleet-gate.sh`, `check-migration-coverage.sh`, `audit-project-drift.sh`, `fleet-install-template.sh` | Bash | Existing files; `jq` filters over the registry. |
| `scripts/check-registry.sh` | Bash | A registry validator alongside the other `check-*.sh` detectors, matching `check-phase-tags.sh`. |
| `tests/frozen-state/run.sh` | Bash | Existing per-suite runner contract. |
| `monitoring/README.md` | Markdown | Where the registry schema belongs. |

No new services. The Language Architecture Decision Matrix is not in play.

## Overview

**Phase 1: Define the state**

1. Change 1 — document the `projects.json` schema in `monitoring/README.md`, including `frozen`.
2. Change 2 — set `frozen: true` on kermit-pa and trim its v1.29 stopgap note.

**Phase 2: The consumers that should ignore it**

3. Change 3 — `fleet-gate.sh` and `fleet_dashboard.py` keep frozen projects, dashboard marks them.

**Phase 3: The consumers that should honour it**

4. Change 4 — `fleet_pins.py`: a `frozen` status instead of a staleness delta.
5. Change 5 — `check-migration-coverage.sh` and `audit-project-drift.sh` skip frozen projects, reporting the skip.
6. Change 6 — `fleet-install-template.sh` refuses a frozen target with its own message.

**Phase 4: Make the state checkable**

7. Change 7 — `scripts/check-registry.sh` validates the schema, including `enabled: false` + `frozen: true`.
8. Change 8 — `tests/frozen-state/` fixture suite.

---

## Phase 1: Define the State

### Change 1: Write down the registry schema

**Problem:** `monitoring/projects.json` is read by six scripts and documented by none. `monitoring/README.md` describes telemetry only. A reader learns the schema by grepping `jq` filters, and v1.29 already added a `notes` field that no document mentions.

**File:** `monitoring/README.md` (existing — new section)

**Implementation:**

A table of every field, its type, whether it is required, and which tools read it:

- `name` (required) — registry key; matches the directory under `projects/` and the `--project` argument to every fleet script.
- `path` (required) — repo-relative (`projects/<name>`) or absolute. Relative paths resolve against the **main checkout**, not the invoking worktree (v1.27, `scripts/lib/main_checkout.sh`), because `projects/` is gitignored.
- `gate_cmd` (required) — the project's own gate, run by `fleet-gate.sh`. Must exist in that repo; a wrong value breaks the whole sweep.
- `primary_language` (required) — informational.
- `enabled` (required) — `false` removes the project from every fleet operation. Missing is treated as `false` by every consumer, so it is effectively required.
- `frozen` (optional, default `false`) — deployed but not developed. Table of the six per-consumer behaviours from the Design Philosophy above.
- `notes` (optional) — free prose for anything the flags cannot express.

State the precedence rule once, here: **`enabled: false` wins; `frozen` only qualifies an enabled project.**

**Acceptance Test:**

```bash
grep -n "frozen" monitoring/README.md      # schema section exists and covers it
./scripts/gate_fast.sh                     # markdown checks pass
```

---

### Change 2: Mark kermit-pa frozen

**Problem:** kermit-pa's state currently lives in a 101-word `notes` string added on 2026-09-04 as a stopgap, explaining in prose what a flag should express. Every fleet tool still treats it as fully active.

**File:** `monitoring/projects.json`

**Implementation:**

Add `"frozen": true` to the kermit-pa entry. Trim the note to what the flag cannot carry — that it is superseded by kermit-v3, the date, and that its pin-bump and lessons asks were closed as moot (`teelr/kermit-pa#178`, `#179`, `PR #176`). Delete the sentences that explained the behaviour the flag now encodes; keeping both is how prose and state drift apart.

Leave `enabled: true`. That is the whole point.

**Acceptance Test:**

```bash
python3 -c "import json; d=json.load(open('monitoring/projects.json')); \
  pa=[p for p in d if p['name']=='kermit-pa'][0]; \
  assert pa['enabled'] is True and pa['frozen'] is True; print('kermit-pa: enabled+frozen')"
```

---

## Phase 2: The Consumers That Should Ignore It

### Change 3: Gate sweeps and the dashboard keep frozen projects

**Problem:** These two must **not** change behaviour, and that is easy to get wrong while touching every other consumer. A frozen project is deployed; dropping it from the gate sweep removes the only automated signal that it still works.

**Files:** `scripts/fleet-gate.sh` (the `jq` filter at ~line 115), `monitoring/fleet_dashboard.py` (the `enabled` filter at ~line 284, and the row renderer)

**Implementation:**

`fleet-gate.sh`: **no filter change.** Add a comment at the filter stating that `frozen` is deliberately not consulted, and why — otherwise the next person adding a `frozen` check "for consistency" removes prod test coverage. The comment is the deliverable.

`fleet_dashboard.py`: keep frozen projects in the list; add a `frozen` marker to the row so the dashboard distinguishes "quiet because nobody is working on it" from "quiet because something is wrong". A frozen project with a red gate is still a real finding.

**Acceptance Test:**

```bash
./scripts/fleet-gate.sh --project kermit-pa    # still sweeps; frozen does not exclude it
./scripts/fleet-status.sh | grep kermit-pa     # still listed, marked frozen
```

---

## Phase 3: The Consumers That Should Honour It

### Change 4: `fleet_pins.py` reports frozen, not behind

**Problem:** kermit-pa reads `⚠ 17 minor behind` beside projects where that number means "go do something". Nobody will bump it, because `dev-platform-gate` fires only on pull requests and a frozen repo raises none.

**File:** `monitoring/fleet_pins.py` — `classify()`, `format_status()`, and `query_project()`

**Implementation:**

Add a `frozen` status, assigned in `query_project` **after** `classify()` returns, the same way `unverifiable` is (v1.27). Do not touch `classify()`'s comparison logic: the pin is still read and still reported in the `Pin (live)` column — only the *staleness judgement* is suppressed, because the reading is true and the judgement is not actionable.

`format_status` renders `— frozen (deployed, not developed)`. `minor_delta` becomes `None`, so a frozen project cannot sort into the "most behind" position of any future report.

Precedence with the statuses added since v1.27: `unverifiable` (a genuine unknown) still wins over `frozen`, because "we could not read it" is a fact about the tool and must never be masked by a fact about the project. Drift detection is unaffected — a frozen project whose local copy disagrees with its default branch is still worth saying, since that is a repo-state problem, not a pin-currency one.

Open bump PRs (v1.31) still surface: a bump PR open against a frozen project is exactly the stale-PR case worth closing.

**Acceptance Test:**

```bash
./scripts/fleet-pins.sh
#   → kermit-pa row: Pin (live) v1.12 preserved, status "— frozen", no "N minor behind"
#   → every other row unchanged
```

---

### Change 5: Migration coverage and drift audit skip frozen projects

**Problem:** Both ask questions that presuppose future work. `check-migration-coverage.sh` asks whether the lessons/shipped migrations *can run*, a convention that exists to stop future concurrent appends colliding — there will be none. `audit-project-drift.sh` checks whether the documented workflow chain is current, which matters only to someone about to follow it.

**Files:** `scripts/check-migration-coverage.sh` (the `jq` filter at ~line 167), `scripts/audit-project-drift.sh` (filters at ~lines 83 and 90)

**Implementation:**

Extend both filters to exclude `frozen == true`. **Report the skip rather than silently shrinking the list** — a project vanishing from a coverage report with no explanation is the same failure class as `check_env_leak`'s vacuous pass (`scripts/gate_fast.sh:77-82`). `check-migration-coverage.sh` gets a `FROZEN (skipped)` row; `audit-project-drift.sh` names skipped projects in its summary line.

`--project <name>` explicitly naming a frozen project should still run and say it is frozen — an explicit request is not the same as a sweep, and refusing it would be surprising.

**Acceptance Test:**

```bash
./scripts/check-migration-coverage.sh              # kermit-pa row reads FROZEN (skipped)
./scripts/check-migration-coverage.sh --project kermit-pa   # explicit request still runs
./scripts/audit-project-drift.sh                   # kermit-pa excluded, named in the summary
```

---

### Change 6: `fleet-install-template.sh` refuses a frozen target

**Problem:** It is the one mutating fleet operation, governed by the Scope-rule carve-out. It already refuses disabled projects; a frozen one should be refused too, and for a different stated reason.

**File:** `scripts/fleet-install-template.sh` (the enabled gate at ~line 148)

**Implementation:**

Add a `frozen` check beside the existing `enabled` one, with its own message and the same exit code 1. Say *why* — the repo is deployed but not developed, so a freshly pinned template would gate PRs that will never be raised. Point at the registry `notes` for the project-specific reason.

Keep the two checks separate rather than merging into one condition: the messages are the value, and a reader hitting the refusal needs to know which state stopped them.

**Acceptance Test:**

```bash
./scripts/fleet-install-template.sh --project kermit-pa
#   → exits 1 naming frozen, NOT "disabled"
./scripts/fleet-install-template.sh --project OPIE
#   → exits 1 naming disabled, unchanged
```

---

## Phase 4: Make the State Checkable

### Change 7: `scripts/check-registry.sh`

**Problem:** Nothing validates `projects.json`. A typo in `gate_cmd` breaks the fleet sweep for every project; a missing `enabled` is silently treated as `false`, removing a project from every operation with no error; and `enabled: false` + `frozen: true` is now expressible and contradictory.

**File:** `scripts/check-registry.sh` (new)

**Implementation:**

Validates and exits 1 on any violation, naming the entry:

1. Required fields present: `name`, `path`, `gate_cmd`, `primary_language`, `enabled`. A **missing `enabled`** is an error, not a default — silently disabling a project is exactly the failure this catches.
2. `enabled` and `frozen` are real booleans, not the strings `"true"`/`"false"`.
3. **`enabled: false` with `frozen: true`** — contradictory; frozen qualifies an enabled project.
4. `name` unique.
5. Where the checkout exists, `gate_cmd`'s script exists in it. Where it does not (CI, fresh clone), **skip that check and say so** — do not pass silently, and do not fail on an absent checkout.

Wired into `gate_fast.sh` beside the other constitutional checks. Rule 5's environment-dependence is the only part that can go vacuous, so it reports SKIP explicitly, following the `check_env_leak` three-way pattern (exit 2 → SKIP) rather than inventing a fourth convention.

**Acceptance Test:**

```bash
./scripts/check-registry.sh          # exits 0 on the real registry
./scripts/gate_fast.sh               # picks it up; PASS count rises
```

---

### Change 8: `tests/frozen-state/` fixture suite

**Problem:** The whole phase is six *different* answers to one flag. A suite that only checks "frozen is honoured" would pass while `fleet-gate` had quietly stopped sweeping prod.

**File:** `tests/frozen-state/run.sh` (new)

**Implementation:**

One fixture registry with an active, a frozen, and a disabled entry, run offline against each consumer. Assertions:

1. `fleet_pins` — frozen project gets `frozen` status, **pin still reported**, `minor_delta` None.
2. `fleet_pins` — `unverifiable` beats `frozen` when both apply.
3. `fleet_pins` — the active project's row is unchanged by the frozen entry's presence.
4. **`fleet-gate` still includes the frozen project** — the regression that matters most.
5. `fleet_dashboard` lists it, marked frozen.
6. `check-migration-coverage` shows `FROZEN (skipped)`, and `--project` on it still runs.
7. `audit-project-drift` excludes it and names it in the summary.
8. `fleet-install-template` refuses it with a frozen-specific message, distinct from the disabled one.
9. `check-registry` rejects `enabled: false` + `frozen: true`.
10. `check-registry` rejects a missing `enabled` and a string `"true"`.
11. A registry with **no `frozen` keys at all** behaves exactly as before — the backward-compatibility guarantee, asserted rather than assumed.

**Acceptance Test:**

```bash
bash tests/frozen-state/run.sh    # offline, no consumer checkouts required
./scripts/gate_fast.sh            # auto-discovered
```

---

## What NOT to Do

- **Do not make `fleet-gate.sh` skip frozen projects.** It is the single most likely wrong "consistency" fix in this phase, and it removes the only automated signal on something running in production. Change 3's comment exists to stop it.
- **Do not replace `enabled` with a tri-state.** Six consumers parse it; a rename is churn with no behavioural gain. `frozen` is additive and absent means false.
- **Do not let `frozen` mask `unverifiable`.** A tool that could not read a repo must say so; that is a fact about the tool, not the project.
- **Do not silently shrink any list.** A project dropping out of a report without explanation is the vacuous-output failure this repo keeps rediscovering — report the skip.
- **Do not suppress drift detection on a frozen project.** Local-vs-live disagreement is a repo-state problem, unrelated to pin currency.
- **Do not stop reading the pin.** Only the staleness *judgement* is suppressed; the reading is still true and still shown.
- **Do not write to any consumer repo.** Same Scope rule as always — this phase changes dev-platform's view of them.
- **Do not mark any project frozen except kermit-pa.** OPIE is dormant (`enabled: false`), atlas deprecated. Those are correct as they are.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `monitoring/README.md` | Modify | Registry schema documented, including `frozen` |
| `monitoring/projects.json` | Modify | `frozen: true` on kermit-pa; note trimmed |
| `scripts/fleet-gate.sh` | Modify | Comment only — states that `frozen` is deliberately ignored |
| `monitoring/fleet_dashboard.py` | Modify | Keeps frozen projects; marks the row |
| `monitoring/fleet_pins.py` | Modify | `frozen` status; no staleness delta; pin still read |
| `scripts/check-migration-coverage.sh` | Modify | Skips frozen, reports `FROZEN (skipped)` |
| `scripts/audit-project-drift.sh` | Modify | Skips frozen, names them in the summary |
| `scripts/fleet-install-template.sh` | Modify | Refuses frozen with its own message |
| `scripts/check-registry.sh` | New | Registry validator, wired into `gate_fast.sh` |
| `scripts/gate_fast.sh` | Modify | Runs the validator |
| `tests/frozen-state/run.sh` | New | 11-assertion offline suite |
| `README.md`, `ROADMAP.md`, `tasks/shipped/`, `tasks/lessons/` | Modify/New | `/code`'s doc step |

## Implementation Order

1. **Change 8's fixture registry first**, before any consumer edit — build the three-entry fixture and record what each consumer does with it *today*. That baseline is what proves Change 3 preserved `fleet-gate`'s behaviour rather than assuming it. Detector-first, per v1.28's lesson.
2. **Changes 1-2** — schema, then the flag on kermit-pa.
3. **Change 3** — the two that must not change, done early so a regression shows up against the baseline immediately.
4. **Changes 4, 5, 6** — the four that honour it.
5. **Change 7** — the validator, once `frozen` exists to validate.
6. **Change 8** — finish the suite.
7. Re-run `fleet-pins`, `fleet-gate --project kermit-pa`, `check-migration-coverage` and `audit-project-drift` against the **real** registry and paste the actual output into the shipped record. Regenerate it; do not copy the table from this spec.

## Verification Checklist

- [ ] kermit-pa is `enabled: true` **and** `frozen: true`
- [ ] `fleet-gate.sh --project kermit-pa` still sweeps it — the load-bearing non-change
- [ ] `fleet-pins.sh` shows kermit-pa as frozen with its pin still read, and no staleness delta
- [ ] `unverifiable` still beats `frozen` (SQRL unaffected)
- [ ] Drift detection still fires on a frozen project
- [ ] `check-migration-coverage.sh` reports `FROZEN (skipped)`, and `--project kermit-pa` still runs
- [ ] `audit-project-drift.sh` excludes kermit-pa and names it in the summary
- [ ] `fleet-install-template.sh --project kermit-pa` refuses with a frozen message, distinct from OPIE's disabled one
- [ ] `check-registry.sh` exits 0 on the real registry; rejects contradictory, missing and string-typed flags
- [ ] A registry with no `frozen` keys behaves exactly as pre-v1.30
- [ ] Registry schema documented in `monitoring/README.md`
- [ ] No file under `projects/` modified
- [ ] `./scripts/gate_fast.sh` passes from the worktree **and** the main checkout
- [ ] `./scripts/verify.sh` clean

`/security-review` is not required — registry metadata and reporting only; no auth, credentials, external input, or endpoints.

## Post-merge

1. **Roadmap-Phase completion** (standard): mark v1.30 complete in `ROADMAP.md`, close its milestone, cut the `v1.30` release tag at the squash-merge commit, verify with `check-phase-milestones.sh` and `check-phase-tags.sh`.
2. **No consumer communication.** This changes how dev-platform *views* its consumers; nothing in any consumer repo changes, and no consumer pins or installs anything affected. kermit-pa's three asks are already closed.
3. **Re-run the fleet reports** and record the resulting output — the standing measure that the six decisions landed as intended.
