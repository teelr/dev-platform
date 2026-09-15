# v1.36: Gate Release Tier

## Coding Specification for Implementation

## Design Philosophy

`commands/gate.md` already documents a three-tier contract for a "generic `gate_fast.sh` project" (dev-platform itself, Keystone, OPIE, SQRL): `fast` runs `./scripts/gate_fast.sh`; `full` and `release` run `./scripts/gate_full.sh`/`./scripts/gate_release.sh` **if they exist**, and report "not available" otherwise. Neither exists for dev-platform today — verified: `ls scripts/gate_full.sh scripts/gate_release.sh` exits 2, "No such file or directory." This spec ships `scripts/gate_release.sh` only. It does NOT ship `gate_full.sh`.

**Why no `gate_full.sh`:** `CLAUDE.md`'s "Gate Tiers" section frames `full` as "load-tier smokes for changes touching threads, async interop, ContextVar state, shared-client adapters, or backend integration" — that's kermit-harness's concurrency-testing shape (verified: `commands/gate.md`'s Kermit Harness section lists `make load-l1-smoke`, `make load-l3-smoke`, etc. under `full`). dev-platform is a Bash/Python tooling repo with no such structural category — its own concurrency surface is the gate-lock take-turns mechanism, already fully covered at the `fast` tier (`tests/worktree/`, `tests/worktree-default/`). Building an empty `gate_full.sh` that just re-runs `gate_fast.sh` would be a check that validates nothing new — the same "vacuous gate" shape `v1.30`'s shipped record already named as a defect class. dev-platform's real two-tier shape is `fast` (every commit) and `release` (before a version bump) — this spec builds the second, real tier that's actually missing, not a placeholder for one that isn't needed.

**What actually belongs at `release` for THIS repo, decided by asking "does this validate dev-platform's own release, or is it fleet monitoring":** `gate_fast.sh` deliberately excludes every script that makes `gh` network calls or depends on `projects/` checkouts being present (documented in each script's own header — verified: `grep -n "NOT wired into gate_fast.sh"` across `scripts/`). Of those, three are genuinely about **dev-platform's own release correctness**: `check-phase-milestones.sh` and `check-phase-tags.sh` are the mechanical backstops for the standard post-merge Roadmap-Phase-completion step (`CLAUDE.md`) — a phase left unclosed or untagged is dev-platform's own bookkeeping being wrong, exactly the shape "before any version bump" exists to catch. `check-migration-coverage.sh` verifies that `migrate-lessons.sh`/`migrate-shipped.sh` — tools dev-platform ships and claims work "so consumer projects can port their own" — still parse what real consumers actually have; that's an integration test of dev-platform's own shipped tool, not an audit of another repo's code quality.

**What's deliberately left OUT, despite being raised as candidates in the planning discussion for this spec:** `fleet-pins.sh`, `fleet-gate.sh`, `check-comms-delivery.sh`, and `verify-remotes.sh` all showed up as candidates before this spec was written down. On closer reading of their own headers, all four are framed as periodic **fleet monitoring** tools (`fleet-gate.sh`'s own docstring: "read-only fleet sweep"; `check-comms-delivery.sh`: "fleet-style tool, like fleet-pins.sh") — they report on the HEALTH OF OTHER PROJECTS (are consumers pinned to a recent version, do their gates pass, are their communiques linked), not on whether DEV-PLATFORM'S OWN code is correct. Running kermit-v3's test suite as a gate on whether dev-platform can cut a release gets the dependency direction backwards — consumers depend on dev-platform, not vice versa. These stay exactly what they are today: standalone tools a human runs via `/dev` or on a schedule, not part of `gate_release.sh`.

**A real, already-verified finding this spec surfaces but does NOT fix:** running `check-migration-coverage.sh` right now (before any code in this spec exists) reports:

```text
| kermit                | FAILS (aborting, 21 row(s) unparseable — nothing written) | FAILS (aborting, 9 problem(s) — nothing written) |
```

