#!/usr/bin/env bash
# tests/git-hooks/run.sh — fixture suite for shell/git-hooks/pre-commit.
# Five tests covering the cross-product of (no-gate / passing / failing) ×
# (default env / SKIP_GATE_FAST=1), plus install integration.
#
# Per tasks/lessons/ (2026-05-16): exit-code capture uses two-line pattern,
# never `cmd || true; check $?` (always yields $? = 0).
# Per tasks/lessons/ (2026-05-11 negative-test rule): assertions check both
# exit code AND specific stderr substring — not exit-code-only.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

HOOK="${REPO}/shell/git-hooks/pre-commit"
# The file under test stays at ${REPO} (this checkout's copy). The DEPLOYED
# symlink target is different: since v1.25 install.sh always deploys from the
# main checkout, so from a worktree the target is main's path, not ours.
HOOK_DEPLOYED="$(deploy_source_repo "${REPO}")/shell/git-hooks/pre-commit"
PASSING_FIXTURE="${HERE}/fixtures/passing-gate.sh"
FAILING_FIXTURE="${HERE}/fixtures/failing-gate.sh"

# Each test creates its own tmpdir + trap so failures still clean up.

# Test 1 — no scripts/gate_fast.sh: hook exits 0 (no-op).
test_no_gate() {
    local tmp; tmp="$(mktemp -d)"
    trap "rm -rf '${tmp}'" RETURN
    (cd "${tmp}" && git init -q)
    local out rc
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"
    rc=$?
    if [[ ${rc} -eq 0 ]]; then
        record_pass "no-gate no-op (exit 0)"
    else
        record_fail "no-gate no-op: expected exit 0, got ${rc}; out: ${out}"
    fi
}

# Test 2 — passing gate: hook exits 0.
test_passing_gate() {
    local tmp; tmp="$(mktemp -d)"
    trap "rm -rf '${tmp}'" RETURN
    (cd "${tmp}" && git init -q)
    mkdir -p "${tmp}/scripts"
    cp "${PASSING_FIXTURE}" "${tmp}/scripts/gate_fast.sh"
    chmod +x "${tmp}/scripts/gate_fast.sh"
    local out rc
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"
    rc=$?
    if [[ ${rc} -eq 0 ]]; then
        record_pass "passing gate (exit 0)"
    else
        record_fail "passing gate: expected exit 0, got ${rc}; out: ${out}"
    fi
}

# Test 3 — failing gate: hook exits 1 with refusal message.
test_failing_gate() {
    local tmp; tmp="$(mktemp -d)"
    trap "rm -rf '${tmp}'" RETURN
    (cd "${tmp}" && git init -q)
    mkdir -p "${tmp}/scripts"
    cp "${FAILING_FIXTURE}" "${tmp}/scripts/gate_fast.sh"
    chmod +x "${tmp}/scripts/gate_fast.sh"
    local out rc
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"
    rc=$?
    if [[ ${rc} -ne 1 ]]; then
        record_fail "failing gate: expected exit 1, got ${rc}; out: ${out}"
        return
    fi
    if [[ "${out}" == *"GATE FAST: FAIL"* ]]; then
        record_pass "failing gate refuses with FAIL message (exit 1)"
    else
        record_fail "failing gate exited 1 but missing 'GATE FAST: FAIL' message; out: ${out}"
    fi
}

# Test 4 — SKIP_GATE_FAST=1 bypasses even when gate would fail.
test_bypass_env_var() {
    local tmp; tmp="$(mktemp -d)"
    trap "rm -rf '${tmp}'" RETURN
    (cd "${tmp}" && git init -q)
    mkdir -p "${tmp}/scripts"
    cp "${FAILING_FIXTURE}" "${tmp}/scripts/gate_fast.sh"
    chmod +x "${tmp}/scripts/gate_fast.sh"
    local out rc
    out="$(cd "${tmp}" && SKIP_GATE_FAST=1 bash "${HOOK}" 2>&1)"
    rc=$?
    if [[ ${rc} -ne 0 ]]; then
        record_fail "SKIP_GATE_FAST=1 bypass: expected exit 0, got ${rc}; out: ${out}"
        return
    fi
    if [[ "${out}" == *"bypassing gate"* ]]; then
        record_pass "SKIP_GATE_FAST=1 bypasses failing gate (exit 0)"
    else
        record_fail "bypass exited 0 but missing 'bypassing gate' message; out: ${out}"
    fi
}

