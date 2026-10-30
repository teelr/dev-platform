#!/usr/bin/env bash
# tests/merge-settings/run.sh — fixture suite for scripts/merge_settings.py
# (v1.6 Local Settings Isolation). Auto-discovered by scripts/gate_fast.sh.
#
# Covers the merge contract: union permission arrays, baseline wins config keys,
# first-install seed, malformed-JSON exit 2, dry-run writes nothing, and the
# load-bearing invariant that the baseline file is NEVER written.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

MERGE="${REPO}/scripts/merge_settings.py"
TMP="$(mktemp -d /tmp/merge-settings.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

# Check 1: module parses
if python3 -c "import ast; ast.parse(open('${MERGE}').read())" 2>/dev/null; then
    record_pass "merge-settings: module parses"
else
    record_fail "merge-settings: module parse error"
fi

# Check 2: union preserves live grants + adds baseline entries
base="${TMP}/base.json"; live="${TMP}/live.json"
printf '{"permissions":{"allow":["Bash(a)","Bash(b)"]},"model":"opusplan"}' > "${base}"
printf '{"permissions":{"allow":["Bash(b)","Bash(LOCAL)"]},"model":"OLD"}' > "${live}"
python3 "${MERGE}" "${base}" "${live}" >/dev/null 2>&1
if python3 -c "
import json,sys
d=json.load(open('${live}'))
sys.exit(0 if set(d['permissions']['allow'])=={'Bash(a)','Bash(b)','Bash(LOCAL)'} else 1)
"; then
    record_pass "merge-settings: union preserves live grants + adds baseline entries"
else
    record_fail "merge-settings: allow union wrong"
fi

# Check 3: baseline wins on config keys
if python3 -c "import json,sys; sys.exit(0 if json.load(open('${live}'))['model']=='opusplan' else 1)"; then
    record_pass "merge-settings: baseline wins on config keys (model)"
else
    record_fail "merge-settings: baseline did not win on config key"
fi

# Check 4: first-install seed (no live file) == baseline verbatim
seed_live="${TMP}/seed.json"
python3 "${MERGE}" "${base}" "${seed_live}" >/dev/null 2>&1
if [[ -f "${seed_live}" ]] && python3 -c "import json,sys; sys.exit(0 if json.load(open('${seed_live}'))['model']=='opusplan' else 1)"; then
    record_pass "merge-settings: first-install seeds baseline verbatim"
else
    record_fail "merge-settings: seed path failed"
fi

# Check 5: malformed baseline → exit 2
bad="${TMP}/bad.json"; printf 'not json' > "${bad}"
python3 "${MERGE}" "${bad}" "${live}" >/dev/null 2>&1
if [[ $? -eq 2 ]]; then
    record_pass "merge-settings: malformed JSON exits 2"
else
    record_fail "merge-settings: malformed JSON did not exit 2"
fi

# Check 6: --dry-run writes nothing to live
dry_live="${TMP}/dry.json"
printf '{"permissions":{"allow":["Bash(keep)"]}}' > "${dry_live}"
before="$(cat "${dry_live}")"
out="$(python3 "${MERGE}" "${base}" "${dry_live}" --dry-run 2>/dev/null)"
after="$(cat "${dry_live}")"
if [[ "${before}" == "${after}" ]] && echo "${out}" | grep -q "Bash(a)"; then
    record_pass "merge-settings: --dry-run prints merged result, writes nothing"
else
    record_fail "merge-settings: --dry-run mutated the live file or printed nothing"
fi

# Check 7: baseline file is NEVER written (the load-bearing safety invariant)
base_before="$(cat "${base}")"
python3 "${MERGE}" "${base}" "${live}" >/dev/null 2>&1
if [[ "$(cat "${base}")" == "${base_before}" ]]; then
    record_pass "merge-settings: baseline file is never written"
else
    record_fail "merge-settings: baseline file was modified — repo-pollution risk"
fi

# --- v1.39 retract support -------------------------------------------------

