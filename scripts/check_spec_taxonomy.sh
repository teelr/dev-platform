#!/usr/bin/env bash
# check_spec_taxonomy.sh
#
# Constitutional check enforcing the Phase + Change taxonomy locked in
# /home/rich/dev/CLAUDE.md across every dev project.
#
# Scans `tasks/*-spec.md` files in the current project for old vocabulary used
# at the *spec-structural* level. A killed-term header (Task/Step/Item/...) is
# flagged ONLY when it appears under a `## Phase N: ...` parent — that is the
# spec-implementation context the taxonomy governs. Workflow-content sections
# (e.g. `## gate fast — Pre-commit Gate` describing what a runner does
# sequentially) may legitimately use `### Step N: ...` and are not flagged.
#
# Top-level `## Section N` headers are always flagged because Section is a
# killed Phase synonym at every level.
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
      echo "  Standard: /home/rich/dev/CLAUDE.md → 'Development Terminology'"
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

if [[ "$found_violations" -ne 0 ]]; then
  echo ""
  echo "Fix: rename headers per the Phase + Change taxonomy."
  echo "Killed terms (in spec-structural context): Section, Task, Step, Item,"
  echo "  Sprint, Stage, Iteration, Milestone, Group, Epic."
  echo "Workflow-runner sections under non-Phase parents (e.g. '## gate fast')"
  echo "  may use Step headers — those describe runner steps, not spec changes."
  exit 1
fi

echo "check_spec_taxonomy: all $spec_count spec files conform"
exit 0
