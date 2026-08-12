#!/usr/bin/env bash
# tests/version-collision/run.sh — offline fixture suite for v1.11's
# scripts/claim_roadmap_version.py + scripts/check_version_collision.py.
#
# Uses a real local git remote (a bare repo standing in for "origin") so the
# scripts' actual `git fetch`/`git show origin/main:...` calls have something
# real to talk to, plus a mock `gh` (fixtures/mock-bin/gh) driven by
# MOCK_MILESTONES_FILE / MOCK_CREATE_FAIL_COUNT so no real GitHub call is
# ever made. VERSION_GUARD_REPO_SLUG (a test-only override added when these
# scripts were promoted — see scripts/check_version_collision.py's
# _repo_slug()) decouples "which repo git talks to" (a local path, for real
# fetch/show) from "which repo gh is asked about" (a fake owner/repo, so the
# mock gets invoked at all — a real local-path origin fails the github.com
# URL regex and short-circuits before gh is ever called).
#
# Auto-discovered by scripts/gate_fast.sh (tests/<suite>/run.sh, excluding
# fixtures/ — so the mock `gh` is never run as a test runner).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

CHECK_SCRIPT="${REPO}/scripts/check_version_collision.py"
CLAIM_SCRIPT="${REPO}/scripts/claim_roadmap_version.py"
MOCK_BIN="${HERE}/fixtures/mock-bin"

TMP="$(mktemp -d /tmp/version-collision.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

# --- Build a real local "origin" + working clone ------------------------------

ORIGIN="${TMP}/origin.git"
git init -q --bare "${ORIGIN}"
git -C "${ORIGIN}" symbolic-ref HEAD refs/heads/main

SEED="${TMP}/seed"
git init -q "${SEED}"
(
    cd "${SEED}"
    git checkout -q -b main
    printf '## v0.1: Foundation\n' > ROADMAP.md
    git add ROADMAP.md
    git -c user.email=t@t -c user.name=t commit -q -m seed
    git remote add origin "${ORIGIN}"
    git push -q origin main
)

WORK="${TMP}/work"
git clone -q "${ORIGIN}" "${WORK}"
(cd "${WORK}" && git checkout -q -b feature)

BADORIGIN="${TMP}/work-badorigin"
git clone -q "${ORIGIN}" "${BADORIGIN}"
(
    cd "${BADORIGIN}"
    git checkout -q -b feature
    git remote set-url origin "${TMP}/does-not-exist.git"
    printf '## v0.1: Foundation\n' > ROADMAP.md
)

# --- Canned gh milestone-list responses (already --jq-filtered titles) -------

empty_titles="${TMP}/empty-titles.txt"
: > "${empty_titles}"

v03_titles="${TMP}/v03-titles.txt"
printf 'v0.3: Something Else\n' > "${v03_titles}"

v02_diff_title="${TMP}/v02-diff-title.txt"
printf 'v0.2: Different Title\n' > "${v02_diff_title}"

# --- Helpers -------------------------------------------------------------------

run_check() {
    # run_check <roadmap-content> <work-dir> [env-assignments...] -> sets OUT, RC
    local content="$1" workdir="$2"; shift 2
    printf '%s' "${content}" > "${workdir}/ROADMAP.md"
    OUT="$(cd "${workdir}" && env "$@" PATH="${MOCK_BIN}:${PATH}" python3 "${CHECK_SCRIPT}" . 2>&1)"
    RC=$?
}

run_claim() {
    # run_claim <title> [env-assignments...] -> sets OUT, RC
    local title="$1"; shift
    OUT="$(cd "${WORK}" && env "$@" PATH="${MOCK_BIN}:${PATH}" python3 "${CLAIM_SCRIPT}" "${title}" --major 0 2>&1)"
    RC=$?
}

# --- check_version_collision.py ------------------------------------------------

# Check 1: no new version headers vs origin/main -> OK, exit 0
run_check '## v0.1: Foundation
' "${WORK}"
if [[ ${RC} -eq 0 ]] && echo "${OUT}" | grep -q "OK: no new Roadmap Phase version headers introduced"; then
    record_pass "version-collision: no new headers -> OK (exit 0)"
else
    record_fail "version-collision: no-new-headers case wrong — rc=${RC}, out=${OUT:0:200}"
fi

# Check 2: v0.1 reused under a different local title -> Layer 1 collision, exit 1
run_check '## v0.1: Something Else
' "${WORK}"
if [[ ${RC} -eq 1 ]] && echo "${OUT}" | grep -q "COLLISION" \
        && echo "${OUT}" | grep -q "Something Else" && echo "${OUT}" | grep -q "Foundation"; then
    record_pass "version-collision: reused v0.1 under different title -> COLLISION (exit 1, Layer 1, no gh)"
else
    record_fail "version-collision: Layer 1 collision missed — rc=${RC}, out=${OUT:0:200}"
fi

