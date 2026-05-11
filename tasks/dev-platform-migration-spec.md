# v0.9: Migration Tooling

## Coding Specification for Implementation

## Design Philosophy

v0.9 closes the gap between the standards dev-platform defines and the state each consumer project is actually in. Three categories of drift accumulated before v0.7–v0.8 enforcement landed: (1) dev-platform's own spec files carry legacy `R<N>-` filename prefixes that predate the semver taxonomy; (2) per-project `CLAUDE.md` files reference the old workflow chain (`/plan → /code → /test → /review → /gate fast → /docs → commit`) rather than the slimmed v0.9 chain (`/plan → /code → /gate fast → commit → push → /pr → CI → /merge`); (3) no tooling exists to audit cross-project drift after a standards update ships.

The implementation follows v0.8's established patterns: a Bash migration script (opt-in, dry-run default, `--apply` flag) + a read-only audit script + a fixture test suite auto-discovered by `gate_fast.sh`. The migration script is purposely narrow — it touches exactly one thing per project (`CLAUDE.md` workflow chain lines) and nothing else, mirroring Phase 3's `fleet-install-template.sh` "write one file, refuse everything else" contract.

Scope: Phase 1 cleans up dev-platform's own house (spec file renames, no cross-project mutations, no new Scope carve-out needed). Phase 2 introduces the cross-project tools and the matching Scope carve-out for the mutation they perform. The carve-out is intentionally as narrow as v0.8 Phase 3's — it names the script, the file, and the exact replacement content, so future expansions require explicit documentation rather than inference.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/migrate-workflow-chain.sh` | Bash | Entry-point pattern matches every prior `scripts/fleet-*.sh` script. No compute or AI — pure text manipulation via `sed` + `git`. |
| `scripts/audit-project-drift.sh` | Bash | Read-only survey; same pattern as `scripts/fleet-gate.sh` registry sweep. No Python needed — `grep` + `git` suffice. |
| `tests/migration/run.sh` | Bash | Test-suite pattern locked in v0.4; mock-project-tree pattern from v0.8 Phase 2. |

## Overview

1. **Phase 1 — Internal Cleanup** (Changes 1–2): rename 3 legacy R-prefix spec files; update all references in ROADMAP.md.
2. **Phase 2 — Cross-project Migration Tools** (Changes 3–5): CLAUDE.md Scope carve-out; `scripts/migrate-workflow-chain.sh`; `scripts/audit-project-drift.sh` + `tests/migration/run.sh`.

---

## Phase 1: Internal Cleanup

### Change 1: Rename legacy R-prefix spec files

**Problem:** Three spec files in `tasks/` carry the pre-semver `R<N>-` filename prefix (`dev-platform-r2-monitoring-spec.md`, `dev-platform-r3-testing-spec.md`, `dev-platform-r4a-scaffolding-spec.md`). The v0.7 taxonomy enforcement rule requires `v<MAJOR>.<MINOR>` prefixes at the Roadmap Phase level, and spec filenames should be descriptive rather than encoding the old numeric scheme. `planning.md` line 47 and 51 call this out as explicitly deferred to v0.9.

**Files:**

- `tasks/dev-platform-r2-monitoring-spec.md` → `tasks/dev-platform-monitoring-spec.md`
- `tasks/dev-platform-r3-testing-spec.md` → `tasks/dev-platform-testing-spec.md`
- `tasks/dev-platform-r4a-scaffolding-spec.md` → `tasks/dev-platform-scaffolding-spec.md`

**Implementation:**

Use `git mv` for all three renames so git tracks the rename rather than treating them as delete + add:

```bash
git mv tasks/dev-platform-r2-monitoring-spec.md tasks/dev-platform-monitoring-spec.md
git mv tasks/dev-platform-r3-testing-spec.md tasks/dev-platform-testing-spec.md
git mv tasks/dev-platform-r4a-scaffolding-spec.md tasks/dev-platform-scaffolding-spec.md
```

Then update the three backtick references in `ROADMAP.md` (lines 9–11) that quote the old filenames:

- Line 9: `` `tasks/dev-platform-r4a-scaffolding-spec.md` `` → `` `tasks/dev-platform-scaffolding-spec.md` ``
- Line 10: `` `tasks/dev-platform-r3-testing-spec.md` `` → `` `tasks/dev-platform-testing-spec.md` ``
- Line 11: `` `tasks/dev-platform-r2-monitoring-spec.md` `` → `` `tasks/dev-platform-monitoring-spec.md` ``

Also update `planning.md` lines 47–48 which reference the legacy `r2`/`r3`/`r4a` prefixes explicitly.

**Acceptance Test:**

```bash
# All three old names must be gone
ls tasks/dev-platform-r2-* tasks/dev-platform-r3-* tasks/dev-platform-r4a-* 2>&1 | grep "No such"
# All three new names must exist
ls tasks/dev-platform-monitoring-spec.md tasks/dev-platform-testing-spec.md tasks/dev-platform-scaffolding-spec.md
# No old filename references remain in ROADMAP.md or planning.md
grep -rn "r2-monitoring\|r3-testing\|r4a-scaffolding" ROADMAP.md planning.md && echo FAIL || echo PASS
# Gate still passes
./scripts/gate_fast.sh 2>&1 | tail -2
```

---

## Phase 2: Cross-project Migration Tools

### Change 2: CLAUDE.md Scope carve-out for v0.9 migration

**Problem:** `scripts/migrate-workflow-chain.sh` (Change 3) writes to a project's `CLAUDE.md`. Without a documented Scope carve-out, the Scope rule bars this — it prohibits writes to `projects/` from dev-platform sessions. The carve-out must be as narrow as v0.8 Phase 3's (one script, one file type, opt-in `--apply`, no other writes).

**File:** `CLAUDE.md` (existing — append after the v0.8 fleet orchestration carve-out paragraph, line ~27)

**Implementation:**

Add a new "Exception — v0.9 migration tooling" paragraph immediately after the v0.8 carve-out paragraph. Mirror the v0.8 carve-out structure exactly: name the script, the file, and the exact mutation scope.

```markdown
**Exception — v0.9 migration tooling:** `scripts/migrate-workflow-chain.sh` IS allowed to edit the **workflow chain line(s)** inside a project's `CLAUDE.md`. Specifically: any line matching the old chain pattern (`/plan → /code → /test`) is rewritten to the canonical chain (`/plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge`). ALL other content in the project's `CLAUDE.md` is left untouched. The mutation is opt-in (`--apply` flag required), shows a diff in dry-run mode, and is idempotent (running twice produces no second change). Future chain updates require updating this carve-out paragraph with the new canonical chain string — not a general "migration scripts may edit CLAUDE.md" loophole.
```

**Acceptance Test:**

```bash
grep -n "v0.9 migration" CLAUDE.md && echo PASS || echo FAIL
```

---

### Change 3: `scripts/migrate-workflow-chain.sh`

**Problem:** `kermit/CLAUDE.md:171`, `kermit-pa/CLAUDE.md:231`, and `atlas/CLAUDE.md:62` each contain variants of the old workflow chain (`/plan → /code → /test → /review → /gate fast → commit → push` and similar). These mislead developers who read the project rules — they describe a workflow that no longer exists. The migration script finds these lines, shows what would change, and rewrites them with `--apply`.

**File:** `scripts/migrate-workflow-chain.sh` (new, ~100 lines)

**Implementation:**

Mirror `scripts/fleet-install-template.sh` structure (lines 1–50 for header + arg parsing; lines 51–100 for logic):

```bash
#!/usr/bin/env bash
# scripts/migrate-workflow-chain.sh — update old workflow chain references
# in a project's CLAUDE.md to the current canonical chain.
#
# Per the Scope-rule carve-out in /home/rich/dev/CLAUDE.md (Exception —
# v0.9 migration tooling). Touches ONLY workflow-chain lines in CLAUDE.md.
#
# Usage:
#   ./scripts/migrate-workflow-chain.sh --project <name>           # dry-run
#   ./scripts/migrate-workflow-chain.sh --project <name> --apply   # rewrite
#   ./scripts/migrate-workflow-chain.sh --registry <path>          # tests
#   ./scripts/migrate-workflow-chain.sh --help
```

**Arguments:** `--project <name>`, `--registry <path>` (default: `monitoring/projects.json`), `--apply`, `--help`.

**Detection pattern:** any line containing the substring `/code → /test` OR `/test → /review` (these fragments only appear in old-chain references, not in any other dev workflow context). Use grep to find matching lines first; if none match, exit 0 with "already up-to-date".

**New canonical chain string** (verbatim replacement target):

```
/plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge
```

**Replacement logic:** For each matching line, replace only the chain substring — not the whole line. This preserves surrounding context (e.g., bullet prefixes like `- **Dev workflow** —`). Use `sed` with the detection pattern as the address:

```bash
sed -i \
  -e 's|/plan → /code → /test → /review → /gate fast → /docs → commit → push → /pr → CI → /merge → post-merge|'"${NEW_CHAIN}"'|g' \
  -e 's|/plan → /code → /test → /review → /gate fast → /docs → commit → push|'"${NEW_CHAIN}"'|g' \
  -e 's|/plan → /code → /test → /review → /gate fast → commit → push|'"${NEW_CHAIN}"'|g' \
  -e 's|/plan → /code → /test → /review → /gate → /docs → commit → push|'"${NEW_CHAIN}"'|g' \
  -e 's|/plan → /code → /test → /review → commit|'"${NEW_CHAIN}"'|g' \
  -e 's|/plan → /code → /test → /gate → /docs → release|'"${NEW_CHAIN}"'|g' \
  "${claude_md}"
