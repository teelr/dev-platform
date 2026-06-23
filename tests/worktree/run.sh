#!/usr/bin/env bash
# tests/worktree/run.sh — regression suite for the v1.4 worktree isolation
# tooling: link-deps.sh (manifest parsing + symlinking) and gate-lock.sh
# (take-turns serialization), plus install integration.
#
# Sourced contract: uses record_pass/record_fail/record_skip from
# tests/helpers/assert.sh; never exit-s (the orchestrator owns the exit code).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
LINK_DEPS="${REPO}/shell/worktree/link-deps.sh"
GATE_LOCK="${REPO}/shell/worktree/gate-lock.sh"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

# --- syntax (these scripts live under shell/, which the gate's syntax loop
#     does not walk, so cover them here) ---
if bash -n "${LINK_DEPS}" 2>/dev/null; then
    record_pass "worktree: link-deps.sh bash syntax clean"
else
    record_fail "worktree: link-deps.sh bash syntax"
fi
if bash -n "${GATE_LOCK}" 2>/dev/null; then
    record_pass "worktree: gate-lock.sh bash syntax clean"
else
    record_fail "worktree: gate-lock.sh bash syntax"
fi

# --- Test 1: link-deps links a present path ---
tmp1="$(mktemp -d)"; trap 'rm -rf "${tmp1}"' EXIT
mkdir -p "${tmp1}/main/.claude" "${tmp1}/wt"
printf '.env\n' > "${tmp1}/main/.claude/worktree-deps"
echo "SECRET=1" > "${tmp1}/main/.env"
out="$(bash "${LINK_DEPS}" "${tmp1}/main" "${tmp1}/wt" 2>&1)"; rc=$?
if [[ ${rc} -eq 0 && -L "${tmp1}/wt/.env" && "$(readlink "${tmp1}/wt/.env")" == "${tmp1}/main/.env" ]]; then
    record_pass "worktree: link-deps links a present path as a symlink"
else
    record_fail "worktree: link-deps present path (rc=${rc}, out: ${out})"
fi

# --- Test 2: link-deps warns + continues on a missing source ---
tmp2="$(mktemp -d)"; trap 'rm -rf "${tmp1}" "${tmp2}"' EXIT
mkdir -p "${tmp2}/main/.claude" "${tmp2}/wt"
printf 'frontend/node_modules\n' > "${tmp2}/main/.claude/worktree-deps"
out="$(bash "${LINK_DEPS}" "${tmp2}/main" "${tmp2}/wt" 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "WARN source missing, skipped: frontend/node_modules"; then
    record_pass "worktree: link-deps warns and exits 0 on missing source"
else
    record_fail "worktree: link-deps missing source (rc=${rc}, out: ${out})"
fi

# --- Test 3: link-deps ignores comment + blank lines ---
tmp3="$(mktemp -d)"; trap 'rm -rf "${tmp1}" "${tmp2}" "${tmp3}"' EXIT
mkdir -p "${tmp3}/main/.claude" "${tmp3}/wt"
printf '# a comment\n\n.env\n' > "${tmp3}/main/.claude/worktree-deps"
echo "x" > "${tmp3}/main/.env"
out="$(bash "${LINK_DEPS}" "${tmp3}/main" "${tmp3}/wt" 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "1 linked, 0 missing"; then
    record_pass "worktree: link-deps ignores comments and blank lines"
else
    record_fail "worktree: link-deps comment/blank handling (rc=${rc}, out: ${out})"
fi

# --- Test 4: link-deps no-op without a manifest ---
tmp4="$(mktemp -d)"; trap 'rm -rf "${tmp1}" "${tmp2}" "${tmp3}" "${tmp4}"' EXIT
mkdir -p "${tmp4}/main" "${tmp4}/wt"
out="$(bash "${LINK_DEPS}" "${tmp4}/main" "${tmp4}/wt" 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "nothing to link"; then
    record_pass "worktree: link-deps no-ops without a manifest"
else
    record_fail "worktree: link-deps no-manifest (rc=${rc}, out: ${out})"
fi

# --- Test 5: gate-lock runs the wrapped command ---
tmp5="$(mktemp -d)"; trap 'rm -rf "${tmp1}" "${tmp2}" "${tmp3}" "${tmp4}" "${tmp5}"' EXIT
(
    cd "${tmp5}" && git init -q
    # shellcheck disable=SC1090
    source "${GATE_LOCK}"
    with_gate_lock true
) && record_pass "worktree: with_gate_lock runs the wrapped command (exit 0)" \
  || record_fail "worktree: with_gate_lock failed to run wrapped command"

# --- Test 6: gate-lock serializes two concurrent calls ---
if command -v flock >/dev/null 2>&1; then
    tmp6="$(mktemp -d)"; trap 'rm -rf "${tmp1}" "${tmp2}" "${tmp3}" "${tmp4}" "${tmp5}" "${tmp6}"' EXIT
    (
        cd "${tmp6}" && git init -q
        # shellcheck disable=SC1090
        source "${GATE_LOCK}"
        order="${tmp6}/order"
        : > "${order}"
        # A grabs the lock first (small head start), holds it ~0.3s.
        with_gate_lock bash -c "echo A-start >> '${order}'; sleep 0.3; echo A-end >> '${order}'" &
        sleep 0.1
        with_gate_lock bash -c "echo B-start >> '${order}'; echo B-end >> '${order}'" &
        wait
        # No interleave: lines 1-2 are one actor, lines 3-4 the other.
        l1="$(sed -n 1p "${order}" | cut -d- -f1)"
        l2="$(sed -n 2p "${order}" | cut -d- -f1)"
        l3="$(sed -n 3p "${order}" | cut -d- -f1)"
        l4="$(sed -n 4p "${order}" | cut -d- -f1)"
        [[ "${l1}" == "${l2}" && "${l3}" == "${l4}" && "${l1}" != "${l3}" ]]
    ) && record_pass "worktree: with_gate_lock serializes concurrent runs (no interleave)" \
      || record_fail "worktree: with_gate_lock did NOT serialize (interleaved)"
else
    record_skip "worktree: gate-lock serialization (flock not installed)"
fi

# --- Test 7: install integration (tmpdir HOME) ---
tmp7="$(mktemp -d)"; trap 'rm -rf "${tmp1}" "${tmp2}" "${tmp3}" "${tmp4}" "${tmp5}" "${tmp6:-}" "${tmp7}"' EXIT
HOME="${tmp7}" bash "${REPO}/scripts/install.sh" worktree >/dev/null 2>&1
ld="${tmp7}/.claude/worktree/link-deps.sh"
gl="${tmp7}/.claude/worktree/gate-lock.sh"
if [[ -L "${ld}" && "$(readlink "${ld}")" == "${LINK_DEPS}" \
   && -L "${gl}" && "$(readlink "${gl}")" == "${GATE_LOCK}" ]]; then
    record_pass "worktree: install deploys link-deps.sh + gate-lock.sh as symlinks"
else
    record_fail "worktree: install integration (ld=$(readlink "${ld}" 2>/dev/null), gl=$(readlink "${gl}" 2>/dev/null))"
fi
