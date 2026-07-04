# v1.9: Template Chain Seeding

## Coding Specification for Implementation

## Design Philosophy

v1.8 taught the drift audit to flag a project `CLAUDE.md` that documents no workflow chain (`MISSING_CHAIN`). This surfaced a gap one layer up: the templates a new project is *born from* carry no chain either. `scripts/new-project.sh` scaffolds from `scaffolding/<template>/`, and all three template `CLAUDE.md` files (`go-service`, `python-agent`, `next-frontend`) — plus the reference `docs/PROJECT_CLAUDE_TEMPLATE.md` — end with `## Rules` → `## Patterns` → `## Spec Files` and never state the dev chain. So a freshly scaffolded project would read `MISSING_CHAIN` on its very first audit. This spec seeds the canonical chain into those four files so a new project is born audit-CLEAN.

There is a real tension to resolve, not paper over: every template header says *"Do NOT duplicate rules from /home/rich/dev/CLAUDE.md — those apply automatically."* Seeding the chain looks like duplication. It is not. The chain **line** is a project-level workflow *declaration* — the one process statement every real project carries in its own `CLAUDE.md` (verified: kermit, kermit-pa, keystone, OPIE all do, and the v1.8 audit treats its absence as drift). The "don't duplicate" guidance targets restating rule *bodies* (the paragraphs of standards), not this one-line affirmation of which chain the project follows. Real projects format it as a short `## Development Workflow` section (see `projects/OPIE/CLAUDE.md`); the templates should match, so a scaffolded project looks like a real one.

The regression guard is end-to-end and deliberately strong: `tests/scaffold/run.sh` already scaffolds each template into `projects/r3-smoke-<template>`; this spec adds an assertion that runs the actual v1.8 audit (`scripts/audit-project-drift.sh`) against each freshly scaffolded project and requires `CLEAN`. That closes the loop the same way v1.8's `no-chain-1` fixture did — proving the real audit verdict, not just that a substring is present.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| Template `CLAUDE.md` edits | Markdown | Static scaffolding content; no logic. Matches the existing templates. |
| `tests/scaffold/run.sh` addition | Bash | The suite that owns `new-project.sh` coverage is Bash on the repo's `assert.sh` harness; the new guard shells out to `audit-project-drift.sh` (also Bash). |

## Overview

Phase 1 — Template Chain Seeding:

- **Change 1:** Seed a `## Development Workflow` section (canonical chain + gate note) into the three scaffolding `CLAUDE.md` templates and `docs/PROJECT_CLAUDE_TEMPLATE.md`.
- **Change 2:** Add an end-to-end regression guard to `tests/scaffold/run.sh` — the v1.8 audit reports each freshly scaffolded project `CLEAN`.
- **Change 3:** Docs — ROADMAP v1.9 entry, `planning.md`, one `lessons.md` entry.

All three land as one atomic commit: the gate runs `tests/scaffold/run.sh`, which must pass with the seeded templates.

---

## Phase 1: Template Chain Seeding

### Change 1: Seed the canonical chain into the four templates

**Problem:** The scaffolding templates and the reference template document no workflow chain, so a scaffolded project reads `MISSING_CHAIN` under the v1.8 audit.

**Files:**
- `scaffolding/go-service/CLAUDE.md` (before the `## Spec Files` header, ~line 91)
- `scaffolding/python-agent/CLAUDE.md` (before `## Spec Files`, ~line 83)
- `scaffolding/next-frontend/CLAUDE.md` (before `## Spec Files`, ~line 94)
- `docs/PROJECT_CLAUDE_TEMPLATE.md` (before `## Spec Files`, ~line 86)

**Implementation:**