# Test 5 — install integration: install.sh git-hooks symlinks the hook
# into <tmpdir>/.claude/git-hooks/pre-commit pointing back at the tracked
# source. Uses HOME override (not actual $HOME modification).
test_install_integration() {
    local tmp; tmp="$(mktemp -d)"
    trap "rm -rf '${tmp}'" RETURN
    local out rc
    out="$(HOME="${tmp}" bash "${REPO}/scripts/install.sh" git-hooks 2>&1)"
    rc=$?
    if [[ ${rc} -ne 0 ]]; then
        record_fail "install git-hooks: expected exit 0, got ${rc}; out: ${out}"
        return
    fi
    local deployed="${tmp}/.claude/git-hooks/pre-commit"
    if [[ ! -L "${deployed}" ]]; then
        record_fail "install git-hooks: symlink ${deployed} not created"
        return
    fi
    local resolved; resolved="$(readlink -f "${deployed}")"
    if [[ "${resolved}" != "${HOOK_DEPLOYED}" ]]; then
        record_fail "install git-hooks: symlink resolves to ${resolved}, expected ${HOOK_DEPLOYED}"
        return
    fi
    record_pass "install git-hooks: symlink at ${deployed#${tmp}} → tracked source"
}

# --- v1.41 secret scan -------------------------------------------------------
# Fake credentials are built at runtime from a prefix plus generated filler, so no
# key-shaped string appears as a literal in this repo (the hook scans its own repo's
# commits, and GitHub push protection scans pushes).

# filler <char> <count> — print <char> repeated <count> times
filler() { printf '%*s' "$2" '' | tr ' ' "$1"; }

# new_repo — create a temp git repo, print its path
new_repo() {
    local d; d="$(mktemp -d)"
    (cd "${d}" && git init -q && git config user.email t@example.invalid && git config user.name t)
    echo "${d}"
}

# stage <repo> <path> <content> — write and stage a file
stage() {
    local repo="$1" path="$2" content="$3"
    mkdir -p "${repo}/$(dirname "${path}")"
    printf '%s\n' "${content}" > "${repo}/${path}"
    (cd "${repo}" && git add -- "${path}")
}

# Test 6 — each content pattern blocks a commit and is named; the value never prints.
test_secret_patterns() {
    local pairs=(
        "github-token:ghp_$(filler a 36)"
        "github-token:github_pat_$(filler b 30)"
        "anthropic-key:sk-ant-$(filler c 30)"
        "openai-key:sk-proj-$(filler d 50)"
        "openai-key:sk-$(filler e 45)"
        "aws-access-key-id:AKIA$(filler A 16)"
        "google-api-key:AIza$(filler g 35)"
        "slack-token:xoxb-$(filler 1 12)"
        "huggingface-token:hf_$(filler f 34)"
        "private-key-block:$(printf '%s%s%s' '-----BEGIN ' 'RSA PRIVATE KEY' '-----')"
    )
    local pair name value tmp out rc leaked
    for pair in "${pairs[@]}"; do
        name="${pair%%:*}"; value="${pair#*:}"
        tmp="$(new_repo)"
        stage "${tmp}" "src/config.txt" "token = ${value}"
        out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"
        rc=$?
        leaked=0
        [[ "${out}" == *"${value}"* ]] && leaked=1
        rm -rf "${tmp}"
        if [[ ${rc} -ne 1 ]]; then
            record_fail "secret scan ${name}: expected exit 1, got ${rc}"
        elif [[ "${out}" != *"SECRET? ${name} in src/config.txt:1"* ]]; then
            record_fail "secret scan ${name}: output missing the pattern name and path:line; out: ${out}"
        elif [[ ${leaked} -eq 1 ]]; then
            record_fail "secret scan ${name}: the matched value was printed"
        else
            record_pass "secret scan blocks ${name} and prints no value"
        fi
    done
}

