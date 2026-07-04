# v1.8: Missing-Chain Detection

## Coding Specification for Implementation

## Design Philosophy

`scripts/audit-project-drift.sh` classifies each registered project's workflow-chain state by grepping its `CLAUDE.md`. Today it recognizes three chain states: `NO_CLAUDE_MD` (no file), `DRIFT` (an old/wrong chain string is present), and `CLEAN` (everything else). The `CLEAN` bucket is a catch-all — and that is the bug. A `CLAUDE.md` that documents **no workflow chain at all** falls through to `CLEAN`, so the audit reports it identically to a project carrying the correct canonical chain.

This is not hypothetical. At plan time (2026-07-04 morning) the live audit reported **SQRL as `CLEAN`** — the same verdict it gives **dev-platform**, which carries the full canonical chain — even though SQRL's `CLAUDE.md` referenced the dev chain nowhere. (SQRL's own session added the chain later that day, so it now reports `CLEAN` legitimately; the blind spot it exposed is what this spec fixes, proven by a fixture rather than by SQRL's now-moved state.) The detector only fires on a *wrong* chain, never on a *missing* one, so a project that drops the workflow section wholesale reads as compliant. This is the third recurrence of the "detector keyed on a bad string can't see an absent one" shape (see the v0.9 and v1.3 self-match lessons in `tasks/lessons.md`), applied here to absence rather than self-reference.

The fix adds a fourth chain state, `MISSING_CHAIN`: `CLAUDE.md` exists, carries no old-chain drift pattern, **and** carries no canonical-chain anchor either. Detection order is load-bearing and mirrors the existing precedence — `NO_CLAUDE_MD` → `DRIFT` (old patterns win first, so a file that both mentions the old chain and the new one is still flagged) → `CLEAN` (canonical anchor present) → `MISSING_CHAIN` (else). `MISSING_CHAIN` counts toward the drift summary but gets a **distinct remediation hint**: `migrate-workflow-chain.sh` rewrites an *existing* chain and cannot insert one where none exists (verified: it reports "already up-to-date" against SQRL), so the fix for a missing chain is a manual add from the project's own session — not the migrate script. The audit stays a read-only reporter, exit 0 always, per its existing contract (`audit-project-drift.sh:9`).

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `audit-project-drift.sh` change | Bash | Modifying an existing Bash reporter in `scripts/`; the whole dev-platform tooling layer is shell, and this is a grep-and-classify change with no network/compute/AI/frontend dimension. Matches every sibling in `scripts/`. |
| `tests/migration/run.sh` additions | Bash | The suite that already owns this script's coverage is Bash, using the repo's `assert.sh` harness. |

## Overview

Phase 1 — Missing-Chain Detection:

- **Change 1:** Add the `MISSING_CHAIN` state to `scripts/audit-project-drift.sh` (detection logic, drift-count inclusion, distinct remediation hint, `--help` + header-comment docs).
- **Change 2:** Add a `no-chain-1` fixture + assertions to `tests/migration/run.sh`.
- **Change 3:** Doc updates — new `ROADMAP.md` v1.8 entry, `README.md` audit-description refresh, `planning.md` shipped summary.

All three land as one atomic commit: the gate runs `tests/migration/run.sh`, which must pass with the new behavior, so the implementation and its tests cannot commit separately.

---

## Phase 1: Missing-Chain Detection

### Change 1: Add `MISSING_CHAIN` state to audit-project-drift.sh

**Problem:** A `CLAUDE.md` that documents no workflow chain is bucketed as `CLEAN`, indistinguishable from a correct one. The audit cannot surface a project (e.g. SQRL) that omits the chain entirely.

**File:** `scripts/audit-project-drift.sh` (existing file)

**Implementation:**

1. **Chain-status logic** (existing block at `audit-project-drift.sh:110-118`). Add a canonical-anchor check and the `MISSING_CHAIN` fall-through. Replace the current three-branch `if` with a four-branch one. The order below is required — `DRIFT` must be evaluated before the canonical check so a file mixing old and new chain strings is still flagged, exactly as today:

   ```bash
   # Check 2: chain drift in CLAUDE.md.
   local chain_status
   if [[ "${has_claude_md}" == "NO" ]]; then
       chain_status="NO_CLAUDE_MD"
   elif grep -qE "/code → /test →|/test → /review|/code → /gate fast" "${claude_md}" 2>/dev/null; then
       chain_status="DRIFT"
   elif grep -qE "/code → /review" "${claude_md}" 2>/dev/null; then
       chain_status="CLEAN"
   else
       chain_status="MISSING_CHAIN"
   fi
   ```

   - The canonical anchor is `/code → /review` — the v1.3 hallmark that distinguishes the current canonical chain from both the old `/test` chains and the review-less chain. Any project on the canonical chain contains it; SQRL (no chain) contains neither a drift pattern nor this anchor, so it lands in `MISSING_CHAIN`.
   - Do NOT widen the anchor to a bare `/review` or `/code` — those appear in unrelated prose and would falsely rescue a chain-less file into `CLEAN`. Keep the two-command arrow-connected anchor.

