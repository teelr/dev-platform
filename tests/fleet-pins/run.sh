#!/usr/bin/env bash
# tests/fleet-pins/run.sh — fixture suite for v0.8 Phase 4 fleet_pins.py.
# Builds a mock project tree under mktemp + writes a registry inline,
# then exercises every classification branch (not-adopted / up-to-date /
# behind / floating / unparseable / self) plus the path-guard contract
# proving fleet-pins is read-only.
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 contract.
#
# Mirrors the Phase 2/3 fleet-* runners: --latest is passed everywhere
# to bypass `gh api` (no network access during tests).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"
# shellcheck disable=SC1091
source "${REPO}/tests/helpers/mock-project-tree.sh"

INSPECTOR="${REPO}/monitoring/fleet_pins.py"
WRAPPER="${REPO}/scripts/fleet-pins.sh"

TMP="$(mktemp -d /tmp/fleet-pins-test.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

# Build the mock project tree
MOCK_ROOT="${TMP}/mock-projects"
mkdir -p "${MOCK_ROOT}"

# clean-1: no template (not-adopted)
mock_project_init "${MOCK_ROOT}/clean-1"

# pinned-v07: helper installs the template with the default @v0.7 pin
mock_project_init "${MOCK_ROOT}/pinned-v07"
mock_project_install_template "${MOCK_ROOT}/pinned-v07"

# pinned-v08: same template, sed-rewritten to @v0.8
mock_project_init "${MOCK_ROOT}/pinned-v08"
mock_project_install_template "${MOCK_ROOT}/pinned-v08"
sed -i 's|@v0.7$|@v0.8|' "${MOCK_ROOT}/pinned-v08/.github/workflows/dev-platform-gate.yml"

# floating-1: same template, sed-rewritten to @main
mock_project_init "${MOCK_ROOT}/floating-1"
mock_project_install_template "${MOCK_ROOT}/floating-1"
sed -i 's|@v0.7$|@main|' "${MOCK_ROOT}/floating-1/.github/workflows/dev-platform-gate.yml"

# garbled-1: template file exists but has no uses: line matching the regex
mock_project_init "${MOCK_ROOT}/garbled-1"
mkdir -p "${MOCK_ROOT}/garbled-1/.github/workflows"
cat > "${MOCK_ROOT}/garbled-1/.github/workflows/dev-platform-gate.yml" <<'EOF'
# garbled fixture — no parseable `uses:` line
name: dev-platform-gate
on:
  pull_request:
    branches: [main]
jobs:
  taxonomy:
    runs-on: ubuntu-latest
    steps:
      - run: echo "no uses: line"
EOF

# commented-uses-1: template with a `# uses: ...@v0.5` comment BEFORE
# the real `uses: ...@v0.8` directive. The anchored regex must extract
# the real pin (v0.8), NOT the value embedded in the comment. Caught a
# real BUG class in /review: pre-anchor, re.search returned the first
# match, which was the comment's shadow pin.
mock_project_init "${MOCK_ROOT}/commented-uses-1"
mkdir -p "${MOCK_ROOT}/commented-uses-1/.github/workflows"
cat > "${MOCK_ROOT}/commented-uses-1/.github/workflows/dev-platform-gate.yml" <<'EOF'
name: dev-platform-gate
# example: uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@v0.5
on:
  pull_request:
    branches: [main]
jobs:
  taxonomy:
    uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@v0.8
EOF

