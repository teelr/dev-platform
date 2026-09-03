#!/usr/bin/env bash
# tests/phase-tags/run.sh — regression suite for scripts/check-phase-tags.sh.
#
# Sourced contract: record_pass/record_fail/record_skip from
# tests/helpers/assert.sh; never exit-s (the orchestrator owns the exit code).
#
# Entirely offline against fixture repos built with `git init` + `git tag`. It
# must NEVER read dev-platform's own tags: otherwise cutting a real release
# would change this suite's result, which is the opposite of a regression test.
#
# The failure mode being guarded is silent. A roadmap form the parser does not
# match yields zero findings and reports clean — the exact shape of the v1.12
# bug, where a single-form regex checked nothing while looking healthy.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
CHECK="${REPO}/scripts/check-phase-tags.sh"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

TMP="$(mktemp -d /tmp/r3-phasetags.XXX)"
trap 'rm -rf "${TMP}"' EXIT

# mkrepo <dir> — a git repo with one commit, ready to tag.
mkrepo() {
    mkdir -p "$1"
    git -C "$1" init -q
    git -C "$1" config user.email t@t
    git -C "$1" config user.name t
    : > "$1/seed"
    git -C "$1" add -A >/dev/null 2>&1
    git -C "$1" commit -qm init >/dev/null 2>&1
}

# run_check <dir> [roadmap-path] — invoke from inside the fixture repo.
run_check() {
    local dir="$1" rp="${2:-ROADMAP.md}"
    ( cd "${dir}" && ROADMAP_PATH="${rp}" bash "${CHECK}" 2>&1 )
}

# --- 1. syntax + help ---------------------------------------------------------
if bash -n "${CHECK}" 2>/dev/null; then
    record_pass "phase-tags: bash syntax clean"
else
    record_fail "phase-tags: bash syntax error"
fi

hout="$(bash "${CHECK}" --help 2>&1)"; hrc=$?
if [[ ${hrc} -eq 0 ]] && grep -q "check-phase-tags.sh" <<<"${hout}"; then
    record_pass "phase-tags: --help exits 0 and prints usage"
else
    record_fail "phase-tags: --help (rc=${hrc})"
fi

# --- 2. every complete phase tagged -> clean ----------------------------------
CLEAN="${TMP}/clean"
mkrepo "${CLEAN}"
cat > "${CLEAN}/ROADMAP.md" <<'MD'
# Roadmap

- **v1.1: First Phase** *(complete — 2026-01-01, `tasks/a-spec.md`)* — done.
- **v1.2: Second Phase** *(complete — 2026-01-02, `tasks/b-spec.md`)* — done.
MD
git -C "${CLEAN}" tag v1.1
git -C "${CLEAN}" tag v1.2
out="$(run_check "${CLEAN}")"; rc=$?
if [[ ${rc} -eq 0 ]] && grep -q "all 2 complete phase(s) tagged" <<<"${out}"; then
    record_pass "phase-tags: fully tagged roadmap exits 0"
else
    record_fail "phase-tags: clean case (rc=${rc}, out: ${out})"
fi

# --- 3. a complete phase with no tag is found, named -------------------------
git -C "${CLEAN}" tag -d v1.2 >/dev/null 2>&1
out="$(run_check "${CLEAN}")"; rc=$?
if [[ ${rc} -eq 1 ]] && grep -q "MISSING TAG  v1.2" <<<"${out}" \
    && grep -q "Second Phase" <<<"${out}"; then
    record_pass "phase-tags: an untagged complete phase exits 1, naming version and title"
else
    record_fail "phase-tags: missing-tag case (rc=${rc}, out: ${out})"
fi

# --- 4. DUAL-FORM REGRESSION --------------------------------------------------
# The same missing tag must be found in the heading form too. Matching only the
# list form would report kermit-v3's entire roadmap as clean while checking
# nothing — the v1.12 bug, repeated.
HEAD_FORM="${TMP}/heading"
mkrepo "${HEAD_FORM}"
cat > "${HEAD_FORM}/ROADMAP.md" <<'MD'
# Roadmap

## v0.194: Tagged Phase *(complete — 2026-01-01)*

Body text.

## v0.195: Untagged Phase *(complete — 2026-01-02)*

Body text.
MD
git -C "${HEAD_FORM}" tag v0.194
out="$(run_check "${HEAD_FORM}")"; rc=$?
if [[ ${rc} -eq 1 ]] && grep -q "MISSING TAG  v0.195" <<<"${out}" \
    && ! grep -q "v0.194" <<<"${out}"; then
    record_pass "phase-tags: heading-form roadmap is parsed (dual-form regression)"
else
    record_fail "phase-tags: heading form (rc=${rc}, out: ${out})"
fi

# --- 5. an in-flight (not complete) untagged phase is NOT a finding -----------
INFLIGHT="${TMP}/inflight"
mkrepo "${INFLIGHT}"
cat > "${INFLIGHT}/ROADMAP.md" <<'MD'
# Roadmap

- **v1.1: Shipped** *(complete — 2026-01-01)* — done.
- **v1.2: Planned** — not started, no completion marker.
MD
git -C "${INFLIGHT}" tag v1.1
out="$(run_check "${INFLIGHT}")"; rc=$?
if [[ ${rc} -eq 0 ]] && ! grep -q "v1.2" <<<"${out}"; then
    record_pass "phase-tags: an incomplete phase without a tag is not flagged"
else
    record_fail "phase-tags: in-flight case (rc=${rc}, out: ${out})"
fi

# --- 6. ROADMAP_PATH override -------------------------------------------------
CUSTOM="${TMP}/custom"
mkrepo "${CUSTOM}"
mkdir -p "${CUSTOM}/docs"
cat > "${CUSTOM}/docs/roadmap.md" <<'MD'
# Roadmap

- **v2.1: Custom Path Phase** *(complete — 2026-01-01)* — done.
MD
out="$(run_check "${CUSTOM}" "docs/roadmap.md")"; rc=$?
if [[ ${rc} -eq 1 ]] && grep -q "MISSING TAG  v2.1" <<<"${out}"; then
    record_pass "phase-tags: ROADMAP_PATH override reads the custom path"
else
    record_fail "phase-tags: ROADMAP_PATH override (rc=${rc}, out: ${out})"
fi

# The default path must be unaffected — no ROADMAP.md at the root here.
out="$(run_check "${CUSTOM}")"; rc=$?
if [[ ${rc} -eq 0 ]] && grep -q "nothing to check" <<<"${out}"; then
    record_pass "phase-tags: a missing roadmap is a clean skip, not a crash or false pass"
else
    record_fail "phase-tags: missing-roadmap case (rc=${rc}, out: ${out})"
fi

# --- 7. outside a git repo -> exit 2, not a false clean ----------------------
NOGIT="${TMP}/nogit"
mkdir -p "${NOGIT}"
out="$( cd "${NOGIT}" && bash "${CHECK}" 2>&1 )"; rc=$?
if [[ ${rc} -eq 2 ]] && grep -q "not a git repository" <<<"${out}"; then
    record_pass "phase-tags: outside a git repo exits 2"
else
    record_fail "phase-tags: non-repo case (rc=${rc}, out: ${out})"
fi