2. **Drift-count inclusion + distinct hint** (markdown-summary block at `audit-project-drift.sh:161-179`). `MISSING_CHAIN` is a real gap and must count toward `drift_count`. Extend the increment condition and add a separate remediation line so users don't reach for the migrate script (which can't fix an absent chain):

   ```bash
   if [[ "${chain}" == "DRIFT" || "${chain}" == "MISSING_CHAIN" || "${taxonomy}" == "DRIFT" || "${has}" == "NO" ]]; then
       (( drift_count++ )) || true
   fi
   ```

   And in the trailing summary (after the existing `Chain drift:` hint):

   ```bash
   echo "  Chain drift: run \`./scripts/migrate-workflow-chain.sh --project <name> --apply\` to fix."
   echo "  Missing chain: add the canonical chain to the project's CLAUDE.md (see docs/PROJECT_CLAUDE_TEMPLATE.md); migrate-workflow-chain.sh cannot insert a chain that isn't there."
   ```

   (Both hint lines may print whenever `drift_count > 0`; that's acceptable — matching the existing single-hint behavior. Do not gate each hint on which specific drift type occurred; keep it simple.)

3. **Docs inside the script** — update the header comment (`audit-project-drift.sh:4-8`) and the `--help` heredoc (`audit-project-drift.sh:46-49`) to list the fourth state. In both places, where they currently enumerate the chain checks, add: `MISSING_CHAIN — CLAUDE.md present but documents no canonical workflow chain`.

**Acceptance Test:**

**Note:** SQRL was the motivating chain-less example at plan time, but its own session added the canonical chain between `/plan` and `/code` — so SQRL now correctly reports `CLEAN`, not `MISSING_CHAIN`. Do NOT anchor the acceptance test to SQRL's live state; the durable proof of `MISSING_CHAIN` is the `no-chain-1` fixture in `tests/migration/run.sh` (Checks 18–20).

```bash
# Live run — dev-platform stays CLEAN; kermit/kermit-pa/keystone/OPIE stay DRIFT.
./scripts/audit-project-drift.sh --project dev-platform | grep -q "CLEAN"
./scripts/audit-project-drift.sh --project kermit | grep -q "DRIFT"
# Help documents the new state.
./scripts/audit-project-drift.sh --help | grep -q "MISSING_CHAIN"
# Still read-only, still exit 0.
./scripts/audit-project-drift.sh; echo "exit=$?"   # exit=0
# MISSING_CHAIN path proven by fixture (not a live project):
bash tests/migration/run.sh | grep -q "no-chain-1 as MISSING_CHAIN"
```

---

### Change 2: Add `no-chain-1` fixture + assertions to tests/migration/run.sh

**Problem:** No fixture exercises a `CLAUDE.md` that exists but carries no chain. Without one, the `MISSING_CHAIN` path has zero regression coverage and could silently revert to the catch-all `CLEAN`.

**File:** `tests/migration/run.sh` (existing file)

**Implementation:**

1. **New mock project** — add alongside the other fixtures (after the `review-less-1` block, around `tests/migration/run.sh:93`). Mirrors SQRL: a real `CLAUDE.md` with sections but no workflow chain:

   ```bash
   # ─── Mock project: no-chain-1 ────────────────────────────────────────────
   # CLAUDE.md exists but documents NO workflow chain at all (the SQRL case).
   # Must be reported MISSING_CHAIN, distinct from CLEAN and DRIFT.
   mkdir -p "${MOCK_ROOT}/no-chain-1/tasks"
   cat > "${MOCK_ROOT}/no-chain-1/CLAUDE.md" <<'EOF'
   # No-Chain Project

   ## Project Overview

   A project whose CLAUDE.md never references the dev workflow chain.

   ## Ports

   Backend on 9999.
   EOF
   ```

2. **Register it** in `MOCK_REGISTRY` (the heredoc at `tests/migration/run.sh:97-106`) — add a row:

   ```bash
     {"name": "no-chain-1",      "path": "${MOCK_ROOT}/no-chain-1",      "gate_cmd": "true", "primary_language": "bash", "enabled": true}
   ```

   (Add a trailing comma to the preceding `review-less-1` row so the JSON stays valid.)

3. **New assertions** (append after the current Check 17, `tests/migration/run.sh:260`). Use the existing `record_pass`/`record_fail` harness:

   - **MISSING_CHAIN detected:**

     ```bash
     audit_out="$("${AUDIT}" --project no-chain-1 --registry "${MOCK_REGISTRY}" 2>&1)"
     if echo "${audit_out}" | grep -q "no-chain-1" && echo "${audit_out}" | grep -q "MISSING_CHAIN"; then
         record_pass "migration: audit reports no-chain-1 as MISSING_CHAIN"
     else
         record_fail "migration: audit did not flag no-chain-1 as MISSING_CHAIN — output: ${audit_out}"
     fi
     ```

   - **CLEAN not falsely reclassified** — a canonical-chain file must NOT be reported MISSING (guards the anchor from being too strict):

     ```bash
     audit_out="$("${AUDIT}" --project clean-1 --registry "${MOCK_REGISTRY}" 2>&1)"
     if echo "${audit_out}" | grep -q "CLEAN" && ! echo "${audit_out}" | grep -q "MISSING_CHAIN"; then
         record_pass "migration: audit keeps canonical clean-1 as CLEAN (not MISSING_CHAIN)"
     else
         record_fail "migration: canonical chain misclassified — output: ${audit_out}"
     fi
     ```

   - **MISSING_CHAIN counts as drift in the full-sweep summary:**

     ```bash
     audit_out="$("${AUDIT}" --registry "${MOCK_REGISTRY}" 2>&1)"
     if echo "${audit_out}" | grep -qE "Drift found in [1-9]"; then
         record_pass "migration: MISSING_CHAIN counts toward the drift summary"
     else
         record_fail "migration: drift summary did not count MISSING_CHAIN — output: ${audit_out}"
     fi
     ```

   - **migrate cannot fix a missing chain** — documents why the remediation hint differs:

     ```bash
     migrate_out="$("${MIGRATE}" --project no-chain-1 --registry "${MOCK_REGISTRY}" --apply 2>&1)"
     if echo "${migrate_out}" | grep -q "already up-to-date"; then
         record_pass "migration: migrate-workflow-chain.sh reports no-chain-1 already-up-to-date (cannot insert a missing chain)"
     else
         record_fail "migration: expected migrate to no-op on a chain-less CLAUDE.md — output: ${migrate_out}"
     fi
     ```

4. **Update the header count comment** (`tests/migration/run.sh:5`, "17 assertions") to the new total (21).

**Acceptance Test:**

```bash
bash tests/migration/run.sh   # all assertions PASS, including the 4 new ones
./scripts/gate_fast.sh        # full gate green; migration suite auto-discovered
```

---

### Change 3: Doc updates

**Problem:** The new Roadmap Phase and the audit's expanded contract must be recorded where readers look.

**Files:** `ROADMAP.md`, `README.md`, `planning.md` (all existing)

**Implementation:**

1. **`ROADMAP.md`** — add a v1.8 Roadmap Phase entry after the v1.7 entry (`ROADMAP.md:26`), matching the existing bullet style:

   > **v1.8: Missing-Chain Detection** *(complete — YYYY-MM-DD, `tasks/audit-project-drift-spec.md`)* — closes the drift-audit blind spot where `audit-project-drift.sh` reported a `CLAUDE.md` that omits the workflow chain as `CLEAN`, indistinguishable from a correct one (surfaced when SQRL joined the fleet registry and read CLEAN despite documenting no chain). Adds a fourth chain state, `MISSING_CHAIN` (file present, no old-chain drift pattern, no canonical `/code → /review` anchor), counted toward the drift summary with a distinct remediation hint — `migrate-workflow-chain.sh` rewrites an existing chain and cannot insert an absent one, so a missing chain is a manual add. +4 assertions in `tests/migration/run.sh`.

2. **`README.md`** — the audit sentence (`README.md:60`, the `audit-project-drift.sh` clause) currently says it produces "a read-only cross-project chain + taxonomy drift report." Extend to note it now distinguishes a missing chain from a wrong one: append "— now reports `MISSING_CHAIN` for a `CLAUDE.md` that documents no workflow chain at all, not just `DRIFT` for a wrong one."

3. **`planning.md`** — update "Current state" / "Recently shipped" per the `/docs` convention: mark v1.8 shipped with a one-line summary; leave "In flight" as nothing-in-flight after merge.

**Acceptance Test:**

```bash
grep -q "v1.8: Missing-Chain Detection" ROADMAP.md
grep -q "MISSING_CHAIN" README.md
./scripts/check_spec_taxonomy.sh   # ROADMAP/planning taxonomy scan stays green
```

---

## What NOT to Do

- **Do NOT widen the canonical anchor to a bare `/review`, `/code`, or `/gate`.** Those tokens appear in unrelated prose (command names, rule text) and would falsely rescue a chain-less `CLAUDE.md` into `CLEAN`. The two-command arrow-connected anchor `/code → /review` is the minimal reliable signal.
- **Do NOT reorder the detection branches.** `DRIFT` must be checked before the canonical anchor, so a file that mentions both an old and the new chain is still flagged DRIFT — preserving today's behavior.
- **Do NOT make the audit exit non-zero on `MISSING_CHAIN`.** It is a read-only reporter (`audit-project-drift.sh:9`, "Exit 0 always"). Counting toward `drift_count` changes the printed summary, not the exit code.
- **Do NOT point the missing-chain remediation at `migrate-workflow-chain.sh`.** That script rewrites an existing chain; on a chain-less file it reports "already up-to-date" and changes nothing. The hint must say "add the chain manually (see the template)."
- **Do NOT edit any project's `CLAUDE.md` under `projects/` to make the audit go green.** Fixing SQRL's actual missing chain is SQRL-session work under its own gate — out of scope here (scope rule in `/home/rich/dev/CLAUDE.md`). This spec only makes the *detector* see the gap.
- **Do NOT introduce a bare review-less chain string (`…/code → /gate fast…`) anywhere in dev-platform's own `CLAUDE.md` or `README.md`.** The audit greps dev-platform (registry path `.`); a bare old-chain string self-flags it as DRIFT (the v1.3 lesson). Describe drift states in prose, never as a literal old-chain example. Verify `./scripts/audit-project-drift.sh --project dev-platform` reports `CLEAN` before commit.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/audit-project-drift.sh` | Modify | Add `MISSING_CHAIN` state (canonical-anchor branch), count it toward drift, distinct remediation hint, update header comment + `--help`. |
| `tests/migration/run.sh` | Modify | Add `no-chain-1` fixture + registry row + 4 assertions; bump header count to 21. |
| `ROADMAP.md` | Modify | New v1.8 Roadmap Phase entry. |
| `README.md` | Modify | Extend the audit-description clause to mention `MISSING_CHAIN`. |
| `planning.md` | Modify | Mark v1.8 shipped (handled by `/code`'s doc step). |

## Implementation Order

1. **Change 1** — detection logic in `audit-project-drift.sh` (no dependency).
2. **Change 2** — fixture + assertions in `tests/migration/run.sh` (depends on Change 1's behavior; the suite must pass against the new logic).
3. **Change 3** — doc updates (`/code`'s final doc step).

All three commit together as one `feat:` commit — the gate runs the migration suite, so the code and its tests are inseparable.

## Verification Checklist

- [ ] `MISSING_CHAIN` path proven by the `no-chain-1` fixture (Checks 18–20). (SQRL — the plan-time example — was chain-fixed by its own session between `/plan` and `/code`, so it now correctly reports `CLEAN`; do not anchor the check to a live project.)
- [ ] `./scripts/audit-project-drift.sh --project dev-platform` still reports `CLEAN`.
- [ ] `./scripts/audit-project-drift.sh --project kermit` still reports `DRIFT`.
- [ ] `./scripts/audit-project-drift.sh --help` documents the fourth state.
- [ ] Audit still exits 0 on a full sweep (read-only reporter contract intact).
- [ ] `bash tests/migration/run.sh` — all assertions pass, including the 4 new ones (21 total).
- [ ] `./scripts/gate_fast.sh` — full gate green.
- [ ] `./scripts/check_spec_taxonomy.sh` — ROADMAP/planning taxonomy scan green.
- [ ] No bare review-less chain string introduced into dev-platform's own `CLAUDE.md`/`README.md` (dev-platform stays `CLEAN` in its own audit).
- [ ] No file under `projects/` modified.

## Follow-on (out of scope — capture, do not build here)

- **`docs/PROJECT_CLAUDE_TEMPLATE.md` does not seed the workflow chain.** A project scaffolded from the template starts chain-less and would now read `MISSING_CHAIN`. Seeding the canonical chain into the template (so new projects start compliant) is a directly-related but separate change — file it as its own small spec rather than folding it into this audit-only one.