`kermit` (`projects/kermit`, remote `teelr/kermit-harness` — verified via `monitoring/remotes.json`) is the ONE consumer whose `lessons.md`/`planning.md` still fail to parse; every other enabled, non-frozen consumer either parses or has already migrated. **This means `scripts/gate_release.sh`'s first real run, right after this spec ships, will correctly exit non-zero** — that is accurate, not a bug in the new script. There is a closed `teelr/kermit-harness#395` ("[dev-platform] Finish the lessons migration — 6 files landed, 153 entries still in lessons.md") that looks related but was closed 2026-09-07, before this live re-check. **Fixing kermit's files, or deciding whether `#395` should reopen, is explicitly out of scope for this spec** — per the Scope rule, this session does not write code in `projects/kermit`, and per Honesty About What Ships, this spec does not claim `gate_release.sh` passes cleanly when it verifiably does not. See "What NOT to Do."

**No fixture/mock test suite for this spec's new script.** Every script `gate_release.sh` calls is documented as read-only / dry-run-only in its own header (`check-migration-coverage.sh`: "STRICTLY READ-ONLY. Dry-run only, never `--apply`"; `check-phase-milestones.sh`/`check-phase-tags.sh`: pure `gh api`/`git tag` reads). `/code` can and should run `gate_release.sh` for real against the live repo as its own acceptance test — there is nothing to mock, and each called script already has its own offline mock-`gh` suite at the `fast` tier proving ITS OWN correctness (`tests/phase-milestones/`, `tests/phase-tags/`, `tests/migration-coverage/`). This spec only has to prove the WIRING is correct: each check's three real exit codes (0/1/2) map to the right PASS/FAIL, in the right order, with the right message.

