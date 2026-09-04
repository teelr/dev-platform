#!/usr/bin/env bash
# tests/reusable-workflow/run.sh — structural assertions on
# .github/workflows/taxonomy-check.yml, the reusable workflow every consumer's
# CI calls via `uses:`.
#
# Until v1.31 this file had NO test of any kind: every `tests/` hit for
# "taxonomy-check.yml" was a fixture pin string, and gate_fast.sh validates JSON
# but never YAML. It is the highest-blast-radius file in the repo — a typo in an
# input name or a renamed step breaks the whole fleet's CI at once, and nothing
# here would have noticed.
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 contract.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

WORKFLOW="${REPO}/.github/workflows/taxonomy-check.yml"
TEMPLATE="${REPO}/extensions/github-actions/dev-platform-gate.yml"
COLLISION_SCRIPT="${REPO}/scripts/check_version_collision.py"

echo "=== reusable-workflow ==="

# pyyaml drives every structural assertion here. If it is missing, SKIP loudly
# rather than passing — a validity suite that validated nothing is the exact
# failure mode this repo keeps rediscovering (check_env_leak, v1.30).
if ! python3 -c "import yaml" 2>/dev/null; then
    record_skip "reusable-workflow: pyyaml not installed — structural assertions cannot run"
    echo ""
    echo "reusable-workflow: ${PASS_COUNT} PASS  ${FAIL_COUNT} FAIL  ${SKIP_COUNT} SKIP"
    exit 0
fi

# One python helper does the parsing; each check calls it with a mode and reads
# a single line back. Keeps the YAML knowledge in one place.
#
# NOTE on the `on:` key: PyYAML follows YAML 1.1, where a bare `on` is the
# BOOLEAN True — so the trigger block is at w[True], not w['on']. Every
# assertion below goes through _triggers() rather than indexing 'on' directly.
probe() {
    python3 - "${WORKFLOW}" "${TEMPLATE}" "$1" <<'PY'
import sys, re, yaml

wf_path, tpl_path, mode = sys.argv[1], sys.argv[2], sys.argv[3]
w = yaml.safe_load(open(wf_path, encoding="utf-8"))


def triggers(doc):
    # YAML 1.1: bare `on` parses as boolean True.
    if "on" in doc:
        return doc["on"]
    return doc.get(True, {})


def step_envs(job):
    return [s.get("env", {}) or {} for s in job.get("steps", [])]


jobs = w.get("jobs", {})

if mode == "input-declared":
    ins = triggers(w).get("workflow_call", {}).get("inputs", {}) or {}
    rp = ins.get("roadmap_path")
    if rp is None:
        print("MISSING")
    else:
        print(f"{rp.get('type')}|{rp.get('default')!r}|{rp.get('required')}")

elif mode == "wired-both":
    out = []
    for name in ("taxonomy", "version-collision"):
        job = jobs.get(name, {})
        found = ""
        for env in step_envs(job):
            if "ROADMAP_PATH" in env:
                found = str(env["ROADMAP_PATH"])
                break
        out.append(f"{name}={found or 'ABSENT'}")
    print(" ".join(out))

elif mode == "gh-token":
    job = jobs.get("version-collision", {})
    tok = ""
    for env in step_envs(job):
        if "GH_TOKEN" in env:
            tok = str(env["GH_TOKEN"])
            break
    print(tok or "ABSENT")

elif mode == "ref-derivation":
    out = []
    for name in ("taxonomy", "version-collision"):
        job = jobs.get(name, {})
        blob = yaml.safe_dump(job)
        checks_out_caller = "path: caller" in blob
        # Match EXPRESSION use (`${{ github.x }}`), not the bare identifier: the
        # taxonomy job's run step carries a shell comment naming
        # github.workflow_sha to warn against it, and that comment lives inside
        # the run: block scalar, so it survives into the dumped YAML. A bare
        # substring check flags the warning as if it were the regression.
        uses_job_wf_ref = "${{ github.job_workflow_ref }}" in blob
        uses_wf_sha = bool(
            re.search(r"\$\{\{\s*github\.(job_)?workflow_sha\s*\}\}", blob)
        )
        out.append(f"{name}={int(checks_out_caller)}{int(uses_job_wf_ref)}{int(uses_wf_sha)}")
    print(" ".join(out))

elif mode == "permissions":
    perms = jobs.get("version-collision", {}).get("permissions", {}) or {}
    print(f"contents={perms.get('contents')} issues={perms.get('issues')}")

elif mode == "pins-agree":
    pin_re = re.compile(r"taxonomy-check\.yml@(v\d+\.\d+[a-z]?)")
    tpl = pin_re.findall(open(tpl_path, encoding="utf-8").read())
    hdr = pin_re.findall(open(wf_path, encoding="utf-8").read())
    print(f"template={sorted(set(tpl))} header={sorted(set(hdr))}")
PY
}