# Check 3: new v0.2, no matching milestone -> OK, exit 0
run_check '## v0.1: Foundation
## v0.2: Widgets
' "${WORK}" VERSION_GUARD_REPO_SLUG=owner/repo MOCK_MILESTONES_FILE="${empty_titles}"
if [[ ${RC} -eq 0 ]] && echo "${OUT}" | grep -q "OK: 1 new version header(s), no collision detected"; then
    record_pass "version-collision: new v0.2, no milestone match -> OK (exit 0)"
else
    record_fail "version-collision: new-version-clean case wrong — rc=${RC}, out=${OUT:0:200}"
fi

# Check 4: new v0.2, milestone exists under a different title -> Layer 2 collision, exit 1
run_check '## v0.1: Foundation
## v0.2: Widgets
' "${WORK}" VERSION_GUARD_REPO_SLUG=owner/repo MOCK_MILESTONES_FILE="${v02_diff_title}"
if [[ ${RC} -eq 1 ]] && echo "${OUT}" | grep -q "COLLISION" \
        && echo "${OUT}" | grep -q "Widgets" && echo "${OUT}" | grep -q "Different Title"; then
    record_pass "version-collision: new v0.2, milestone collision -> COLLISION (exit 1, Layer 2)"
else
    record_fail "version-collision: Layer 2 collision missed — rc=${RC}, out=${OUT:0:200}"
fi

# Check 5: repo slug unresolvable (local-path origin, no override) -> degraded SKIP, exit 2
run_check '## v0.1: Foundation
## v0.2: Widgets
' "${WORK}"
if [[ ${RC} -eq 2 ]] && echo "${OUT}" | grep -q "SKIP: could not determine owner/repo from origin remote"; then
    record_pass "version-collision: unresolvable repo slug -> SKIP (exit 2), not a failure"
else
    record_fail "version-collision: degraded-coverage case wrong — rc=${RC}, out=${OUT:0:200}"
fi

# Check 6: git fetch failure (origin points nowhere) -> SKIP, exit 2
run_check '## v0.1: Foundation
' "${BADORIGIN}"
if [[ ${RC} -eq 2 ]] && echo "${OUT}" | grep -q "SKIP: could not fetch origin/main"; then
    record_pass "version-collision: git fetch failure -> SKIP (exit 2)"
else
    record_fail "version-collision: fetch-failure case wrong — rc=${RC}, out=${OUT:0:200}"
fi

# --- claim_roadmap_version.py ---------------------------------------------------

# Check 7: ROADMAP.md highest v0.1, no milestones -> claims v0.2
run_claim "Widgets" VERSION_GUARD_REPO_SLUG=owner/repo MOCK_MILESTONES_FILE="${empty_titles}"
if [[ ${RC} -eq 0 ]] && echo "${OUT}" | grep -q "Claimed v0.2"; then
    record_pass "claim-roadmap-version: no milestones -> claims v0.2 (roadmap-driven)"
else
    record_fail "claim-roadmap-version: roadmap-only claim wrong — rc=${RC}, out=${OUT:0:200}"
fi

# Check 8: milestones ahead of ROADMAP.md (v0.3 exists) -> claims v0.4, not v0.2
run_claim "Widgets" VERSION_GUARD_REPO_SLUG=owner/repo MOCK_MILESTONES_FILE="${v03_titles}"
if [[ ${RC} -eq 0 ]] && echo "${OUT}" | grep -q "Claimed v0.4"; then
    record_pass "claim-roadmap-version: milestone ahead of roadmap -> claims v0.4 (max, not roadmap-only)"
else
    record_fail "claim-roadmap-version: milestone-driven max wrong — rc=${RC}, out=${OUT:0:200}"
fi

# Check 9: create-race — first POST attempt collides, second succeeds -> claims v0.3, not a failure
counter9="${TMP}/counter9"
run_claim "Widgets" VERSION_GUARD_REPO_SLUG=owner/repo MOCK_MILESTONES_FILE="${empty_titles}" \
    MOCK_CREATE_FAIL_COUNT=1 MOCK_CREATE_COUNTER_FILE="${counter9}"
if [[ ${RC} -eq 0 ]] && echo "${OUT}" | grep -q "Claimed v0.3"; then
    record_pass "claim-roadmap-version: single create-race -> retries forward and succeeds (Claimed v0.3)"
else
    record_fail "claim-roadmap-version: retry-forward case wrong — rc=${RC}, out=${OUT:0:200}"
fi

# Check 10: create-race exhausts all attempts -> exit 1, names the attempt count
counter10="${TMP}/counter10"
run_claim "Widgets" VERSION_GUARD_REPO_SLUG=owner/repo MOCK_MILESTONES_FILE="${empty_titles}" \
    MOCK_CREATE_FAIL_COUNT=99 MOCK_CREATE_COUNTER_FILE="${counter10}"
if [[ ${RC} -eq 1 ]] && echo "${OUT}" | grep -q "5 consecutive collisions"; then
    record_pass "claim-roadmap-version: exhausted retries -> exit 1, names attempt count"
else
    record_fail "claim-roadmap-version: exhausted-retries case wrong — rc=${RC}, out=${OUT:0:200}"
fi