```

**Dry-run output:** show a unified diff of what would change using `diff -u`. If no changes, say "already up-to-date". Never write without `--apply`.

**Path resolution:** Look up the project path from the registry (same `jq` pattern as `fleet-install-template.sh:81-90`). Accept both absolute paths and REPO-relative paths. The `CLAUDE.md` target is always `<project_path>/CLAUDE.md`.

**Guard:** If `<project_path>/CLAUDE.md` does not exist, exit 1 with an actionable error.

**Idempotency:** After applying, grep for the old patterns again — if any still match, exit 1 with "sed rewrite incomplete". This catches edge cases where a new chain variant appears that the sed rules don't cover.

**Acceptance Test:**

```bash
# Dry-run against kermit — must show a diff without changing the file
./scripts/migrate-workflow-chain.sh --project kermit 2>&1 | grep -q "^-.*\/test" && echo "PASS: dry-run shows old chain" || echo FAIL
hash_before=$(sha256sum /home/rich/dev/projects/kermit/CLAUDE.md | awk '{print $1}')
./scripts/migrate-workflow-chain.sh --project kermit
hash_after=$(sha256sum /home/rich/dev/projects/kermit/CLAUDE.md | awk '{print $1}')
[[ "$hash_before" == "$hash_after" ]] && echo "PASS: dry-run did not write" || echo "FAIL: file was modified"