# ─── 1: the input exists, typed, and defaults to ROADMAP.md ─────────────
# The default is the load-bearing part. An empty default hands every consumer
# that omits the input a false COLLISION failure: Path(root) / "" is the root
# DIRECTORY, which .exists() accepts and read_text() cannot read, so the script
# dies with IsADirectoryError and exits 1 — which this workflow maps to
# "::error::version collision detected".
decl="$(probe input-declared)"
if [[ "${decl}" == "string|'ROADMAP.md'|False" ]]; then
    record_pass "reusable-workflow: roadmap_path input declared, type string, default 'ROADMAP.md'"
elif [[ "${decl}" == "MISSING" ]]; then
    record_fail "reusable-workflow: roadmap_path input MISSING — consumers cannot set ROADMAP_PATH through CI"
else
    record_fail "reusable-workflow: roadmap_path input wrong (${decl}; want string|'ROADMAP.md'|False)"
fi

# ─── 2: wired into BOTH jobs ────────────────────────────────────────────
# Per job, not "at least one". Wiring only one is the likely defect, and it
# leaves the two jobs disagreeing about which file is the roadmap — the
# taxonomy job would scan nothing and still report success.
wired="$(probe wired-both)"
if [[ "${wired}" == "taxonomy=\${{ inputs.roadmap_path }} version-collision=\${{ inputs.roadmap_path }}" ]]; then
    record_pass "reusable-workflow: ROADMAP_PATH wired from inputs.roadmap_path into BOTH jobs"
else
    record_fail "reusable-workflow: ROADMAP_PATH not wired into both jobs (${wired})"
fi

# ─── 3: GH_TOKEN survived ───────────────────────────────────────────────
# Adding an env key to that step must not displace the existing one.
tok="$(probe gh-token)"
if [[ "${tok}" == "\${{ github.token }}" ]]; then
    record_pass "reusable-workflow: version-collision step still sets GH_TOKEN"
else
    record_fail "reusable-workflow: GH_TOKEN missing or changed on version-collision (${tok})"
fi

# ─── 4: caller checkout + job_workflow_ref derivation intact ────────────
# The header comment records why this must not regress to workflow_sha: that
# context caches the SHA at dispatch and breaks if a tag was force-updated.
refs="$(probe ref-derivation)"
if [[ "${refs}" == "taxonomy=110 version-collision=110" ]]; then
    record_pass "reusable-workflow: both jobs check out the caller and derive the ref from job_workflow_ref (no workflow_sha)"
else
    record_fail "reusable-workflow: ref derivation changed (${refs}; want taxonomy=110 version-collision=110)"
fi

# ─── 5: cross-org permissions intact ────────────────────────────────────
# Found live on SQRL's adoption (2026-08-12): without these the cross-org call
# is rejected as a startup_failure that never appears in the PR's checks list.
perms="$(probe permissions)"
if [[ "${perms}" == "contents=read issues=read" ]]; then
    record_pass "reusable-workflow: version-collision keeps contents:read + issues:read"
else
    record_fail "reusable-workflow: version-collision permissions changed (${perms})"
fi

# ─── 6: template pin and header example name the same tag ───────────────
pins="$(probe pins-agree)"
tpl_pins="${pins%% header=*}"
tpl_pins="${tpl_pins#template=}"
hdr_pins="${pins#*header=}"
if [[ "${tpl_pins}" == "${hdr_pins}" ]]; then
    record_pass "reusable-workflow: consumer template pin and workflow header example agree (${tpl_pins})"
else
    record_fail "reusable-workflow: pin mismatch — template ${tpl_pins}, header ${hdr_pins}"
fi

# ─── 7: empty ROADMAP_PATH does not crash the collision check ───────────
# bash's ${VAR:-default} treats empty as unset; Python's os.environ.get() does
# NOT — it returns "". This asserts the Python side was hardened to match.
TMP="$(mktemp -d /tmp/reusable-wf-test.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT
(
    cd "${TMP}" || exit 1
    git init -q -b main
    printf '# Roadmap\n\n## v1.0: Thing\n' > ROADMAP.md
    git -c user.email=t@t -c user.name=t add -A
    git -c user.email=t@t -c user.name=t commit -qm init
) >/dev/null 2>&1
empty_out="$(cd "${TMP}" && ROADMAP_PATH= python3 "${COLLISION_SCRIPT}" . 2>&1)"
if echo "${empty_out}" | grep -q "IsADirectoryError"; then
    record_fail "reusable-workflow: empty ROADMAP_PATH still crashes check_version_collision.py (IsADirectoryError)"
else
    record_pass "reusable-workflow: empty ROADMAP_PATH treated as unset, no crash"
fi

echo ""
echo "reusable-workflow: ${PASS_COUNT} PASS  ${FAIL_COUNT} FAIL  ${SKIP_COUNT} SKIP"
[[ ${FAIL_COUNT} -eq 0 ]] || exit 1
exit 0