**Where the new script's checks live:** NOT under `tests/` — `tests/README.md` is explicit that `tests/` is exclusively for `gate_fast.sh`'s offline fixtures ("build / integration tests requiring network access... deferred to a future `gate_full.sh` spec" — that placeholder is this spec's target, just under a different name; see Change 4). The one genuinely new check this spec adds beyond re-wiring existing scripts — a real, non-mocked `install.sh all` → `verify.sh` round trip against a **fresh local clone** (not the already-checked-out worktree `tests/install/run.sh` already exercises) — is written inline in `gate_release.sh` itself, matching how `gate_fast.sh` already inlines its own checks (taxonomy, bash syntax, JSON/YAML validity, secrets scan) rather than delegating every check to a `tests/<suite>/` directory. A fresh clone is the one thing `tests/install/run.sh` cannot catch: it runs directly against this already-checked-out working tree, so a script that silently depends on some untracked scratch file present in every real working copy would still pass there. A genuine `git clone` excludes anything gitignored, closing that gap — directly relevant given three prior Consumer-Audit gitignore-trap incidents already recorded in `CLAUDE.md`.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/gate_release.sh` | Bash | Matches every existing gate/check entry point (`gate_fast.sh`, `check-phase-milestones.sh`, `check-phase-tags.sh`, `check-migration-coverage.sh`) — all Bash, all sourcing `tests/helpers/assert.sh`. Zero new deps: `gh` and `jq` are already required by the scripts it calls. |
| Doc updates (`tests/README.md`, `README.md`) | Markdown | Standard. |

## Overview

1. **Phase 1: Release Gate Script** — `scripts/gate_release.sh`: runs `gate_fast.sh`, then `check-phase-milestones.sh`, `check-phase-tags.sh`, `check-migration-coverage.sh` (each with 3-way exit-code handling matching `check-registry.sh`'s existing pattern in `gate_fast.sh`), then an inline fresh-clone install/verify round trip (Change 1)
2. **Phase 2: Wire-up** — correct `tests/README.md`'s stale "future `gate_full.sh`" placeholder; mention `gate_release.sh` in root `README.md` (Changes 2–3)

**Demo:** `./scripts/gate_release.sh` runs `gate_fast.sh` in full (488 PASS baseline), then each of the three fleet-bookkeeping checks against the live repo, then clones the current working tree into a throwaway directory and round-trips `install.sh all` → `verify.sh` there with a sandboxed `$HOME`. **Today, right now, this correctly exits 1** — every check passes except `check-migration-coverage.sh`, which correctly reports kermit's two unparseable files. That FAIL is accurate; a clean exit would be the bug.

---

## Phase 1: Release Gate Script

### Change 1: `scripts/gate_release.sh` — the release-tier gate

**Problem:** `/gate release` has nothing to dispatch to for dev-platform. The checks that would answer "is it safe to cut a version bump" already exist as standalone scripts, but nothing runs them together, and nothing has ever verified their wiring produces one coherent PASS/FAIL.

**File:** `scripts/gate_release.sh` (new, executable)

**Implementation:**

Follow `scripts/gate_fast.sh`'s own structure and helpers directly (same `tests/helpers/assert.sh` source, same `record_pass`/`record_fail`/`record_skip` calls, same summary shape) — do not invent a different aggregation mechanism.

```bash
#!/usr/bin/env bash
# scripts/gate_release.sh — dev-platform release gate. Runs gate_fast.sh,
# then the fleet-bookkeeping checks gate_fast.sh deliberately excludes
# (network calls, gh auth, or projects/ dependence), then a fresh-clone
# install/verify round trip. Run before any minor/major version bump —
# see CLAUDE.md's "Gate Tiers" and Roadmap-Phase-completion post-merge step.
#
# NOT wired into CI: makes gh network calls and clones the repo locally.
# Run this by hand (or via /gate release) before cutting a release tag.
#
# Usage: ./scripts/gate_release.sh
# Runtime: dominated by gate_fast.sh (~15-50s) + gh API calls (~5-15s) +
# the fresh-clone round trip (~5-10s).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export _GATE_COUNTS_FILE
_GATE_COUNTS_FILE="$(mktemp /tmp/gate-release-counts.XXXXXX)"
trap "rm -f '${_GATE_COUNTS_FILE}'" EXIT

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

START=$(date +%s)
echo "=== gate release ==="
echo ""
echo "--- gate fast (foundation) ---"

# gate_fast.sh prints its own full PASS/FAIL/SKIP detail and exits non-zero
# on any FAIL. Treated here as ONE named check — its own internal counts
# are already proven correct by its own summary line; re-parsing them would
# duplicate that, not add coverage.
if bash "${REPO}/scripts/gate_fast.sh"; then
    record_pass "gate fast (constitutional checks + test suites)"
else
    record_fail "gate fast (constitutional checks + test suites — see output above)"
fi

echo ""
echo "--- fleet bookkeeping (release-only: gh network calls) ---"

# check-phase-milestones.sh — 0 clean, 1 flagged milestone(s) found, 2 setup
# error (missing gh/jq, unresolvable repo, fetch failure).
(cd "${REPO}" && bash scripts/check-phase-milestones.sh)
milestones_rc=$?
case ${milestones_rc} in
    0) record_pass "phase milestones (no open-but-complete milestones)" ;;
    1) record_fail "phase milestones (open-but-complete milestone found — close it)" ;;
    *) record_fail "phase milestones (check-phase-milestones.sh setup error, exit ${milestones_rc})" ;;
esac

# check-phase-tags.sh — 0 clean, 1 untagged complete phase(s), 2 setup error.
(cd "${REPO}" && bash scripts/check-phase-tags.sh)
tags_rc=$?
case ${tags_rc} in
    0) record_pass "phase tags (every complete phase tagged)" ;;
    1) record_fail "phase tags (complete phase missing its release tag — cut it)" ;;
    *) record_fail "phase tags (check-phase-tags.sh setup error, exit ${tags_rc})" ;;
esac

# check-migration-coverage.sh — 0 every source parses/migrated, 1 a source
# fails to parse, 2 setup error (jq absent, registry missing, bad arg).
#
# KNOWN, VERIFIED, NOT-YET-FIXED: as of this writing kermit's lessons.md and
# planning.md both fail to parse (21 + 9 problems) — this correctly reports
# exit 1 today. Fixing kermit's files is out of scope for dev-platform (Scope
# rule: no writes under projects/) — see the spec's Design Philosophy.
(cd "${REPO}" && bash scripts/check-migration-coverage.sh)
migration_rc=$?
case ${migration_rc} in
    0) record_pass "migration coverage (every consumer source parses or is migrated)" ;;
    1) record_fail "migration coverage (a consumer source fails to parse — see table above)" ;;
    *) record_fail "migration coverage (check-migration-coverage.sh setup error, exit ${migration_rc})" ;;
esac

echo ""
echo "--- fresh-clone install/verify round trip (release-only) ---"

# tests/install/run.sh (gate-fast tier) already round-trips install.sh /
# verify.sh / uninstall.sh against a sandboxed $HOME — but it runs directly
# against this already-checked-out working tree. A script that silently
# depends on an untracked scratch file present in every real working copy
# would still pass there. A genuine `git clone` excludes anything
# gitignored, closing that specific gap — three prior Consumer-Audit
# gitignore-trap incidents are exactly this failure mode (CLAUDE.md).
CLONE_DIR="$(mktemp -d /tmp/gate-release-clone.XXXXXX)"
FAKE_HOME="$(mktemp -d /tmp/gate-release-home.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${CLONE_DIR}' '${FAKE_HOME}'; rm -f '${_GATE_COUNTS_FILE}'" EXIT

if git clone --quiet "${REPO}" "${CLONE_DIR}" >/dev/null 2>&1; then
    if HOME="${FAKE_HOME}" bash "${CLONE_DIR}/scripts/install.sh" all >/dev/null 2>&1 \
            && HOME="${FAKE_HOME}" bash "${CLONE_DIR}/scripts/verify.sh" >/dev/null 2>&1; then
        record_pass "fresh clone: install.sh all + verify.sh round trip"
    else
        record_fail "fresh clone: install.sh/verify.sh failed against a genuine clone"
    fi
else
    record_fail "fresh clone: git clone of ${REPO} failed"
fi

echo ""
echo "=== summary ==="
END=$(date +%s)

total_pass=$(grep -c "^PASS$" "${_GATE_COUNTS_FILE}" 2>/dev/null); total_pass=${total_pass:-0}
total_fail=$(grep -c "^FAIL$" "${_GATE_COUNTS_FILE}" 2>/dev/null); total_fail=${total_fail:-0}
total_skip=$(grep -c "^SKIP$" "${_GATE_COUNTS_FILE}" 2>/dev/null); total_skip=${total_skip:-0}

echo "  ${total_pass} PASS  ${total_fail} FAIL  ${total_skip} SKIP  ($((END - START))s)"

if [[ ${total_fail} -gt 0 ]]; then
    echo ""
    echo "GATE RELEASE: FAIL"
    exit 1
fi
echo "GATE RELEASE: PASS"
```

**Notes on deviations from `gate_fast.sh`'s exact pattern, and why:**

- No gate-lock (`with_gate_lock`) around the fresh-clone step. The lock exists to serialize concurrent gates hitting the SAME live `~/.claude/` deploy target (`scripts/verify.sh` against the real one). The fresh-clone step targets a brand-new `mktemp -d`, unique per invocation — there is nothing shared to serialize.
- No telemetry emission. `gate_fast.sh`'s telemetry block logs every commit-time gate run for the `gate_run` event/metrics catalog (`monitoring/metrics.md`). A release gate runs rarely (before a version bump, not every commit) and logging it would need its own event type and a `monitoring/metrics.md` update — explicitly out of scope for this spec; see "Out of Scope."
- `gate_fast.sh`'s own output is NOT suppressed (no `>/dev/null`) — a release-gate run is a deliberate, infrequent, thorough pass; seeing the full constitutional-check detail is the point, unlike the terser fleet-bookkeeping checks where only the PASS/FAIL matters for the summary (their own tables/detail still print to stdout either way, since they aren't redirected).

**Acceptance Test:**

```bash
chmod +x scripts/gate_release.sh
bash -n scripts/gate_release.sh

./scripts/gate_release.sh
echo "exit=$?"
# EXPECT (verified live, before this Change exists): exit 1.
# Expect to see, in order:
#   "gate fast (constitutional checks + test suites)" — PASS
#   "phase milestones (no open-but-complete milestones)" — PASS
#   "phase tags (every complete phase tagged)" — PASS
#   "migration coverage (a consumer source fails to parse — see table above)" — FAIL
#   "fresh clone: install.sh all + verify.sh round trip" — PASS
# Final summary: 4 PASS, 1 FAIL, 0 SKIP, "GATE RELEASE: FAIL"
```

**If `check-migration-coverage.sh`'s kermit finding has been fixed by the time `/code` runs this** (unlikely, but the acceptance test must not silently assume today's exact state forever): re-run `bash scripts/check-migration-coverage.sh` directly first and match the acceptance test's expectation to whatever it reports NOW, not to the FAIL this spec was written against. Either way, the wiring correctness being tested is "each script's real exit code maps to the right PASS/FAIL/message," not "the fleet is currently perfectly healthy."