# Apply against kermit — must rewrite and verify idempotency
./scripts/migrate-workflow-chain.sh --project kermit --apply
grep -q "/test → /review" /home/rich/dev/projects/kermit/CLAUDE.md && echo "FAIL: old chain remains" || echo "PASS: old chain removed"
grep -q "gate fast → commit → push → /pr" /home/rich/dev/projects/kermit/CLAUDE.md && echo "PASS: new chain present" || echo FAIL

# Second apply must be no-op
./scripts/migrate-workflow-chain.sh --project kermit --apply 2>&1 | grep -q "already up-to-date" && echo "PASS: idempotent" || echo FAIL
```

---

### Change 4: `scripts/audit-project-drift.sh` + `tests/migration/run.sh`

**Problem:** After migrating the known projects, future chain updates will introduce new drift. The audit script gives a single-command view of every enabled project's compliance with the canonical chain and taxonomy — read-only, no mutations.

**Files:**

- `scripts/audit-project-drift.sh` (new, ~80 lines)
- `tests/migration/run.sh` (new, ~120 lines)

**Implementation — `audit-project-drift.sh`:**

Mirror `scripts/fleet-gate.sh` structure (lines 1–60 for setup + registry load; lines 61–120 for sweep loop; lines 121–180 for summary).

```bash
#!/usr/bin/env bash
# scripts/audit-project-drift.sh — read-only cross-project drift report.
# Checks each enabled project for:
#   (1) old workflow chain in CLAUDE.md
#   (2) taxonomy violations in ROADMAP.md / planning.md (via check_spec_taxonomy.sh)
#   (3) missing CLAUDE.md
```

**Arguments:** `--registry <path>` (default: `monitoring/projects.json`), `--project <name>` (filter), `--json`.

**Per-project checks (three):**

1. **chain_drift** — `grep -l "/code → /test\|/test → /review" <path>/CLAUDE.md 2>/dev/null` → `DRIFT` / `CLEAN` / `NO_CLAUDE_MD`
2. **taxonomy_drift** — `bash /home/rich/dev/scripts/check_spec_taxonomy.sh` run from the project root → exit code 0 = `CLEAN`, non-zero = `DRIFT` (capture stderr for the violation lines)
3. **has_claude_md** — `test -f <path>/CLAUDE.md` → `YES` / `NO`

**Output (markdown, default):**

```markdown
# Project Drift Audit — 2026-05-11

