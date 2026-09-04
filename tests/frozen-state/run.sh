#!/usr/bin/env bash
# tests/frozen-state/run.sh — fixture suite for v1.30's `frozen` registry flag.
#
# The whole point of the flag is that it produces SIX DIFFERENT answers, not
# one. A suite that only asserted "frozen is honoured" would pass while
# fleet-gate had quietly stopped sweeping a project that is still in
# production — the single worst outcome of this phase, and the one this suite
# exists to catch.
#
# So the assertions are split deliberately:
#   - two consumers MUST keep including frozen projects (fleet-gate,
#     fleet_dashboard),
#   - four MUST honour the flag (fleet_pins, check-migration-coverage,
#     audit-project-drift, fleet-install-template),
#   - check-registry MUST reject the ways an entry can be malformed,
#   - and a registry with NO `frozen` keys at all must behave exactly as it did
#     before this phase — the backward-compatibility guarantee, asserted rather
#     than assumed.
#
# Offline: no consumer checkouts and no network required. The live-read
# assertion borrows tests/fleet-pins/fixtures/mock-bin/gh rather than
# duplicating a second mock `gh` (Derivation Sweep rule — one definition).
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 contract.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"
# shellcheck disable=SC1091
source "${REPO}/tests/helpers/mock-project-tree.sh"

REGISTRY_THREE="${HERE}/fixtures/registry-three.json"
REGISTRY_NO_FROZEN="${HERE}/fixtures/registry-no-frozen.json"
MOCK_BIN="${REPO}/tests/fleet-pins/fixtures/mock-bin"

PINS="${REPO}/monitoring/fleet_pins.py"
DASHBOARD="${REPO}/monitoring/fleet_dashboard.py"
FLEET_GATE="${REPO}/scripts/fleet-gate.sh"
MIGRATION="${REPO}/scripts/check-migration-coverage.sh"
DRIFT="${REPO}/scripts/audit-project-drift.sh"
INSTALL="${REPO}/scripts/fleet-install-template.sh"
CHECK_REGISTRY="${REPO}/scripts/check-registry.sh"

TMP="$(mktemp -d /tmp/frozen-state-test.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

echo "=== frozen-state ==="

# ══════════════════════════════════════════════════════════════════
# An absolute-path registry, for the five consumers that resolve one.
# fleet-gate is the exception — it always prefixes FLEET_ROOT — so its
# assertions use the committed relative-path fixture instead.
# ══════════════════════════════════════════════════════════════════
ABS_ROOT="${TMP}/projects"
mkdir -p "${ABS_ROOT}"

abs_project() {
    local name="$1" pin="$2" slug="$3"
    mock_project_init "${ABS_ROOT}/${name}"
    (cd "${ABS_ROOT}/${name}" && git remote add origin "git@github.com:${slug}.git")
    mkdir -p "${ABS_ROOT}/${name}/.github/workflows"
    cat > "${ABS_ROOT}/${name}/.github/workflows/dev-platform-gate.yml" <<EOF
name: dev-platform-gate
on: [pull_request]
jobs:
  taxonomy:
    uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@${pin}
EOF
    printf '#!/usr/bin/env bash\nexit 0\n' > "${ABS_ROOT}/${name}/gate.sh"
    chmod +x "${ABS_ROOT}/${name}/gate.sh"
}

abs_project active-1 v1.12 mock/active-1
abs_project frozen-1 v1.12 mock/frozen-1
abs_project disabled-1 v1.12 mock/disabled-1

write_abs_registry() {
    local out="$1" frozen_key="$2"
    python3 - "${ABS_ROOT}" "${out}" "${frozen_key}" <<'PY'
import json, sys
root, out, frozen_key = sys.argv[1], sys.argv[2], sys.argv[3]


def entry(name, enabled, frozen=None):
    e = {
        "name": name,
        "path": f"{root}/{name}",
        "gate_cmd": "./gate.sh",
        "primary_language": "bash",
        "enabled": enabled,
    }
    if frozen is not None:
        e["frozen"] = frozen
    return e


rows = [
    entry("active-1", True),
    entry("frozen-1", True, True if frozen_key == "with" else None),
    entry("disabled-1", False),
]
with open(out, "w", encoding="utf-8") as fh:
    json.dump(rows, fh, indent=2)
PY
}

