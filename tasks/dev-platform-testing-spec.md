# R3 Testing — Consolidated Gate-Fast Coverage

## Coding Specification for Implementation

## Design Philosophy

R3 makes the dev-platform "gate fast" runnable. Every prior spec (R1, R1.5, R4a) has shipped via a /gate fast invocation where the assistant cobbled together ~10 Bash one-liners in conversation — spec taxonomy, syntax checks, JSON validity, install round-trip, live verify, hook smoke, scaffold smoke, edge cases. Each cycle, the assistant infers what to test from the spec being shipped. There is no `scripts/gate_fast.sh`. No future-Rich (or future-assistant) running /gate fast a month from now has a mechanical way to know nothing broke unless they remember the same 10 checks.

R3 consolidates those checks into a real script, plus adds three categories of fixture-based regression coverage: hook payload tests, slash command frontmatter validation, and a self-test for `check_spec_taxonomy.sh` itself. The result is a runnable `./scripts/gate_fast.sh` that exits non-zero on any failure, takes ~15 seconds, and replaces conversation-derived coverage with mechanical enforcement. Future specs (R4b, R5, additional templates) can rely on it instead of re-deriving the test set every cycle.

R3 explicitly does NOT ship slow tests — no per-template full builds (npm install / pip install / go test), no performance benchmarks, no pre-commit git hook. Those are deferred to future specs when there's evidence they'd catch something gate-fast doesn't. The asymmetric-gate principle from kermit-harness applies: keep fast surgical (~15s); load-tier and release-tier coverage when warranted by real bug evidence. R3 establishes the inner-loop gate; everything else builds on top.

R3 introduces a new top-level directory: `tests/`. This is the first new top-level directory since R1 Foundation. Per the existing Repo Structure section of `dev/CLAUDE.md`, `tests/` aligns with the Standard Project Structure (every project has a `tests/`); dev-platform just hasn't had its own until now. Per the Consistency rule, the addition propagates through standard channels: gitignore allow-list extension, Repo Structure table update, README mention.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/gate_fast.sh` | Bash | Orchestrator running shell commands sequentially; matches the existing `install.sh`/`verify.sh`/`uninstall.sh`/`new-project.sh` pattern. Zero new dependencies. |
| `tests/helpers/assert.sh` | Bash | Shared `record_pass`/`record_fail`/`pass_count`/`fail_count` helpers sourced by per-suite runners. Pure shell — no test framework. |
| `tests/hooks/*/run.sh` | Bash | Per-hook fixture runners. Feed JSON fixtures via stdin to the hook script, assert log lines match expected shape. |
| `tests/commands/frontmatter.sh` | Bash | Parses each `commands/*.md` front matter manually (sed/awk), validates required fields exist. Stays zero-dep. |
| `tests/taxonomy/run.sh` | Bash | Runs `check_spec_taxonomy.sh` against fixture specs (one conformant, one with a killed term) and asserts correct exit codes. |
| `tests/install/run.sh` | Bash | Install / verify / uninstall round-trip on a throwaway `$HOME`. Extracts the conversation-derived logic from prior /gate cycles. |
| `tests/scaffold/run.sh` | Bash | new-project.sh smoke test (3 templates + refuse-to-clobber + invalid-args). Extracts from prior /gate cycles. |
| JSON fixtures | JSON | Hook payload samples (`valid.json`, `invalid.json`, `empty.txt` for the no-stdin case). |
| Markdown fixtures | Markdown | Spec fixtures for taxonomy checker tests. |

## Overview

1. **Phase 1:** Foundation — `tests/` skeleton, helper script, gitignore allow-list extension (Changes 1–2)
2. **Phase 2:** Per-suite test runners + fixtures — hooks, commands, taxonomy, install, scaffold (Changes 3–7)
3. **Phase 3:** Orchestrator + wire-up — `scripts/gate_fast.sh`, `dev/CLAUDE.md` updates, end-to-end acceptance (Changes 8–10)

**Demo:** running `./scripts/gate_fast.sh` from `/home/rich/dev/` produces structured PASS/FAIL output across all consolidated checks, exits 0 (all PASS), and completes in under 20 seconds. Re-running after an intentional taxonomy violation (e.g., adding `### Stage 1` to a spec) produces a FAIL on the taxonomy step with exit code 1. The script catches regressions in hook payload handling, slash command structure, taxonomy enforcement, install pipeline, and scaffold path without any conversation-derived check setup.

---

## Phase 1: Foundation

### Change 1: `dev/tests/` skeleton + helper script

**Problem:** R3 introduces a new top-level directory `tests/` whose contract needs to be set before any individual test suite ships. Per the Repo Structure pattern, the directory needs a `README.md` documenting what belongs there, and a `helpers/assert.sh` providing shared PASS/FAIL counting that every per-suite runner sources.

