#!/usr/bin/env bash
# tests/comms-delivery/run.sh — fixture suite for the v1.5 comms delivery
# checker (monitoring/comms_delivery.py + scripts/check-comms-delivery.sh).
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 auto-discovery contract.
# Fully offline: a mock `gh` at fixtures/mock-bin/gh + a mock consumer tree and
# registry under mktemp (absolute paths). Never touches a real GitHub repo.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

WRAPPER="${REPO}/scripts/check-comms-delivery.sh"
MODULE="${REPO}/monitoring/comms_delivery.py"
MOCK_BIN="${HERE}/fixtures/mock-bin"

TMP="$(mktemp -d /tmp/comms-delivery.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

# make_comm <consumer_tasks_dir> <filename> <body>
make_comm() {
    local dir="$1" name="$2" body="$3"
    mkdir -p "${dir}"
    printf '# Communique\n\n%s\n' "${body}" > "${dir}/${name}"
}

# --- Comprehensive tree: pa (active, all cases) + ks (active) + old (inactive) ---
PA_TASKS="${TMP}/projects/pa/tasks"
KS_TASKS="${TMP}/projects/ks/tasks"
OLD_TASKS="${TMP}/projects/old/tasks"

make_comm "${PA_TASKS}" "communique-to-harness-2026-06-30-good.md" \
    "Ask filed as teelr/kermit-harness#200 (source of truth)."
make_comm "${PA_TASKS}" "communique-to-harness-2026-06-30-shorthand.md" \
    "See kermit-harness#200 for status."
make_comm "${PA_TASKS}" "communique-to-harness-2026-06-30-undelivered.md" \
    "We hit a bug. PR #121 wired the routing. No upstream issue here."
make_comm "${PA_TASKS}" "communique-to-harness-2026-06-30-deadlink.md" \
    "Filed as kermit-harness#9999."
make_comm "${PA_TASKS}" "communique-to-harness-2026-05-01-legacy.md" \
    "Old file-relay era ask, no issue."
make_comm "${PA_TASKS}" "communique-to-harness-behavioral-gap.md" \
    "Undated legacy ask."
make_comm "${PA_TASKS}" "communique-to-pa-2026-06-30-reply.md" \
    "Harness reply TO pa — not an ask, must be ignored. kermit-harness#1."

make_comm "${KS_TASKS}" "communique-to-harness-2026-06-30-ks-undelivered.md" \
    "Keystone ask, no upstream issue linked."
make_comm "${OLD_TASKS}" "communique-to-harness-2026-06-30-old-undelivered.md" \
    "Deprecated consumer ask, no issue."

REG_ALL="${TMP}/registry-all.json"
cat > "${REG_ALL}" <<JSON
[
  {"consumer": "pa", "path": "${TMP}/projects/pa", "dep_slug": "harness", "upstream_repo": "teelr/kermit-harness", "label": "consumer:pa", "active": true},
  {"consumer": "ks", "path": "${TMP}/projects/ks", "dep_slug": "harness", "upstream_repo": "teelr/kermit-harness", "label": "consumer:keystone", "active": true},
  {"consumer": "old", "path": "${TMP}/projects/old", "dep_slug": "harness", "upstream_repo": "teelr/kermit-harness", "label": "consumer:atlas", "active": false}
]
JSON

# --- Happy tree: only deliverable / skipped files (no FAIL) ---
HAPPY_TASKS="${TMP}/happy/pa/tasks"
make_comm "${HAPPY_TASKS}" "communique-to-harness-2026-06-30-good.md" \
    "Filed as teelr/kermit-harness#200."
make_comm "${HAPPY_TASKS}" "communique-to-harness-2026-06-30-shorthand.md" \
    "kermit-harness#200."
make_comm "${HAPPY_TASKS}" "communique-to-harness-2026-05-01-legacy.md" "old."
make_comm "${HAPPY_TASKS}" "communique-to-pa-2026-06-30-reply.md" "reply only."
REG_HAPPY="${TMP}/registry-happy.json"
cat > "${REG_HAPPY}" <<JSON
[
  {"consumer": "pa", "path": "${TMP}/happy/pa", "dep_slug": "harness", "upstream_repo": "teelr/kermit-harness", "label": "consumer:pa", "active": true}
]
JSON

run_checker() {
    # run_checker <registry> <extra args...> ; sets global OUT and RC. gh has #200.
    OUT="$(PATH="${MOCK_BIN}:${PATH}" MOCK_GH_EXISTING="200" \
        "${WRAPPER}" --registry "$1" "${@:2}" 2>&1)"
    RC=$?
}

