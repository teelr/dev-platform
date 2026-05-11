#!/usr/bin/env bash
# check_spec_taxonomy.sh
#
# Constitutional check enforcing the Phase + Change taxonomy locked in
# /home/rich/dev/CLAUDE.md across every dev project.
#
# Two scan passes:
#
# (1) Spec-structural: walks `tasks/*-spec.md` for old vocabulary at the
#     *spec-structural* level. A killed-term header (Task/Step/Item/...) is
#     flagged ONLY when it appears under a `## Phase N: ...` parent — that is
#     the spec-implementation context the taxonomy governs. Workflow-content
#     sections (e.g. `## gate fast — Pre-commit Gate` describing what a runner
#     does sequentially) may legitimately use `### Step N: ...` and are not
#     flagged.  Top-level `## Section N` headers are always flagged because
#     Section is a killed Phase synonym at every level.
#
# (2) Roadmap-level (added v0.7): scans `ROADMAP.md` and `planning.md` for
#     non-conforming Roadmap Phase headers. The locked rule (dev/CLAUDE.md →
#     Development Terminology) requires `v<MAJOR>.<MINOR>[<letter>]: <Title>`
#     for every Roadmap Phase. Killed prefixes flagged: `R<N>:` (legacy form
#     migrated 2026-05-11), `Sprint X:`, `Stage Y:`, quarter buckets like
#     `Q2-2026:` or `2026Q2:`.
#
# Usage:
#   ./check_spec_taxonomy.sh                       # check ./tasks/
#   ./check_spec_taxonomy.sh /path/to/project      # check /path/to/project/tasks/
#
# Exit codes:
#   0 — all spec files conform
#   1 — at least one spec uses killed terminology in spec-structural context
#   2 — usage / setup error

set -euo pipefail

PROJECT_ROOT="${1:-.}"
TASKS_DIR="$PROJECT_ROOT/tasks"

if [[ ! -d "$TASKS_DIR" ]]; then
  echo "check_spec_taxonomy: no tasks/ directory at $TASKS_DIR — skipping"
  exit 0
fi

# Killed terms that are illegal as ### Change-level headers when nested under
# a ## Phase N parent. Requires the trailing colon to avoid false positives
# on prose headings like "### Step 1 of the recipe" — the spec-structural form
# is always `### Step N: <title>`.
KILLED_CHANGE_RE='^### (Task|Step|Item|Sprint|Stage|Iteration|Milestone|Group|Epic) [0-9]+(\.[0-9]+)?:'

# Killed terms always illegal at the ## level (Phase synonyms). Same
# colon-terminator requirement.
KILLED_PHASE_RE='^## (Section|Sprint|Stage|Iteration|Milestone|Group|Epic) [0-9]+:'

found_violations=0
spec_count=0

while IFS= read -r -d '' spec; do
  spec_count=$((spec_count + 1))
  rel="${spec#$PROJECT_ROOT/}"
  current_phase_ctx=0
  file_violations=()

  while IFS= read -r line; do
    # Track ## parent: are we under a Phase N section?
    if [[ "$line" =~ ^##[[:space:]] ]]; then
      if [[ "$line" =~ ^##[[:space:]]Phase[[:space:]][0-9] ]]; then
        current_phase_ctx=1
      else
        current_phase_ctx=0
      fi
      # Always flag killed Phase-level synonyms.
      if [[ "$line" =~ $KILLED_PHASE_RE ]]; then
        file_violations+=("$line")
      fi
      continue
    fi

    # Flag killed Change-level headers ONLY when under a Phase parent.
    if [[ "$current_phase_ctx" -eq 1 && "$line" =~ $KILLED_CHANGE_RE ]]; then
      file_violations+=("$line")
    fi
  done < "$spec"

  if [[ ${#file_violations[@]} -gt 0 ]]; then
    if [[ "$found_violations" -eq 0 ]]; then
      echo "check_spec_taxonomy: spec files using killed terminology"
      echo "  Locked taxonomy: ## Phase N + ### Change N (continuous numbering)"
      echo "  Standard: https://github.com/teelr/dev-platform/blob/main/CLAUDE.md (Development Terminology)"
      echo ""
    fi
    found_violations=1
    echo "  $rel"
    for v in "${file_violations[@]}"; do
      echo "    $v"
    done
  fi
done < <(find "$TASKS_DIR" -name "*-spec.md" -type f \
            ! -path "*/_archive/*" \
            ! -path "*/archive/*" \
            -print0)

# ---------------------------------------------------------------------------
# Scan pass (2): Roadmap-level — ROADMAP.md + planning.md
# ---------------------------------------------------------------------------
# Roadmap Phase headers MUST match v<MAJOR>.<MINOR>[<letter>]: <Title>.
# The KILLED regex flags the wrong taxonomies we want to keep out of those
# files — legacy R<N>: prefix, Sprint X:, Stage Y:, quarter buckets.
#
# Both forms count as headers: `- **<title>**` (markdown list item) and
# `## <title>` (heading). Lines that don't start with either pattern are
# ignored — historical mentions of "R3" inside a description paragraph are
# fine; only the heading position matters.
KILLED_ROADMAP_RE='^(- \*\*|## )(R[0-9]+(\.[0-9]+)?[a-z]?:|Sprint [A-Z0-9]+:|Stage [A-Z0-9]+:|Q[0-9]+-[0-9]+:|[0-9]+Q[0-9]+:)'

found_roadmap_violations=0

scan_roadmap_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local violations=()
  while IFS= read -r line; do
    if [[ "$line" =~ $KILLED_ROADMAP_RE ]]; then
      violations+=("$line")
    fi
  done < "$f"
  if [[ ${#violations[@]} -gt 0 ]]; then
    if [[ "$found_roadmap_violations" -eq 0 ]]; then
      echo ""
      echo "check_spec_taxonomy: Roadmap Phase headers using killed terminology"
      echo "  Required format: v<MAJOR>.<MINOR>[<letter>]: <Title>"
      echo "  Standard: https://github.com/teelr/dev-platform/blob/main/CLAUDE.md (Development Terminology)"
      echo ""
    fi
    found_roadmap_violations=1
    echo "  ${f#$PROJECT_ROOT/}"
    for v in "${violations[@]}"; do
      echo "    $v"
    done
  fi
}

scan_roadmap_file "$PROJECT_ROOT/ROADMAP.md"
scan_roadmap_file "$PROJECT_ROOT/planning.md"

if [[ "$found_roadmap_violations" -eq 1 ]]; then
  found_violations=1
fi

if [[ "$found_violations" -ne 0 ]]; then
  echo ""
  echo "Fix: rename headers per the locked taxonomy."
  echo "  Spec-structural killed terms: Section, Task, Step, Item, Sprint,"
  echo "    Stage, Iteration, Milestone, Group, Epic."
  echo "  Roadmap-level killed prefixes: R<N>:, Sprint X:, Stage Y:, Q<N>-<YYYY>:."
  echo "  Workflow-runner sections under non-Phase parents (e.g. '## gate fast')"
  echo "    may use Step headers — those describe runner steps, not spec changes."
  exit 1
fi

echo "check_spec_taxonomy: all $spec_count spec files conform"
exit 0
