#!/usr/bin/env bash
# scripts/check-registry.sh — validate monitoring/projects.json.
#
# Six scripts read the fleet registry (fleet-gate.sh, fleet-install-template.sh,
# check-migration-coverage.sh, audit-project-drift.sh, fleet_pins.py,
# fleet_dashboard.py) and until v1.30 nothing validated it. A typo in gate_cmd
# breaks the fleet sweep for one project; a MISSING `enabled` key silently
# removes a project from every fleet operation, because every consumer reads it
# as false-if-absent. Neither produced an error anywhere.
#
# Schema reference: monitoring/README.md → "projects.json — the fleet registry".
#
# Checks:
#   1. Required fields present: name, path, gate_cmd, primary_language, enabled.
#      A missing `enabled` is an ERROR, not a default — silently disabling a
#      project is exactly the failure this catches.
#   2. `enabled` / `frozen` are real JSON booleans, not the strings
#      "true"/"false". This is not pedantry: the two consumer families would
#      disagree about the same entry. Given `"enabled": "false"`, the bash
#      consumers' `jq 'select(.enabled == true)'` excludes the project (a string
#      is not the boolean true), while Python's `entry.get("enabled", False)`
#      INCLUDES it — a non-empty string is truthy. One registry, two answers.
#   3. `enabled: false` + `frozen: true` is contradictory — `frozen` qualifies
#      an ENABLED project. Rejected outright rather than left as a precedence
#      rule for a reader to remember.
#   4. `name` is unique.
#   5. Where the project's checkout exists, gate_cmd's script exists in it.
#
# Check 5 is the only environment-dependent one: `projects/` is gitignored, so
# on a CI runner or a fresh clone there is nothing to resolve against. It is
# reported as verified-vs-skipped per project rather than passing silently —
# see the note above the summary for why the SCRIPT still exits 0/1 there.
#
# Usage:
#   ./scripts/check-registry.sh                    # the real registry
#   ./scripts/check-registry.sh --registry <path>  # tests
#   ./scripts/check-registry.sh --help
#
# Exit codes:
#   0 — registry valid
#   1 — at least one violation (each named)
#   2 — setup error (jq absent, registry missing or not a JSON array)

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REPO}/monitoring/projects.json"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --registry)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --registry requires an argument" >&2; exit 2; }
            REGISTRY="$1"
            ;;
        --help|-h)
            cat <<'HELP'
scripts/check-registry.sh — validate monitoring/projects.json.

Checks required fields, boolean types, the contradictory
`enabled: false` + `frozen: true` combination, unique names, and (where
the checkout exists) that each gate_cmd's script is really there.

Options:
  --registry <path>   Override registry path (for tests).
  --help, -h          Show this help.

Exit:
  0  registry valid
  1  at least one violation
  2  setup error (jq absent, registry missing or not a JSON array)

Schema reference: monitoring/README.md
HELP
            exit 0
            ;;
        *)
            echo "ERROR: unknown arg: $1" >&2
            exit 2
            ;;
    esac
    shift
done

command -v jq >/dev/null || { echo "ERROR: jq required" >&2; exit 2; }
[[ -f "${REGISTRY}" ]] || { echo "ERROR: registry not found at ${REGISTRY}" >&2; exit 2; }

# After the required-tools gate on purpose: REPO is built with `dirname`, an
# external command, so with an emptied PATH it comes out empty and sourcing from
# it would fail first — masking the tool error the gate exists to report. Same
# ordering as fleet-gate.sh and fleet-install-template.sh.
# shellcheck source=lib/main_checkout.sh
source "${REPO}/scripts/lib/main_checkout.sh" || {
    echo "ERROR: missing ${REPO}/scripts/lib/main_checkout.sh" >&2
    exit 2
}
FLEET_ROOT="$(resolve_main_checkout "${REPO}")"

if ! jq -e 'type == "array"' "${REGISTRY}" >/dev/null 2>&1; then
    echo "ERROR: registry must be a JSON array: ${REGISTRY}" >&2
    exit 2
fi

