---
description: Run the smoke test suite for the current project interactively. Single-tier runner — fast, full, or scale.
argument-hint: "fast | full | scale"
allowed-tools: Bash, Read
---

# Smoke Test Runner

Run a single smoke tier interactively with verbose output. Detects which project you're in and dispatches to the right scripts.

**Argument:** `$ARGUMENTS` — must be `fast`, `full`, or `scale`. Defaults to `fast`.

## Project Detection

Check `$PWD` to determine which project is active:

- Path contains `kermit-pa` → **PA project**
- Path contains `kermit` but NOT `kermit-pa` → **Harness project**

---

## Kermit PA Smoke Tests

Work directory: `/home/rich/dev/projects/kermit-pa`

### fast (~3 min, no infra required)

```bash
cd /home/rich/dev/projects/kermit-pa && ./scripts/smoke_test.sh fast
```

Runs `pytest -m fast -v` — 14 offline unit tests, no running services required.

### full (~35 min, requires PostgreSQL + backend + agents + Claude API)

```bash
cd /home/rich/dev/projects/kermit-pa && ./scripts/smoke_test.sh full
```

Runs `python tests/test_smoke_dev.py` — 20-test suite with real LLM responses.

### scale (requires full stack under load)

```bash
cd /home/rich/dev/projects/kermit-pa && ./scripts/smoke_test.sh scale
```

Runs `pytest -m scale -v` — L1 (5 concurrent WS), L3 (level3 governance), L4 (20-burst spike).
Skips gracefully if level3 project not present in DB.

---

## Kermit Harness Smoke Tests

Work directory: `/home/rich/dev/projects/kermit`

### fast (~2s, no live services)

```bash
cd /home/rich/dev/projects/kermit && make smoke-fast
```

### full (~30 min, Docker backends + Ollama)

```bash
cd /home/rich/dev/projects/kermit && make test-infra-up && make smoke-full
```

### scale (~2 hours, L3/L4 load profiles)

```bash
cd /home/rich/dev/projects/kermit && make test-infra-up && make smoke-scale
```

---

## Execution Rules

Review results and report any failures. If there are failures:

1. Diagnose the root cause
2. Propose fixes
3. Only fix if the user approves

Do NOT fix issues automatically — report them first.