---

## Phase 2: Wire-up

### Change 2: `tests/README.md` — resolve the stale "future `gate_full.sh`" placeholder

**Problem:** `tests/README.md`'s "What does NOT go here" section says network/infra-dependent tests are "deferred to a future `gate_full.sh` spec." That placeholder's target has arrived, under a different name (`gate_release.sh`, per this spec's Design Philosophy on why `full` doesn't apply here), and it doesn't live under `tests/` at all — it's inline in the script itself.

**File:** `tests/README.md` (existing)

**Implementation:**

Edit the "What does NOT go here" bullet:

```markdown
- build / integration tests requiring network access, slow installs (npm/pip/go), or running infra — these run at RELEASE tier (`scripts/gate_release.sh`, v1.36), not under `tests/`. `tests/` stays exclusively for `gate_fast.sh`'s offline fixtures; `gate_release.sh`'s checks are either existing standalone scripts it calls directly (`check-phase-milestones.sh`, `check-phase-tags.sh`, `check-migration-coverage.sh` — each already has its own offline mock-`gh` suite under `tests/` proving ITS OWN correctness) or written inline in `gate_release.sh` itself, matching how `gate_fast.sh` inlines its own taxonomy/syntax/JSON/YAML checks.
```

**Acceptance Test:**

```bash
grep -q "gate_release.sh" tests/README.md
! grep -q "future \`gate_full.sh\` spec" tests/README.md
```