# Test 7 — .env and key files block; example env files do not.
test_secret_paths() {
    local tmp out rc
    tmp="$(new_repo)"; stage "${tmp}" ".env" "PORT=1"
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"; rc=$?; rm -rf "${tmp}"
    if [[ ${rc} -eq 1 && "${out}" == *"path-env-file in .env"* ]]; then
        record_pass "staged .env blocks (path-env-file)"
    else
        record_fail "staged .env: expected exit 1 + path-env-file, got ${rc}; out: ${out}"
    fi
    tmp="$(new_repo)"; stage "${tmp}" "deploy/id_rsa" "x"
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"; rc=$?; rm -rf "${tmp}"
    if [[ ${rc} -eq 1 && "${out}" == *"path-key-file in deploy/id_rsa"* ]]; then
        record_pass "staged id_rsa blocks (path-key-file)"
    else
        record_fail "staged id_rsa: expected exit 1 + path-key-file, got ${rc}; out: ${out}"
    fi
    tmp="$(new_repo)"; stage "${tmp}" ".env.example" "PORT=1"
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"; rc=$?; rm -rf "${tmp}"
    if [[ ${rc} -eq 0 ]]; then
        record_pass "staged .env.example does not block"
    else
        record_fail "staged .env.example: expected exit 0, got ${rc}; out: ${out}"
    fi
}

# Test 8 — the secret check runs in a repo that has no scripts/gate_fast.sh, and
# SKIP_GATE_FAST=1 alone does not bypass it.
test_secret_independent_of_gate() {
    local tmp out rc
    tmp="$(new_repo)"; stage "${tmp}" "a.txt" "k = ghp_$(filler a 36)"
    out="$(cd "${tmp}" && SKIP_GATE_FAST=1 bash "${HOOK}" 2>&1)"; rc=$?; rm -rf "${tmp}"
    if [[ ${rc} -eq 1 && "${out}" == *"SECRET? github-token"* ]]; then
        record_pass "secret scan runs without gate_fast.sh and ignores SKIP_GATE_FAST=1"
    else
        record_fail "secret scan with no gate / SKIP_GATE_FAST=1: expected exit 1, got ${rc}; out: ${out}"
    fi
}

# Test 9 — SKIP_SECRET_SCAN=1 bypasses the scan and says so.
test_secret_bypass() {
    local tmp out rc
    tmp="$(new_repo)"; stage "${tmp}" "a.txt" "k = ghp_$(filler a 36)"
    out="$(cd "${tmp}" && SKIP_SECRET_SCAN=1 bash "${HOOK}" 2>&1)"; rc=$?; rm -rf "${tmp}"
    if [[ ${rc} -eq 0 && "${out}" == *"SKIP_SECRET_SCAN=1 — bypassing secret scan"* ]]; then
        record_pass "SKIP_SECRET_SCAN=1 bypasses the scan with a message"
    else
        record_fail "SKIP_SECRET_SCAN=1: expected exit 0 + message, got ${rc}; out: ${out}"
    fi
}

# Test 10 — the three ways to allow something: inline marker, allowlist glob, vendored dir.
test_secret_allowances() {
    local tmp out rc tok
    tok="ghp_$(filler a 36)"
    tmp="$(new_repo)"; stage "${tmp}" "a.txt" "k = ${tok}  # secret-scan:allow"
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"; rc=$?; rm -rf "${tmp}"
    [[ ${rc} -eq 0 ]] && record_pass "inline secret-scan:allow marker passes" \
        || record_fail "inline marker: expected exit 0, got ${rc}; out: ${out}"

    tmp="$(new_repo)"
    printf '# fixtures\nfixtures/*\n' > "${tmp}/.secret-scan-allow"
    stage "${tmp}" "fixtures/a.txt" "k = ${tok}"
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"; rc=$?; rm -rf "${tmp}"
    [[ ${rc} -eq 0 ]] && record_pass ".secret-scan-allow glob passes" \
        || record_fail ".secret-scan-allow glob: expected exit 0, got ${rc}; out: ${out}"

    tmp="$(new_repo)"; stage "${tmp}" "venv/lib/x.py" "k = ${tok}"
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"; rc=$?; rm -rf "${tmp}"
    [[ ${rc} -eq 0 ]] && record_pass "vendored venv/ path is skipped" \
        || record_fail "venv path: expected exit 0, got ${rc}; out: ${out}"
}