| Project | CLAUDE.md | Chain | Taxonomy |
| ------- | --------- | ----- | -------- |
| dev-platform | YES | CLEAN | CLEAN |
| kermit | YES | CLEAN | DRIFT |
| kermit-pa | YES | CLEAN | CLEAN |
| atlas | YES | CLEAN | CLEAN |
| keystone | YES | DRIFT | DRIFT |

Drift found in 2 projects. Run `./scripts/migrate-workflow-chain.sh --project <name> --apply` to fix chain drift.
```

**Implementation — `tests/migration/run.sh`:**

Auto-discovered by `gate_fast.sh`. Fixture suite using `mktemp` + inline mock registry. Same structure as `tests/fleet-install/run.sh`.

**Mock projects:**

- `clean-1`: CLAUDE.md with new canonical chain, no taxonomy violations
- `old-chain-1`: CLAUDE.md with old chain (`/plan → /code → /test → /review → /gate fast → commit → push`)
- `old-chain-2`: CLAUDE.md with variant (`/plan → /code → /test → /review → commit`)
- `no-claude-1`: directory with no CLAUDE.md
- `taxonomy-drift-1`: CLAUDE.md clean, but ROADMAP.md with `Sprint 1:` header

**Checks (target: 12):**

1. `bash -n scripts/migrate-workflow-chain.sh` — syntax clean
2. `bash -n scripts/audit-project-drift.sh` — syntax clean
3. `migrate-workflow-chain.sh --help` renders
4. `audit-project-drift.sh --help` renders
5. dry-run on `old-chain-1` shows diff, does not write
6. `--apply` on `old-chain-1` rewrites to new chain
7. second `--apply` is idempotent (`already up-to-date`)
8. `--apply` on `old-chain-2` rewrites the variant
9. `audit-project-drift.sh` shows `old-chain-1` as `CHAIN=DRIFT` after no apply
10. `audit-project-drift.sh` shows `no-claude-1` as `NO_CLAUDE_MD`
11. `audit-project-drift.sh` shows `taxonomy-drift-1` as `TAXONOMY=DRIFT`
12. path-guard: snapshot mock tree before and after all invocations; no new files under the mock root from `audit-project-drift.sh` (read-only contract)

**Acceptance Test:**

```bash
cd /home/rich/dev && ./scripts/gate_fast.sh 2>&1 | grep "migration:" | head -5
# Expect 12 PASS lines
```

---

## What NOT to Do

- **Do not attempt to rename `R<N>` phases in kermit's or keystone's ROADMAP.md** — those are project-internal planning docs governed by each project's own session. The audit script surfaces the drift; the project team migrates when they're ready.
- **Do not add new sed patterns to the migration script speculatively** — only the 6 known old-chain variants (confirmed by grep above) are in scope. Unknown future variants get added when discovered.
- **Do not make the audit script exit non-zero on drift found** — it's a reporting tool, not a gate. Exit 0 always; the human decides what to act on.
- **Do not fold the migrate script into the audit script** — they have different contracts (read-only vs. mutating) and must stay separate.
- **Do not update per-project planning.md or ROADMAP.md** — those are project-internal state docs. The Scope carve-out covers only `CLAUDE.md` workflow chain lines.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `tasks/dev-platform-r2-monitoring-spec.md` | Rename → `tasks/dev-platform-monitoring-spec.md` | Remove legacy R-prefix |
| `tasks/dev-platform-r3-testing-spec.md` | Rename → `tasks/dev-platform-testing-spec.md` | Remove legacy R-prefix |
| `tasks/dev-platform-r4a-scaffolding-spec.md` | Rename → `tasks/dev-platform-scaffolding-spec.md` | Remove legacy R-prefix |
| `ROADMAP.md` | Modify | Update 3 backtick filename references (lines 9–11) |
| `planning.md` | Modify | Update legacy prefix references (lines 47–48) |
| `CLAUDE.md` | Modify | Add v0.9 Scope carve-out paragraph after v0.8 carve-out |
| `scripts/migrate-workflow-chain.sh` | New | Opt-in workflow chain rewriter for project CLAUDE.md files |
| `scripts/audit-project-drift.sh` | New | Read-only cross-project drift report |
| `tests/migration/run.sh` | New | 12-assertion fixture suite |

## Implementation Order

1. Change 1 — rename spec files + update ROADMAP.md + planning.md (no dependencies)
2. Change 2 — add CLAUDE.md Scope carve-out (depends on Change 1 landing cleanly so gate still passes)
3. Change 3 — `migrate-workflow-chain.sh` (depends on Change 2 carve-out existing)
4. Change 4 — `audit-project-drift.sh` + `tests/migration/run.sh` (depends on Change 3 existing so tests can invoke it)

Ship as two PRs: Phase 1 (Changes 1) and Phase 2 (Changes 2–4).

## Post-merge Runbook

After Phase 2 merges:

1. Run the audit to confirm current state:
   ```bash
   ./scripts/audit-project-drift.sh
   ```
2. Apply chain migration to each drifting project (kermit, kermit-pa, atlas confirmed; keystone TBD):
   ```bash
   ./scripts/migrate-workflow-chain.sh --project kermit --apply
   ./scripts/migrate-workflow-chain.sh --project kermit-pa --apply
   ./scripts/migrate-workflow-chain.sh --project atlas --apply
   ```
3. Each project's `CLAUDE.md` edit must be committed from a session opened in THAT project's directory — dev-platform writes the file but does not commit it (same pattern as `fleet-install-template.sh`).
4. Close the v0.9 GitHub Milestone and cut the `v0.9` release tag.
5. Open `v1.0` Milestone.

## Verification Checklist

- [ ] `tasks/dev-platform-r2-monitoring-spec.md`, `r3-testing`, `r4a-scaffolding` all gone; renamed files exist
- [ ] No references to old filenames remain in ROADMAP.md or planning.md
- [ ] `./scripts/gate_fast.sh` passes at 131+ PASS after Phase 1 rename
- [ ] CLAUDE.md contains v0.9 Scope carve-out paragraph
- [ ] `scripts/migrate-workflow-chain.sh --help` renders
- [ ] Dry-run on kermit shows diff without writing
- [ ] `--apply` on kermit removes `/test → /review` from CLAUDE.md:171
- [ ] Second `--apply` is idempotent
- [ ] `scripts/audit-project-drift.sh` produces markdown table with correct DRIFT/CLEAN per project
- [ ] `tests/migration/run.sh` — 12 PASS, 0 FAIL (auto-discovered by gate_fast.sh)
- [ ] `./scripts/gate_fast.sh` passes after Phase 2 (count increases by 12)
- [ ] Language architecture matrix followed — all new components in Bash
