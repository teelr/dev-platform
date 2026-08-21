#!/usr/bin/env bash
# check_duplicate_numbering.sh
#
# Constitutional check for the shared "Ask #N" / "L#" numbering conventions
# used by Kermit-harness-consumer projects (kermit-v3, Keystone, kermit-pa)
# in their tasks/HARNESS_HANDOFF_QUEUE.md and tasks/lessons.md files. Two
# Roadmap Phases in flight at once can each independently pick the next
# free number for a new queue row or lessons entry; git merges the text
# cleanly (different line positions), leaving a silent duplicate nothing
# caught until a human noticed. See teelr/dev-platform#75.
#
# Two independent scan passes, each a graceful no-op (not an error) when its
# target file is absent or doesn't use the convention at all:
#
# (1) Handoff-queue tables: any markdown table whose header row's first
#     column is literally "#". A queue file legitimately has SEVERAL such
#     tables (Pending, Migrated, ...), each independently numbered — the
#     same value repeating across two DIFFERENT tables is fine and must
#     NOT be flagged; only a repeat within the SAME table's data rows is a
#     violation. Table scope resets at every new "| # | ... |" header row
#     and ends at the first line that doesn't start with "|".
#
# (2) Lessons headers: "## L<N> — <title>" headings, checked for duplicate
#     <N> globally across the whole file (no per-table scoping — lessons.md
#     is one running numbered list, not independently-numbered tables).
#
# Usage:
#   ./check_duplicate_numbering.sh                   # check ./tasks/
#   ./check_duplicate_numbering.sh /path/to/project   # check <path>/tasks/
#
# Override the default file paths (relative to the project root) if a
# project's layout differs from the kermit-v3/Keystone/kermit-pa convention:
#   HANDOFF_QUEUE_PATH="tasks/HARNESS_HANDOFF_QUEUE.md"
#   LESSONS_PATH="tasks/lessons.md"
#
# Exit codes:
#   0 — no duplicates found (includes "file absent" / "convention unused")
#   1 — at least one duplicate found

set -uo pipefail

PROJECT_ROOT="${1:-.}"
: "${HANDOFF_QUEUE_PATH:=tasks/HARNESS_HANDOFF_QUEUE.md}"
: "${LESSONS_PATH:=tasks/lessons.md}"

QUEUE_FILE="${PROJECT_ROOT}/${HANDOFF_QUEUE_PATH}"
LESSONS_FILE="${PROJECT_ROOT}/${LESSONS_PATH}"

found_violations=0

# ---------------------------------------------------------------------------
# Pass (1): handoff-queue tables — duplicate "#" column values within ONE table
# ---------------------------------------------------------------------------
check_queue_file() {
    local f="$1"
    if [[ ! -f "$f" ]]; then
        echo "check_duplicate_numbering: no ${HANDOFF_QUEUE_PATH} — skipping queue-table check"
        return 0
    fi

    local -A seen_line=()
    local in_table=0 table_idx=0 table_count=0 lineno=0 violations_here=0

    while IFS= read -r line; do
        lineno=$((lineno + 1))

        if [[ "$line" != \|* ]]; then
            in_table=0
            continue
        fi

        local rest="${line#|}"
        local first="${rest%%|*}"
        first="$(echo "$first" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        if [[ "$first" == "#" ]]; then
            table_idx=$((table_idx + 1))
            table_count=$((table_count + 1))
            in_table=1
            continue
        fi

        [[ "$in_table" -eq 1 ]] || continue
        [[ "$first" =~ ^:?-+:?$ ]] && continue   # separator row (---, :---, ---: , -)
        [[ -z "$first" ]] && continue

        local key="${table_idx}:${first}"
        if [[ -n "${seen_line[$key]:-}" ]]; then
            echo "  ${f#"$PROJECT_ROOT"/}:${lineno}: duplicate '#${first}' in table #${table_idx} (first seen at line ${seen_line[$key]})"
            violations_here=1
        else
            seen_line[$key]="$lineno"
        fi
    done < "$f"

    if [[ "$table_count" -eq 0 ]]; then
        echo "check_duplicate_numbering: ${HANDOFF_QUEUE_PATH} has no '#'-headed tables — skipping queue-table check"
        return 0
    fi

    if [[ "$violations_here" -eq 1 ]]; then
        echo "check_duplicate_numbering: duplicate row numbers in ${f#"$PROJECT_ROOT"/}"
        return 1
    fi

    echo "check_duplicate_numbering: ${HANDOFF_QUEUE_PATH} — ${table_count} table(s), no duplicate row numbers"
    return 0
}

if ! check_queue_file "$QUEUE_FILE"; then
    found_violations=1
fi

# ---------------------------------------------------------------------------
# Pass (2): lessons.md "## L<N> —" headers — duplicate <N> across the WHOLE file
# ---------------------------------------------------------------------------
check_lessons_file() {
    local f="$1"
    if [[ ! -f "$f" ]]; then
        echo "check_duplicate_numbering: no ${LESSONS_PATH} — skipping lessons-L# check"
        return 0
    fi

    local -A seen_line=()
    local lineno=0 header_count=0 violations_here=0

    while IFS= read -r line; do
        lineno=$((lineno + 1))
        if [[ "$line" =~ ^##[[:space:]]+L([0-9]+)([[:space:]]|$) ]]; then
            local key="${BASH_REMATCH[1]}"
            header_count=$((header_count + 1))
            if [[ -n "${seen_line[$key]:-}" ]]; then
                echo "  ${f#"$PROJECT_ROOT"/}:${lineno}: duplicate 'L${key}' header (first seen at line ${seen_line[$key]})"
                violations_here=1
            else
                seen_line[$key]="$lineno"
            fi
        fi
    done < "$f"

    if [[ "$header_count" -eq 0 ]]; then
        echo "check_duplicate_numbering: ${LESSONS_PATH} has no '## L<N>' headers — skipping lessons-L# check"
        return 0
    fi

    if [[ "$violations_here" -eq 1 ]]; then
        echo "check_duplicate_numbering: duplicate lesson numbers in ${f#"$PROJECT_ROOT"/}"
        return 1
    fi

    echo "check_duplicate_numbering: ${LESSONS_PATH} — ${header_count} L# header(s), no duplicates"
    return 0
}

if ! check_lessons_file "$LESSONS_FILE"; then
    found_violations=1
fi

if [[ "$found_violations" -ne 0 ]]; then
    echo ""
    echo "Fix: renumber the later-added row/entry to the next free number,"
    echo "  updating every cross-reference to the old number in the same commit."
    exit 1
fi

echo "check_duplicate_numbering: all checks clean"
exit 0