ABS_WITH="${TMP}/registry-abs-frozen.json"
ABS_WITHOUT="${TMP}/registry-abs-no-frozen.json"
write_abs_registry "${ABS_WITH}" with
write_abs_registry "${ABS_WITHOUT}" without

# ─── Assertion 1: fleet_pins — frozen status, pin STILL read, no delta ───
pins_json="$(python3 "${PINS}" --registry "${ABS_WITH}" --latest v1.29 \
    --source local --format json 2>/dev/null)"
f_status="$(echo "${pins_json}" | jq -r '.projects[] | select(.name=="frozen-1") | .status')"
f_pin="$(echo "${pins_json}" | jq -r '.projects[] | select(.name=="frozen-1") | .pin')"
f_delta="$(echo "${pins_json}" | jq -r '.projects[] | select(.name=="frozen-1") | .minor_delta')"
if [[ "${f_status}" == "frozen" && "${f_pin}" == "v1.12" && "${f_delta}" == "null" ]]; then
    record_pass "fleet-pins: frozen project → status frozen, pin still read (v1.12), no staleness delta"
else
    record_fail "fleet-pins: frozen row wrong (status=${f_status} pin=${f_pin} delta=${f_delta}; want frozen/v1.12/null)"
fi

# ─── Assertion 2: unverifiable BEATS frozen ─────────────────────────────
# A fact about this tool failing to read a repo must never be masked by a fact
# about the project. mock/frozen-1 has no fixture file → 404 → unreachable.
GH_FIXTURE="${TMP}/gh-fixture"
mkdir -p "${GH_FIXTURE}"
unv_json="$(PATH="${MOCK_BIN}:${PATH}" MOCK_GH_FIXTURE="${GH_FIXTURE}" \
    python3 "${PINS}" --registry "${ABS_WITH}" --latest v1.29 \
    --source github --format json 2>/dev/null)"
u_status="$(echo "${unv_json}" | jq -r '.projects[] | select(.name=="frozen-1") | .status')"
u_live="$(echo "${unv_json}" | jq -r '.projects[] | select(.name=="frozen-1") | .live_state')"
if [[ "${u_status}" == "unverifiable" && "${u_live}" == "unreachable" ]]; then
    record_pass "fleet-pins: unverifiable beats frozen (a failed read is never masked by the flag)"
else
    record_fail "fleet-pins: frozen masked unverifiable (status=${u_status} live_state=${u_live})"
fi

# ─── Assertion 3: the ACTIVE row is untouched by a frozen entry ──────────
a_status="$(echo "${pins_json}" | jq -r '.projects[] | select(.name=="active-1") | .status')"
a_delta="$(echo "${pins_json}" | jq -r '.projects[] | select(.name=="active-1") | .minor_delta')"
if [[ "${a_status}" == "behind" && "${a_delta}" == "17" ]]; then
    record_pass "fleet-pins: active project unchanged by a frozen entry's presence (behind, 17)"
else
    record_fail "fleet-pins: active row changed (status=${a_status} delta=${a_delta}; want behind/17)"
fi

# ─── Assertion 4: fleet-gate STILL SWEEPS the frozen project ────────────
# The load-bearing NON-change. Asserted on row presence, not on PASS: the
# fixture path resolves against the MAIN checkout, so from a worktree (before
# this branch merges) the row reads MISSING. Whether it PASSes is a property of
# the checkout; whether it is SWEPT AT ALL is the property under test.
gate_out="$(bash "${FLEET_GATE}" --registry "${REGISTRY_THREE}" --timeout 10 2>&1)"
if echo "${gate_out}" | grep -qE '^\| frozen-1 '; then
    record_pass "fleet-gate: frozen project STILL swept (deployed — its tests are the signal that matters)"
else
    record_fail "fleet-gate: frozen project dropped from the sweep — removes the only automated signal on a project in production"
fi
if echo "${gate_out}" | grep -qE '^\| disabled-1 '; then
    record_fail "fleet-gate: disabled project swept (enabled:false must still exclude)"
else
    record_pass "fleet-gate: disabled project still excluded (frozen did not weaken the enabled filter)"
fi

