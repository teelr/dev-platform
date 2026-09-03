#!/usr/bin/env bash
# tests/fleet-worktree/run.sh — the main-checkout resolver, asserted from BOTH
# locations it has to work from.
#
# The bug this exists to catch: `projects/` is gitignored, so it lives only in
# the main checkout, while five fleet scripts derived their root from their own
# file location. Run from a worktree they resolved `projects/<name>` to a path
# that does not exist — and none of them errored. `fleet-pins.sh` reported
# "— not adopted" for all seven consumers, which reads exactly like a real
# answer (v1.27).
#
# The v1.25 lesson (tasks/lessons/2026-09-03-run-the-gate-from-where-users-will-
# run-it.md) is the same shape: every gate run was from the main checkout, so
# suites asserting against their own ${REPO} passed while being wrong from a
# worktree. So this suite builds its own throwaway repo AND a real worktree of
# it, and checks both. It never reads dev-platform's own worktrees — whether one
# exists must not change the result.
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 contract. Offline.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

HELPER_SH="${REPO}/scripts/lib/main_checkout.sh"
HELPER_PY="${REPO}/scripts/lib/main_checkout.py"

TMP="$(mktemp -d /tmp/fleet-worktree-test.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

# ─── Fixture: a repo with a worktree, shaped like dev-platform ────
# monitoring/ + scripts/lib/ are committed, so they exist in the worktree too.
# projects/ is deliberately left UNCOMMITTED, which is how a gitignored
# directory behaves: present in the main checkout, absent from every worktree.
MAIN="${TMP}/main"
mkdir -p "${MAIN}/monitoring" "${MAIN}/scripts/lib"
cp "${REPO}/monitoring/fleet_pins.py" "${MAIN}/monitoring/"
cp "${REPO}/scripts/lib/main_checkout.py" "${REPO}/scripts/lib/repo_slug.py" "${MAIN}/scripts/lib/"
cp "${HELPER_SH}" "${MAIN}/scripts/lib/"
(
    cd "${MAIN}" && \
    git init -q -b main && \
    git add -A && \
    git -c user.email=test@test -c user.name=test commit -q -m "fixture"
) >/dev/null 2>&1

WT="${TMP}/wt"
(cd "${MAIN}" && git worktree add -q -b wt-branch "${WT}") >/dev/null 2>&1

if [[ ! -d "${WT}" ]]; then
    record_fail "fleet-worktree: fixture worktree was not created — cannot run suite"
    exit 0
fi

# The consumer lives only in the main checkout, exactly like projects/.
CONSUMER="${MAIN}/projects/consumer-a"
mkdir -p "${CONSUMER}/.github/workflows"
cat > "${CONSUMER}/.github/workflows/dev-platform-gate.yml" <<'EOF'
name: dev-platform-gate
on: [pull_request]
jobs:
  taxonomy:
    uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@v1.12
EOF

# `realpath` on macOS/BSD differs; resolve with pwd -P, which the helper uses.
MAIN_REAL="$(cd "${MAIN}" && pwd -P)"

sh_resolve() {
    # shellcheck disable=SC1090
    (source "${HELPER_SH}" && resolve_main_checkout "$1")
}

py_resolve() {
    python3 "${HELPER_PY}" "$1"
}

# ─── Check 1: bash -n syntax clean (runner + helper) ──────────────
if bash -n "${HERE}/run.sh" 2>/dev/null && bash -n "${HELPER_SH}" 2>/dev/null; then
    record_pass "fleet-worktree: bash -n syntax clean (runner + main_checkout.sh)"
else
    record_fail "fleet-worktree: bash -n syntax error"
fi

# ─── Check 2: python ast.parse clean ──────────────────────────────
if python3 -c "import ast; ast.parse(open('${HELPER_PY}').read())" 2>/dev/null; then
    record_pass "fleet-worktree: main_checkout.py python syntax clean"
else
    record_fail "fleet-worktree: main_checkout.py python syntax error"
fi

# ─── Check 3: bash helper, from the main checkout ─────────────────
got="$(sh_resolve "${MAIN}")"
if [[ "${got}" == "${MAIN_REAL}" ]]; then
    record_pass "fleet-worktree: main_checkout.sh from the main checkout → itself"
else
    record_fail "fleet-worktree: main_checkout.sh wrong from main — got '${got}', want '${MAIN_REAL}'"
fi

# ─── Check 4: bash helper, from a worktree ────────────────────────
# The load-bearing one: a worktree must resolve to the MAIN checkout, not
# to itself, or `projects/` is unreachable and every consumer reads as
# "not adopted".
got="$(sh_resolve "${WT}")"
if [[ "${got}" == "${MAIN_REAL}" ]]; then
    record_pass "fleet-worktree: main_checkout.sh from a worktree → the main checkout"
else
    record_fail "fleet-worktree: main_checkout.sh wrong from worktree — got '${got}', want '${MAIN_REAL}'"
fi

# ─── Check 5: python helper, from the main checkout ───────────────
got="$(py_resolve "${MAIN}")"
if [[ "${got}" == "${MAIN_REAL}" ]]; then
    record_pass "fleet-worktree: main_checkout.py from the main checkout → itself"