**File:** `dev/tests/` (new directory tree)

**Implementation:**

Ship these files:

- `dev/tests/README.md` — directory contract. ~25 lines. Covers: what goes here (per-suite runners under `tests/<suite>/run.sh`, fixtures under `tests/<suite>/<fixture-name>`, shared helpers in `tests/helpers/`), what does NOT go here (project tests — those live in each project's own `tests/`; build/integration tests requiring network or slow ops — deferred to future gate_full.sh), and how the suite is invoked (the orchestrator `scripts/gate_fast.sh` sources each suite's `run.sh` and runs it).
- `dev/tests/helpers/assert.sh` — shared helpers. Defines `record_pass <message>`, `record_fail <message>`, `record_skip <message>`, and increments globals `PASS_COUNT`, `FAIL_COUNT`, `SKIP_COUNT`. Per-suite runners source this. Format example:
  ```bash
  # tests/helpers/assert.sh — sourced by per-suite runners.
  # Maintains running PASS/FAIL/SKIP counters; per-suite runners call
  # record_pass / record_fail / record_skip then leave aggregation
  # to the gate_fast.sh orchestrator.

  : "${PASS_COUNT:=0}"
  : "${FAIL_COUNT:=0}"
  : "${SKIP_COUNT:=0}"

  record_pass() {
      PASS_COUNT=$((PASS_COUNT + 1))
      echo "  PASS  $1"
  }
  record_fail() {
      FAIL_COUNT=$((FAIL_COUNT + 1))
      echo "  FAIL  $1" >&2
  }
  record_skip() {
      SKIP_COUNT=$((SKIP_COUNT + 1))
      echo "  SKIP  $1"
  }

  # Helper: assert command exits non-zero (for negative tests).
  assert_fails() {
      local description="$1"
      shift
      if "$@" >/dev/null 2>&1; then
          record_fail "${description} (expected non-zero exit, got 0)"
      else
          record_pass "${description}"
      fi
  }
  ```

**Acceptance Test:** `dev/tests/README.md` and `dev/tests/helpers/assert.sh` exist. `bash -n dev/tests/helpers/assert.sh` exits 0. Sourcing the helper from another bash script makes `record_pass` / `record_fail` / `record_skip` available without error.

### Change 2: `.gitignore` allow-list extension for `tests/`

**Problem:** The new `tests/` top-level directory needs to be re-included in the gitignore, similar to how `scaffolding/` was extended in R4a. Without this, the tests directory and its contents would be silently gitignored under the project's "ignore-everything default" strategy.

**File:** `dev/.gitignore` (existing — extend the re-include block)

**Implementation:**

Add a `!tests/` entry in the "Re-include top-level directories" block, and add `tests/**` to the "Inside re-included directories" block. Then add allow-list entries for the file types tests will use:

```text
# Re-include top-level directories
... existing entries ...
!tests/

# Inside re-included directories, allow only specific extensions
... existing entries ...
tests/**

# Tests allow-list — runners (sh), fixtures (json/md), spec docs (md)
!tests/*.md
!tests/**/*.md
!tests/**/*.sh
!tests/**/*.json
!tests/**/*.txt
```

Pattern matches the `scaffolding/` allow-list pattern. No subdirectory re-include is needed at this level because the `!tests/` and `!tests/**/*.<ext>` combination correctly traverses. (For confirmation: scaffolding/ needed `!scaffolding/**/` because the `scaffolding/**` ignore line matches subdirectories themselves; same will be true for tests/, so add `!tests/**/` to be safe.)

**Acceptance Test:** After the gitignore update, `git ls-files --others --exclude-standard tests/` lists every file under `tests/` that's not already tracked. `git check-ignore -v tests/helpers/assert.sh` confirms the last matching rule is a re-include (`!tests/...`).

---

## Phase 2: Per-Suite Test Runners + Fixtures

### Change 3: `tests/hooks/post-tool-heartbeat/` fixtures + runner

**Problem:** The R1.5 heartbeat hook (`hooks/post-tool-heartbeat.sh`) was smoke-tested manually during /test cycles but has no automated regression coverage. If a future edit changes the JSON-parsing logic, broken behavior wouldn't surface until a real Claude Code session fires the hook with a malformed payload. R3 ships fixture-based tests covering valid, invalid, and empty inputs.

**File:** `dev/tests/hooks/post-tool-heartbeat/` (new directory tree)

**Implementation:**

Fixtures:

- `dev/tests/hooks/post-tool-heartbeat/valid.json` — `{"tool_name":"Bash","tool_input":{"command":"ls"}}`
- `dev/tests/hooks/post-tool-heartbeat/invalid.json` — `not valid json at all`
- `dev/tests/hooks/post-tool-heartbeat/empty.txt` — zero-byte file (for the empty-stdin path; not JSON, hence `.txt`)
- `dev/tests/hooks/post-tool-heartbeat/missing-tool-name.json` — `{"tool_input":{"command":"ls"}}` (valid JSON, no `tool_name` key)

