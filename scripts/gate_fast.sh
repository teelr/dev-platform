#!/usr/bin/env bash
# scripts/gate_fast.sh — dev-platform constitutional gate. Runs lift checks
# (taxonomy enforcement, bash syntax, JSON validity, secrets scan, live
# ~/.claude/ verify) plus all per-suite test runners under tests/. Aggregates
# PASS/FAIL/SKIP and exits non-zero on any FAIL.
#
# Usage: ./scripts/gate_fast.sh
# Runtime: ~15s

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Shared count file so subshell runners feed their PASS/FAIL/SKIP into the
# orchestrator's totals. Assert helpers append to this when set.
export _GATE_COUNTS_FILE
_GATE_COUNTS_FILE="$(mktemp /tmp/gate-counts.XXXXXX)"
trap "rm -f '${_GATE_COUNTS_FILE}'" EXIT

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

# Take-turns lock (v1.4): serialize the live ~/.claude/ verify across concurrent
# gates so two worktree sessions don't race on the shared deploy. Prefer the
# deployed copy; fall back to the tracked source (e.g. on a CI runner with no
# ~/.claude/).
_LOCK_HELPER="${HOME}/.claude/worktree/gate-lock.sh"
[[ -f "${_LOCK_HELPER}" ]] || _LOCK_HELPER="${REPO}/shell/worktree/gate-lock.sh"
# shellcheck disable=SC1090
source "${_LOCK_HELPER}"

# Docs-only diff detection (v1.14) — skip the expensive test-suite loop below
# when every changed file is pure documentation. Lift checks above/below this
# block (taxonomy, syntax, JSON, secrets, live verify) always still run — see
# docs/RULE_RATIONALE.md "Gate-Fast Docs-Only Diff Skip" for why that's safe.
#
# Override the shared helper's generic default: bare `*.md` matches ANY .md
# file at any depth (bash's `[[ str == pattern ]]` lets `*` cross `/`), which
# would wrongly classify commands/*.md and skills/**/*.md as inert docs —
# tests/commands/frontmatter.sh validates the LIVE commands/*.md files
# directly, and a docs-only diff that only touched a command file would
# silently skip the one test that checks it. Scope dev-platform's own
# allowlist to what's actually inert here: root markdown + docs/ + tasks/.
DOCS_ONLY_ALLOW_PATTERNS=("README.md" "CLAUDE.md" "ROADMAP.md" "planning.md" "docs/*" "tasks/*")
# shellcheck disable=SC1091
source "${REPO}/scripts/lib/docs_only_diff.sh"
compute_docs_only_diff

START=$(date +%s)
echo "=== gate fast ==="
echo ""
echo "--- lift checks ---"

# Taxonomy enforcement
if (cd "${REPO}" && bash scripts/check_spec_taxonomy.sh >/dev/null 2>&1); then
    record_pass "spec taxonomy"
else
    record_fail "spec taxonomy (check_spec_taxonomy.sh exit 1)"
fi

# Duplicate-number check (Kermit-consumer handoff-queue "Ask #" rows +
# lessons.md "L#" headers). dev-platform itself has neither convention, so
# this is a graceful no-op here — the reference implementation for the
# three consumer projects that DO use it (see docs/RULE_RATIONALE.md).
if (cd "${REPO}" && bash scripts/check_duplicate_numbering.sh >/dev/null 2>&1); then
    record_pass "duplicate numbering (handoff-queue / lessons)"
else
    record_fail "duplicate numbering (check_duplicate_numbering.sh exit 1)"
fi

# Fleet registry schema (monitoring/projects.json). Six scripts read it and
# nothing validated it before v1.30: a missing `enabled` key silently drops a
# project from every fleet operation, and `enabled: false` + `frozen: true` is
# expressible and contradictory.
#
# No SKIP state, unlike check_env_leak below: four of its five checks read the
# tracked registry file, which is always present, so they really do run on a CI
# runner. Only the gate_cmd leg depends on `projects/`, and the script reports
# that leg's coverage in its own output rather than degrading the whole check
# to SKIP and hiding four checks that passed.
#
# 2 is still separated from 1 so the message names the real problem: a missing
# registry or an absent `jq` is a setup fault, not a malformed entry, and
# telling the reader to "run it for the offending entry" would send them
# looking for an entry that isn't the cause. (jq is pre-installed on the
# ubuntu-latest runner — see .github/workflows/gate.yml.)
(cd "${REPO}" && bash scripts/check-registry.sh >/dev/null 2>&1)
registry_rc=$?
case ${registry_rc} in
    0) record_pass "fleet registry schema" ;;
    1) record_fail "fleet registry schema (check-registry.sh — run it for the offending entry)" ;;
    *) record_fail "fleet registry schema (check-registry.sh setup error, exit ${registry_rc} — missing registry or jq)" ;;
esac

