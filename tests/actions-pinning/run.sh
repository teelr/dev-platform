#!/usr/bin/env bash
# tests/actions-pinning/run.sh — structural assertions on this repo's GitHub Actions
# hardening (v1.42): third-party actions pinned to a commit SHA with a version comment,
# Dependabot configured to keep those pins current, no expression expanded inside a
# `run:` script, and an explicit permission scope on every workflow.
#
# Each check is also run against a small fixture tree that violates it, so a check that
# silently stopped matching would be noticed (a validity suite that validated nothing is
# the failure mode this repo keeps rediscovering).
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 contract.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

echo "=== actions-pinning ==="

if ! python3 -c "import yaml" 2>/dev/null; then
    record_skip "actions-pinning: pyyaml not installed — structural assertions cannot run"
    echo ""
    echo "actions-pinning: ${PASS_COUNT} PASS  ${FAIL_COUNT} FAIL  ${SKIP_COUNT} SKIP"
    exit 0
fi

# probe <root> <mode> — prints one line. <root> is a directory containing .github/.
probe() {
    python3 - "$1" "$2" <<'PY'
import glob, os, re, sys, yaml

root, mode = sys.argv[1], sys.argv[2]
wf_files = sorted(glob.glob(os.path.join(root, ".github", "workflows", "*.y*ml")))

USES = re.compile(r"^\s*(?:-\s+)?uses:\s*(\S+)(?:\s+#\s*(.*))?\s*$")
SHA = re.compile(r"@[0-9a-f]{40}$")


def exempt(ref):
    # Local reusable workflows, and this repo's own tags (consumers pin those).
    return ref.startswith("./") or ref.startswith("teelr/dev-platform/")


if mode == "pinned":
    bad, seen = [], 0
    for f in wf_files:
        for n, line in enumerate(open(f, encoding="utf-8"), 1):
            if line.lstrip().startswith("#"):
                continue
            m = USES.match(line)
            if not m or exempt(m.group(1)):
                continue
            seen += 1
            ref, comment = m.group(1), (m.group(2) or "").strip()
            if not SHA.search(ref):
                bad.append(f"{os.path.basename(f)}:{n} not a 40-hex SHA")
            elif not comment.startswith("v"):
                bad.append(f"{os.path.basename(f)}:{n} no '# v...' comment")
    print(f"checked={seen} bad={len(bad)}" + ("" if not bad else " :: " + "; ".join(bad)))

elif mode == "dependabot":
    p = os.path.join(root, ".github", "dependabot.yml")
    if not os.path.exists(p):
        print("MISSING")
    else:
        d = yaml.safe_load(open(p, encoding="utf-8")) or {}
        eco = [u.get("package-ecosystem") for u in d.get("updates", [])]
        print("OK" if "github-actions" in eco else f"NO-GITHUB-ACTIONS ({eco})")

elif mode == "run-expressions":
    bad = []
    for f in wf_files:
        w = yaml.safe_load(open(f, encoding="utf-8")) or {}
        for jname, job in (w.get("jobs") or {}).items():
            for s in job.get("steps", []) or []:
                if "${{" in (s.get("run") or ""):
                    bad.append(f"{os.path.basename(f)}:{jname}")
    print(f"bad={len(bad)}" + ("" if not bad else " :: " + "; ".join(bad)))

elif mode == "permissions":
    bad = []
    for f in wf_files:
        w = yaml.safe_load(open(f, encoding="utf-8")) or {}
        if "permissions" in w:
            continue
        for jname, job in (w.get("jobs") or {}).items():
            if "permissions" not in job:
                bad.append(f"{os.path.basename(f)}:{jname}")
    print(f"bad={len(bad)}" + ("" if not bad else " :: " + "; ".join(bad)))
PY
}

# fixture <dir> <workflow-body> — build a tiny tree with one workflow.
fixture() {
    mkdir -p "$1/.github/workflows"
    printf '%s\n' "$2" > "$1/.github/workflows/w.yml"
}

TMP="$(mktemp -d /tmp/actions-pinning.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

SHA40="$(printf 'a%.0s' {1..40})"

# ─── 1: every third-party action is pinned to a SHA with a version comment ───
out="$(probe "${REPO}" pinned)"
if [[ "${out}" == checked=*" bad=0" && "${out}" != "checked=0 "* ]]; then
    record_pass "actions-pinning: every third-party action is a 40-hex SHA with a '# v' comment (${out})"
else
    record_fail "actions-pinning: unpinned or uncommented action (${out})"
fi

fixture "${TMP}/tag" $'name: t\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4'
out="$(probe "${TMP}/tag" pinned)"
[[ "${out}" == *"bad=1"* ]] && record_pass "actions-pinning: a tag pin is detected (fixture)" \
    || record_fail "actions-pinning: a tag pin was NOT detected (${out})"

fixture "${TMP}/nocomment" "$(printf 'name: t\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@%s' "${SHA40}")"
out="$(probe "${TMP}/nocomment" pinned)"
[[ "${out}" == *"bad=1"* && "${out}" == *"comment"* ]] && record_pass "actions-pinning: a SHA pin with no version comment is detected (fixture)" \
    || record_fail "actions-pinning: a missing version comment was NOT detected (${out})"

fixture "${TMP}/self" $'name: t\non: push\njobs:\n  a:\n    uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@v1.31'
out="$(probe "${TMP}/self" pinned)"
[[ "${out}" == "checked=0 bad=0" ]] && record_pass "actions-pinning: this repo's own tag refs are exempt (fixture)" \
    || record_fail "actions-pinning: own-tag ref was not exempt (${out})"

# ─── 2: Dependabot keeps the pins current ────────────────────────────────────
out="$(probe "${REPO}" dependabot)"
[[ "${out}" == "OK" ]] && record_pass "actions-pinning: .github/dependabot.yml exists with the github-actions ecosystem" \
    || record_fail "actions-pinning: dependabot config wrong (${out})"

# ─── 3: no expression expanded inside a run: script ─────────────────────────
out="$(probe "${REPO}" run-expressions)"
[[ "${out}" == "bad=0" ]] && record_pass "actions-pinning: no \${{ }} expression inside any run: script" \
    || record_fail "actions-pinning: expression inside a run: script (${out})"

fixture "${TMP}/expr" $'name: t\non: push\npermissions:\n  contents: read\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo "${{ github.head_ref }}"'
out="$(probe "${TMP}/expr" run-expressions)"
[[ "${out}" == *"bad=1"* ]] && record_pass "actions-pinning: an expression in run: is detected (fixture)" \
    || record_fail "actions-pinning: an expression in run: was NOT detected (${out})"

# ─── 4: every workflow scopes its token ─────────────────────────────────────
out="$(probe "${REPO}" permissions)"
[[ "${out}" == "bad=0" ]] && record_pass "actions-pinning: every workflow has top-level or per-job permissions" \
    || record_fail "actions-pinning: workflow without a permissions scope (${out})"

fixture "${TMP}/noperm" $'name: t\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi'
out="$(probe "${TMP}/noperm" permissions)"
[[ "${out}" == *"bad=1"* ]] && record_pass "actions-pinning: a workflow with no permissions is detected (fixture)" \
    || record_fail "actions-pinning: missing permissions was NOT detected (${out})"

echo ""
echo "actions-pinning: ${PASS_COUNT} PASS  ${FAIL_COUNT} FAIL  ${SKIP_COUNT} SKIP"
exit $(( FAIL_COUNT > 0 ? 1 : 0 ))
