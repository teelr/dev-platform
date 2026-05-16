#!/usr/bin/env bash
# tests/remote-verify/run.sh — fixture suite for scripts/verify-remotes.sh.
# Validates remote URL and per-repo identity checks against mock git repos
# under mktemp. 10 assertions.
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 contract.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

VERIFY="${REPO}/scripts/verify-remotes.sh"

TMP="$(mktemp -d /tmp/remote-verify-test.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

MOCK_ROOT="${TMP}/mock-repos"
mkdir -p "${MOCK_ROOT}"

# ─── Mock repo helpers ───────────────────────────────────────────────────────

make_repo() {
    local dir="$1" remote_url="$2"
    git init -q "${dir}"
    git -C "${dir}" remote add origin "${remote_url}"
}

make_repo_with_email() {
    local dir="$1" remote_url="$2" email="$3"
    make_repo "${dir}" "${remote_url}"
    git -C "${dir}" config user.email "${email}"
}

# ─── Check 1: verify-remotes.sh syntax clean ─────────────────────────────────
if bash -n "${VERIFY}" 2>/dev/null; then
    record_pass "remote-verify: bash -n verify-remotes.sh — syntax clean"
else
    record_fail "remote-verify: bash -n verify-remotes.sh — syntax error"
fi

# ─── Check 2: --help renders ─────────────────────────────────────────────────
help_out="$("${VERIFY}" --help 2>&1)"
if echo "${help_out}" | grep -q "verify-remotes"; then
    record_pass "remote-verify: --help renders expected text"
else
    record_fail "remote-verify: --help missing expected text — output: ${help_out}"
fi

# ─── Check 3: all correct repos → exits 0 ────────────────────────────────────
make_repo          "${MOCK_ROOT}/proj-a" "git@github.com:teelr/proj-a.git"
make_repo          "${MOCK_ROOT}/proj-b" "git@github.com:teelr/proj-b.git"
make_repo_with_email "${MOCK_ROOT}/proj-c" "git@github-teelr129:Osigin-LLC/proj-c.git" "teelr129@users.noreply.github.com"

REGISTRY_OK="${TMP}/registry-ok.json"
cat > "${REGISTRY_OK}" <<EOF
[
  {"name":"proj-a","path":"${MOCK_ROOT}/proj-a","remote_url":"git@github.com:teelr/proj-a.git","github_account":"teelr","local_email":null},
  {"name":"proj-b","path":"${MOCK_ROOT}/proj-b","remote_url":"git@github.com:teelr/proj-b.git","github_account":"teelr","local_email":null},
  {"name":"proj-c","path":"${MOCK_ROOT}/proj-c","remote_url":"git@github-teelr129:Osigin-LLC/proj-c.git","github_account":"teelr129","local_email":"teelr129@users.noreply.github.com"}
]
EOF

ok3_out="$("${VERIFY}" --registry "${REGISTRY_OK}" 2>&1)"
ok3_exit=$?
if [[ ${ok3_exit} -eq 0 ]] && ! echo "${ok3_out}" | grep -q "FAIL"; then
    record_pass "remote-verify: all correct repos → exits 0, no FAIL lines"
else
    record_fail "remote-verify: all-correct run failed — exit=${ok3_exit}, output: ${ok3_out}"
fi

# ─── Check 4: wrong origin URL → exits 1, reports project + "origin mismatch" ─
make_repo "${MOCK_ROOT}/proj-wrong-url" "git@github.com:teelr/wrong-repo.git"

REGISTRY_WRONG_URL="${TMP}/registry-wrong-url.json"
cat > "${REGISTRY_WRONG_URL}" <<EOF
[
  {"name":"proj-wrong-url","path":"${MOCK_ROOT}/proj-wrong-url","remote_url":"git@github.com:teelr/expected-repo.git","github_account":"teelr","local_email":null}
]
EOF

wrong_url_out="$("${VERIFY}" --registry "${REGISTRY_WRONG_URL}" 2>&1)"
wrong_url_exit=$?
if [[ ${wrong_url_exit} -ne 0 ]] && echo "${wrong_url_out}" | grep -q "proj-wrong-url" && echo "${wrong_url_out}" | grep -q "origin mismatch"; then
    record_pass "remote-verify: wrong origin URL → exits 1, reports project + 'origin mismatch'"
else
    record_fail "remote-verify: wrong-url detection failed — exit=${wrong_url_exit}, output: ${wrong_url_out}"
fi

# ─── Check 5: unexpected per-repo email → exits 1 ────────────────────────────
make_repo_with_email "${MOCK_ROOT}/proj-spurious-email" "git@github.com:teelr/proj-x.git" "spurious@example.com"

REGISTRY_SPURIOUS="${TMP}/registry-spurious.json"
cat > "${REGISTRY_SPURIOUS}" <<EOF
[
  {"name":"proj-spurious-email","path":"${MOCK_ROOT}/proj-spurious-email","remote_url":"git@github.com:teelr/proj-x.git","github_account":"teelr","local_email":null}
]
EOF

spurious_out="$("${VERIFY}" --registry "${REGISTRY_SPURIOUS}" 2>&1)"
spurious_exit=$?
if [[ ${spurious_exit} -ne 0 ]] && echo "${spurious_out}" | grep -q "unexpected per-repo user.email"; then
    record_pass "remote-verify: unexpected per-repo email → exits 1, reports 'unexpected per-repo user.email'"