In each of the three **scaffolding** templates, insert this section immediately before the `## Spec Files` header (a blank line above and below, matching `projects/OPIE/CLAUDE.md`'s format):

```markdown
## Development Workflow

`/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`

Run `./scripts/gate_fast.sh` before every commit.
```

- The gate note is accurate for all three templates — each ships `scripts/gate_fast.sh` (see the File Structure block in each template).
- Keep the scaffolding templates' section clean (no explanatory comment) so a scaffolded project's `CLAUDE.md` reads exactly like a real project's.

In `docs/PROJECT_CLAUDE_TEMPLATE.md` (the human-facing reference, not shipped into projects), insert the same section but prefix it with a one-line HTML comment so a maintainer doesn't mistake the chain for a "don't duplicate" violation:

```markdown
<!-- The chain line is a required project-level workflow declaration that
     audit-project-drift.sh checks for — not a duplicated rule body. Keep it. -->
## Development Workflow

`/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`

Run `./scripts/gate_fast.sh` before every commit.
```

**Acceptance Test:**

```bash
# All four templates now contain the canonical /review anchor.
for f in scaffolding/go-service/CLAUDE.md scaffolding/python-agent/CLAUDE.md \
         scaffolding/next-frontend/CLAUDE.md docs/PROJECT_CLAUDE_TEMPLATE.md; do
  grep -q "/code → /review" "$f" && echo "OK  $f" || echo "MISSING  $f"
done
# The three scaffolding templates carry NO stray review-less chain.
! grep -rqE "/code → /gate fast" scaffolding/*/CLAUDE.md && echo "no review-less drift in templates"
```

---

### Change 2: End-to-end scaffold → audit-CLEAN regression guard

**Problem:** Nothing proves a scaffolded project is audit-CLEAN. Without a guard, a future template edit could drop the chain and silently reintroduce the `MISSING_CHAIN` gap.

**File:** `tests/scaffold/run.sh` (existing file — the per-template happy-path loop at lines 27–65)

**Implementation:**

Inside the per-template `for` loop, after the `{{PROJECT_NAME}}` substitution assertion (~line 46) and **before** the `rm -rf "${project_dir}"` teardown (~line 64), add an audit-CLEAN assertion. It writes a one-entry mock registry pointing at the freshly scaffolded project (absolute path) and runs the real v1.8 audit:

```bash
    # v1.8 audit reports the freshly scaffolded project CLEAN (chain seeded,
    # no spec files → taxonomy clean). Guards against a template edit dropping
    # the chain and reintroducing MISSING_CHAIN.
    audit_reg="$(mktemp)"
    cat > "${audit_reg}" <<REOF
[{"name": "${project}", "path": "${project_dir}", "gate_cmd": "true", "primary_language": "bash", "enabled": true}]
REOF
    audit_out="$(bash "${REPO}/scripts/audit-project-drift.sh" --project "${project}" --registry "${audit_reg}" 2>&1)"
    if echo "${audit_out}" | grep -q "CLEAN" && ! echo "${audit_out}" | grep -q "MISSING_CHAIN"; then
        record_pass "scaffold ${template}: audit-project-drift reports CLEAN (chain seeded)"
    else
        record_fail "scaffold ${template}: audit not CLEAN — ${audit_out}"
    fi
    rm -f "${audit_reg}"
```

- `${project_dir}` is absolute (`${REPO}/projects/r3-smoke-<template>`), which `audit_project()` uses as-is (its `path == /*` branch), so no path-resolution surprise.
- The scaffolded `tasks/` has no `*-spec.md`, so `check_spec_taxonomy.sh` reports taxonomy CLEAN — the only variable under test is the chain.
- `audit-project-drift.sh` needs `jq`; the gate environment already provides it (every fleet suite depends on it).

**Acceptance Test:**

```bash
bash tests/scaffold/run.sh   # all assertions PASS, including the 3 new audit-CLEAN ones
./scripts/gate_fast.sh       # full gate green; scaffold suite auto-discovered
```

---

### Change 3: Doc updates

**Problem:** The new Roadmap Phase must be recorded.

**Files:** `ROADMAP.md`, `planning.md`, `tasks/lessons.md` (all existing)

**Implementation:**

1. **`ROADMAP.md`** — add a v1.9 entry after the v1.8 entry, matching the bullet style:

   > **v1.9: Template Chain Seeding** *(complete — YYYY-MM-DD, `tasks/template-chain-seeding-spec.md`)* — the companion to v1.8: seeds the canonical dev workflow chain into the project `CLAUDE.md` templates so a freshly scaffolded project is born audit-CLEAN instead of reading `MISSING_CHAIN`. Adds a `## Development Workflow` section (chain + gate note) to the three `scaffolding/*/CLAUDE.md` templates and `docs/PROJECT_CLAUDE_TEMPLATE.md`; `tests/scaffold/run.sh` gains an end-to-end guard that runs the v1.8 audit against each freshly scaffolded project and requires `CLEAN`. The chain line is a required project-level workflow declaration (what real projects carry), not a "don't duplicate" violation.

2. **`planning.md`** — mark v1.9 per the `/docs` convention (Current state + in-flight → nothing-in-flight after merge).

3. **`tasks/lessons.md`** — add one entry (table row, matching the file's format): fixing a detector (v1.8) without seeding the thing it checks at creation time (templates) leaves a birth-defect gap — the audit would flag every newly scaffolded project until the templates carry the chain. Pattern: when a check enforces the presence of X, seed X into whatever bootstraps new instances, or every new instance starts in violation.

**Acceptance Test:**

```bash
grep -q "v1.9: Template Chain Seeding" ROADMAP.md
./scripts/check_spec_taxonomy.sh   # ROADMAP/planning taxonomy scan stays green
```

---

## What NOT to Do

- **Do NOT strip the `## Development Workflow` section as a "don't duplicate rules" cleanup.** The chain line is a required project-level workflow declaration that `audit-project-drift.sh` checks for — that's why real projects carry it. The HTML comment in `docs/PROJECT_CLAUDE_TEMPLATE.md` records this; the scaffolding templates stay clean to mirror real projects.
- **Do NOT seed the review-less chain.** Seed `/plan → /code → /review → /gate fast → …` (with `/review`). A template carrying `/code → /gate fast` would scaffold projects that immediately read `DRIFT` — the exact bug the fleet just spent this session migrating away from.
- **Do NOT weaken the audit to stop flagging `MISSING_CHAIN` instead of seeding the templates.** That would undo v1.8's purpose (catching projects that drop the workflow section). Seed at the source.
- **Do NOT add the chain anywhere that `audit-project-drift.sh` greps dev-platform's own `CLAUDE.md`.** This spec only edits `scaffolding/*` and `docs/*` templates (never grepped for chain drift) — leave dev-platform's `CLAUDE.md` untouched so it stays `CLEAN` in its own audit.
- **Do NOT hardcode the scaffolded project path as relative in the mock registry.** Use the absolute `${project_dir}`; the audit's path resolver only treats a leading `/` as absolute.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scaffolding/go-service/CLAUDE.md` | Modify | Add `## Development Workflow` (chain + gate note) before `## Spec Files`. |
| `scaffolding/python-agent/CLAUDE.md` | Modify | Same section. |
| `scaffolding/next-frontend/CLAUDE.md` | Modify | Same section. |
| `docs/PROJECT_CLAUDE_TEMPLATE.md` | Modify | Same section + one-line HTML rationale comment. |
| `tests/scaffold/run.sh` | Modify | Per-template audit-CLEAN assertion (3 new) via a mock registry. |
| `ROADMAP.md` | Modify | v1.9 Roadmap Phase entry. |
| `planning.md` | Modify | Mark v1.9 shipped. |
| `tasks/lessons.md` | Modify | One entry on seeding-at-source. |

## Implementation Order

1. **Change 1** — seed the four templates (no dependency).
2. **Change 2** — scaffold-test guard (depends on Change 1; the audit must find the seeded chain to report CLEAN).
3. **Change 3** — docs (`/code`'s final doc step).

All three commit together as one `feat:` commit — the gate runs the scaffold suite, so the templates and their guard are inseparable.

## Verification Checklist

- [ ] All four templates contain the canonical `/code → /review` chain anchor.
- [ ] No scaffolding template contains a review-less `/code → /gate fast` chain.
- [ ] `bash tests/scaffold/run.sh` — all assertions pass, including the 3 new audit-CLEAN guards.
- [ ] A manual scaffold (`./scripts/new-project.sh go-service tmp-check`) produces a `CLAUDE.md` whose audit reads `CLEAN`; then remove `projects/tmp-check`.
- [ ] `./scripts/gate_fast.sh` — full gate green.
- [ ] `./scripts/check_spec_taxonomy.sh` — ROADMAP/planning taxonomy scan green.
- [ ] dev-platform's own `CLAUDE.md` untouched (still `CLEAN` in its own audit); no file under `projects/` committed.