else
    record_fail "fleet-worktree: main_checkout.py wrong from main — got '${got}', want '${MAIN_REAL}'"
fi

# ─── Check 6: python helper, from a worktree ──────────────────────
got="$(py_resolve "${WT}")"
if [[ "${got}" == "${MAIN_REAL}" ]]; then
    record_pass "fleet-worktree: main_checkout.py from a worktree → the main checkout"
else
    record_fail "fleet-worktree: main_checkout.py wrong from worktree — got '${got}', want '${MAIN_REAL}'"
fi

# ─── Check 7: non-git directory → input returned unchanged ────────
# A tarball checkout has no .git. Returning the input keeps it working;
# an empty string or a crash would take the caller's paths with it.
PLAIN="${TMP}/not-a-repo"
mkdir -p "${PLAIN}"
sh_got="$(sh_resolve "${PLAIN}")"
py_got="$(py_resolve "${PLAIN}")"
plain_real="$(cd "${PLAIN}" && pwd -P)"
if [[ "${sh_got}" == "${plain_real}" || "${sh_got}" == "${PLAIN}" ]] && \
   [[ "${py_got}" == "${plain_real}" || "${py_got}" == "${PLAIN}" ]]; then
    record_pass "fleet-worktree: non-git directory → input returned unchanged (both helpers)"
else
    record_fail "fleet-worktree: non-git fallback wrong — sh='${sh_got}', py='${py_got}', want '${PLAIN}'"
fi

# ─── Check 8: git absent from PATH → same graceful fallback ───────
# Both helpers run before any required-tools gate their callers have, so
# a missing git must degrade, never abort.
# Both interpreters are invoked by ABSOLUTE path so the emptied PATH takes
# away `git` and nothing else — pointing PATH at /tmp while also resolving
# `python3` through it tests the harness, not the helper.
PYTHON_BIN="$(command -v python3)"
sh_got="$(PATH=/tmp /bin/bash -c "source '${HELPER_SH}' && resolve_main_checkout '${MAIN}'" 2>/dev/null)"
py_got="$(PATH=/tmp "${PYTHON_BIN}" "${HELPER_PY}" "${MAIN}" 2>/dev/null)"
if [[ "${sh_got}" == "${MAIN}" || "${sh_got}" == "${MAIN_REAL}" ]] && \
   [[ "${py_got}" == "${MAIN}" || "${py_got}" == "${MAIN_REAL}" ]]; then
    record_pass "fleet-worktree: git absent from PATH → falls back to the input, no crash"
else
    record_fail "fleet-worktree: no-git fallback wrong — sh='${sh_got}', py='${py_got}'"
fi

# ─── Check 9: a RELATIVE registry path resolves from a worktree ───
# End-to-end: fleet_pins.py running inside the worktree must find the
# consumer that exists only in the main checkout. This is the exact case
# that reported "not adopted" for all seven real consumers.
REL_REGISTRY="${TMP}/registry-rel.json"
cat > "${REL_REGISTRY}" <<EOF
[
  {"name": "consumer-a", "path": "projects/consumer-a", "gate_cmd": "true", "primary_language": "bash", "enabled": true}
]
EOF
out="$(cd "${WT}" && python3 "${WT}/monitoring/fleet_pins.py" \
    --source local --latest v1.26 --format json --registry "${REL_REGISTRY}" 2>&1)"
pin="$(echo "${out}" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print('PARSE-ERROR'); raise SystemExit(0)
print(d['projects'][0]['pin'])
" 2>/dev/null)"
if [[ "${pin}" == "v1.12" ]]; then
    record_pass "fleet-worktree: relative registry path resolves under the main checkout from a worktree"
else
    record_fail "fleet-worktree: relative path unresolved from worktree — pin='${pin}' (want v1.12)"
fi

# ─── Check 10: an ABSOLUTE registry path is untouched ─────────────
# Every fleet test suite points the registry at mktemp dirs by absolute
# path. FLEET_ROOT must not be prepended to those.
ABS_REGISTRY="${TMP}/registry-abs.json"
cat > "${ABS_REGISTRY}" <<EOF
[
  {"name": "consumer-a", "path": "${CONSUMER}", "gate_cmd": "true", "primary_language": "bash", "enabled": true}
]
EOF
out="$(cd "${WT}" && python3 "${WT}/monitoring/fleet_pins.py" \
    --source local --latest v1.26 --format json --registry "${ABS_REGISTRY}" 2>&1)"
pin="$(echo "${out}" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print('PARSE-ERROR'); raise SystemExit(0)
print(d['projects'][0]['pin'])
" 2>/dev/null)"
if [[ "${pin}" == "v1.12" ]]; then
    record_pass "fleet-worktree: absolute registry path is used as-is (FLEET_ROOT not prepended)"
else
    record_fail "fleet-worktree: absolute path handling broke — pin='${pin}' (want v1.12)"
fi

# Leave no worktree registered behind in the fixture repo before the trap
# removes the tree — a stale entry in the fixture's own .git is harmless
# once deleted, but pruning keeps the teardown honest.
(cd "${MAIN}" && git worktree remove --force "${WT}") >/dev/null 2>&1 || true