Runner: `dev/tests/hooks/post-tool-heartbeat/run.sh`. Sources `helpers/assert.sh`. For each fixture, pipes it into the hook script, captures the log line written to `~/.claude/dev-platform-telemetry.log`, asserts the line matches the expected pattern.

```bash
#!/usr/bin/env bash
# tests/hooks/post-tool-heartbeat/run.sh — fixture suite for post-tool-heartbeat.sh.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../../.." && pwd)"
# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

LOG="${HOME}/.claude/dev-platform-telemetry.log"
HOOK="${REPO}/hooks/post-tool-heartbeat.sh"

# Each fixture → expected log-line regex
declare -A CASES=(
    ["valid.json"]="tool=Bash$"
    ["invalid.json"]="tool=\?$"
    ["empty.txt"]="tool=\?$"
    ["missing-tool-name.json"]="tool=\?$"
)

for fixture in "${!CASES[@]}"; do
    expected="${CASES[$fixture]}"
    cat "${HERE}/${fixture}" | bash "${HOOK}" >/dev/null 2>&1
    last_line="$(tail -1 "${LOG}")"
    if [[ "${last_line}" =~ ${expected} ]]; then
        record_pass "heartbeat ${fixture} → ${expected}"
    else
        record_fail "heartbeat ${fixture} expected ${expected}, got: ${last_line}"
    fi
done
```

**Acceptance Test:** `bash tests/hooks/post-tool-heartbeat/run.sh` records 4 PASS, 0 FAIL when the hook script is correct. If the hook is mutated (e.g., remove the `try/except` so invalid JSON causes a script error), the corresponding fixtures FAIL.

### Change 4: `tests/commands/frontmatter.sh`

**Problem:** Each slash command lives as `commands/*.md` with YAML frontmatter declaring `description` and `allowed-tools`. There's no validation that the frontmatter parses cleanly or that required fields exist. If a future edit breaks the frontmatter (e.g., unclosed string, missing field), the command file would still appear to exist but `/foo` invocations might silently fail or behave incorrectly. R3 ships a frontmatter validator.

**File:** `dev/tests/commands/frontmatter.sh` (new, executable)

**Implementation:**

Per-command checker. For each `commands/*.md` (excluding `README.md`):

1. Confirm the file starts with `---` on line 1
2. Find the closing `---` (must exist on a subsequent line)
3. The block between is parsed as key-value pairs (one per line, `key: value` format)
4. Required keys present: `description`. Optional but-common keys: `allowed-tools`, `argument-hint`, `model`.
5. `description` non-empty and ≤ 200 chars
6. If `allowed-tools` is present, it's a comma-separated list of plausible tool names (no leading/trailing whitespace per entry)

Parse with awk/sed — no YAML library. Skip strict YAML validation (multi-line values, etc.) — keep it simple, catch the common breakage shapes.

```bash
#!/usr/bin/env bash
# tests/commands/frontmatter.sh — validates each commands/*.md has well-formed
# frontmatter with required fields.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

for cmd in "${REPO}/commands"/*.md; do
    name="$(basename "${cmd}")"
    [[ "${name}" == "README.md" ]] && continue

    # First line must be ---
    first_line="$(head -1 "${cmd}")"
    if [[ "${first_line}" != "---" ]]; then
        record_fail "${name}: first line is not '---' (got: '${first_line}')"
        continue
    fi

    # Closing --- present after line 1
    if ! awk 'NR>1 && $0=="---" {found=1; exit} END {exit !found}' "${cmd}"; then
        record_fail "${name}: missing closing '---' for frontmatter"
        continue
    fi

    # description non-empty
    desc="$(awk '/^description:/ {sub(/^description:[[:space:]]*/, ""); print; exit}' "${cmd}")"
    if [[ -z "${desc}" ]]; then
        record_fail "${name}: 'description' field missing or empty"
        continue
    fi
    if (( ${#desc} > 200 )); then
        record_fail "${name}: description too long (${#desc} > 200 chars)"
        continue
    fi

    record_pass "${name}: frontmatter valid (desc: ${desc:0:50}...)"
done
```

**Acceptance Test:** `bash tests/commands/frontmatter.sh` records 8 PASS (one per slash command: code, dev, docs, gate, plan, review, smoke_test, test), 0 FAIL. If a command file's frontmatter is corrupted (e.g., remove the closing `---`), that command's check FAILs.

### Change 5: `tests/taxonomy/` fixtures + self-test runner

