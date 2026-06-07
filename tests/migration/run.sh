#!/usr/bin/env bash
# tests/migration/run.sh — fixture suite for v0.9 Phase 2 migration tooling.
# Validates migrate-workflow-chain.sh and audit-project-drift.sh against
# mock project trees under mktemp. 17 assertions.
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 contract.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

MIGRATE="${REPO}/scripts/migrate-workflow-chain.sh"
AUDIT="${REPO}/scripts/audit-project-drift.sh"

TMP="$(mktemp -d /tmp/migration-test.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

MOCK_ROOT="${TMP}/mock-projects"
mkdir -p "${MOCK_ROOT}"

NEW_CHAIN="/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge"

# ─── Mock project: clean-1 ────────────────────────────────────────────────
# CLAUDE.md with new canonical chain. No drift.
mkdir -p "${MOCK_ROOT}/clean-1/tasks"
cat > "${MOCK_ROOT}/clean-1/CLAUDE.md" <<EOF
# Clean Project

## Dev Workflow

Follow: ${NEW_CHAIN}
EOF

# ─── Mock project: old-chain-1 ───────────────────────────────────────────
# CLAUDE.md with old chain variant 3 (gate fast, no /docs).
mkdir -p "${MOCK_ROOT}/old-chain-1/tasks"
cat > "${MOCK_ROOT}/old-chain-1/CLAUDE.md" <<'EOF'
# Old Chain Project 1

## Dev Workflow

- Follow the dev workflow: `/plan → /code → /test → /review → /gate fast → commit → push`.
EOF

# ─── Mock project: old-chain-2 ───────────────────────────────────────────
# CLAUDE.md with old chain variant 5 (no gate, just commit).
mkdir -p "${MOCK_ROOT}/old-chain-2/tasks"
cat > "${MOCK_ROOT}/old-chain-2/CLAUDE.md" <<'EOF'
# Old Chain Project 2

## Dev Workflow

Follow: /plan → /code → /test → /review → commit
EOF

# ─── Mock project: no-claude-1 ───────────────────────────────────────────
# Directory with no CLAUDE.md.
mkdir -p "${MOCK_ROOT}/no-claude-1"

# ─── Mock project: taxonomy-drift-1 ─────────────────────────────────────
# CLAUDE.md clean; ROADMAP.md has a Sprint-prefixed header.
mkdir -p "${MOCK_ROOT}/taxonomy-drift-1/tasks"
cat > "${MOCK_ROOT}/taxonomy-drift-1/CLAUDE.md" <<EOF
# Taxonomy Drift Project

## Dev Workflow

Follow: ${NEW_CHAIN}
EOF
cat > "${MOCK_ROOT}/taxonomy-drift-1/ROADMAP.md" <<'EOF'
# Roadmap

## Sprint 1: Initial Work

Some content here.
EOF

# ─── Mock project: review-less-1 ─────────────────────────────────────────
# CLAUDE.md on the prior review-less canonical chain (post-v0.9, pre-v1.3).
# This is the upgrade path v1.3 consumers undergo: insert /review.
mkdir -p "${MOCK_ROOT}/review-less-1/tasks"
cat > "${MOCK_ROOT}/review-less-1/CLAUDE.md" <<'EOF'
# Review-less Project

## Dev Workflow

Follow: /plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge
EOF