# App-API-key -> Claude Code env leak across projects/ (read-only audit).
# Three-way, NOT two: exit 2 means projects/ does not exist, which is every CI
# runner and any fresh clone. Recording that as PASS would be a check that
# reports success having read nothing — the script exited 0 with
# "Clean, 0 projects checked" in exactly that situation before PR #101, which is
# why it is worth being explicit here.
(cd "${REPO}" && bash scripts/check_env_leak.sh >/dev/null 2>&1)
env_leak_rc=$?
case ${env_leak_rc} in
    0) record_pass "env leak (no project injects an Anthropic key into its terminal)" ;;
    2) record_skip "env leak (no projects/ — likely CI runner)" ;;
    *) record_fail "env leak (check_env_leak.sh exit ${env_leak_rc} — run it for the offending project)" ;;
esac

# Bash syntax — all .sh files under scripts/, hooks/, scaffolding/*/scripts/, tests/
syntax_pass=0
syntax_fail=0
while IFS= read -r -d '' f; do
    if bash -n "${f}" 2>/dev/null; then
        syntax_pass=$((syntax_pass + 1))
    else
        syntax_fail=$((syntax_fail + 1))
        record_fail "bash syntax: ${f#${REPO}/}"
    fi
done < <(find \
    "${REPO}/scripts" \
    "${REPO}/hooks" \
    "${REPO}/scaffolding"/*/scripts \
    "${REPO}/shell" \
    "${REPO}/tests" \
    -type f -name "*.sh" -print0 2>/dev/null)
[[ ${syntax_fail} -eq 0 ]] && record_pass "bash syntax (${syntax_pass} scripts)"

# JSON validity — all .json files under settings/, scaffolding/
json_pass=0
json_fail=0
while IFS= read -r -d '' f; do
    if python3 -c "import json; json.load(open('${f}'))" 2>/dev/null; then
        json_pass=$((json_pass + 1))
    else
        json_fail=$((json_fail + 1))
        record_fail "JSON validity: ${f#${REPO}/}"
    fi
done < <(find "${REPO}/settings" "${REPO}/scaffolding" -type f -name "*.json" -print0 2>/dev/null)
if [[ ${json_fail} -eq 0 ]]; then
    # Zero matches is a broken glob, not a clean repo — reporting PASS on it
    # would be a check that validated nothing. Same guard as the YAML block
    # below; added here in v1.31 after writing that one made the gap obvious.
    if [[ ${json_pass} -eq 0 ]]; then
        record_fail "JSON validity: 0 files matched — the glob is broken, not the JSON"
    else
        record_pass "JSON validity (${json_pass} files)"
    fi
fi

# YAML validity — workflows + the consumer templates.
# The gate validated every tracked .json and no .yml at all until v1.31, while
# .github/workflows/taxonomy-check.yml is the highest-blast-radius file here:
# every consumer's CI calls it, so a malformed edit breaks the whole fleet at
# once. The file count is reported, like the JSON check's, so a glob that stops
# matching is visible instead of passing silently on zero files.
#
# scaffolding/ is deliberately NOT scanned. Its docker-compose.yml files are
# TEMPLATES carrying {{PROJECT_NAME}} placeholders, and `{{` opens a flow
# mapping in YAML — so they are not parseable until new-project.sh substitutes
# them, by design. Scanning them reported two failures against files that are
# correct as written. Validating what they render to is a different check than
# this one, and would need the substitution step to run first.
if python3 -c "import yaml" 2>/dev/null; then
    yaml_pass=0
    yaml_fail=0
    while IFS= read -r -d '' f; do
        if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "${f}" 2>/dev/null; then
            yaml_pass=$((yaml_pass + 1))
        else
            yaml_fail=$((yaml_fail + 1))
            record_fail "YAML validity: ${f#${REPO}/}"
        fi
    done < <(find \
        "${REPO}/.github/workflows" \
        "${REPO}/extensions/github-actions" \
        -type f \( -name "*.yml" -o -name "*.yaml" \) -print0 2>/dev/null)
    if [[ ${yaml_fail} -eq 0 ]]; then
        if [[ ${yaml_pass} -eq 0 ]]; then
            record_fail "YAML validity: 0 files matched — the glob is broken, not the YAML"
        else
            record_pass "YAML validity (${yaml_pass} files)"
        fi
    fi
else
    record_skip "YAML validity (pyyaml not installed)"
fi

# Secrets scan — literal passwords in tracked settings.json
if grep -qE 'PGPASSWORD=[a-z]' "${REPO}/settings/settings.json" 2>/dev/null; then
    record_fail "secrets: literal password in tracked settings.json"
else
    record_pass "secrets scan (no literal pwds in tracked file)"
fi

# Live ~/.claude/ verify — checks that the deployed symlinks under ~/.claude/
# match the tracked source. This is a developer-environment integrity check
# meaningful only where the repo has been deployed (via scripts/install.sh).
# On a fresh CI runner ~/.claude/ doesn't exist, so the check has nothing to
# verify and we record SKIP rather than FAIL. The CI environment runs all
# OTHER lift checks + every test suite — only the live-deploy check is
# environment-dependent.
if [[ ! -d "${HOME}/.claude" ]]; then
    record_skip "live ~/.claude/ verify (no ~/.claude/ — likely CI runner)"
elif with_gate_lock bash "${REPO}/scripts/verify.sh" >/dev/null 2>&1; then
    record_pass "live ~/.claude/ verify"
else
    record_fail "live ~/.claude/ verify (drift — run scripts/verify.sh for details)"
fi

# Per-suite test runners. Auto-discovery: every subdirectory of tests/
# (except tests/helpers/) is a suite. Within each suite, every executable
# *.sh file is a runner. New suites land automatically without editing
# this orchestrator — matching the contract documented in tests/README.md.
echo ""
echo "--- test suites ---"
if [[ "${DOCS_ONLY_DIFF}" -eq 1 ]]; then
    echo "  docs-only diff detected — skipping test suites (structural lift checks above still ran)"
    echo "  changed: ${DOCS_ONLY_CHANGED_FILES//$'\n'/ }"
fi

for suite_dir in "${REPO}/tests"/*/; do
    suite_dir="${suite_dir%/}"
    suite_name="$(basename "${suite_dir}")"
    # Skip the shared helpers/ dir — it's not a suite.
    [[ "${suite_name}" == "helpers" ]] && continue

    # Find every executable *.sh under this suite, any depth (run.sh inside
    # per-fixture subdirs like hooks/post-tool-heartbeat/ is supported).
    # Exclude fixtures/ — runnable fixtures (mock binaries, mock project
    # gates) live there and are NOT test runners. The contract: test runners
    # live at tests/<suite>/*.sh or tests/<suite>/<test>/*.sh, NEVER under
    # tests/<suite>/fixtures/. Added v0.8 Phase 1 when fleet-gate's mock-
    # project tree introduced runnable gate.sh files under fixtures/.
    found_any=0
    while IFS= read -r runner; do
        found_any=1
        echo "  suite: ${runner#${REPO}/}"
        if [[ "${DOCS_ONLY_DIFF}" -eq 1 ]]; then
            record_skip "${suite_name}: ${runner#${REPO}/} (docs-only diff)"
        elif [[ -x "${runner}" ]]; then
            bash "${runner}" || true   # PASS/FAIL captured via assert.sh helpers
        else
            record_fail "${suite_name}: ${runner#${REPO}/} not executable"
        fi
    done < <(find "${suite_dir}" -type f -name "*.sh" \
                ! -path "*/fixtures/*" \
                2>/dev/null)
    [[ ${found_any} -eq 0 ]] && record_skip "${suite_name} (no *.sh runners found)"
done

# Summary — aggregate from the shared count file so subshell runners
# contribute to the totals (their in-subshell counters don't propagate
# back to this script's scope).
echo ""
echo "=== summary ==="
END=$(date +%s)

total_pass=$(grep -c "^PASS$" "${_GATE_COUNTS_FILE}" 2>/dev/null); total_pass=${total_pass:-0}
total_fail=$(grep -c "^FAIL$" "${_GATE_COUNTS_FILE}" 2>/dev/null); total_fail=${total_fail:-0}
total_skip=$(grep -c "^SKIP$" "${_GATE_COUNTS_FILE}" 2>/dev/null); total_skip=${total_skip:-0}

echo "  ${total_pass} PASS  ${total_fail} FAIL  ${total_skip} SKIP  ($((END - START))s)"

# Emit gate_run telemetry event (v0.5 Phase 2, Change 7). Failure-tolerant:
# Python failure is silent; the gate's exit code is determined ONLY by
# total_fail above, never by the emission.
_GATE_LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${_GATE_LOG}")" 2>/dev/null || true
_GATE_OUTCOME="pass"
[[ ${total_fail} -gt 0 ]] && _GATE_OUTCOME="fail"
python3 - "${PWD}" "${_GATE_OUTCOME}" "${total_pass}" "${total_fail}" "$((END - START))" >> "${_GATE_LOG}" 2>/dev/null <<'PY' || true
import sys, json
from datetime import datetime, timezone

cwd, outcome, p, f, d = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])

def project_for(cwd):
    if cwd.startswith("/home/rich/dev/projects/"):
        parts = cwd.split("/")
        if len(parts) >= 6 and parts[5]:
            return parts[5]
    if cwd == "/home/rich/dev" or cwd.startswith("/home/rich/dev/"):
        return "dev-platform"
    return "other"

event = {
    "v": 1,
    "ts": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
    "event": "gate_run",
    "session_id": "gate",
    "project": project_for(cwd),
    "outcome": outcome,
    "pass_count": p,
    "fail_count": f,
    "duration_s": d,
}
print(json.dumps(event))
PY

if [[ ${total_fail} -gt 0 ]]; then
    echo ""
    echo "GATE FAST: FAIL"
    exit 1
fi
echo "GATE FAST: PASS"
