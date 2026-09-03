#!/usr/bin/env bash
# scripts/check-phase-tags.sh — flag Roadmap Phases marked COMPLETE that have no
# matching git tag.
#
# This is the mechanical backstop for the release-tag half of the standard
# post-merge Roadmap-Phase-completion step (see /home/rich/dev/CLAUDE.md). Its
# sibling check-phase-milestones.sh (v1.10) does the same job for milestones,
# and that pairing is why milestones have never drifted. Tagging had no such
# backstop: it was documented only in docs/GLOSSARY.md, a reference doc nobody
# executes from, and stopped after v1.13 — leaving v1.14 through v1.25
# unpinnable — freezing every consumer at @v1.12 or @v1.13, the newest tags
# that existed, because a tag nobody cut is one nobody can pin.
#
# WHY IT MATTERS: the tag is the only identifier a consumer can pin
# (taxonomy-check.yml@v1.26). A phase with no tag is a phase no consumer can
# depend on, however complete it is.
#
# WHAT IT CATCHES: a ROADMAP entry carrying the *(complete — ...)* marker with
# no git tag of the same name.
#
# WHAT IT CANNOT CATCH: a tag that exists but points at the wrong commit, and a
# phase whose ROADMAP entry was never marked complete (indistinguishable from
# in-flight work, so flagging it would fire on every planned phase). Do not read
# a clean result as "every phase is correctly released."
#
# NOT wired into gate_fast.sh: a diagnostic, same rationale as
# check-phase-milestones.sh and check-comms-delivery.sh. Only its offline test
# suite (tests/phase-tags/) is gate-discovered.
#
# Usage:
#   ./scripts/check-phase-tags.sh          # check the repo containing $PWD
#   ./scripts/check-phase-tags.sh --help
#
# Set ROADMAP_PATH (relative to the repo root, e.g. "docs/roadmap.md") if the
# roadmap does not live at the default ROADMAP.md — same override its siblings
# honour (v1.13).
#
# Exit codes:
#   0  clean — every complete phase has a tag (or no roadmap to check)
#   1  one or more complete phases are missing tags (action: cut them)
#   2  error — bad args, or not a git repository

set -uo pipefail

usage() {
    cat <<'HELP'
check-phase-tags.sh — flag complete Roadmap Phases with no release tag

  ./scripts/check-phase-tags.sh     check the repo containing $PWD
  --help                            this text

The tag is the only identifier a consumer can pin, so a complete phase without
one is unreachable to every consumer. Cutting it is a standard post-merge
sub-step; this is the backstop.

Env: ROADMAP_PATH (default ROADMAP.md)

Exit: 0 clean, 1 missing tags, 2 error
HELP
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    "") ;;
    *) echo "check-phase-tags: unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: not a git repository" >&2
    exit 2
fi

ROADMAP_PATH="${ROADMAP_PATH:-ROADMAP.md}"
ROOT="$(git rev-parse --show-toplevel)"
ROADMAP="${ROOT}/${ROADMAP_PATH}"

if [[ ! -f "${ROADMAP}" ]]; then
    echo "check-phase-tags: no ${ROADMAP_PATH} — nothing to check"
    exit 0
fi

# Parse BOTH roadmap forms. dev-platform uses the list form and kermit-v3 the
# heading form; matching only one reports clean while checking nothing, which is
# precisely the bug v1.12 had to come back and fix.
#   - **v1.25: Title** *(complete — 2026-09-03, ...)*
#   ## v0.195: Title *(complete — ...)*
# "complete" is required: a planned or in-flight phase with no tag is correct,
# not a finding.
missing=0
checked=0
while IFS= read -r line; do
    [[ "${line}" =~ ^(-[[:space:]]\*\*|##[[:space:]])(v[0-9]+\.[0-9]+[a-z]?):[[:space:]] ]] || continue
    version="${BASH_REMATCH[2]}"
    [[ "${line}" == *"(complete"* ]] || continue
    checked=$((checked + 1))
    if git tag --list "${version}" | grep -qx "${version}"; then
        continue
    fi
    if [[ ${missing} -eq 0 ]]; then
        echo "check-phase-tags: complete Roadmap Phase(s) with NO release tag —"
        echo "  consumers cannot pin these; cut each at the phase's merge commit."
        echo ""
    fi
    # Title: text after "<version>: " up to the completion marker or bold close.
    title="${line#*"${version}": }"
    title="${title%%\**}"
    title="${title%"${title##*[![:space:]]}"}"
    printf '  MISSING TAG  %-8s %s\n' "${version}" "${title}"
    missing=$((missing + 1))
done < "${ROADMAP}"

if [[ ${missing} -gt 0 ]]; then
    echo ""
    echo "check-phase-tags: ${missing} of ${checked} complete phase(s) untagged."
    echo "  gh release create <version> --target <merge-sha>"
    exit 1
fi

echo "check-phase-tags: all ${checked} complete phase(s) tagged."
exit 0