### Change 3: root `README.md` — mention `gate_release.sh`

**Problem:** `README.md`'s Roadmap section paragraph names every gate/check script dev-platform ships (`gate_fast.sh`, `fleet-gate.sh`, `check-phase-milestones.sh`, `check-phase-tags.sh`, etc.) but has no mention of the new release-tier entry point.

**File:** `README.md` (existing)

**Implementation:**

In the "## Roadmap" paragraph, immediately after the existing sentence ending "...skipping its test-suite checks (structural/taxonomy checks unaffected) when a diff is pure documentation (v1.14, `scripts/lib/docs_only_diff.sh`)." insert:

```markdown
`./scripts/gate_release.sh` (v1.36) runs before any minor/major version bump: `gate_fast.sh` in full, plus the fleet-bookkeeping checks `gate_fast.sh` deliberately excludes for speed (`check-phase-milestones.sh`, `check-phase-tags.sh`, `check-migration-coverage.sh` — each makes `gh` network calls or depends on `projects/` checkouts), plus a fresh-clone `install.sh`/`verify.sh` round trip. Not wired into CI; run it locally.
```

**Acceptance Test:**

```bash
grep -q "gate_release.sh" README.md
```

---

## What NOT to Do

- **Do not build `scripts/gate_full.sh`.** dev-platform has no concurrency/async/backend-integration category that tier exists for in `CLAUDE.md`'s generic framing — see Design Philosophy. Building it anyway would be a check that validates nothing.
- **Do not attempt to fix kermit's `lessons.md`/`planning.md` parse failures.** This session does not write code under `projects/` (Scope rule). The correct action, if any, is a GitHub issue against `teelr/kermit-harness` or a decision about the already-closed `teelr/kermit-harness#395` — a decision for the user, not this spec.
- **Do not soften `check-migration-coverage.sh`'s exit 1 into a SKIP or a warning to make `gate_release.sh` report a clean PASS.** That would be exactly the "vacuous gate" failure mode `CLAUDE.md` already names as a recurring defect class (`check_env_leak`'s three-way fix, `v1.30`'s registry validation). A release gate that cannot fail is not a gate.
- **Do not wire `fleet-pins.sh`, `fleet-gate.sh`, `check-comms-delivery.sh`, or `verify-remotes.sh` into `gate_release.sh`.** All four report on OTHER projects' health, not dev-platform's own release correctness — see Design Philosophy's "deliberately left OUT" paragraph. They remain standalone fleet-monitoring tools.
- **Do not add telemetry emission for `gate_release.sh`.** `gate_fast.sh`'s `gate_run` event exists for commit-frequency metrics; a rarely-run release gate needs its own event type and a `monitoring/metrics.md` update, which is out of scope here.
- **Do not have the fresh-clone check push to or fetch from the real GitHub remote.** `git clone "${REPO}" "${CLONE_DIR}"` clones the LOCAL working tree (no network, no dependency on what's pushed) — this tests "does a clean checkout of what's on disk right now work," not "is `origin` reachable."

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/gate_release.sh` | New | Release-tier gate: `gate_fast.sh` + 3 fleet-bookkeeping checks + fresh-clone round trip |
| `tests/README.md` | Modify | Resolve stale "future `gate_full.sh`" placeholder to point at `gate_release.sh` |
| `README.md` | Modify | Mention `gate_release.sh` in the Roadmap paragraph |
| `tasks/gate-release-tier-spec.md` | (this file) | Spec |

## Implementation Order

1. **Phase 1 (Change 1)** — `scripts/gate_release.sh`. Self-contained; no dependency on Phase 2.
2. **Phase 2 (Changes 2–3)** — doc wire-up, once the script's real name and behavior are final.

Both Changes fit in one `/code` session (one new script, two small doc edits). Single feature branch/worktree → single PR — the two Phases aren't independently shippable in a way that matters (Phase 2 is just documenting Phase 1's existence), so splitting them would be pure ceremony over a small diff.

## Verification Checklist

- [ ] `bash -n scripts/gate_release.sh` passes
- [ ] `./scripts/gate_release.sh` runs `gate_fast.sh`, then the three fleet-bookkeeping checks, then the fresh-clone round trip, in that order
- [ ] Each of the three fleet-bookkeeping checks correctly maps its real 0/1/2 exit code to PASS/FAIL per the case statements above
- [ ] Today's real run reports exactly 1 FAIL (`check-migration-coverage.sh`'s kermit finding) and 4 PASS, with `GATE RELEASE: FAIL` — verified as the CORRECT result, not patched away
- [ ] `tests/README.md` no longer references a "future `gate_full.sh` spec"
- [ ] `README.md` mentions `gate_release.sh`
- [ ] `gate_fast.sh`'s own PASS count is unchanged by this spec (488 — this spec adds nothing under `tests/`)
- [ ] No file under `projects/` modified
- [ ] `scripts/check_spec_taxonomy.sh` passes
- [ ] Spec deviations (if any) explicitly flagged at `/code` time

## Out of Scope (Future Specs)

- **`scripts/gate_full.sh`** — not needed for dev-platform's current shape; revisit only if a genuinely concurrency/backend-integration-shaped component gets added.
- **Telemetry for `gate_release.sh` runs** — would need a new event type + `monitoring/metrics.md` update.
- **Wiring `fleet-pins.sh`/`fleet-gate.sh`/`check-comms-delivery.sh`/`verify-remotes.sh` into any gate tier** — these stay standalone fleet-monitoring tools, run via `/dev` or on a schedule, not as a gate.
- **CI integration for `gate_release.sh`** — deliberately local-only; a CI runner has no `projects/` checkouts for `check-migration-coverage.sh` to read and no reason to clone-and-reinstall on every PR.
- **Fixing kermit's `lessons.md`/`planning.md` parse failures, or resolving `teelr/kermit-harness#395`** — a decision and a fix that belong to kermit-harness's own session, not this one.
