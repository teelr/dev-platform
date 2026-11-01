#!/usr/bin/env bash
# tests/prune-live-grants/run.sh — fixture suite for scripts/prune_live_grants.py
# (v1.43 Security Review Leftovers). Auto-discovered by scripts/gate_fast.sh.
#
# A tool that deletes permissions has to be shown to delete only what it should.
# Fixtures are built at runtime; each classification is also shown able to fail.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

PRUNE="${REPO}/scripts/prune_live_grants.py"
TMP="$(mktemp -d /tmp/prune-live-grants.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

base="${TMP}/base.json"
live="${TMP}/live.json"

reset_fixtures() {
    printf '{"permissions":{"allow":["Bash(git status)","Bash(sudo -n true)"]}}' > "${base}"
    python3 - "${live}" <<'EOF'
import json, sys
allow = [
    "Bash(git status)",                   # in baseline: kept
    "Bash(sudo -n true)",                 # in baseline though sudo-shaped: kept
    "Bash(kill 4242)",                    # pid-kill
    "Bash(kill -9 4243)",                 # pid-kill
    "Bash(sudo aa-status)",               # sudo
    "Bash(node /tmp/claude-1000/x/s.js)", # scratch-path
    "Bash(GH_TOKEN=$(cat ~/.t) gh pr list)",  # inline-token
    "Bash(kill *)",                       # unclassified: not a PID
    "Bash(npm run build)",                # unclassified
]
json.dump({"permissions": {"allow": allow, "deny": ["Bash(rm -rf /)"]},
           "hooks": {"x": 1}, "model": "m"}, open(sys.argv[1], "w"), indent=2)
EOF
}

# Check 1: module parses
if python3 -c "import ast; ast.parse(open('${PRUNE}').read())" 2>/dev/null; then
    record_pass "prune-live-grants: module parses"
else
    record_fail "prune-live-grants: module parse error"
fi

# Check 2: list mode writes nothing
reset_fixtures
before="$(sha256sum "${live}")"
out="$(python3 "${PRUNE}" "${base}" "${live}" 2>&1)"
after="$(sha256sum "${live}")"
baks="$(find "${TMP}" -name '*.bak-*' | wc -l)"
if [[ "${before}" == "${after}" && "${baks}" -eq 0 ]]; then
    record_pass "prune-live-grants: list mode writes nothing (no change, no backup)"
else
    record_fail "prune-live-grants: list mode modified files"
fi

# Check 3: each class detected, and non-matching entries are not
want_ok=1
for pair in "pid-kill:Bash(kill 4242)" "pid-kill:Bash(kill -9 4243)" "sudo:Bash(sudo aa-status)" \
            "scratch-path:Bash(node /tmp/claude-1000/x/s.js)" "inline-token:Bash(GH_TOKEN=" \
            "unclassified:Bash(kill *)" "unclassified:Bash(npm run build)"; do
    cls="${pair%%:*}"; frag="${pair#*:}"
    if ! grep -F -- "${frag}" <<<"${out}" | grep -q "^${cls} "; then
        want_ok=0; echo "    missing: ${cls} ${frag}" >&2
    fi
done
if [[ "${want_ok}" -eq 1 ]]; then
    record_pass "prune-live-grants: every class detected; 'kill *' and ordinary grants stay unclassified"
else
    record_fail "prune-live-grants: classification wrong"
fi

# Check 4: baseline entries are not candidates
if grep -q 'sudo -n true' <<<"${out}" || grep -q 'git status' <<<"${out}"; then
    record_fail "prune-live-grants: baseline entry listed as a candidate"
else
    record_pass "prune-live-grants: baseline entries are never candidates"
fi

# Check 5: --apply removes only the four classes, keeps the rest in order
reset_fixtures
python3 "${PRUNE}" "${base}" "${live}" --apply >/dev/null 2>&1
if python3 - "${live}" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
ok = (d["permissions"]["allow"] == ["Bash(git status)", "Bash(sudo -n true)", "Bash(kill *)", "Bash(npm run build)"]
      and d["permissions"]["deny"] == ["Bash(rm -rf /)"] and d["hooks"] == {"x": 1} and d["model"] == "m")
sys.exit(0 if ok else 1)
EOF
then
    record_pass "prune-live-grants: --apply removes only the four classes; other keys untouched"
else
    record_fail "prune-live-grants: --apply result wrong"
fi

# Check 6: backup exists, is 0600, and equals the pre-run file
reset_fixtures
cp "${live}" "${TMP}/pre.json"
python3 "${PRUNE}" "${base}" "${live}" --apply >/dev/null 2>&1
bak="$(find "${TMP}" -name 'live.json.bak-*' | head -1)"
if [[ -n "${bak}" ]] && cmp -s "${bak}" "${TMP}/pre.json" && [[ "$(stat -c %a "${bak}")" == "600" ]]; then
    record_pass "prune-live-grants: backup equals the pre-run file and is mode 600"
else
    record_fail "prune-live-grants: backup missing, different or wrong mode"
fi

# Check 7: baseline byte-identical after --apply
reset_fixtures
bsum="$(sha256sum "${base}")"
python3 "${PRUNE}" "${base}" "${live}" --apply >/dev/null 2>&1
if [[ "$(sha256sum "${base}")" == "${bsum}" ]]; then
    record_pass "prune-live-grants: baseline is never written"
else
    record_fail "prune-live-grants: baseline changed"
fi

# Check 8: nothing to remove writes no backup
printf '{"permissions":{"allow":["Bash(git status)","Bash(npm run build)"]}}' > "${live}"
rm -f "${TMP}"/live.json.bak-*
python3 "${PRUNE}" "${base}" "${live}" --apply >/dev/null 2>&1
if [[ -z "$(find "${TMP}" -name 'live.json.bak-*')" ]]; then
    record_pass "prune-live-grants: --apply with nothing to remove writes no backup"
else
    record_fail "prune-live-grants: backup written with nothing to remove"
fi

# Check 9: malformed live JSON exits 2
printf 'not json' > "${live}"
python3 "${PRUNE}" "${base}" "${live}" >/dev/null 2>&1
if [[ $? -eq 2 ]]; then
    record_pass "prune-live-grants: malformed live JSON exits 2"
else
    record_fail "prune-live-grants: malformed live JSON did not exit 2"
fi
