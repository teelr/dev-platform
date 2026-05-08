---
description: Run the commit gate for the current project. Three levels — fast (commit gate), full (nightly gate), release (pre-release gate).
argument-hint: "fast | full | release"
allowed-tools: Bash, Read, TodoWrite
---

# Gate Runner

Run the test gate at the requested level. Detects which project you're in and dispatches to the right scripts.

**Argument:** `$ARGUMENTS` — must be `fast`, `full`, or `release`. Defaults to `fast`.

## Project Detection

Check `$PWD` to determine which project is active:

- Path contains `kermit-pa` → **PA project**
- Path contains `kermit` but NOT `kermit-pa` → **Harness project**

---

## Kermit PA Gate

Work directory: `/home/rich/dev/projects/kermit-pa`

### PA fast (~3 min, no infra required)

Run before every commit.

```bash
cd /home/rich/dev/projects/kermit-pa && ./scripts/gate.sh fast
```

Steps (run by gate.sh) — counts grow with the suite; see live output
for current totals:

1. `scripts/constitutional_check.py` — PA constitutional checks (no localhost, no print(), harness pin, harness import, CLAUDE.md rule)
2. `pytest -m fast` — offline unit tests (no running services)

### PA full (~35 min, requires PostgreSQL + backend + agents + Claude API)

Run after full-stack changes.

```bash
cd /home/rich/dev/projects/kermit-pa && ./scripts/gate.sh full
```

All fast steps, plus:

1. `python tests/test_smoke_dev.py` — smoke suite (real LLM responses)
2. `pytest -m full` — infra integration tests

### PA release (~3+ hours, full stack under sustained load)

Run before tagging a release.

```bash
cd /home/rich/dev/projects/kermit-pa && ./scripts/gate.sh release
```

All full steps, plus:

1. `pytest -m scale` — L1 (5 concurrent WS), L3 (level3 governance), L4 (20-burst spike)

---

## Kermit Harness Gate

Work directory: `/home/rich/dev/projects/kermit`

### fast (~3 min, no infra required)

Counts grow with the suite — see actual `make check` / `make test-quiet`
/ `make smoke-fast` output for current totals.

1. `make check` — constitutional checks (AST + pytest tiers)
2. `make test-quiet` — full unit/integration suite
3. `make smoke-fast` — in-process production-gate smoke tier

### full (~12-15 min cold, ~6-8 min warm; requires test infra + Ollama + service binaries)

All fast steps, plus:
4. `make test-infra-up` — start Docker DATA containers (PG/Mongo/Milvus/Redis/NATS)
5. `make services-up` — start Go wiki-service (8022) + Rust wiki-processor (8023) binaries (R13-0; first run ~3-5 min cold for Rust release build)
6. `make smoke-full` — full smoke tier (real backends + Ollama + service binaries)
7. `make load-l1-smoke` — 50 agents single process (~3 min) — load-tier per L15 promotion in `/home/rich/dev/CLAUDE.md` "Workflow Discipline / Pre-commit Gate Coverage"
8. `make load-l3-smoke` — 100 tenants × 3 req each, isolation check (~5 min)
9. `make load-l4-smoke` — 100 tenants horizontal-scale smoke (~5 min)

If `smoke-full` skips more than 1 test (the vision-pass test that needs `WIKI_VISION_MODEL_URL`), report which services are missing.

The load-tier smokes (steps 7-9) are MANDATORY at /gate full per the L15 3rd-recurrence rule promoted to global CLAUDE.md after v2.19.2. They catch the bug class where shared-client adapter glue or async/threading state breaks at concurrent-tenant scale (CT68/CT69/CT70 lineage). Smoke tier (50/100/100 tenants) is the right balance: catches the bug class, doesn't burn the GPU for an hour like /gate release.

### release (~3+ hours, requires test infra + Ollama + service binaries)

All full steps, plus:
10. `make api-contract-check` — public API + docstrings + contract tests
    (~5 min, narrow gate; superset enforcement so no release ships with
    an API contract regression)
11. `make smoke-scale`
12. `RUN_LOAD_TESTS=1 make load-l1-full` — 1,000 agents, single process (~3 min)
13. `RUN_LOAD_TESTS=1 make load-l3-full` — 1,000 tenants × 10 reqs, isolation (~30 min)
14. `RUN_LOAD_TESTS=1 make load-l4-full` — 2,500 tenants × 10 reqs, horizontal scale (~50 min)

`/gate release` is also scheduled to run weekly via the `schedule` skill (background agent — see Option D in the v2.20.0 R13-0 follow-up). Manual invocation is for ad-hoc release qualification before any `__api_version__` minor or major bump.

---

## Execution Rules

Run each step sequentially. After each step:
- **PASS**: note the result and continue
- **FAIL**: stop immediately, report what failed with full error output, do not proceed

Do NOT fix failures automatically. Report them and wait for user instruction.

## Report Format

```
Project: kermit-pa | kermit-harness
Gate: fast | full | release
Result: PASS | FAIL

Step results:
Counts in this sample are illustrative — fill from live output, do
NOT hardcode them in this template (they drift every release).

  [kermit-pa]
  constitutional check    PASS
  offline unit tests      PASS  (N passed)
  [smoke suite            PASS  (N/N)]        ← full/release only
  [infra tests            PASS  (N passed)]   ← full/release only
  [scale tests            PASS  (N/N)]        ← release only

  [kermit-harness]
  constitutional checks   PASS  (N/N)
  unit/integration tests  PASS  (N passed, N skipped)
  smoke_fast              PASS  (N/N)
  [smoke_full             PASS  (N/N)]        ← full/release only
  [api_contract           PASS]               ← release only
  [smoke_scale            PASS  (N/N)]        ← release only
  [load L1                PASS]               ← release only
  [load L3                PASS]               ← release only
  [load L4                PASS]               ← release only

Skipped tests: <list any skipped with reason>
Total time: Xs
```

If any step FAIL, replace its line with `FAIL` and include the failure summary below the table.