# Test 11 — a secret already in the file (not added by this commit) does not block.
test_secret_not_added() {
    local tmp out rc
    tmp="$(new_repo)"
    printf 'k = ghp_%s\nline2\n' "$(filler a 36)" > "${tmp}/a.txt"
    (cd "${tmp}" && git add a.txt && SKIP_SECRET_SCAN=1 bash "${HOOK}" >/dev/null 2>&1 && git commit -q -m seed)
    printf 'k = ghp_%s\nline2 changed\n' "$(filler a 36)" > "${tmp}/a.txt"
    (cd "${tmp}" && git add a.txt)
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"; rc=$?; rm -rf "${tmp}"
    [[ ${rc} -eq 0 ]] && record_pass "an unchanged secret line does not block" \
        || record_fail "unchanged secret line: expected exit 0, got ${rc}; out: ${out}"
}

# Test 12 — devplatform.precommitGate=false skips a failing gate but still blocks a secret.
test_gate_off_switch() {
    local tmp out rc
    tmp="$(new_repo)"
    mkdir -p "${tmp}/scripts"
    cp "${FAILING_FIXTURE}" "${tmp}/scripts/gate_fast.sh"; chmod +x "${tmp}/scripts/gate_fast.sh"
    (cd "${tmp}" && git config --bool devplatform.precommitGate false)
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"; rc=$?
    if [[ ${rc} -ne 0 ]]; then
        record_fail "gate off-switch: failing gate should be skipped, got ${rc}; out: ${out}"
    else
        record_pass "devplatform.precommitGate=false skips a failing gate"
    fi
    stage "${tmp}" "a.txt" "k = ghp_$(filler a 36)"
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"; rc=$?; rm -rf "${tmp}"
    if [[ ${rc} -eq 1 && "${out}" == *"SECRET? github-token"* ]]; then
        record_pass "gate off-switch still blocks a secret"
    else
        record_fail "gate off-switch + secret: expected exit 1, got ${rc}; out: ${out}"
    fi
}

# Test 13 — more than 20 findings are capped and the remainder is counted.
test_secret_cap() {
    local tmp out rc i
    tmp="$(new_repo)"
    for i in $(seq 1 25); do stage "${tmp}" "f${i}.txt" "k = ghp_$(filler a 36)"; done
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"; rc=$?; rm -rf "${tmp}"
    if [[ ${rc} -eq 1 && "${out}" == *"and 5 more suppressed"* ]]; then
        record_pass "findings are capped at 20 with the remainder counted"
    else
        record_fail "finding cap: expected exit 1 + '5 more suppressed', got ${rc}; out: ${out}"
    fi
}

# Test 14 — a secret in the middle of a large commit is still caught, at the right line.
# Regression: a `grep -q` fast path was killed by SIGPIPE under pipefail and skipped the
# scan on any diff large enough that the upstream grep had not finished.
test_secret_in_large_diff() {
    local tmp out rc
    tmp="$(new_repo)"
    {
        seq 1 5000 | sed 's/^/x /'
        printf 'k = ghp_%s\n' "$(filler a 36)"
        seq 1 5000 | sed 's/^/y /'
    } > "${tmp}/mixed.txt"
    (cd "${tmp}" && git add mixed.txt)
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"; rc=$?; rm -rf "${tmp}"
    if [[ ${rc} -eq 1 && "${out}" == *"SECRET? github-token in mixed.txt:5001"* ]]; then
        record_pass "a secret inside a 10,001-line commit is caught at the right line"
    else
        record_fail "large diff: expected exit 1 naming mixed.txt:5001, got ${rc}; out: ${out}"
    fi
}