# ─── Mock registry ───────────────────────────────────────────────────────
MOCK_REGISTRY="${TMP}/registry.json"
cat > "${MOCK_REGISTRY}" <<EOF
[
  {"name": "clean-1",         "path": "${MOCK_ROOT}/clean-1",         "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "old-chain-1",     "path": "${MOCK_ROOT}/old-chain-1",     "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "old-chain-2",     "path": "${MOCK_ROOT}/old-chain-2",     "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "no-claude-1",     "path": "${MOCK_ROOT}/no-claude-1",     "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "taxonomy-drift-1","path": "${MOCK_ROOT}/taxonomy-drift-1","gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "review-less-1",   "path": "${MOCK_ROOT}/review-less-1",   "gate_cmd": "true", "primary_language": "bash", "enabled": true}
]
EOF

# ─── Snapshot helper ─────────────────────────────────────────────────────
snapshot_tree() {
    local root="$1"
    (cd "${root}" && find . -type f | sort)
}

# ─── Check 1: migrate-workflow-chain.sh syntax clean ─────────────────────
if bash -n "${MIGRATE}" 2>/dev/null; then
    record_pass "migration: bash -n migrate-workflow-chain.sh — syntax clean"
else
    record_fail "migration: bash -n migrate-workflow-chain.sh — syntax error"
fi

# ─── Check 2: audit-project-drift.sh syntax clean ────────────────────────
if bash -n "${AUDIT}" 2>/dev/null; then
    record_pass "migration: bash -n audit-project-drift.sh — syntax clean"
else
    record_fail "migration: bash -n audit-project-drift.sh — syntax error"
fi

# ─── Check 3: migrate --help renders ─────────────────────────────────────
help_out="$("${MIGRATE}" --help 2>&1)"
if echo "${help_out}" | grep -q "migrate-workflow-chain"; then
    record_pass "migration: migrate --help renders"
else
    record_fail "migration: migrate --help missing expected text"
fi

# ─── Check 4: audit --help renders ───────────────────────────────────────
help_out="$("${AUDIT}" --help 2>&1)"
if echo "${help_out}" | grep -q "audit-project-drift"; then
    record_pass "migration: audit --help renders"
else
    record_fail "migration: audit --help missing expected text"
fi

# ─── Check 5: audit shows old-chain-1 as CHAIN=DRIFT (before any apply) ──
audit_out="$("${AUDIT}" --project old-chain-1 --registry "${MOCK_REGISTRY}" 2>&1)"
if echo "${audit_out}" | grep -q "old-chain-1" && echo "${audit_out}" | grep -q "DRIFT"; then
    record_pass "migration: audit reports old-chain-1 as CHAIN=DRIFT"
else
    record_fail "migration: audit did not detect old-chain-1 chain drift — output: ${audit_out}"
fi

# ─── Check 6: audit shows no-claude-1 as NO_CLAUDE_MD ───────────────────
audit_out="$("${AUDIT}" --project no-claude-1 --registry "${MOCK_REGISTRY}" 2>&1)"
if echo "${audit_out}" | grep -q "no-claude-1" && echo "${audit_out}" | grep -q "NO_CLAUDE_MD"; then
    record_pass "migration: audit reports no-claude-1 as NO_CLAUDE_MD"
else
    record_fail "migration: audit did not report NO_CLAUDE_MD for no-claude-1 — output: ${audit_out}"
fi

# ─── Check 7: audit shows taxonomy-drift-1 as TAXONOMY=DRIFT ─────────────
audit_out="$("${AUDIT}" --project taxonomy-drift-1 --registry "${MOCK_REGISTRY}" 2>&1)"
if echo "${audit_out}" | grep -q "taxonomy-drift-1" && echo "${audit_out}" | grep -q "DRIFT"; then
    record_pass "migration: audit reports taxonomy-drift-1 as TAXONOMY=DRIFT"
else
    record_fail "migration: audit did not detect taxonomy-drift-1 taxonomy drift — output: ${audit_out}"
fi

# ─── Check 8: audit writes no new files (read-only contract) ─────────────
BASELINE="$(snapshot_tree "${MOCK_ROOT}")"
"${AUDIT}" --registry "${MOCK_REGISTRY}" >/dev/null 2>&1 || true
AFTER_AUDIT="$(snapshot_tree "${MOCK_ROOT}")"
if [[ "${BASELINE}" == "${AFTER_AUDIT}" ]]; then
    record_pass "migration: audit read-only contract — no new files created under mock root"
else
    NEW_FILES="$(comm -13 <(echo "${BASELINE}") <(echo "${AFTER_AUDIT}") | sed 's/^/    /')"
    record_fail "migration: audit VIOLATED read-only contract — unexpected files:
${NEW_FILES}"
fi

# ─── Check 9: dry-run on old-chain-1 shows diff, does not write ──────────
hash_before="$(sha256sum "${MOCK_ROOT}/old-chain-1/CLAUDE.md" | awk '{print $1}')"
dry_out="$("${MIGRATE}" --project old-chain-1 --registry "${MOCK_REGISTRY}" 2>&1)"
hash_after="$(sha256sum "${MOCK_ROOT}/old-chain-1/CLAUDE.md" | awk '{print $1}')"
if echo "${dry_out}" | grep -q "^-.*\/test" && [[ "${hash_before}" == "${hash_after}" ]]; then
    record_pass "migration: dry-run shows old chain in diff and writes nothing"
else
    record_fail "migration: dry-run broken — diff_shows_old=$( echo "${dry_out}" | grep -q "^-.*\/test" && echo yes || echo no), file_changed=$([[ "${hash_before}" != "${hash_after}" ]] && echo yes || echo no)"
fi

# ─── Check 10: --apply on old-chain-1 rewrites to new chain ──────────────
"${MIGRATE}" --project old-chain-1 --registry "${MOCK_REGISTRY}" --apply >/dev/null 2>&1
old_present="$(grep -c "/test → /review" "${MOCK_ROOT}/old-chain-1/CLAUDE.md" 2>/dev/null)" || old_present=0
new_present="$(grep -c "gate fast → commit → push → /pr" "${MOCK_ROOT}/old-chain-1/CLAUDE.md" 2>/dev/null)" || new_present=0
if [[ "${old_present}" -eq 0 ]] && [[ "${new_present}" -gt 0 ]]; then
    record_pass "migration: --apply on old-chain-1 rewrites old chain to new chain"
else
    record_fail "migration: --apply on old-chain-1 failed — old_remaining=${old_present}, new_present=${new_present}"
fi

# ─── Check 11: second --apply is idempotent ──────────────────────────────
second_out="$("${MIGRATE}" --project old-chain-1 --registry "${MOCK_REGISTRY}" --apply 2>&1)"
if echo "${second_out}" | grep -q "already up-to-date"; then
    record_pass "migration: second --apply is idempotent (already up-to-date)"
else
    record_fail "migration: idempotency check failed — output: ${second_out}"
fi

# ─── Check 12: --apply on old-chain-2 rewrites the variant ──────────────
"${MIGRATE}" --project old-chain-2 --registry "${MOCK_REGISTRY}" --apply >/dev/null 2>&1
old2_present="$(grep -c "/test → /review" "${MOCK_ROOT}/old-chain-2/CLAUDE.md" 2>/dev/null)" || old2_present=0
new2_present="$(grep -c "gate fast → commit → push → /pr" "${MOCK_ROOT}/old-chain-2/CLAUDE.md" 2>/dev/null)" || new2_present=0
if [[ "${old2_present}" -eq 0 ]] && [[ "${new2_present}" -gt 0 ]]; then
    record_pass "migration: --apply on old-chain-2 rewrites the /test → /review → commit variant"
else
    record_fail "migration: --apply on old-chain-2 failed — old_remaining=${old2_present}, new_present=${new2_present}"
fi

# ─── Check 13: audit flags review-less-1 as CHAIN=DRIFT (v1.3 upgrade path) ─
audit_out="$("${AUDIT}" --project review-less-1 --registry "${MOCK_REGISTRY}" 2>&1)"
if echo "${audit_out}" | grep -q "review-less-1" && echo "${audit_out}" | grep -q "DRIFT"; then
    record_pass "migration: audit reports review-less-1 (no /review) as CHAIN=DRIFT"
else
    record_fail "migration: audit did not flag review-less chain — output: ${audit_out}"
fi

# ─── Check 14: dry-run on review-less-1 shows /review insert, writes nothing ─
hash_before="$(sha256sum "${MOCK_ROOT}/review-less-1/CLAUDE.md" | awk '{print $1}')"
dry_out="$("${MIGRATE}" --project review-less-1 --registry "${MOCK_REGISTRY}" 2>&1)"
hash_after="$(sha256sum "${MOCK_ROOT}/review-less-1/CLAUDE.md" | awk '{print $1}')"
if echo "${dry_out}" | grep -q "^+.*/code → /review → /gate fast" && [[ "${hash_before}" == "${hash_after}" ]]; then
    record_pass "migration: dry-run on review-less-1 shows /review insert and writes nothing"
else
    record_fail "migration: review-less dry-run broken — diff_shows_insert=$(echo "${dry_out}" | grep -q "^+.*/code → /review → /gate fast" && echo yes || echo no), file_changed=$([[ "${hash_before}" != "${hash_after}" ]] && echo yes || echo no)"
fi

# ─── Check 15: --apply on review-less-1 inserts /review ──────────────────
"${MIGRATE}" --project review-less-1 --registry "${MOCK_REGISTRY}" --apply >/dev/null 2>&1
reviewful_present="$(grep -c "/code → /review → /gate fast" "${MOCK_ROOT}/review-less-1/CLAUDE.md" 2>/dev/null)" || reviewful_present=0
reviewless_remaining="$(grep -cE "/code → /gate" "${MOCK_ROOT}/review-less-1/CLAUDE.md" 2>/dev/null)" || reviewless_remaining=0
if [[ "${reviewful_present}" -gt 0 ]] && [[ "${reviewless_remaining}" -eq 0 ]]; then
    record_pass "migration: --apply on review-less-1 inserts /review into the chain"
else
    record_fail "migration: review-less --apply failed — reviewful=${reviewful_present}, reviewless_remaining=${reviewless_remaining}"
fi

# ─── Check 16: second --apply on review-less-1 is idempotent ─────────────
second_out="$("${MIGRATE}" --project review-less-1 --registry "${MOCK_REGISTRY}" --apply 2>&1)"
if echo "${second_out}" | grep -q "already up-to-date"; then
    record_pass "migration: second --apply on review-less-1 is idempotent (already up-to-date)"
else
    record_fail "migration: review-less idempotency check failed — output: ${second_out}"
fi

# ─── Check 17: review-ful clean-1 is NOT falsely flagged as drift ────────
audit_out="$("${AUDIT}" --project clean-1 --registry "${MOCK_REGISTRY}" 2>&1)"
if echo "${audit_out}" | grep -q "clean-1" && echo "${audit_out}" | grep -q "CLEAN"; then
    record_pass "migration: audit reports review-ful clean-1 as CHAIN=CLEAN (no false flag)"
else
    record_fail "migration: review-ful chain falsely flagged — output: ${audit_out}"
fi