# --- Checks 1-4: schema, entirely from the registry file. ---------------------
# One jq program emitting one line per violation. Entries missing `name` are
# still identifiable, by index.
violations="$(jq -r '
    def err($who; $msg): "\($who): \($msg)";
    . as $all
    | [
        ( range(0; ($all | length)) as $i
          | $all[$i] as $e
          | (if ($e | type) == "object" and ($e.name | type) == "string"
             then $e.name else "<entry \($i)>" end) as $n
          | (
              if ($e | type) != "object" then
                  err($n; "entry is a \($e | type), not an object")
              else
                  (
                      ( ["name","path","gate_cmd","primary_language","enabled"][] as $f
                        | select($e | has($f) | not)
                        | err($n; "missing required field `\($f)`"
                                  + (if $f == "enabled"
                                     then " — every consumer reads a missing `enabled` as FALSE, which silently drops the project from the whole fleet"
                                     else "" end)) ),
                      ( select(($e | has("enabled")) and (($e.enabled | type) != "boolean"))
                        | err($n; "`enabled` must be a real boolean, got \($e.enabled | type) \($e.enabled | tojson)") ),
                      ( select(($e | has("frozen")) and (($e.frozen | type) != "boolean"))
                        | err($n; "`frozen` must be a real boolean, got \($e.frozen | type) \($e.frozen | tojson)") ),
                      ( select($e.enabled == false and $e.frozen == true)
                        | err($n; "contradictory `enabled: false` with `frozen: true` — `frozen` qualifies an ENABLED project; a disabled entry is skipped regardless") )
                  )
              end
            )
        ),
        ( $all
          | map(select((type == "object") and (.name | type == "string")))
          | group_by(.name) | .[] | select(length > 1)
          | err(.[0].name; "duplicate `name` (\(length) entries)") )
      ]
    | .[]
' "${REGISTRY}")"

FAILURES=0
if [[ -n "${violations}" ]]; then
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        echo "FAIL  ${line}"
        FAILURES=$((FAILURES + 1))
    done <<< "${violations}"
fi

# --- Check 5: gate_cmd's script exists, where the checkout does. --------------
gate_checked=0
gate_skipped=0
gate_external=0
skipped_names=()
external_names=()

while IFS=$'\t' read -r name path gate_cmd; do
    [[ -z "${name}" ]] && continue

    if [[ "${path}" == "." ]]; then
        target="${REPO}"
    elif [[ "${path}" == /* ]]; then
        target="${path}"
    else
        target="${FLEET_ROOT}/${path}"
    fi

    if [[ ! -d "${target}" ]]; then
        gate_skipped=$((gate_skipped + 1))
        skipped_names+=("${name}")
        continue
    fi

    # gate_cmd carries arguments ("./scripts/gate.sh fast"); the script is the
    # first token. Only its existence is checkable without running it.
    #
    # Not every gate_cmd names a file in the repo: kermit's is `make check`, a
    # command resolved on PATH. Asserting a repo-relative file for that one
    # reports a missing `make` script that was never supposed to exist — a
    # checker inventing a violation is worse than one check fewer, so the two
    # shapes are counted separately and only the path-shaped form is asserted.
    script="${gate_cmd%% *}"
    if [[ "${script}" != */* ]]; then
        gate_external=$((gate_external + 1))
        external_names+=("${name} (${script})")
    elif [[ -f "${target}/${script}" ]]; then
        gate_checked=$((gate_checked + 1))
    else
        echo "FAIL  ${name}: gate_cmd script not found — ${script} is missing from ${target}"
        FAILURES=$((FAILURES + 1))
    fi
done < <(jq -r '.[] | select(type == "object")
                    | select(has("name") and has("path") and has("gate_cmd"))
                    | "\(.name)\t\(.path)\t\(.gate_cmd)"' "${REGISTRY}")

# The gate_cmd leg's coverage is REPORTED, never assumed. It is the one leg that
# can verify nothing (no `projects/` on a CI runner or a fresh clone), and a
# check that passes having read nothing is the failure mode this repo keeps
# rediscovering.
#
# Unlike check_env_leak.sh, this script does NOT exit 2 in that situation: four
# of its five checks read the tracked registry file, which is always present, so
# they really did run. Reporting the whole script as SKIP would hide four
# passing checks to describe one that could not run. The coverage line says
# which is which instead.
echo "check-registry: gate_cmd — ${gate_checked} verified, ${gate_skipped} skipped (no checkout), ${gate_external} not a repo path"
if [[ ${gate_skipped} -gt 0 ]]; then
    echo "  no checkout: ${skipped_names[*]}"
fi
if [[ ${gate_external} -gt 0 ]]; then
    echo "  PATH command, not asserted: ${external_names[*]}"
fi

entry_count="$(jq -r 'length' "${REGISTRY}")"
if [[ ${FAILURES} -gt 0 ]]; then
    echo "check-registry: ${FAILURES} violation(s) in ${REGISTRY}"
    echo "  Schema reference: monitoring/README.md → \"projects.json — the fleet registry\""
    exit 1
fi

echo "check-registry: ${entry_count} entries conform"
exit 0