# Test 15 — scripts/check-secret-hook.sh classifies projects as ENABLED / NOT-ENABLED /
# OTHER-HOOK, never writes to them, and exits 0.
test_status_script() {
    local pd tmp out rc before after
    pd="$(mktemp -d)"
    for tmp in enabled-proj plain-proj other-proj; do
        mkdir -p "${pd}/${tmp}"; (cd "${pd}/${tmp}" && git init -q)
    done
    ln -s "${HOOK}" "${pd}/enabled-proj/.git/hooks/pre-commit"
    printf '#!/bin/sh\nexit 0\n' > "${pd}/other-proj/.git/hooks/pre-commit"
    mkdir -p "${pd}/plain-proj/scripts"; printf '#!/bin/sh\n' > "${pd}/plain-proj/scripts/gate_fast.sh"; chmod +x "${pd}/plain-proj/scripts/gate_fast.sh"
    before="$(find "${pd}" -type f -o -type l | sort | xargs -r stat -c '%n %Y' 2>/dev/null | md5sum)"
    out="$(DEVPLATFORM_HOOK="${HOOK}" bash "${REPO}/scripts/check-secret-hook.sh" --projects-dir "${pd}" 2>&1)"; rc=$?
    after="$(find "${pd}" -type f -o -type l | sort | xargs -r stat -c '%n %Y' 2>/dev/null | md5sum)"
    rm -rf "${pd}"
    if [[ ${rc} -ne 0 ]]; then
        record_fail "status script: expected exit 0, got ${rc}; out: ${out}"
    elif ! echo "${out}" | grep -qE '^enabled-proj +ENABLED'; then
        record_fail "status script: enabled-proj not reported ENABLED; out: ${out}"
    elif ! echo "${out}" | grep -qE '^plain-proj +NOT-ENABLED +yes'; then
        record_fail "status script: plain-proj not reported NOT-ENABLED with gate yes; out: ${out}"
    elif ! echo "${out}" | grep -qE '^other-proj +OTHER-HOOK'; then
        record_fail "status script: other-proj not reported OTHER-HOOK; out: ${out}"
    elif [[ "${before}" != "${after}" ]]; then
        record_fail "status script modified files under the projects dir (must be read-only)"
    else
        record_pass "status script reports ENABLED / NOT-ENABLED / OTHER-HOOK and is read-only"
    fi
}

# Test 16 — a secret added while renaming a file is caught (git reports it as R, not A/M),
# and a file whose name git quotes (a double quote in it) is scanned, not skipped.
test_secret_rename_and_quoted_name() {
    local tmp out rc
    tmp="$(new_repo)"
    printf 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\n' > "${tmp}/a.txt"
    (cd "${tmp}" && git add a.txt && git commit -q -m seed && git mv a.txt b.txt)
    printf 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nk = ghp_%s\n' "$(filler a 36)" > "${tmp}/b.txt"
    (cd "${tmp}" && git add b.txt)
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"; rc=$?; rm -rf "${tmp}"
    if [[ ${rc} -eq 1 && "${out}" == *"SECRET? github-token in b.txt:9"* ]]; then
        record_pass "a secret added during a rename is caught"
    else
        record_fail "rename + secret: expected exit 1 naming b.txt:9, got ${rc}; out: ${out}"
    fi
    tmp="$(new_repo)"
    stage "${tmp}" 'we"ird.txt' "k = ghp_$(filler a 36)"
    out="$(cd "${tmp}" && bash "${HOOK}" 2>&1)"; rc=$?; rm -rf "${tmp}"
    if [[ ${rc} -eq 1 && "${out}" == *'SECRET? github-token in we\"ird.txt:1'* ]]; then
        record_pass "a file name that git quotes is scanned, not skipped"
    else
        record_fail "quoted name: expected exit 1 naming we\"ird.txt:1, got ${rc}; out: ${out}"
    fi
}

test_no_gate
test_passing_gate
test_failing_gate
test_bypass_env_var
test_install_integration
test_secret_rename_and_quoted_name
test_status_script
test_secret_in_large_diff
test_secret_patterns
test_secret_paths
test_secret_independent_of_gate
test_secret_bypass
test_secret_allowances
test_secret_not_added
test_gate_off_switch
test_secret_cap