# Write the mock registry inline. Mock-projects use ABSOLUTE paths via
# mktemp; the inspector handles both absolute and REPO-relative entries.
MOCK_REGISTRY="${TMP}/registry.json"
cat > "${MOCK_REGISTRY}" <<EOF
[
  {"name": "clean-1",           "path": "${MOCK_ROOT}/clean-1",           "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "pinned-v07",        "path": "${MOCK_ROOT}/pinned-v07",        "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "pinned-v08",        "path": "${MOCK_ROOT}/pinned-v08",        "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "floating-1",        "path": "${MOCK_ROOT}/floating-1",        "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "garbled-1",         "path": "${MOCK_ROOT}/garbled-1",         "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "commented-uses-1",  "path": "${MOCK_ROOT}/commented-uses-1",  "gate_cmd": "true", "primary_language": "bash", "enabled": true}
]
EOF

# Snapshot the mock tree so the path-guard test can prove no writes happened.
snapshot_tree() {
    local root="$1"
    (cd "${root}" && find . -type f | sort)
}
BASELINE="$(snapshot_tree "${MOCK_ROOT}")"

# Helper to fetch a single project field from the JSON render. Re-uses
# the cached JSON output so we don't re-invoke the inspector 5+ times.
json_field() {
    local json="$1" name="$2" field="$3"
    echo "${json}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for p in d['projects']:
    if p['name'] == '${name}':
        print(p.get('${field}'))
        break
"
}

# ─── Check 1: bash -n syntax clean ────────────────────────────────
if bash -n "${HERE}/run.sh" 2>/dev/null; then
    record_pass "fleet-pins: bash -n syntax clean (runner)"
else
    record_fail "fleet-pins: bash -n syntax error (runner)"
fi

# ─── Check 2: python ast.parse clean ──────────────────────────────
if python3 -c "import ast; ast.parse(open('${INSPECTOR}').read())" 2>/dev/null; then
    record_pass "fleet-pins: fleet_pins.py python syntax clean"
else
    record_fail "fleet-pins: fleet_pins.py python syntax error"
fi

# ─── Check 3: --help renders ──────────────────────────────────────
help_out="$(python3 "${INSPECTOR}" --help 2>&1)"
if echo "${help_out}" | grep -qi "fleet pin inspector"; then
    record_pass "fleet-pins: --help renders the descriptor"
else
    record_fail "fleet-pins: --help missing descriptor"
fi

# Cache the JSON render for the subsequent state assertions.
JSON_OUT="$(python3 "${INSPECTOR}" --source local --latest v0.8 --format json --registry "${MOCK_REGISTRY}" 2>&1)"; rc=$?

# ─── Check 4: markdown render ────────────────────────────────────
md_out="$(python3 "${INSPECTOR}" --source local --latest v0.8 --registry "${MOCK_REGISTRY}" 2>&1)"
md_rc=$?
if [[ ${md_rc} -eq 0 ]] && echo "${md_out}" | grep -q "^# Fleet Pins"; then
    record_pass "fleet-pins: markdown render exits 0 with title"
else
    record_fail "fleet-pins: markdown render failed — rc=${md_rc}"
fi

# ─── Check 5: JSON render parses + latest_release is correct ─────
if [[ ${rc} -eq 0 ]] && echo "${JSON_OUT}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['latest_release'] == 'v0.8', f'expected v0.8, got {d[\"latest_release\"]}'
assert isinstance(d['projects'], list)
assert len(d['projects']) == 6, f'expected 6 projects, got {len(d[\"projects\"])}'
" >/dev/null 2>&1; then
    record_pass "fleet-pins: JSON render — latest_release='v0.8', 6 projects"
else
    record_fail "fleet-pins: JSON render shape wrong — rc=${rc}"
fi

# ─── Check 6: clean-1 → not-adopted ───────────────────────────────
clean_adopted="$(json_field "${JSON_OUT}" clean-1 adopted)"
clean_status="$(json_field "${JSON_OUT}" clean-1 status)"
clean_pin="$(json_field "${JSON_OUT}" clean-1 pin)"
if [[ "${clean_adopted}" == "False" ]] && [[ "${clean_status}" == "not-adopted" ]] && [[ "${clean_pin}" == "None" ]]; then
    record_pass "fleet-pins: clean-1 → adopted=False, status=not-adopted, pin=None"
else
    record_fail "fleet-pins: clean-1 wrong — adopted=${clean_adopted}, status=${clean_status}, pin=${clean_pin}"
fi

# ─── Check 7: pinned-v07 → behind ─────────────────────────────────
v07_adopted="$(json_field "${JSON_OUT}" pinned-v07 adopted)"
v07_pin="$(json_field "${JSON_OUT}" pinned-v07 pin)"
v07_status="$(json_field "${JSON_OUT}" pinned-v07 status)"
v07_delta="$(json_field "${JSON_OUT}" pinned-v07 minor_delta)"
if [[ "${v07_adopted}" == "True" ]] && [[ "${v07_pin}" == "v0.7" ]] && [[ "${v07_status}" == "behind" ]] && [[ "${v07_delta}" == "1" ]]; then
    record_pass "fleet-pins: pinned-v07 → adopted=True, pin=v0.7, status=behind, minor_delta=1"
else
    record_fail "fleet-pins: pinned-v07 wrong — adopted=${v07_adopted}, pin=${v07_pin}, status=${v07_status}, delta=${v07_delta}"
fi

# ─── Check 8: pinned-v08 → up-to-date ─────────────────────────────
v08_adopted="$(json_field "${JSON_OUT}" pinned-v08 adopted)"
v08_pin="$(json_field "${JSON_OUT}" pinned-v08 pin)"
v08_status="$(json_field "${JSON_OUT}" pinned-v08 status)"
if [[ "${v08_adopted}" == "True" ]] && [[ "${v08_pin}" == "v0.8" ]] && [[ "${v08_status}" == "up-to-date" ]]; then
    record_pass "fleet-pins: pinned-v08 → adopted=True, pin=v0.8, status=up-to-date"
else
    record_fail "fleet-pins: pinned-v08 wrong — adopted=${v08_adopted}, pin=${v08_pin}, status=${v08_status}"
fi

# ─── Check 9: floating-1 → floating ──────────────────────────────
float_pin="$(json_field "${JSON_OUT}" floating-1 pin)"
float_status="$(json_field "${JSON_OUT}" floating-1 status)"
if [[ "${float_pin}" == "main" ]] && [[ "${float_status}" == "floating" ]]; then
    record_pass "fleet-pins: floating-1 → pin=main, status=floating"
else
    record_fail "fleet-pins: floating-1 wrong — pin=${float_pin}, status=${float_status}"
fi

# ─── Check 10: garbled-1 → unparseable ────────────────────────────
garbled_adopted="$(json_field "${JSON_OUT}" garbled-1 adopted)"
garbled_status="$(json_field "${JSON_OUT}" garbled-1 status)"
if [[ "${garbled_adopted}" == "True" ]] && [[ "${garbled_status}" == "unparseable" ]]; then
    record_pass "fleet-pins: garbled-1 → adopted=True, status=unparseable"
else
    record_fail "fleet-pins: garbled-1 wrong — adopted=${garbled_adopted}, status=${garbled_status}"
fi

# ─── Check 11: dev-platform → self short-circuit ──────────────────
# Add a dev-platform entry to a side registry and confirm the self
# short-circuit fires regardless of filesystem state.
SELF_REGISTRY="${TMP}/registry-self.json"
cat > "${SELF_REGISTRY}" <<EOF
[
  {"name": "dev-platform", "path": ".", "gate_cmd": "true", "primary_language": "bash", "enabled": true}
]
EOF
SELF_OUT="$(python3 "${INSPECTOR}" --source local --latest v0.8 --format json --registry "${SELF_REGISTRY}" 2>&1)"
self_status="$(json_field "${SELF_OUT}" dev-platform status)"
self_adopted="$(json_field "${SELF_OUT}" dev-platform adopted)"
if [[ "${self_status}" == "self" ]] && [[ "${self_adopted}" == "self" ]]; then
    record_pass "fleet-pins: dev-platform → status=self, adopted=self (short-circuit)"
else
    record_fail "fleet-pins: dev-platform short-circuit failed — status=${self_status}, adopted=${self_adopted}"
fi

# ─── Check 12: --project filter narrows to 1 row ─────────────────
filt_out="$(python3 "${INSPECTOR}" --source local --latest v0.8 --project pinned-v07 --registry "${MOCK_REGISTRY}" 2>&1)"
table_rows="$(echo "${filt_out}" | grep -c "^| pinned-v07\|^| clean-1\|^| pinned-v08\|^| floating-1\|^| garbled-1")"
if [[ "${table_rows}" -eq 1 ]]; then
    record_pass "fleet-pins: --project filter returns 1 row"
else
    record_fail "fleet-pins: --project filter wrong — got ${table_rows} rows"
fi

# ─── Check 13: --registry override actually used ─────────────────
# Same registry path, but verify the output names the override path in
# the header rather than the default monitoring/projects.json path.
reg_out="$(python3 "${INSPECTOR}" --source local --latest v0.8 --registry "${MOCK_REGISTRY}" 2>&1)"
if echo "${reg_out}" | grep -qF "Registry: ${MOCK_REGISTRY}"; then
    record_pass "fleet-pins: --registry override surfaced in header"
else
    record_fail "fleet-pins: --registry override not honored in header"
fi

# ─── Check 14: --latest v0.6 flips pinned-v07 to up-to-date ──────
# Proves the latest-release axis is genuinely configurable (not
# hardcoded). With latest=v0.6, pinned-v07 is now AHEAD of latest,
# which the code treats as "up-to-date" (not stale).
older_out="$(python3 "${INSPECTOR}" --source local --latest v0.6 --format json --registry "${MOCK_REGISTRY}" 2>&1)"
older_v07_status="$(json_field "${older_out}" pinned-v07 status)"
if [[ "${older_v07_status}" == "up-to-date" ]]; then
    record_pass "fleet-pins: --latest v0.6 flips pinned-v07 to up-to-date (latest axis configurable)"
else
    record_fail "fleet-pins: --latest override failed — pinned-v07 status=${older_v07_status} with latest=v0.6"
fi

# ─── Check 15: PATH-GUARD CONTRACT (LOAD-BEARING) ────────────────
# fleet-pins is READ-ONLY by design. After every prior invocation,
# no new files may have appeared under mock-projects/.
CURRENT="$(snapshot_tree "${MOCK_ROOT}")"
NEW_FILES="$(comm -13 <(echo "${BASELINE}") <(echo "${CURRENT}") | sort)"
if [[ -z "${NEW_FILES}" ]]; then
    record_pass "fleet-pins: path-guard contract — read-only (no new files appeared under mock-projects/)"
else
    record_fail "fleet-pins: PATH-GUARD VIOLATION — fleet-pins wrote new files:
$(echo "${NEW_FILES}" | sed 's/^/      /')"
fi

# ─── Check 16: commented `# uses: ...@v0.5` does NOT shadow real pin ─
# The template has a comment containing `# uses: ...@v0.5` BEFORE the
# real `uses: ...@v0.8` line. Pre-anchor, the unanchored regex captured
# the comment's shadow pin (v0.5). Anchored regex (^\s*uses:...) must
# skip the comment and extract the real pin (v0.8).
commented_pin="$(json_field "${JSON_OUT}" commented-uses-1 pin)"
commented_status="$(json_field "${JSON_OUT}" commented-uses-1 status)"
if [[ "${commented_pin}" == "v0.8" ]] && [[ "${commented_status}" == "up-to-date" ]]; then
    record_pass "fleet-pins: commented '# uses: ...@v0.5' line does NOT shadow real 'uses: ...@v0.8' (anchored regex)"
else
    record_fail "fleet-pins: SHADOW BUG — commented-uses-1 extracted wrong pin: ${commented_pin}, status=${commented_status}"
fi

# ─── Check 17: --latest validates semver shape ───────────────────
# Non-semver --latest values silently degraded every project to
# up-to-date pre-fix. Fail-loud guard exits 2 with an actionable
# error message.
out="$(python3 "${INSPECTOR}" --source local --latest "0.7" --registry "${MOCK_REGISTRY}" 2>&1)"; rc=$?
if [[ ${rc} -eq 2 ]] && echo "${out}" | grep -q "must be a semver tag"; then
    record_pass "fleet-pins: --latest validates semver shape ('0.7' missing 'v' rejected with exit 2)"
else
    record_fail "fleet-pins: --latest semver validation broken — rc=${rc}, output: ${out}"
fi

# ══════════════════════════════════════════════════════════════════
# v1.27 — the LIVE read. Everything above asserts against the local
# working copy; the pin that matters is the one on the repo's default
# branch, because that is the file GitHub Actions runs. The two differ
# in production right now (OPIE: local @v1.12, live @v1.2), which is
# what these checks exist to keep visible.
#
# A mock `gh` (fixtures/mock-bin/gh) supplies the live side, so the
# suite stays offline.
# ══════════════════════════════════════════════════════════════════

MOCK_BIN="${HERE}/fixtures/mock-bin"
GH_FIXTURE="${TMP}/gh-fixture"
LIVE_ROOT="${TMP}/live-projects"
mkdir -p "${GH_FIXTURE}" "${LIVE_ROOT}"

# A live template body at an arbitrary pin.
live_template() {
    cat <<EOF
name: dev-platform-gate
on: [pull_request]
jobs:
  taxonomy:
    uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@$1
EOF
}

# Mock project + an origin remote, so repo_slug_for() resolves a slug.
live_project() {
    local name="$1" slug="$2"
    mock_project_init "${LIVE_ROOT}/${name}"
    (cd "${LIVE_ROOT}/${name}" && git remote add origin "git@github.com:${slug}.git")
}

# current-1: live @v1.26, no local template at all.
live_project current-1 mock/current-1
live_template v1.26 > "${GH_FIXTURE}/mock__current-1.yml"

# drift-1: local @v1.12, live @v1.2 — the OPIE case.
live_project drift-1 mock/drift-1
mkdir -p "${LIVE_ROOT}/drift-1/.github/workflows"
live_template v1.12 > "${LIVE_ROOT}/drift-1/.github/workflows/dev-platform-gate.yml"
live_template v1.2 > "${GH_FIXTURE}/mock__drift-1.yml"

# hidden-1: repo unreachable (no fixture file), local @v1.12 — the SQRL case.
live_project hidden-1 mock/hidden-1
mkdir -p "${LIVE_ROOT}/hidden-1/.github/workflows"
live_template v1.12 > "${LIVE_ROOT}/hidden-1/.github/workflows/dev-platform-gate.yml"

# absent-1: repo reachable, no template on the default branch.
live_project absent-1 mock/absent-1
touch "${GH_FIXTURE}/mock__absent-1.absent"

# uncommitted-1: a local template that the default branch does NOT have —
# someone ran fleet-install-template and never committed. Its pin runs on
# nobody's CI, so it must not be reported as this project's pin.
live_project uncommitted-1 mock/uncommitted-1
mkdir -p "${LIVE_ROOT}/uncommitted-1/.github/workflows"
live_template v1.26 > "${LIVE_ROOT}/uncommitted-1/.github/workflows/dev-platform-gate.yml"
touch "${GH_FIXTURE}/mock__uncommitted-1.absent"

# shadow-1: live body has a `# uses: ...@v0.5` comment above the real pin.
live_project shadow-1 mock/shadow-1
cat > "${GH_FIXTURE}/mock__shadow-1.yml" <<'EOF'
name: dev-platform-gate
# example: uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@v0.5
on: [pull_request]
jobs:
  taxonomy:
    uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@v1.26
EOF

# garbled-live-1: live body with no `uses:` directive at all.
live_project garbled-live-1 mock/garbled-live-1
cat > "${GH_FIXTURE}/mock__garbled-live-1.yml" <<'EOF'
name: dev-platform-gate
on: [pull_request]
jobs:
  taxonomy:
    runs-on: ubuntu-latest
    steps:
      - run: echo "no uses: line"
EOF

# noremote-1: a checkout with NO origin remote — nothing to ask gh about.
mock_project_init "${LIVE_ROOT}/noremote-1"
mkdir -p "${LIVE_ROOT}/noremote-1/.github/workflows"
live_template v1.13 > "${LIVE_ROOT}/noremote-1/.github/workflows/dev-platform-gate.yml"

LIVE_REGISTRY="${TMP}/registry-live.json"
cat > "${LIVE_REGISTRY}" <<EOF
[
  {"name": "current-1",      "path": "${LIVE_ROOT}/current-1",      "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "drift-1",        "path": "${LIVE_ROOT}/drift-1",        "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "hidden-1",       "path": "${LIVE_ROOT}/hidden-1",       "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "absent-1",       "path": "${LIVE_ROOT}/absent-1",       "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "shadow-1",       "path": "${LIVE_ROOT}/shadow-1",       "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "garbled-live-1", "path": "${LIVE_ROOT}/garbled-live-1", "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "noremote-1",     "path": "${LIVE_ROOT}/noremote-1",     "gate_cmd": "true", "primary_language": "bash", "enabled": true},
  {"name": "uncommitted-1",  "path": "${LIVE_ROOT}/uncommitted-1",  "gate_cmd": "true", "primary_language": "bash", "enabled": true}
]
EOF

LIVE_JSON="$(PATH="${MOCK_BIN}:${PATH}" MOCK_GH_FIXTURE="${GH_FIXTURE}" \
    python3 "${INSPECTOR}" --source both --latest v1.26 --format json --registry "${LIVE_REGISTRY}" 2>&1)"
LIVE_MD="$(PATH="${MOCK_BIN}:${PATH}" MOCK_GH_FIXTURE="${GH_FIXTURE}" \
    python3 "${INSPECTOR}" --source both --latest v1.26 --registry "${LIVE_REGISTRY}" 2>&1)"

# ─── Check 18: live pin read from the default branch ─────────────
cur_live="$(json_field "${LIVE_JSON}" current-1 live_pin)"
cur_pin="$(json_field "${LIVE_JSON}" current-1 pin)"
cur_status="$(json_field "${LIVE_JSON}" current-1 status)"
cur_repo="$(json_field "${LIVE_JSON}" current-1 repo)"
if [[ "${cur_live}" == "v1.26" ]] && [[ "${cur_pin}" == "v1.26" ]] && \
   [[ "${cur_status}" == "up-to-date" ]] && [[ "${cur_repo}" == "mock/current-1" ]]; then
    record_pass "fleet-pins: live pin read from the default branch (adopted with no local copy)"
else
    record_fail "fleet-pins: live read wrong — live=${cur_live}, pin=${cur_pin}, status=${cur_status}, repo=${cur_repo}"
fi

# ─── Check 19: local ≠ live is reported as drift (the OPIE case) ──
d_local="$(json_field "${LIVE_JSON}" drift-1 local_pin)"
d_live="$(json_field "${LIVE_JSON}" drift-1 live_pin)"
d_pin="$(json_field "${LIVE_JSON}" drift-1 pin)"
d_drift="$(json_field "${LIVE_JSON}" drift-1 drift)"
if [[ "${d_local}" == "v1.12" ]] && [[ "${d_live}" == "v1.2" ]] && \
   [[ "${d_pin}" == "v1.2" ]] && [[ "${d_drift}" == "True" ]]; then
    record_pass "fleet-pins: local v1.12 vs live v1.2 → drift=True, live pin is authoritative"
else
    record_fail "fleet-pins: drift detection wrong — local=${d_local}, live=${d_live}, pin=${d_pin}, drift=${d_drift}"
fi

# ─── Check 20: drift row names both pins in the markdown ─────────
drift_row="$(echo "${LIVE_MD}" | grep "^| drift-1")"
if echo "${drift_row}" | grep -q "local ≠ live" && \
   echo "${drift_row}" | grep -q "v1.12" && echo "${drift_row}" | grep -q "v1.2"; then
    record_pass "fleet-pins: drift row names both pins in the markdown table"
else
    record_fail "fleet-pins: drift row missing pins or marker — ${drift_row}"
fi

# ─── Check 21: unreachable repo → unverifiable, NOT the local pin ─
# The SQRL case. Reporting the local copy here would be a pin no CI run
# has ever used — an unknown rendered as a fact, which is the whole
# defect v1.27 corrects. The status cell must not carry the local value.
h_status="$(json_field "${LIVE_JSON}" hidden-1 status)"
h_live_state="$(json_field "${LIVE_JSON}" hidden-1 live_state)"
hidden_status_cell="$(echo "${LIVE_MD}" | grep "^| hidden-1" | awk -F'|' '{print $6}')"
if [[ "${h_status}" == "unverifiable" ]] && [[ "${h_live_state}" == "unreachable" ]] && \
   ! echo "${hidden_status_cell}" | grep -q "v1.12"; then
    record_pass "fleet-pins: unreachable repo → unverifiable; local pin never presented as the answer"
else
    record_fail "fleet-pins: unreachable handling wrong — status=${h_status}, live_state=${h_live_state}, cell='${hidden_status_cell}'"
fi

# ─── Check 22: reachable + no template → not-adopted (≠ Check 21) ─
a_status="$(json_field "${LIVE_JSON}" absent-1 status)"
a_live_state="$(json_field "${LIVE_JSON}" absent-1 live_state)"
if [[ "${a_status}" == "not-adopted" ]] && [[ "${a_live_state}" == "absent" ]]; then
    record_pass "fleet-pins: reachable repo with no template → not-adopted (distinct from unverifiable)"
else
    record_fail "fleet-pins: absent handling wrong — status=${a_status}, live_state=${a_live_state}"
fi

# ─── Check 23: commented `uses:` does not shadow the LIVE pin ────
s_pin="$(json_field "${LIVE_JSON}" shadow-1 live_pin)"
if [[ "${s_pin}" == "v1.26" ]]; then
    record_pass "fleet-pins: live path uses the anchored regex — '# uses: ...@v0.5' does not shadow @v1.26"
else
    record_fail "fleet-pins: SHADOW BUG on the live path — extracted ${s_pin}"
fi

# ─── Check 24: live body with no `uses:` line → unparseable ──────
g_status="$(json_field "${LIVE_JSON}" garbled-live-1 status)"
if [[ "${g_status}" == "unparseable" ]]; then
    record_pass "fleet-pins: live body with no 'uses:' line → unparseable"
else
    record_fail "fleet-pins: live unparseable handling wrong — status=${g_status}"
fi

# ─── Check 25: no origin remote → skipped, local pin still reported ─
n_state="$(json_field "${LIVE_JSON}" noremote-1 live_state)"
n_pin="$(json_field "${LIVE_JSON}" noremote-1 pin)"
n_repo="$(json_field "${LIVE_JSON}" noremote-1 repo)"
if [[ "${n_state}" == "skipped" ]] && [[ "${n_pin}" == "v1.13" ]] && [[ "${n_repo}" == "None" ]]; then
    record_pass "fleet-pins: no origin remote → live_state=skipped, local pin still reported, no crash"
else
    record_fail "fleet-pins: no-remote handling wrong — live_state=${n_state}, pin=${n_pin}, repo=${n_repo}"
fi

# ─── Check 26: --source local makes ZERO gh calls ────────────────
# This is what keeps the whole suite runnable offline, and what makes
# `--source local` a real promise rather than a label.
ARGS_LOG="${TMP}/gh-calls.txt"
: > "${ARGS_LOG}"
PATH="${MOCK_BIN}:${PATH}" MOCK_GH_FIXTURE="${GH_FIXTURE}" MOCK_GH_ARGS_FILE="${ARGS_LOG}" \
    python3 "${INSPECTOR}" --source local --latest v1.26 --registry "${LIVE_REGISTRY}" >/dev/null 2>&1
if [[ ! -s "${ARGS_LOG}" ]]; then
    record_pass "fleet-pins: --source local makes zero gh calls"
else
    record_fail "fleet-pins: --source local called gh $(wc -l < "${ARGS_LOG}") time(s): $(head -3 "${ARGS_LOG}" | tr '\n' ' ')"
fi

# ─── Check 27: a local-only template is NOT reported as the pin ──
# The default branch has no template, so CI runs nothing — reporting the
# uncommitted local copy's pin would be the same wrong-file failure as the
# OPIE case, just in the other direction. Caught in v1.27's self-review.
u_pin="$(json_field "${LIVE_JSON}" uncommitted-1 pin)"
u_status="$(json_field "${LIVE_JSON}" uncommitted-1 status)"
u_adopted="$(json_field "${LIVE_JSON}" uncommitted-1 adopted)"
u_drift="$(json_field "${LIVE_JSON}" uncommitted-1 drift)"
u_local="$(json_field "${LIVE_JSON}" uncommitted-1 local_pin)"
if [[ "${u_pin}" == "None" ]] && [[ "${u_status}" == "not-adopted" ]] && \
   [[ "${u_adopted}" == "False" ]] && [[ "${u_drift}" == "True" ]] && [[ "${u_local}" == "v1.26" ]]; then
    record_pass "fleet-pins: local-only template → not-adopted + drift, local pin not reported as the pin"
else
    record_fail "fleet-pins: local-only template wrong — pin=${u_pin}, status=${u_status}, adopted=${u_adopted}, drift=${u_drift}, local=${u_local}"
fi

# ─── Check 28: JSON carries the new fields ───────────────────────
if echo "${LIVE_JSON}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
p = {x['name']: x for x in d['projects']}['drift-1']
for f in ('repo', 'local_pin', 'live_pin', 'live_state', 'drift'):
    assert f in p, f'missing field {f}'
assert p['repo'] == 'mock/drift-1', p['repo']
assert p['drift'] is True, p['drift']
" >/dev/null 2>&1; then
    record_pass "fleet-pins: JSON carries repo / local_pin / live_pin / live_state / drift"
else
    record_fail "fleet-pins: JSON missing the v1.27 fields"
fi
