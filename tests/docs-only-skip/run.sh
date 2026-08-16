#!/usr/bin/env bash
# tests/docs-only-skip/run.sh — unit suite for scripts/lib/docs_only_diff.sh.
# Builds a disposable local git repo per assertion (main + feature branch),
# sources the detector directly, and checks DOCS_ONLY_DIFF / _CHANGED_FILES.
#
# Auto-discovered by scripts/gate_fast.sh (tests/<suite>/run.sh).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"
# shellcheck disable=SC1091
source "${REPO}/scripts/lib/docs_only_diff.sh"

TMP="$(mktemp -d /tmp/docs-only-skip.XXXXXX)"
trap 'rm -rf "${TMP}"' EXIT

# new_repo <name> — creates $TMP/<name> with an initial commit on main
# (README.md + a placeholder scripts/x.sh), returns the path via stdout.
new_repo() {
    local dir="${TMP}/$1"
    git init -q "${dir}"
    (
        cd "${dir}"
        git checkout -q -b main
        echo "# seed" > README.md
        mkdir -p scripts
        echo "#!/usr/bin/env bash" > scripts/x.sh
        git add README.md scripts/x.sh
        git -c user.email=t@t -c user.name=t commit -q -m seed
    )
    echo "${dir}"
}

run_case() {
    local description="$1" dir="$2" expected="$3"
    (
        cd "${dir}"
        compute_docs_only_diff
        [[ "${DOCS_ONLY_DIFF}" -eq "${expected}" ]]
    )
    if [[ $? -eq 0 ]]; then
        record_pass "${description}"
    else
        record_fail "${description}"
    fi
}

# 1. Committed docs-only diff -> 1
d="$(new_repo case1)"
(cd "${d}" && git checkout -q -b feature && echo "x" >> README.md && mkdir -p docs && echo "y" > docs/z.md && git add -A && git -c user.email=t@t -c user.name=t commit -q -m docs)
run_case "committed docs-only diff -> DOCS_ONLY_DIFF=1" "${d}" 1

# 2. Committed diff includes one non-doc file -> 0
d="$(new_repo case2)"
(cd "${d}" && git checkout -q -b feature && echo "x" >> README.md && echo "code" >> scripts/x.sh && git add -A && git -c user.email=t@t -c user.name=t commit -q -m mixed)
run_case "committed diff with one non-doc file -> DOCS_ONLY_DIFF=0" "${d}" 0

# 3. No diff at all (still on main) -> 0 (never infer docs-only from nothing)
d="$(new_repo case3)"
(cd "${d}" && git checkout -q -b feature)
run_case "empty diff -> DOCS_ONLY_DIFF=0" "${d}" 0

# 4. Committed docs-only diff, but an uncommitted non-doc change contaminates it -> 0
d="$(new_repo case4)"
(cd "${d}" && git checkout -q -b feature && echo "x" >> README.md && git add -A && git -c user.email=t@t -c user.name=t commit -q -m docs && echo "dirty" >> scripts/x.sh)
run_case "docs-only commit + uncommitted non-doc change -> DOCS_ONLY_DIFF=0" "${d}" 0

# 5. No commits yet, but uncommitted docs-only changes (staged + untracked) -> 1
d="$(new_repo case5)"
(cd "${d}" && git checkout -q -b feature && echo "x" >> README.md && git add README.md && echo "untracked" > NOTES.md)
run_case "uncommitted docs-only changes only -> DOCS_ONLY_DIFF=1" "${d}" 1

# 6. DOCS_ONLY_BASE_REF override -- baseline diverges from main with its own
# non-doc commit, so this only passes if the override is genuinely read:
# diffing against "baseline" (correct) sees only feature's docs-only commit;
# diffing against the default "main" (bug: override silently ignored) would
# also pick up baseline's non-doc commit and wrongly report DOCS_ONLY_DIFF=0.
d="$(new_repo case6)"
(
    cd "${d}"
    git checkout -q -b baseline
    echo "baseline-only code" >> scripts/x.sh
    git add -A && git -c user.email=t@t -c user.name=t commit -q -m baseline-code
    git checkout -q -b feature
    echo "x" >> README.md
    git add -A && git -c user.email=t@t -c user.name=t commit -q -m docs
)
(
    cd "${d}"
    DOCS_ONLY_BASE_REF="baseline"
    compute_docs_only_diff
    [[ "${DOCS_ONLY_DIFF}" -eq 1 ]]
)
if [[ $? -eq 0 ]]; then record_pass "DOCS_ONLY_BASE_REF override diffs against custom ref (not main)"; else record_fail "DOCS_ONLY_BASE_REF override diffs against custom ref (not main)"; fi

# 7. DOCS_ONLY_ALLOW_PATTERNS override -- a custom project layout
d="$(new_repo case7)"
(cd "${d}" && git checkout -q -b feature && mkdir -p spec && echo "y" > spec/w.txt && git add -A && git -c user.email=t@t -c user.name=t commit -q -m custom-docs)
(
    cd "${d}"
    DOCS_ONLY_ALLOW_PATTERNS=("spec/*")
    compute_docs_only_diff
    [[ "${DOCS_ONLY_DIFF}" -eq 1 ]]
)
if [[ $? -eq 0 ]]; then record_pass "DOCS_ONLY_ALLOW_PATTERNS override respects custom allowlist"; else record_fail "DOCS_ONLY_ALLOW_PATTERNS override respects custom allowlist"; fi

echo ""
echo "docs-only-skip: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL, ${SKIP_COUNT} SKIP"
[[ "${FAIL_COUNT}" -eq 0 ]]