rbase="${TMP}/rbase.json"; rlive="${TMP}/rlive.json"; rret="${TMP}/rret.json"
printf '{"permissions":{"allow":["Bash(keep)"]}}' > "${rbase}"
printf '{"permissions":{"allow":["Bash(bash *)","Bash(bash ~/x/*)","Bash(other)"],"deny":["Bash(bash *)"]}}' > "${rlive}"
printf '{"allow":["Bash(bash *)"]}' > "${rret}"

# Check 8: retract removes only the exact match; narrow entry and baseline entry survive
python3 "${MERGE}" "${rbase}" "${rlive}" --retract "${rret}" >/dev/null 2>&1
if python3 -c "
import json,sys
d=json.load(open('${rlive}'))['permissions']
ok = set(d['allow'])=={'Bash(bash ~/x/*)','Bash(other)','Bash(keep)'} and d['deny']==['Bash(bash *)']
sys.exit(0 if ok else 1)
"; then
    record_pass "merge-settings: retract removes exact match only, leaves narrow allow and deny"
else
    record_fail "merge-settings: retract result wrong"
fi

# Check 9: no --retract argument removes nothing
printf '{"permissions":{"allow":["Bash(bash *)"]}}' > "${rlive}"
python3 "${MERGE}" "${rbase}" "${rlive}" >/dev/null 2>&1
if python3 -c "
import json,sys
sys.exit(0 if 'Bash(bash *)' in json.load(open('${rlive}'))['permissions']['allow'] else 1)
"; then
    record_pass "merge-settings: without --retract nothing is removed"
else
    record_fail "merge-settings: entry removed without --retract"
fi

# Check 10: contradiction (baseline allow also retracted) exits 2
printf '{"allow":["Bash(keep)"]}' > "${TMP}/rcontra.json"
python3 "${MERGE}" "${rbase}" "${rlive}" --retract "${TMP}/rcontra.json" >/dev/null 2>&1
if [[ $? -eq 2 ]]; then
    record_pass "merge-settings: baseline/retract contradiction exits 2"
else
    record_fail "merge-settings: contradiction did not exit 2"
fi

# Check 11: malformed, wrong-shape, and missing retract files exit 2
printf 'not json' > "${TMP}/rbad.json"
printf '{"allow":"Bash(x)"}' > "${TMP}/rshape.json"
rc_ok=1
for f in "${TMP}/rbad.json" "${TMP}/rshape.json" "${TMP}/does-not-exist.json"; do
    python3 "${MERGE}" "${rbase}" "${rlive}" --retract "${f}" >/dev/null 2>&1
    [[ $? -eq 2 ]] || rc_ok=0
done
if [[ "${rc_ok}" -eq 1 ]]; then
    record_pass "merge-settings: malformed / wrong-shape / missing retract file exits 2"
else
    record_fail "merge-settings: a bad retract file did not exit 2"
fi

# Check 12: --dry-run with --retract prints the retracted result, writes nothing
printf '{"permissions":{"allow":["Bash(bash *)"]}}' > "${rlive}"
before="$(cat "${rlive}")"
out="$(python3 "${MERGE}" "${rbase}" "${rlive}" --retract "${rret}" --dry-run 2>/dev/null)"
if [[ "$(cat "${rlive}")" == "${before}" ]] && ! echo "${out}" | grep -q 'Bash(bash \*)'; then
    record_pass "merge-settings: --dry-run --retract prints result, writes nothing"
else
    record_fail "merge-settings: --dry-run --retract wrong"
fi

# Check 13: the baseline and retract files are never written
rbase_before="$(cat "${rbase}")"; rret_before="$(cat "${rret}")"
python3 "${MERGE}" "${rbase}" "${rlive}" --retract "${rret}" >/dev/null 2>&1
if [[ "$(cat "${rbase}")" == "${rbase_before}" && "$(cat "${rret}")" == "${rret_before}" ]]; then
    record_pass "merge-settings: baseline and retract files are never written"
else
    record_fail "merge-settings: a tracked input file was modified"
fi

exit $(( FAIL_COUNT > 0 ? 1 : 0 ))