**Problem:** `scripts/check_spec_taxonomy.sh` is the mechanical enforcement layer for the Phase + Change taxonomy. If it ever gets broken (regex edited incorrectly, exit code logic flipped), every project's gate-fast that depends on it would silently allow killed terms back into specs. R3 ships a self-test: small fixture specs (one conformant, one with a killed term) verify the checker exits 0/1 correctly.

**File:** `dev/tests/taxonomy/` (new directory tree)

**Implementation:**

Fixtures:

- `dev/tests/taxonomy/conformant-spec.md` — minimal valid spec using `## Phase 1: Foo` and `### Change 1: Bar` headers. ~10 lines.
- `dev/tests/taxonomy/bad-spec-sprint.md` — uses `## Phase 1: Foo` and `### Sprint 1: Bar` (a killed term). Should cause the checker to exit 1.
- `dev/tests/taxonomy/bad-spec-step.md` — uses `### Step 1: Bar` under a Phase. Should also exit 1.
- `dev/tests/taxonomy/legitimate-step.md` — uses `### Step N` under a non-Phase parent (e.g., `## gate fast` → `### Step 1`). This is the explicit carve-out documented in the existing checker. Should NOT cause exit 1.

Runner: `dev/tests/taxonomy/run.sh`. Runs `check_spec_taxonomy.sh` against each fixture (in isolation — passing the fixture's directory or specific path), captures exit code, asserts.

```bash
#!/usr/bin/env bash
# tests/taxonomy/run.sh — self-test for check_spec_taxonomy.sh.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

CHECKER="${REPO}/scripts/check_spec_taxonomy.sh"

# Each fixture → expected exit (0 = clean, 1 = violation found)
# Note: check_spec_taxonomy.sh scans tasks/*-spec.md by default. To test
# specific fixtures in isolation, run from inside a temp dir that has
# only the target fixture symlinked into tasks/.

run_fixture() {
    local fixture="$1"
    local expected_exit="$2"
    local description="$3"

    local tmp; tmp="$(mktemp -d)"
    mkdir -p "${tmp}/tasks"
    cp "${HERE}/${fixture}" "${tmp}/tasks/${fixture}"
    # Some fixtures need to end in -spec.md to match the checker's glob
    [[ "${fixture}" == *-spec.md ]] || cp "${HERE}/${fixture}" "${tmp}/tasks/$(basename "${fixture}" .md)-spec.md"

    (cd "${tmp}" && bash "${CHECKER}" >/dev/null 2>&1)
    local actual_exit=$?

    if [[ ${actual_exit} -eq ${expected_exit} ]]; then
        record_pass "taxonomy: ${description} (exit ${expected_exit})"
    else
        record_fail "taxonomy: ${description} (expected exit ${expected_exit}, got ${actual_exit})"
    fi
    rm -rf "${tmp}"
}

run_fixture "conformant-spec.md" 0 "conformant spec passes"
run_fixture "bad-spec-sprint.md" 1 "Sprint killed-term detected"
run_fixture "bad-spec-step.md" 1 "Step under Phase detected"
run_fixture "legitimate-step.md" 0 "Step under non-Phase legitimately allowed"
```

**Acceptance Test:** `bash tests/taxonomy/run.sh` records 4 PASS, 0 FAIL. The checker correctly distinguishes killed terms under `## Phase N:` headers (FAIL) from the same terms under non-Phase parents (PASS).

### Change 6: `tests/install/run.sh` — install round-trip extraction

**Problem:** The install-uninstall-verify round-trip on a throwaway `$HOME` is currently a Bash one-liner the assistant reconstructs each /gate fast cycle. R3 extracts it into a runnable test that's part of the canonical suite.

**File:** `dev/tests/install/run.sh` (new, executable)

**Implementation:**

Pure extraction of the existing conversation-derived round-trip logic. Steps:

1. Create a throwaway `$HOME` via `mktemp -d`
2. Run `scripts/install.sh` against it
3. Run `scripts/verify.sh`; assert exit 0
4. Run `scripts/uninstall.sh`
5. Run `scripts/verify.sh`; assert exit 1 (drift expected)
6. Run `scripts/install.sh` again (idempotency)
7. Run `scripts/verify.sh`; assert exit 0
8. Refuse-to-clobber sub-test: drop a real file at one of the deployed paths, run `scripts/install.sh`; assert exit non-zero, real file preserved
9. Clean up the throwaway `$HOME`

Each step uses `record_pass` / `record_fail` from `helpers/assert.sh`.

**Acceptance Test:** `bash tests/install/run.sh` records 7+ PASS, 0 FAIL. The throwaway `$HOME` is cleaned up regardless of pass/fail (use `trap` for cleanup).

### Change 7: `tests/scaffold/run.sh` — scaffold smoke extraction

**Problem:** Same shape as Change 6 — the scaffold smoke test from R4a is a Bash one-liner in conversation. Extract it.

**File:** `dev/tests/scaffold/run.sh` (new, executable)

**Implementation:**

For each of the 3 templates (go-service, python-agent, next-frontend):

1. Run `scripts/new-project.sh <template> qc-test-<template>` — assert exit 0
2. Confirm the scaffolded project directory exists, contains expected structure (CLAUDE.md, gate_fast.sh, etc.)
3. Confirm `grep -r "{{PROJECT_NAME}}" <scaffold>/` returns nothing (full substitution)
4. Confirm `<scaffold>/.git/` exists and has one commit with the expected message prefix
5. For go-service only: confirm `<scaffold>/go.sum` exists (post-`go mod tidy`)
6. Tear down with `rm -rf <scaffold>`

After templates: edge cases:

7. Refuse-to-clobber: pre-create `projects/qc-clobber/`, run `new-project.sh python-agent qc-clobber`, assert non-zero exit, pre-existing file preserved
8. Invalid template name: `new-project.sh nope foo` exits non-zero
9. Invalid project name (slashes): `new-project.sh python-agent x/y` exits non-zero
10. Invalid `--gh-repo` visibility: `new-project.sh python-agent foo --gh-repo invalidvis` exits non-zero, no `projects/foo/` created

**Acceptance Test:** `bash tests/scaffold/run.sh` records ~12 PASS (3 templates × 4 sub-checks + 4 edge cases), 0 FAIL. No residue under `projects/qc-*` after the suite runs.

---

## Phase 3: Orchestrator + Wire-Up

### Change 8: `scripts/gate_fast.sh` orchestrator

**Problem:** With per-suite runners in `tests/`, an orchestrator at `scripts/gate_fast.sh` runs them in sequence, aggregates the PASS/FAIL/SKIP counts, and exits non-zero on any failure. This is what `/gate fast` invocations will call.

**File:** `dev/scripts/gate_fast.sh` (new, executable)

**Implementation:**

```bash
#!/usr/bin/env bash
# scripts/gate_fast.sh — dev-platform constitutional gate. Runs all per-suite
# test runners under tests/ plus a small set of "lift checks" (taxonomy
# enforcement, bash syntax, JSON validity, secrets scan) that don't
# warrant their own suite. Exits non-zero on any FAIL.
#
# Usage: ./scripts/gate_fast.sh
# Runtime: ~15s
# Successor steps (future specs): gate_full.sh (per-template builds),
#                                 gate_release.sh (multi-machine cutover).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

START=$(date +%s)
echo "=== gate fast ==="

# Lift checks (single-purpose, don't warrant their own suite)

echo ""
echo "--- lift checks ---"

# Taxonomy: invoke the existing checker. Run from repo root so it finds tasks/.
if (cd "${REPO}" && bash scripts/check_spec_taxonomy.sh >/dev/null 2>&1); then
    record_pass "spec taxonomy"
else
    record_fail "spec taxonomy (check_spec_taxonomy.sh exit 1)"
fi

# Bash syntax: all scripts under scripts/, hooks/, scaffolding/*/scripts/, tests/
syntax_pass=0; syntax_fail=0
while IFS= read -r -d '' f; do
    if bash -n "${f}" 2>/dev/null; then
        syntax_pass=$((syntax_pass + 1))
    else
        syntax_fail=$((syntax_fail + 1))
        record_fail "bash syntax: ${f}"
    fi
done < <(find "${REPO}/scripts" "${REPO}/hooks" "${REPO}/scaffolding"/*/scripts "${REPO}/tests" -type f -name "*.sh" -print0 2>/dev/null)
[[ ${syntax_fail} -eq 0 ]] && record_pass "bash syntax (${syntax_pass} scripts)"

# JSON validity: all .json files under settings/, scaffolding/
json_pass=0; json_fail=0
while IFS= read -r -d '' f; do
    if python3 -c "import json; json.load(open('${f}'))" 2>/dev/null; then
        json_pass=$((json_pass + 1))
    else
        json_fail=$((json_fail + 1))
        record_fail "JSON validity: ${f}"
    fi
done < <(find "${REPO}/settings" "${REPO}/scaffolding" -type f -name "*.json" -print0 2>/dev/null)
[[ ${json_fail} -eq 0 ]] && record_pass "JSON validity (${json_pass} files)"

# Secrets scan: literal passwords in tracked settings.json
if grep -qE 'PGPASSWORD=[a-z]' "${REPO}/settings/settings.json" 2>/dev/null; then
    record_fail "secrets: literal password in tracked settings.json"
else
    record_pass "secrets scan (no literal pwds in tracked file)"
fi

# Live ~/.claude/ verify (R1.5+ symlinks healthy)
if bash "${REPO}/scripts/verify.sh" >/dev/null 2>&1; then
    record_pass "live ~/.claude/ verify"
else
    record_fail "live ~/.claude/ verify (drift)"
fi

# Per-suite test runners
echo ""
echo "--- test suites ---"

for suite in hooks commands taxonomy install scaffold; do
    if [[ ! -d "${REPO}/tests/${suite}" ]]; then
        record_skip "${suite} (suite dir missing)"
        continue
    fi
    # Find each runner; for hooks/, runners are per-hook in subdirs
    while IFS= read -r runner; do
        echo "  suite: ${runner#${REPO}/}"
        if [[ -x "${runner}" ]]; then
            bash "${runner}" || true  # PASS/FAIL is captured via assert.sh helpers
        else
            record_fail "${suite}: ${runner#${REPO}/} not executable"
        fi
    done < <(find "${REPO}/tests/${suite}" -type f -name "run.sh" -o -name "frontmatter.sh" 2>/dev/null)
done

# Aggregate + report
echo ""
echo "=== summary ==="
END=$(date +%s)
echo "  ${PASS_COUNT} PASS  ${FAIL_COUNT} FAIL  ${SKIP_COUNT} SKIP  ($((END - START))s)"

if [[ ${FAIL_COUNT} -gt 0 ]]; then
    echo ""
    echo "GATE FAST: FAIL"
    exit 1
fi
echo "GATE FAST: PASS"
```

**Acceptance Test:** `bash scripts/gate_fast.sh` runs all lift checks + all 5 test suites, prints PASS/FAIL summary, exits 0 with all PASS. If a hook fixture is broken or a script has bad syntax, exit code is 1. Total runtime < 20s.

### Change 9: Update `dev/CLAUDE.md` Repo Structure + workflow

**Problem:** R3 introduces `tests/` and `scripts/gate_fast.sh`. The Repo Structure table in `dev/CLAUDE.md` doesn't list `tests/` (it doesn't exist pre-R3), and the workflow rules don't reference the now-runnable dev-platform `gate fast` script.

