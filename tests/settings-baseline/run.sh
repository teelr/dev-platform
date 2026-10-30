#!/usr/bin/env bash
# tests/settings-baseline/run.sh — invariants on the tracked permission baseline
# (v1.39 Settings Permission Tightening). Auto-discovered by scripts/gate_fast.sh.
#
# Stops a later edit from re-adding a broad allow (Bash(bash *), Bash(curl *), ...),
# dropping the force-push / secret-read denies, or leaving the retract list and
# the baseline disagreeing.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

BASE="${REPO}/settings/settings.json"
RETRACT="${REPO}/settings/permissions-retract.json"

# Check 1: both files parse
if python3 -c "import json; json.load(open('${BASE}')); json.load(open('${RETRACT}'))" 2>/dev/null; then
    record_pass "settings-baseline: settings.json and permissions-retract.json parse"
else
    record_fail "settings-baseline: settings.json or permissions-retract.json is not valid JSON"
    exit 1
fi

# Check 2: no broad allow that re-opens arbitrary execution or remote access
bad="$(python3 -c "
import json
allow = set(json.load(open('${BASE}'))['permissions']['allow'])
banned = ['Bash(bash *)', 'Bash(sh *)', 'Bash(curl *)', 'Bash(ssh *)', 'Bash(scp *)',
          'Bash(kill *)', 'Bash(pkill *)', 'Bash(source *)', 'Bash(xargs *)', 'Bash(apt *)',
          'Bash(systemctl *)', 'Bash(env *)', 'Bash(export *)', 'Bash(tee *)', 'Bash(/tmp/*)']
print(' '.join(b for b in banned if b in allow))
")"
if [[ -z "${bad}" ]]; then
    record_pass "settings-baseline: no broad allow entry re-added"
else
    record_fail "settings-baseline: banned allow entries present: ${bad}"
fi

# Check 3: required deny entries are present
missing="$(python3 -c "
import json
deny = set(json.load(open('${BASE}'))['permissions']['deny'])
required = ['Bash(git push --force*)', 'Bash(git push -f *)', 'Bash(curl * | *)',
            'Read(//home/rich/.ssh/**)', 'Read(**/.env)', 'Read(**/.env.*)',
            'Bash(rm -rf /)', 'Bash(chmod 777*)']
print(' '.join(r for r in required if r not in deny))
")"
if [[ -z "${missing}" ]]; then
    record_pass "settings-baseline: required deny entries present"
else
    record_fail "settings-baseline: deny entries missing: ${missing}"
fi

# Check 4: no allow entry is also retracted (merge_settings.py exits 2 on this)
both="$(python3 -c "
import json
allow = set(json.load(open('${BASE}'))['permissions']['allow'])
retract = set(json.load(open('${RETRACT}'))['allow'])
print(' '.join(sorted(allow & retract)))
")"
if [[ -z "${both}" ]]; then
    record_pass "settings-baseline: no entry is both allowed and retracted"
else
    record_fail "settings-baseline: allowed and retracted: ${both}"
fi

# Check 5: retract entries are well-formed permission strings
badshape="$(python3 -c "
import json
r = json.load(open('${RETRACT}'))['allow']
print(' '.join(e for e in r if not (isinstance(e, str) and e.startswith(('Bash(', 'Read(')) and e.endswith(')'))))
")"
if [[ -z "${badshape}" ]]; then
    record_pass "settings-baseline: retract entries are well-formed"
else
    record_fail "settings-baseline: malformed retract entries: ${badshape}"
fi

# Check 6: ask never holds a pattern that would override a narrow workflow allow
# (ask outranks allow; Bash(bash *) in ask would prompt on link-deps.sh).
ask_bad="$(python3 -c "
import json
ask = set(json.load(open('${BASE}'))['permissions'].get('ask', []))
print(' '.join(a for a in ['Bash(bash *)', 'Bash(rm *)', 'Bash(kill *)', 'Bash(curl *)'] if a in ask))
")"
if [[ -z "${ask_bad}" ]]; then
    record_pass "settings-baseline: ask list holds no pattern that overrides workflow allows"
else
    record_fail "settings-baseline: ask holds ${ask_bad} (ask outranks allow)"
fi

exit $(( FAIL_COUNT > 0 ? 1 : 0 ))
