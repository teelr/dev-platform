#!/usr/bin/env bash
# scripts/sync-milestones.sh — mirror ROADMAP.md entries to GitHub Milestones.
#
# Idempotent: each run computes the diff between ROADMAP.md and the repo's
# current Milestone list, then either reports the plan (dry-run, default)
# or applies it (--apply). Closed-and-released Milestones (the ones backing
# shipped release tags) are NEVER reopened or mutated.
#
# Usage:
#   ./scripts/sync-milestones.sh                       # dry-run against teelr/dev-platform
#   ./scripts/sync-milestones.sh --apply               # actually create/update
#   ./scripts/sync-milestones.sh --repo OWNER/REPO     # different repo
#   ./scripts/sync-milestones.sh --file <ROADMAP.md>   # different source file (tests)
#   ./scripts/sync-milestones.sh --help
#
# Requires: gh CLI authenticated, jq, awk.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROADMAP="${REPO_ROOT}/ROADMAP.md"
GH_REPO="teelr/dev-platform"
APPLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply) APPLY=1 ;;
        --repo)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --repo requires an argument (owner/repo)" >&2; exit 1; }
            GH_REPO="$1"
            ;;
        --file)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --file requires an argument (path to ROADMAP.md)" >&2; exit 1; }
            ROADMAP="$1"
            ;;
        --help|-h)
            cat <<'HELP'
scripts/sync-milestones.sh — sync ROADMAP.md entries to GitHub Milestones.

Modes:
  (default)   Dry-run: print the plan, make no API changes.
  --apply     Actually create/update Milestones.

Options:
  --repo <owner/repo>   Operate against a different repo (default: teelr/dev-platform).
  --file <path>         Read entries from a non-default ROADMAP.md (for tests).
  --help, -h            Show this help.

Idempotency:
  Each run computes the diff between ROADMAP.md and the repo's Milestone list:
    CREATE   ROADMAP entry has no matching Milestone — create it.
    UPDATE   Milestone exists but state or description differs — patch.
    SKIP     Milestone matches ROADMAP exactly — no-op.
    LOCKED   Milestone is already closed — leave untouched (release tag exists).

  Re-running with --apply after a successful run yields all SKIPs and LOCKEDs.
HELP
            exit 0
            ;;
        *) echo "ERROR: unknown arg: $1" >&2; exit 1 ;;
    esac
    shift
done

command -v gh >/dev/null || { echo "ERROR: gh CLI required (https://cli.github.com)" >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq required" >&2; exit 1; }
[[ -f "${ROADMAP}" ]] || { echo "ERROR: ROADMAP.md not found at ${ROADMAP}" >&2; exit 1; }

# Parse ROADMAP.md entries: lines like
#   - **v0.5: Monitoring** *(complete — 2026-05-11, `tasks/...`)* — first phase…
#
# Extract: title (the bold-wrapped "v<N>.<N>[a-z]?: <Title>"), state
# (closed if the italicized block contains "complete", open otherwise), and
# description (rest of the bullet line, used as the Milestone description).
#
# Output: tab-separated "title<TAB>state<TAB>description" per matched line.
parse_entries() {
    awk '
        /^- \*\*v[0-9]+\.[0-9]+[a-z]?: / {
            line = $0
            # Title: between leading "- **" and the closing "**"
            title = line
            sub(/^- \*\*/, "", title)
            sub(/\*\* .*/, "", title)

            # State: detect "(complete " or "(complete —" anywhere in line
            state = "open"
            if (line ~ /\*\(complete[ —]/) state = "closed"

            # Description: strip the leading "- **title** " then the trailing
            # *(...)* italicized status block, then leading " — " separator.
            # ASSUMES: ROADMAP description prose contains no '*' characters
            # (no inline **bold**, *emphasis*, etc. after the italicized
            # status block). The [^*]* sub will truncate at the first stray
            # asterisk if the convention breaks — flag here if it ever does.
            desc = line
            sub(/^- \*\*[^*]+\*\* /, "", desc)
            sub(/\*\([^*]*\)\*[ ]*—?[ ]*/, "", desc)
            # Truncate to 500 chars (GitHub Milestone description hard limit
            # is 1024 — leave headroom for future prose growth).
            # NOTE: awk substr is byte-bounded; mostly-ASCII descriptions
            # tolerate this, but a description with many em-dashes (3 bytes
            # each in UTF-8) hitting the limit could break a codepoint.
            # Acceptable risk given current ROADMAP entries.
            if (length(desc) > 500) desc = substr(desc, 1, 497) "..."

            print title "\t" state "\t" desc
        }
    ' "${ROADMAP}"
}

# Fetch all existing Milestones (state=all, per_page=100 — well above the
# foreseeable Roadmap-Phase count). Emit one JSON object per line for
# downstream jq-by-title lookup.
fetch_milestones() {
    gh api "repos/${GH_REPO}/milestones?state=all&per_page=100" \
        --jq '.[] | {number, title, state, description}'
}

existing="$(fetch_milestones | jq -s .)"

# Plan / execution loop.
create_count=0
update_count=0
skip_count=0
locked_count=0

echo "Syncing ROADMAP.md → Milestones at ${GH_REPO}"
echo ""

while IFS=$'\t' read -r title state desc; do
    [[ -z "${title}" ]] && continue

    # Lookup by title.
    match="$(echo "${existing}" | jq --arg t "${title}" '.[] | select(.title == $t)')"
    existing_number="$(echo "${match}" | jq -r '.number // empty')"
    existing_state="$(echo "${match}" | jq -r '.state // empty')"
    existing_desc="$(echo "${match}" | jq -r '.description // empty')"

    if [[ -z "${existing_number}" ]]; then
        action="CREATE"
        create_count=$((create_count + 1))
        if [[ ${APPLY} -eq 1 ]]; then
            gh api "repos/${GH_REPO}/milestones" -X POST \
                -f title="${title}" -f state="${state}" -f description="${desc}" >/dev/null
        fi
    elif [[ "${existing_state}" == "closed" ]]; then
        # Closed Milestones back released tags — NEVER mutate. Edit history
        # goes through `gh release edit`, not here.
        action="LOCKED (already closed)"
        locked_count=$((locked_count + 1))
    elif [[ "${existing_state}" == "${state}" && "${existing_desc}" == "${desc}" ]]; then
        action="SKIP (in sync)"
        skip_count=$((skip_count + 1))
    else
        action="UPDATE (state=${state})"
        update_count=$((update_count + 1))
        if [[ ${APPLY} -eq 1 ]]; then
            gh api "repos/${GH_REPO}/milestones/${existing_number}" -X PATCH \
                -f state="${state}" -f description="${desc}" >/dev/null
        fi
    fi
    echo "  ${action}: ${title}"
done < <(parse_entries)

echo ""
echo "Summary: ${create_count} create, ${update_count} update, ${skip_count} skip, ${locked_count} locked"
if [[ ${APPLY} -eq 0 ]]; then
    echo ""
    echo "Dry-run — no changes made. Re-run with --apply to commit."
fi