else
    record_fail "remote-verify: spurious-email detection failed — exit=${spurious_exit}, output: ${spurious_out}"
fi

# ─── Check 6: missing required per-repo email → exits 1 ──────────────────────
make_repo "${MOCK_ROOT}/proj-missing-email" "git@github-teelr129:Osigin-LLC/proj-y.git"
# No user.email set — but registry says it's required

REGISTRY_MISSING="${TMP}/registry-missing.json"
cat > "${REGISTRY_MISSING}" <<EOF
[
  {"name":"proj-missing-email","path":"${MOCK_ROOT}/proj-missing-email","remote_url":"git@github-teelr129:Osigin-LLC/proj-y.git","github_account":"teelr129","local_email":"teelr129@users.noreply.github.com"}
]
EOF

missing_out="$("${VERIFY}" --registry "${REGISTRY_MISSING}" 2>&1)"
missing_exit=$?
if [[ ${missing_exit} -ne 0 ]] && echo "${missing_out}" | grep -q "user.email mismatch"; then
    record_pass "remote-verify: missing required email → exits 1, reports 'user.email mismatch'"
else
    record_fail "remote-verify: missing-email detection failed — exit=${missing_exit}, output: ${missing_out}"
fi

# ─── Check 7: wrong per-repo email value → exits 1 ───────────────────────────
make_repo_with_email "${MOCK_ROOT}/proj-wrong-email" "git@github-teelr129:Osigin-LLC/proj-z.git" "wrong@example.com"

REGISTRY_WRONG_EMAIL="${TMP}/registry-wrong-email.json"
cat > "${REGISTRY_WRONG_EMAIL}" <<EOF
[
  {"name":"proj-wrong-email","path":"${MOCK_ROOT}/proj-wrong-email","remote_url":"git@github-teelr129:Osigin-LLC/proj-z.git","github_account":"teelr129","local_email":"teelr129@users.noreply.github.com"}
]
EOF

wrong_email_out="$("${VERIFY}" --registry "${REGISTRY_WRONG_EMAIL}" 2>&1)"
wrong_email_exit=$?
if [[ ${wrong_email_exit} -ne 0 ]] && echo "${wrong_email_out}" | grep -q "user.email mismatch"; then
    record_pass "remote-verify: wrong per-repo email value → exits 1, reports 'user.email mismatch'"
else
    record_fail "remote-verify: wrong-email detection failed — exit=${wrong_email_exit}, output: ${wrong_email_out}"
fi

# ─── Check 8: path does not exist → SKIP, exits 0 ────────────────────────────
REGISTRY_NO_PATH="${TMP}/registry-no-path.json"
cat > "${REGISTRY_NO_PATH}" <<EOF
[
  {"name":"proj-nonexistent","path":"${MOCK_ROOT}/does-not-exist","remote_url":"git@github.com:teelr/whatever.git","github_account":"teelr","local_email":null}
]
EOF

no_path_out="$("${VERIFY}" --registry "${REGISTRY_NO_PATH}" 2>&1)"
no_path_exit=$?
if [[ ${no_path_exit} -eq 0 ]] && echo "${no_path_out}" | grep -q "SKIP"; then
    record_pass "remote-verify: missing path → SKIP, exits 0"
else
    record_fail "remote-verify: missing-path handling failed — exit=${no_path_exit}, output: ${no_path_out}"
fi

# ─── Check 9: path exists but not a git repo → SKIP, exits 0 ─────────────────
mkdir -p "${MOCK_ROOT}/not-a-repo"

REGISTRY_NOT_GIT="${TMP}/registry-not-git.json"
cat > "${REGISTRY_NOT_GIT}" <<EOF
[
  {"name":"not-a-repo","path":"${MOCK_ROOT}/not-a-repo","remote_url":"git@github.com:teelr/whatever.git","github_account":"teelr","local_email":null}
]
EOF

not_git_out="$("${VERIFY}" --registry "${REGISTRY_NOT_GIT}" 2>&1)"
not_git_exit=$?
if [[ ${not_git_exit} -eq 0 ]] && echo "${not_git_out}" | grep -q "SKIP"; then
    record_pass "remote-verify: non-git directory → SKIP, exits 0"
else
    record_fail "remote-verify: non-git handling failed — exit=${not_git_exit}, output: ${not_git_out}"
fi

# ─── Check 10: --project flag checks only named project ──────────────────────
# Registry has proj-a (correct) and proj-wrong-url (wrong). Filter to proj-a only → exits 0.
REGISTRY_TWO="${TMP}/registry-two.json"
cat > "${REGISTRY_TWO}" <<EOF
[
  {"name":"proj-a","path":"${MOCK_ROOT}/proj-a","remote_url":"git@github.com:teelr/proj-a.git","github_account":"teelr","local_email":null},
  {"name":"proj-wrong-url","path":"${MOCK_ROOT}/proj-wrong-url","remote_url":"git@github.com:teelr/expected-repo.git","github_account":"teelr","local_email":null}
]
EOF

filter_out="$("${VERIFY}" --registry "${REGISTRY_TWO}" --project proj-a 2>&1)"
filter_exit=$?
if [[ ${filter_exit} -eq 0 ]] && echo "${filter_out}" | grep -q "proj-a"; then
    record_pass "remote-verify: --project flag checks only named project, exits 0"
else
    record_fail "remote-verify: --project filter failed — exit=${filter_exit}, output: ${filter_out}"
fi
