#!/usr/bin/env bash
# scripts/lib/docs_only_diff.sh — reusable docs-only-diff detector.
#
# Sourced by scripts/gate_fast.sh to skip expensive code-verifying checks
# (test suites, lint, build — whatever a project's own gate considers
# "expensive") when every changed file is pure documentation. Portable to
# any project's own gate_fast.sh — see docs/RULE_RATIONALE.md "Gate-Fast
# Docs-Only Diff Skip" for the adoption guide and why this ships as a
# pattern to copy in, not a script consumers source at runtime.
#
# Conservative by construction: any file outside the allowlist disables the
# skip for the WHOLE diff, and an empty diff (nothing changed, or no local
# base ref — e.g. a shallow CI checkout) also disables it. Never infer
# "docs-only" from missing information.
#
# Usage:
#   source this file, optionally override the knobs below, then call
#   compute_docs_only_diff. Sets, in the CALLER's shell:
#     DOCS_ONLY_DIFF          0 or 1
#     DOCS_ONLY_CHANGED_FILES newline-separated changed-file list (may be empty)
#
# Override before calling compute_docs_only_diff if your project's default
# branch or doc-file layout differs from dev-platform's own:
#   DOCS_ONLY_BASE_REF="main"
#   DOCS_ONLY_ALLOW_PATTERNS=("*.md" "docs/*" "tasks/*")
#
# Careful with a bare "*.md" default: bash's `[[ str == pattern ]]` lets `*`
# cross `/`, so "*.md" matches ANY .md file at ANY depth (commands/plan.md,
# skills/foo/SKILL.md, ...), not just root-level files. If your gate has a
# test that validates a nested .md file's live content directly (dev-platform
# itself does — see the override in scripts/gate_fast.sh, added because
# tests/commands/frontmatter.sh checks commands/*.md), narrow the allowlist
# to name that path explicitly rather than relying on the bare "*.md" default.

: "${DOCS_ONLY_BASE_REF:=main}"
if [[ -z "${DOCS_ONLY_ALLOW_PATTERNS+x}" ]]; then
    DOCS_ONLY_ALLOW_PATTERNS=("*.md" "docs/*" "tasks/*")
fi

compute_docs_only_diff() {
    local changed
    changed=$( { git diff --name-only "${DOCS_ONLY_BASE_REF}...HEAD" 2>/dev/null; \
                  git status --porcelain --untracked-files=all 2>/dev/null | awk '{print $2}'; } \
                | sort -u)

    DOCS_ONLY_CHANGED_FILES="${changed}"
    DOCS_ONLY_DIFF=0

    # Empty diff — nothing changed, or the base ref isn't locally resolvable
    # (e.g. a shallow CI checkout with no local `main`). Never guess.
    [[ -z "${changed}" ]] && return 0

    DOCS_ONLY_DIFF=1
    local f pattern matched
    while IFS= read -r f; do
        [[ -z "${f}" ]] && continue
        matched=0
        for pattern in "${DOCS_ONLY_ALLOW_PATTERNS[@]}"; do
            # shellcheck disable=SC2053
            if [[ "${f}" == ${pattern} ]]; then
                matched=1
                break
            fi
        done
        if [[ "${matched}" -eq 0 ]]; then
            DOCS_ONLY_DIFF=0
            break
        fi
    done <<< "${changed}"
}
