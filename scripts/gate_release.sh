#!/usr/bin/env bash
# scripts/gate_release.sh — dev-platform release gate. Runs gate_fast.sh,
# then the fleet-bookkeeping checks gate_fast.sh deliberately excludes
# (network calls, gh auth, or projects/ dependence), then a fresh-clone
# install/verify round trip. Run before any minor/major version bump —
# see CLAUDE.md's "Gate Tiers" and Roadmap-Phase-completion post-merge step.
#
# NOT wired into CI: makes gh network calls and clones the repo locally.
# Run this by hand (or via /gate release) before cutting a release tag.
#
# Usage: ./scripts/gate_release.sh
# Runtime: dominated by gate_fast.sh (~15-50s) + gh API calls (~5-15s) +
# the fresh-clone round trip (~5-10s).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export _GATE_COUNTS_FILE
_GATE_COUNTS_FILE="$(mktemp /tmp/gate-release-counts.XXXXXX)"

# Single cleanup function covering every scratch path this script creates,
# including CLONE_DIR/FAKE_HOME (set later, in the fresh-clone step below) —
# the function only runs at exit, once everything is set, so declaring it
# once here (rather than re-declaring `trap ... EXIT` a second time further
# down) can't silently drop a cleanup target the way two separate trap
# strings could.
_cleanup() {
    rm -f "${_GATE_COUNTS_FILE:-}"
    rm -rf "${CLONE_DIR:-}" "${FAKE_HOME:-}"
}
trap _cleanup EXIT

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

START=$(date +%s)
echo "=== gate release ==="
echo ""
echo "--- gate fast (foundation) ---"

# gate_fast.sh prints its own full PASS/FAIL/SKIP detail and exits non-zero
# on any FAIL. Treated here as ONE named check — its own internal counts
# are already proven correct by its own summary line; re-parsing them would
# duplicate that, not add coverage.
if bash "${REPO}/scripts/gate_fast.sh"; then
    record_pass "gate fast (constitutional checks + test suites)"
else
    record_fail "gate fast (constitutional checks + test suites — see output above)"
fi

echo ""
echo "--- fleet bookkeeping (release-only: gh network calls) ---"

# check-phase-milestones.sh — 0 clean, 1 flagged milestone(s) found, 2 setup
# error (missing gh/jq, unresolvable repo, fetch failure).
(cd "${REPO}" && bash scripts/check-phase-milestones.sh)
milestones_rc=$?
case ${milestones_rc} in
    0) record_pass "phase milestones (no open-but-complete milestones)" ;;
    1) record_fail "phase milestones (open-but-complete milestone found — close it)" ;;
    *) record_fail "phase milestones (check-phase-milestones.sh setup error, exit ${milestones_rc})" ;;
esac

# check-phase-tags.sh — 0 clean, 1 untagged complete phase(s), 2 setup error.
(cd "${REPO}" && bash scripts/check-phase-tags.sh)
tags_rc=$?
case ${tags_rc} in
    0) record_pass "phase tags (every complete phase tagged)" ;;
    1) record_fail "phase tags (complete phase missing its release tag — cut it)" ;;
    *) record_fail "phase tags (check-phase-tags.sh setup error, exit ${tags_rc})" ;;
esac

# check-migration-coverage.sh — 0 every source parses/migrated, 1 a source
# fails to parse, 2 setup error (jq absent, registry missing, bad arg).
#
# KNOWN, VERIFIED, NOT-YET-FIXED: as of this writing kermit's lessons.md and
# planning.md both fail to parse (21 + 9 problems) — this correctly reports
# exit 1 today. Fixing kermit's files is out of scope for dev-platform (Scope
# rule: no writes under projects/) — see the spec's Design Philosophy.
(cd "${REPO}" && bash scripts/check-migration-coverage.sh)
migration_rc=$?
case ${migration_rc} in
    0) record_pass "migration coverage (every consumer source parses or is migrated)" ;;
    1) record_fail "migration coverage (a consumer source fails to parse — see table above)" ;;
    *) record_fail "migration coverage (check-migration-coverage.sh setup error, exit ${migration_rc})" ;;
esac

echo ""
echo "--- fresh-clone install/verify round trip (release-only) ---"

# tests/install/run.sh (gate-fast tier) already round-trips install.sh /
# verify.sh / uninstall.sh against a sandboxed $HOME — but it runs directly
# against this already-checked-out working tree. A script that silently
# depends on an untracked scratch file present in every real working copy
# would still pass there. A genuine `git clone` excludes anything
# gitignored, closing that specific gap — three prior Consumer-Audit
# gitignore-trap incidents are exactly this failure mode (CLAUDE.md).
CLONE_DIR="$(mktemp -d /tmp/gate-release-clone.XXXXXX)"
FAKE_HOME="$(mktemp -d /tmp/gate-release-home.XXXXXX)"

if git clone --quiet "${REPO}" "${CLONE_DIR}" >/dev/null 2>&1; then
    # A local clone's origin points at the local path, not GitHub —
    # verify.sh's remote-verify step (scripts/verify-remotes.sh) checks the
    # real origin against monitoring/remotes.json's expected URL and would
    # always mismatch otherwise (verified: it did, before this fix). Fix the
    # clone's origin to what a genuine GitHub clone would have —
    # `remote set-url` is metadata-only, no network call, so this stays
    # fully offline. Read the expected URL from the registry rather than
    # hardcoding it, so this can't drift from monitoring/remotes.json.
    _expected_origin="$(jq -r '.[] | select(.path == ".") | .remote_url' "${REPO}/monitoring/remotes.json" 2>/dev/null)"
    if [[ -n "${_expected_origin}" && "${_expected_origin}" != "null" ]]; then
        git -C "${CLONE_DIR}" remote set-url origin "${_expected_origin}"
    fi
    if HOME="${FAKE_HOME}" bash "${CLONE_DIR}/scripts/install.sh" all >/dev/null 2>&1 \
            && HOME="${FAKE_HOME}" bash "${CLONE_DIR}/scripts/verify.sh" >/dev/null 2>&1; then
        record_pass "fresh clone: install.sh all + verify.sh round trip"
    else
        record_fail "fresh clone: install.sh/verify.sh failed against a genuine clone"
    fi
else
    record_fail "fresh clone: git clone of ${REPO} failed"
fi

echo ""
echo "=== summary ==="
END=$(date +%s)

total_pass=$(grep -c "^PASS$" "${_GATE_COUNTS_FILE}" 2>/dev/null); total_pass=${total_pass:-0}
total_fail=$(grep -c "^FAIL$" "${_GATE_COUNTS_FILE}" 2>/dev/null); total_fail=${total_fail:-0}
total_skip=$(grep -c "^SKIP$" "${_GATE_COUNTS_FILE}" 2>/dev/null); total_skip=${total_skip:-0}

echo "  ${total_pass} PASS  ${total_fail} FAIL  ${total_skip} SKIP  ($((END - START))s)"

if [[ ${total_fail} -gt 0 ]]; then
    echo ""
    echo "GATE RELEASE: FAIL"
    exit 1
fi
echo "GATE RELEASE: PASS"