**File:** `dev/CLAUDE.md` (existing — two edits)

**Implementation:**

Edit 1 — Repo Structure table (currently lists 11 dirs): add a row for `tests/`:

```markdown
| `tests/` | Constitutional gate-fast fixtures + per-suite runners; orchestrated by `scripts/gate_fast.sh` (R3) |
```

Edit 2 — find the workflow section that mentions `/gate fast` and add a clarifying note that for dev-platform specifically, `/gate fast` is now `./scripts/gate_fast.sh` (rather than the conversation-derived Bash). Single sentence inline, no new section. Search for "`gate fast`" near the workflow rules and append a parenthetical: *"(dev-platform: run `./scripts/gate_fast.sh` — consolidated since R3)."*

**Acceptance Test:** Repo Structure table includes `tests/`. The /gate fast guidance references `scripts/gate_fast.sh`.

### Change 10: End-to-end acceptance + cleanup

**Problem:** The whole spec needs an end-to-end acceptance run to prove `gate_fast.sh` works against the real repo state — not just the fixtures.

**File:** none (procedural verification)

**Implementation:**

```bash
# 1. From a clean state (no smoke residue), run gate_fast.sh
ls /home/rich/dev/projects/qc-* 2>&1 | grep -q "No such" && echo "OK no residue"
bash /home/rich/dev/scripts/gate_fast.sh
# Expected: GATE FAST: PASS, all checks green, ~15s

# 2. Confirm exit code
bash /home/rich/dev/scripts/gate_fast.sh; echo "exit=$?"  # expect 0

# 3. Induce a failure: temporarily break a hook fixture
echo '{"tool_name": "Bash"' > /home/rich/dev/tests/hooks/post-tool-heartbeat/valid.json   # malformed JSON
bash /home/rich/dev/scripts/gate_fast.sh; rc=$?
[[ $rc -ne 0 ]] && echo "OK gate correctly FAILed on bad fixture"
# Restore the fixture
git checkout /home/rich/dev/tests/hooks/post-tool-heartbeat/valid.json

# 4. Re-run, confirm green
bash /home/rich/dev/scripts/gate_fast.sh; [[ $? -eq 0 ]] && echo "OK restored"

# 5. Cleanup: ensure no smoke residue under projects/
ls /home/rich/dev/projects/qc-* 2>&1 | grep -q "No such" && echo "OK no residue post-acceptance"
```

