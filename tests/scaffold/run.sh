#!/usr/bin/env bash
# tests/scaffold/run.sh — new-project.sh smoke test. For each of the three
# R4a templates, scaffold + verify structure + verify substitution + verify
# git init + (Go-only) verify go.sum was generated, then teardown. Plus four
# edge cases: refuse-to-clobber, invalid template, invalid name, invalid
# --gh-repo visibility. Cleans up via trap regardless of pass/fail.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

cleanup() {
    rm -rf "${REPO}/projects/r3-smoke-go-service" \
           "${REPO}/projects/r3-smoke-python-agent" \
           "${REPO}/projects/r3-smoke-next-frontend" \
           "${REPO}/projects/r3-smoke-clobber" 2>/dev/null || true
}
trap cleanup EXIT

NEW_PROJECT="${REPO}/scripts/new-project.sh"

# Per-template happy path
for template in go-service python-agent next-frontend; do
    project="r3-smoke-${template}"
    project_dir="${REPO}/projects/${project}"

    bash "${NEW_PROJECT}" "${template}" "${project}" >/dev/null 2>&1
    rc=$?
    if [[ ${rc} -eq 0 && -d "${project_dir}" ]]; then
        record_pass "scaffold ${template}: created"
    else
        record_fail "scaffold ${template}: scaffold failed (exit ${rc})"
        continue
    fi

    # Substitution: zero {{PROJECT_NAME}} matches
    remaining="$(grep -rl "{{PROJECT_NAME}}" "${project_dir}" 2>/dev/null | wc -l)"
    if [[ ${remaining} -eq 0 ]]; then
        record_pass "scaffold ${template}: {{PROJECT_NAME}} fully substituted"
    else
        record_fail "scaffold ${template}: ${remaining} files still contain {{PROJECT_NAME}}"
    fi

    # Git init with initial commit
    if git -C "${project_dir}" log --oneline -1 2>/dev/null | grep -q "feat: initial scaffold from ${template}"; then
        record_pass "scaffold ${template}: git initial commit"
    else
        record_fail "scaffold ${template}: git initial commit missing or wrong message"
    fi

    # Go-only: confirm go.sum landed from `go mod tidy`
    if [[ "${template}" == "go-service" ]]; then
        if [[ -f "${project_dir}/go.sum" ]]; then
            record_pass "scaffold go-service: go.sum generated"
        else
            record_fail "scaffold go-service: go.sum missing (go mod tidy didn't run or failed)"
        fi
    fi

    rm -rf "${project_dir}"
done

# Edge case: refuse-to-clobber
mkdir -p "${REPO}/projects/r3-smoke-clobber"
echo "sentinel" > "${REPO}/projects/r3-smoke-clobber/x"
bash "${NEW_PROJECT}" python-agent r3-smoke-clobber >/dev/null 2>&1
rc=$?
if [[ ${rc} -ne 0 && -f "${REPO}/projects/r3-smoke-clobber/x" ]]; then
    record_pass "scaffold edge: refuse-to-clobber preserves sentinel"
else
    record_fail "scaffold edge: refuse-to-clobber failed (rc=${rc}, sentinel intact=$([[ -f "${REPO}/projects/r3-smoke-clobber/x" ]] && echo yes || echo no))"
fi
rm -rf "${REPO}/projects/r3-smoke-clobber"

# Edge case: invalid template name
bash "${NEW_PROJECT}" nonexistent-template r3-test >/dev/null 2>&1
[[ $? -ne 0 ]] && record_pass "scaffold edge: invalid template rejected" || record_fail "scaffold edge: invalid template accepted"

# Edge case: invalid project name (contains slash)
bash "${NEW_PROJECT}" python-agent "with/slashes" >/dev/null 2>&1
[[ $? -ne 0 ]] && record_pass "scaffold edge: project name with slashes rejected" || record_fail "scaffold edge: bad name accepted"

# Edge case: invalid --gh-repo visibility, plus no project created
bash "${NEW_PROJECT}" python-agent r3-test-vis --gh-repo invalidvis >/dev/null 2>&1
rc=$?
if [[ ${rc} -ne 0 && ! -e "${REPO}/projects/r3-test-vis" ]]; then
    record_pass "scaffold edge: invalid --gh-repo visibility rejected; no project created"
else
    record_fail "scaffold edge: bad gh-repo visibility allowed or partial scaffold left"
fi
rm -rf "${REPO}/projects/r3-test-vis" 2>/dev/null || true