# ─── Assertion 5: fleet_dashboard lists it, marked frozen ───────────────
dash_out="$(python3 "${DASHBOARD}" --registry "${ABS_WITH}" 2>&1)"
dash_json="$(python3 "${DASHBOARD}" --registry "${ABS_WITH}" --format json 2>/dev/null)"
d_frozen="$(echo "${dash_json}" | jq -r '.projects[] | select(.name=="frozen-1") | .frozen')"
if echo "${dash_out}" | grep -q 'frozen-1 (frozen)' && [[ "${d_frozen}" == "true" ]]; then
    record_pass "fleet-dashboard: frozen project still listed, and marked frozen"
else
    record_fail "fleet-dashboard: frozen project missing or unmarked (json frozen=${d_frozen})"
fi

# ─── Assertion 6: check-migration-coverage skips, and SAYS SO ───────────
mig_out="$(bash "${MIGRATION}" --registry "${ABS_WITH}" 2>&1)"
if echo "${mig_out}" | grep -qE '^\| frozen-1 .*FROZEN'; then
    record_pass "check-migration-coverage: frozen row reads FROZEN (skip reported, not a silent drop)"
else
    record_fail "check-migration-coverage: frozen project silently absent or not marked FROZEN"
fi
mig_one="$(bash "${MIGRATION}" --registry "${ABS_WITH}" --project frozen-1 2>&1)"
if echo "${mig_one}" | grep -qE '^\| frozen-1 ' && ! echo "${mig_one}" | grep -q 'FROZEN'; then
    record_pass "check-migration-coverage: --project on a frozen project still runs (explicit request is not a sweep)"
else
    record_fail "check-migration-coverage: --project on a frozen project did not run it"
fi

# ─── Assertion 7: audit-project-drift skips, and NAMES the skip ─────────
drift_out="$(bash "${DRIFT}" --registry "${ABS_WITH}" 2>&1)"
if echo "${drift_out}" | grep -qE '^\| frozen-1 '; then
    record_fail "audit-project-drift: frozen project still audited in a sweep"
elif echo "${drift_out}" | grep -q 'Skipped (frozen'; then
    record_pass "audit-project-drift: frozen project excluded AND named in the summary"
else
    record_fail "audit-project-drift: frozen project vanished with no explanation (silent shrink)"
fi
drift_one="$(bash "${DRIFT}" --registry "${ABS_WITH}" --project frozen-1 2>&1)"
if echo "${drift_one}" | grep -qE '^\| frozen-1 '; then
    record_pass "audit-project-drift: --project on a frozen project still audits it"
else
    record_fail "audit-project-drift: --project on a frozen project refused"
fi

# ─── Assertion 8: fleet-install-template refuses, with its OWN message ──
inst_frozen="$(bash "${INSTALL}" --registry "${ABS_WITH}" --project frozen-1 2>&1)"
inst_frozen_rc=$?
inst_disabled="$(bash "${INSTALL}" --registry "${ABS_WITH}" --project disabled-1 2>&1)"
inst_disabled_rc=$?
if [[ ${inst_frozen_rc} -eq 1 ]] && echo "${inst_frozen}" | grep -q 'is frozen in the registry' \
   && ! echo "${inst_frozen}" | grep -q 'is disabled in the registry'; then
    record_pass "fleet-install-template: refuses a frozen target with a frozen-specific message"
else
    record_fail "fleet-install-template: frozen refusal wrong (rc=${inst_frozen_rc})"
fi
if [[ ${inst_disabled_rc} -eq 1 ]] && echo "${inst_disabled}" | grep -q 'is disabled in the registry'; then
    record_pass "fleet-install-template: disabled refusal unchanged and still distinct from frozen"
else
    record_fail "fleet-install-template: disabled refusal changed (rc=${inst_disabled_rc})"
fi

# ─── Assertion 9: check-registry rejects the contradiction ──────────────
bad_contra="${TMP}/bad-contradictory.json"
cat > "${bad_contra}" <<'EOF'
[{"name":"a","path":"/no/such/checkout","gate_cmd":"./gate.sh","primary_language":"bash","enabled":false,"frozen":true}]
EOF
contra_out="$(bash "${CHECK_REGISTRY}" --registry "${bad_contra}" 2>&1)"
contra_rc=$?
if [[ ${contra_rc} -eq 1 ]] && echo "${contra_out}" | grep -q 'contradictory'; then
    record_pass "check-registry: rejects enabled:false + frozen:true (frozen qualifies an ENABLED project)"