**Acceptance Test:** All 5 sub-steps pass: clean start → green; intentional fixture corruption → red; restoration → green; no residue.

---

## Acceptance Criteria

- [ ] `dev/tests/` directory exists with README and helpers/assert.sh (Change 1)
- [ ] `dev/.gitignore` allow-list extended to expose tests/ (Change 2)
- [ ] `tests/hooks/post-tool-heartbeat/` has 4 fixtures + run.sh, 4/4 PASS (Change 3)
- [ ] `tests/commands/frontmatter.sh` exists, 8/8 commands pass frontmatter validation (Change 4)
- [ ] `tests/taxonomy/` has 4 fixtures + run.sh, 4/4 PASS (Change 5)
- [ ] `tests/install/run.sh` exists, 7+ checks pass on round-trip (Change 6)
- [ ] `tests/scaffold/run.sh` exists, ~12 checks pass (Change 7)
- [ ] `scripts/gate_fast.sh` exists, orchestrates all lift checks + suites, exits 0 on green (Change 8)
- [ ] `dev/CLAUDE.md` Repo Structure + workflow updated (Change 9)
- [ ] End-to-end acceptance: gate_fast.sh runs in < 20s; intentional fixture corruption causes exit 1; restored fixture causes exit 0 (Change 10)
- [ ] No file under `dev/projects/` left behind by `tests/install/run.sh` or `tests/scaffold/run.sh`
- [ ] R1.5 live verify (`~/.claude/` symlinks) still passes — R3 does not touch deployed symlinks
- [ ] Spec taxonomy check passes against R3's own spec file
- [ ] All Phase 1+2 sub-runners are sourced by Phase 3's orchestrator — none orphaned