# Check 1: wrapper syntax + module parses
if bash -n "${WRAPPER}" && python3 -c "import ast,sys; ast.parse(open('${MODULE}').read())"; then
    record_pass "comms-delivery: wrapper syntax clean + module parses"
else
    record_fail "comms-delivery: syntax/parse error"
fi

# Check 2: --help renders
if "${WRAPPER}" --help 2>&1 | grep -qi "comms.delivery\|ask-communique\|upstream issue"; then
    record_pass "comms-delivery: --help renders"
else
    record_fail "comms-delivery: --help missing"
fi

# Comprehensive run (gh online, #200 exists)
run_checker "${REG_ALL}"
OUT_ALL="${OUT}"; RC_ALL="${RC}"

# Check 3: all-good tree → exit 0, no FAIL status line
run_checker "${REG_HAPPY}"
if [[ ${RC} -eq 0 ]] && ! echo "${OUT}" | grep -qE "^[[:space:]]*FAIL "; then
    record_pass "comms-delivery: all-good tree exits 0 with no FAIL"
else
    record_fail "comms-delivery: happy tree wrong — rc=${RC}, out=${OUT:0:300}"
fi

# Check 4: undelivered (no ref) → exit 1 + filename + 'no upstream issue'
if [[ ${RC_ALL} -eq 1 ]] && \
   echo "${OUT_ALL}" | grep "undelivered.md" | grep -q "no upstream issue"; then
    record_pass "comms-delivery: undelivered communique FAILs with 'no upstream issue'"
else
    record_fail "comms-delivery: undelivered not flagged — rc=${RC_ALL}"
fi

# Check 5: dead link (#9999 missing) → FAIL + '9999' + 'not found'
if echo "${OUT_ALL}" | grep "deadlink.md" | grep -q "9999" && \
   echo "${OUT_ALL}" | grep "deadlink.md" | grep -q "not found"; then
    record_pass "comms-delivery: dead-link communique FAILs with 'not found'"
else
    record_fail "comms-delivery: dead link not flagged — line=$(echo "${OUT_ALL}" | grep deadlink.md)"
fi

# Check 6: repo-name shorthand resolves → OK
if echo "${OUT_ALL}" | grep "shorthand.md" | grep -q "OK"; then
    record_pass "comms-delivery: repo-name shorthand (kermit-harness#200) resolves to OK"
else
    record_fail "comms-delivery: shorthand not OK — line=$(echo "${OUT_ALL}" | grep shorthand.md)"
fi

# Check 7: pre-cutover → SKIP
if echo "${OUT_ALL}" | grep "2026-05-01-legacy.md" | grep -q "SKIP"; then
    record_pass "comms-delivery: pre-cutover file SKIPped (legacy)"
else
    record_fail "comms-delivery: pre-cutover not SKIPped"
fi

# Check 8: undated → SKIP
if echo "${OUT_ALL}" | grep "behavioral-gap.md" | grep -q "SKIP"; then
    record_pass "comms-delivery: undated file SKIPped (legacy)"
else
    record_fail "comms-delivery: undated not SKIPped"
fi

# Check 9: reply-direction file ignored entirely (appears in no line)
if ! echo "${OUT_ALL}" | grep -q "communique-to-pa-"; then
    record_pass "comms-delivery: reply-direction file (communique-to-pa-*) ignored"
else
    record_fail "comms-delivery: reply-direction file leaked into output"
fi

# Check 10: --offline → dead-link becomes UNVERIFIED, no-ref still FAIL → exit 1
run_checker "${REG_ALL}" --offline
if [[ ${RC} -eq 1 ]] && \
   echo "${OUT}" | grep "deadlink.md" | grep -q "UNVERIFIED" && \
   echo "${OUT}" | grep "undelivered.md" | grep -q "FAIL"; then
    record_pass "comms-delivery: --offline → dead-link UNVERIFIED, no-ref still FAIL"
else
    record_fail "comms-delivery: --offline wrong — rc=${RC}, dead=$(echo "${OUT}" | grep deadlink.md)"
fi

# Check 11: --consumer pa filters out ks's file
run_checker "${REG_ALL}" --consumer pa
if ! echo "${OUT}" | grep -q "ks-undelivered.md" && echo "${OUT}" | grep -q "projects/pa/"; then
    record_pass "comms-delivery: --consumer pa excludes other consumers"
else
    record_fail "comms-delivery: --consumer filter wrong — out=${OUT:0:300}"
fi

# Check 12: active:false consumer ('old') never scanned
if ! echo "${OUT_ALL}" | grep -q "old-undelivered.md"; then
    record_pass "comms-delivery: active:false consumer skipped"
else
    record_fail "comms-delivery: inactive consumer was scanned"
fi

exit $(( FAIL_COUNT > 0 ? 1 : 0 ))