else
    record_fail "check-registry: contradiction accepted (rc=${contra_rc})"
fi

# ─── Assertion 10: check-registry rejects missing / string-typed flags ───
bad_missing="${TMP}/bad-missing-enabled.json"
cat > "${bad_missing}" <<'EOF'
[{"name":"a","path":"/no/such/checkout","gate_cmd":"./gate.sh","primary_language":"bash"}]
EOF
missing_out="$(bash "${CHECK_REGISTRY}" --registry "${bad_missing}" 2>&1)"
missing_rc=$?
if [[ ${missing_rc} -eq 1 ]] && echo "${missing_out}" | grep -q 'missing required field `enabled`'; then
    record_pass "check-registry: a MISSING enabled is an error, not a silent false"
else
    record_fail "check-registry: missing enabled accepted (rc=${missing_rc})"
fi

bad_string="${TMP}/bad-string-bool.json"
cat > "${bad_string}" <<'EOF'
[{"name":"a","path":"/no/such/checkout","gate_cmd":"./gate.sh","primary_language":"bash","enabled":"true"}]
EOF
string_out="$(bash "${CHECK_REGISTRY}" --registry "${bad_string}" 2>&1)"
string_rc=$?
if [[ ${string_rc} -eq 1 ]] && echo "${string_out}" | grep -q 'must be a real boolean'; then
    record_pass "check-registry: rejects a string \"true\" where a boolean belongs"
else
    record_fail "check-registry: string-typed enabled accepted (rc=${string_rc})"
fi

# The real registry must pass its own validator — the check that would have
# caught this phase shipping a malformed entry.
if bash "${CHECK_REGISTRY}" >/dev/null 2>&1; then
    record_pass "check-registry: the live monitoring/projects.json conforms"
else
    record_fail "check-registry: the live monitoring/projects.json does NOT conform"
fi

# ─── Assertion 11: a registry with NO frozen keys is unchanged ──────────
# The backward-compatibility guarantee. Every pre-v1.30 registry omits the key
# entirely, and absent must mean false everywhere — asserted, not assumed.
nf_pins="$(python3 "${PINS}" --registry "${ABS_WITHOUT}" --latest v1.29 \
    --source local --format json 2>/dev/null)"
nf_status="$(echo "${nf_pins}" | jq -r '.projects[] | select(.name=="frozen-1") | .status')"
nf_dash="$(python3 "${DASHBOARD}" --registry "${ABS_WITHOUT}" 2>&1)"
nf_mig="$(bash "${MIGRATION}" --registry "${ABS_WITHOUT}" 2>&1)"
nf_drift="$(bash "${DRIFT}" --registry "${ABS_WITHOUT}" 2>&1)"
if [[ "${nf_status}" == "behind" ]] \
   && ! echo "${nf_dash}" | grep -q '(frozen)' \
   && ! echo "${nf_mig}" | grep -q 'FROZEN' \
   && ! echo "${nf_drift}" | grep -q 'Skipped (frozen'; then
    record_pass "no-frozen-key registry behaves exactly as pre-v1.30 (absent means false, everywhere)"
else
    record_fail "no-frozen-key registry changed behaviour (pins status=${nf_status})"
fi

nf_install="$(bash "${INSTALL}" --registry "${ABS_WITHOUT}" --project frozen-1 2>&1)"
nf_install_rc=$?
if [[ ${nf_install_rc} -eq 0 ]] && echo "${nf_install}" | grep -q 'Dry-run'; then
    record_pass "no-frozen-key registry: fleet-install-template still proceeds (no phantom refusal)"
else
    record_fail "no-frozen-key registry: install refused a project that is not frozen (rc=${nf_install_rc})"
fi

echo ""
echo "frozen-state: ${PASS_COUNT} PASS  ${FAIL_COUNT} FAIL  ${SKIP_COUNT} SKIP"
[[ ${FAIL_COUNT} -eq 0 ]] || exit 1
exit 0