## Out of Scope (Future Specs)

- **`gate_full.sh`** — per-template full builds (npm install + build, pip install + pytest, go test). Defer until there's evidence gate-fast misses something. The R4a templates already have per-project `gate_fast.sh` scripts that run the project's own full build; dev-platform doesn't need to re-run those.
- **`gate_release.sh`** — multi-machine cutover acceptance. Multi-machine implies the live-cutover bit from R1/R1.5; not relevant to dev-platform's inner-loop concerns.
- **Performance benchmarks** — step-time regression detection. Defer until there's evidence a slow check has crept in.
- **Pre-commit git hook** — opt-in `shell/git-hooks/pre-commit` that calls `gate_fast.sh` automatically. Useful, but not core to R3. A future small spec can ship it.
- **CI integration** — GitHub Actions / similar wiring of gate-fast on push/PR. Not needed for a solo-dev environment yet; revisit when there's a need.
- **R4b VSCode Coverage** — still its own Roadmap Phase. Unrelated to R3.

## What NOT to Do

- **Do not introduce bats / make / shellspec as a dependency.** Decision 1 locked: pure bash with PASS/FAIL counter. Any future test framework introduction is its own spec discussion.
- **Do not put test fixtures inside the components they test** (e.g., `hooks/tests/`, `commands/tests/`). Decision 2 locked: all fixtures under top-level `tests/`. Distributed fixtures fragment the suite and complicate the orchestrator's runner discovery.
- **Do not ship slow tests in gate_fast.sh.** Decision 3 locked: per-template full builds belong in a future `gate_full.sh`. R3 stays under 20s.
- **Do not have `gate_fast.sh` call itself.** Self-test recursion adds no value; the test fixtures are the regression guard, not the orchestrator's behavior.
- **Do not auto-install a pre-commit hook.** Even though it would catch commits-without-gate-fast, that's out of scope for R3.
- **Do not write tests that depend on network access** (DNS, npm registry, PyPI, GitHub API). gate_fast must work offline.
- **Do not write tests that depend on a specific shell** other than `bash`. The shebang is `#!/usr/bin/env bash`; assume bash 4+ but no other shell.
- **Do not delete or move `check_spec_taxonomy.sh`.** R3 wraps it (Change 5) with self-test fixtures but the script itself stays where it is — projects across the repo reference it by absolute path (`/home/rich/dev/scripts/check_spec_taxonomy.sh`).
- **Do not bundle R4b VSCode work.** R3 is scoped to testing only; resist temptations to also extend tests/ for VSCode config that doesn't exist yet.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `dev/tests/README.md` | New | Directory contract |
| `dev/tests/helpers/assert.sh` | New | Shared PASS/FAIL helpers |
| `dev/.gitignore` | Modify | Allow-list for `tests/` |
| `dev/tests/hooks/post-tool-heartbeat/{valid.json,invalid.json,empty.txt,missing-tool-name.json}` | New | Heartbeat fixtures |
| `dev/tests/hooks/post-tool-heartbeat/run.sh` | New | Heartbeat suite runner |
| `dev/tests/commands/frontmatter.sh` | New | Frontmatter validator |
| `dev/tests/taxonomy/{conformant-spec.md,bad-spec-sprint.md,bad-spec-step.md,legitimate-step.md}` | New | Taxonomy fixtures |
| `dev/tests/taxonomy/run.sh` | New | Taxonomy self-test runner |
| `dev/tests/install/run.sh` | New | Install round-trip runner |
| `dev/tests/scaffold/run.sh` | New | Scaffold smoke runner |
| `dev/scripts/gate_fast.sh` | New | Orchestrator + lift checks |
| `dev/CLAUDE.md` | Modify | Repo Structure + workflow notes |
| `dev/tasks/dev-platform-r3-testing-spec.md` | (this file) | Spec |

## Implementation Order

1. **Phase 1 (Change 1)** — `tests/README.md` + `tests/helpers/assert.sh`. Foundation; nothing depends on this except Phase 2 sourcing the helper.
2. **Phase 1 (Change 2)** — gitignore extension. Independent. Can be done in parallel with Change 1.
3. **Phase 2 (Changes 3–7)** — five test suites. Independent of each other; can be developed in any order or in parallel. Each suite sources `helpers/assert.sh` from Change 1.
4. **Phase 3 (Change 8)** — `scripts/gate_fast.sh`. Depends on at least one Phase-2 suite existing (for the orchestrator to source). Can be developed alongside Phase 2 — just need to run a no-op suite for early testing.
5. **Phase 3 (Change 9)** — `dev/CLAUDE.md` updates. Independent. Can be done first or last.
6. **Phase 3 (Change 10)** — end-to-end acceptance. MUST come last — validates everything else.

Within Phase 2, Changes 3, 4, 5, 6, 7 can be batched in a single `/code` session. The whole spec is approximately one full session of work to plan + implement + acceptance-test.

## Verification Checklist

- [ ] All 10 Changes implemented.
- [ ] `bash -n` passes on every new `.sh` file (helpers + 5 runners + orchestrator).
- [ ] All `.json` fixtures parse as valid JSON (except `invalid.json` which is intentionally malformed and read as raw text by the hook).
- [ ] All 5 test suites individually pass when run directly: `bash tests/hooks/post-tool-heartbeat/run.sh`, `bash tests/commands/frontmatter.sh`, `bash tests/taxonomy/run.sh`, `bash tests/install/run.sh`, `bash tests/scaffold/run.sh`.
- [ ] `bash scripts/gate_fast.sh` exits 0 with all PASS; total runtime < 20s.
- [ ] Intentional fixture corruption causes `gate_fast.sh` to exit 1 (Change 10 acceptance).
- [ ] `tests/install/run.sh` and `tests/scaffold/run.sh` clean up after themselves — no `/tmp/r3-*` or `/home/rich/dev/projects/qc-*` residue.
- [ ] No `console.log` / `print()` / debug code in production paths.
- [ ] No path leakage outside `/home/rich/` in test runners (deliberate hardcoding allowed where it matches existing pattern, e.g., `/home/rich/dev/scripts/check_spec_taxonomy.sh`).
- [ ] `dev/CLAUDE.md` Repo Structure table includes `tests/`.
- [ ] R1.5 live verify still passes — R3 does not touch deployed symlinks.
- [ ] No file under `projects/` modified except for transient `tests/scaffold/run.sh` smoke runs that clean up.

## Notes for Implementation

- **No bats. No make. No shellspec.** Decision 1 is locked. If the test suite ever outgrows pure bash + counters, that's a future spec discussion.
- **`set -uo pipefail` (without `-e`) in runners.** Standard bash test pattern: don't exit on first failure, accumulate FAILs via `record_fail`, let the orchestrator decide whether to exit 1 at the end. This matches the existing `verify.sh` pattern.
- **`tests/install/run.sh` and `tests/scaffold/run.sh` use `trap` for cleanup.** Even if a step fails partway through, the throwaway `$HOME` and `projects/qc-*` dirs get removed. Pattern: `tmpdir=$(mktemp -d); trap 'rm -rf "${tmpdir}"' EXIT`.
- **YAML frontmatter parsing in `tests/commands/frontmatter.sh` is intentionally simple.** It doesn't handle multi-line values, quoted strings, comments, anchors, etc. — just enough to catch the common breakage shapes (missing `---`, missing field, empty value, too-long description). If a future command's frontmatter needs richer parsing, fix it then. Don't pre-engineer.
- **`tests/taxonomy/` uses temp dirs per fixture.** Because `check_spec_taxonomy.sh` scans `tasks/*-spec.md` in the current directory by default, isolating each fixture into its own temp `tasks/` dir is the cleanest way to test in isolation without polluting the real `tasks/`.
- **The "lift checks" in `gate_fast.sh` (taxonomy, syntax, JSON, secrets) are NOT under `tests/`** because they're single-purpose and don't benefit from fixture structure. They live inline in the orchestrator. If any of them grow more complex, promote to a proper test suite then.
- **Future R3+ followups already implied by this spec:**
  - Pre-commit git hook template (`shell/git-hooks/pre-commit` calling `gate_fast.sh`)
  - `gate_full.sh` for per-template full builds
  - Performance benchmarks if a check gets slow
  - Add a `tests/gitignore/` suite once R4b ships VSCode config — verifies the gitignore allow-list correctly handles new extensions
