#!/usr/bin/env bash
# scripts/check-migration-coverage.sh — do the migration scripts actually parse
# what consumers actually have?
#
# WHY THIS EXISTS: migrate-lessons.sh and migrate-shipped.sh each say in their
# own headers that they are committed "so consumer projects can port their own."
# That claim sat in the tree from v1.23/v1.24 until v1.28 without anyone running
# either script against a consumer file — and when someone did, both failed on
# every consumer but one. A claim with no detector is the failure this repo has
# now recorded three times (v1.10 milestones, v1.26 tags, v1.28 this).
#
# WHAT IT DOES: walks monitoring/projects.json and dry-runs both scripts against
# each consumer's real tasks/lessons.md and planning.md. One row per source.
#
# STRICTLY READ-ONLY. Dry-run only, never --apply; writes nothing under
# projects/. The Scope rule permits read-only cross-project operations.
#
# Not wired into gate_fast.sh: it depends on consumer checkouts being present,
# which a CI runner's fresh clone does not have. It is a fleet report, like
# scripts/fleet-pins.sh.
#
# Usage:
#   ./scripts/check-migration-coverage.sh              # all enabled consumers
#   ./scripts/check-migration-coverage.sh --project X  # one
#   ./scripts/check-migration-coverage.sh --registry <path>   # tests
#   ./scripts/check-migration-coverage.sh --help
#
# Exit codes:
#   0 — every consumer's source file either parses or is already migrated
#   1 — at least one source file exists and fails to parse
#   2 — setup error (jq absent, registry missing, bad argument)

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REPO}/monitoring/projects.json"
SINGLE_PROJECT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --project requires a name" >&2; exit 2; }
            SINGLE_PROJECT="$1"; shift ;;
        --registry)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --registry requires a path" >&2; exit 2; }
            REGISTRY="$1"; shift ;;
        --help|-h)
            cat <<'HELP'
check-migration-coverage.sh — dry-run the migration scripts against every
consumer's real lessons.md / planning.md and report whether they parse.

  ./scripts/check-migration-coverage.sh              all enabled consumers
  ./scripts/check-migration-coverage.sh --project X  one project
  ./scripts/check-migration-coverage.sh --registry <path>

Read-only: dry-run only, never --apply, writes nothing under projects/.
Exit 1 when a source file exists and fails to parse.
HELP
            exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    esac
done

command -v jq >/dev/null || { echo "ERROR: jq required" >&2; exit 2; }
[[ -f "${REGISTRY}" ]] || { echo "ERROR: registry not found at ${REGISTRY}" >&2; exit 2; }

# Registry paths are relative to the MAIN checkout — projects/ is gitignored and
# exists nowhere else. Sourced after the tools gate above: REPO is built with
# `dirname`, so under an emptied PATH it is empty and sourcing from it would
# fail first, masking the jq error (v1.27).
# shellcheck source=lib/main_checkout.sh
source "${REPO}/scripts/lib/main_checkout.sh" || {
    echo "ERROR: missing ${REPO}/scripts/lib/main_checkout.sh" >&2
    exit 2
}
FLEET_ROOT="$(resolve_main_checkout "${REPO}")"

LESSONS_SCRIPT="${REPO}/scripts/migrate-lessons.sh"
SHIPPED_SCRIPT="${REPO}/scripts/migrate-shipped.sh"
PROBE_DIR="$(mktemp -d /tmp/migration-coverage.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${PROBE_DIR}'" EXIT

FAILURES=0
ROWS=""

# Probe one source file with one script. Echoes "<ok|fail>|<cell>".
#
# The caller splits and counts, because probe() runs inside a command
# substitution — a subshell — so anything it increments is discarded when it
# exits. An earlier draft did exactly that and printed FAILS rows while exiting
# 0, which is the precise failure this detector exists to catch. Returning the
# verdict in the output is what makes the count survive.
#
# Never runs --apply, so PROBE_DIR stays empty; it exists only to give the
# scripts a target they will not write to.
probe() {
    local script="$1" env_file_var="$2" env_dir_var="$3" src="$4" migrated_dir="$5"

    if [[ -d "${migrated_dir}" ]]; then
        echo "ok|MIGRATED ($(find "${migrated_dir}" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ') files)"
        return 0
    fi
    if [[ ! -f "${src}" ]]; then
        echo "ok|NO SOURCE"
        return 0
    fi

    local out rc
    out="$(env "${env_file_var}=${src}" "${env_dir_var}=${PROBE_DIR}/out" \
           bash "${script}" 2>&1)"
    rc=$?

    # A format with no per-entry date refuses to guess one — correct behaviour,
    # not a parse failure. Retry with a date so the probe can see whether the
    # CONTENT parses. Only on that specific complaint: the dated format rejects
    # --date-from outright, and passing it blindly turned a working consumer
    # into a FAILS row on the first version of this check.
    if [[ ${rc} -ne 0 ]] && echo "${out}" | grep -q 'pass --date-from'; then
        out="$(env "${env_file_var}=${src}" "${env_dir_var}=${PROBE_DIR}/out" \
               bash "${script}" --date-from today 2>&1)"
        rc=$?
    fi

    # "Nothing to migrate" is not a failure: the file exists but holds no
    # shipped content in any known shape. Distinguish it from a parser choking.
    if echo "${out}" | grep -q "nothing to migrate"; then
        echo "ok|NO SECTION"
        return 0
    fi

    if [[ ${rc} -ne 0 ]]; then
        # A run that only needs per-project flags is actionable work for that
        # project, not a defect in the tool. SQRL's 8 category headings are the
        # case: it parses cleanly once they are named.
        if echo "${out}" | grep -qE '^  ## '; then
            local n
            n="$(echo "${out}" | grep -cE '^  ## ')"
            echo "ok|NEEDS --ignore-heading (${n})"
            return 0
        fi
        local why
        why="$(echo "${out}" | grep -m1 -E 'aborting|no .* found' \
               | sed -e 's/^[a-z-]*: //' -e "s#${src}#<source>#" | cut -c1-52)"
        echo "fail|FAILS (${why:-see output})"
        return 0
    fi

    # rc == 0 is not the same as "worked". A parser that matches nothing exits
    # cleanly having found 0 entries in a file full of them — which is what the
    # table parser does to every heading-format consumer. A non-empty source
    # yielding 0 entries is a failure, not a pass.
    local n
    n="$(echo "${out}" | grep -oE '— [0-9]+ ' | head -1 | tr -dc '0-9')"
    if [[ -z "${n}" ]]; then
        echo "fail|FAILS (no entry count in output)"
    elif [[ "${n}" -eq 0 ]]; then
        echo "fail|FAILS (0 of $(grep -c '^## ' "${src}" 2>/dev/null || echo '?') headings parsed)"
    else
        echo "ok|PARSES (${n} entries)"
    fi
    return 0
}

mapfile -t entries < <(jq -c '.[] | select(.enabled == true) | select(.name != "dev-platform")' "${REGISTRY}")

for entry in "${entries[@]}"; do
    name="$(echo "${entry}" | jq -r '.name')"
    [[ -n "${SINGLE_PROJECT}" && "${name}" != "${SINGLE_PROJECT}" ]] && continue

    # A frozen project is deployed but not developed. This check asks whether
    # the lessons/shipped migrations CAN run — a convention that exists to stop
    # FUTURE concurrent appends colliding in one file. A frozen repo gets no
    # future appends, so migrating it would be reorganising a file nobody will
    # write to again.
    #
    # The row is still printed, reading FROZEN, rather than the project quietly
    # dropping out of the table: an unexplained absence is indistinguishable
    # from a broken filter. Named explicitly with --project, it still runs —
    # an explicit request is not a sweep.
    frozen="$(echo "${entry}" | jq -r '.frozen // false')"
    if [[ "${frozen}" == "true" && -z "${SINGLE_PROJECT}" ]]; then
        ROWS+="$(printf '| %-20s | %-34s | %-34s |' \
            "${name}" "FROZEN (skipped)" "FROZEN (skipped)")"$'\n'
        continue
    fi

    path_raw="$(echo "${entry}" | jq -r '.path')"
    if [[ "${path_raw}" == /* ]]; then target="${path_raw}"; else target="${FLEET_ROOT}/${path_raw}"; fi

    lessons_raw="$(probe "${LESSONS_SCRIPT}" LESSONS_FILE LESSONS_DIR \
        "${target}/tasks/lessons.md" "${target}/tasks/lessons")"
    shipped_raw="$(probe "${SHIPPED_SCRIPT}" PLANNING_FILE SHIPPED_DIR \
        "${target}/planning.md" "${target}/tasks/shipped")"

    # Split "<verdict>|<cell>" and count in THIS shell, not the subshell.
    [[ "${lessons_raw%%|*}" == "fail" ]] && FAILURES=$((FAILURES + 1))
    [[ "${shipped_raw%%|*}" == "fail" ]] && FAILURES=$((FAILURES + 1))
    lessons_cell="${lessons_raw#*|}"
    shipped_cell="${shipped_raw#*|}"

    ROWS+="$(printf '| %-20s | %-34s | %-34s |' "${name}" "${lessons_cell}" "${shipped_cell}")"$'\n'
done

if [[ -n "${SINGLE_PROJECT}" && -z "${ROWS}" ]]; then
    echo "ERROR: project '${SINGLE_PROJECT}' not found in registry (or disabled)" >&2
    exit 2
fi

echo "# Migration Coverage"
echo
echo "Registry: ${REGISTRY#"${REPO}"/}"
echo "Fleet root: ${FLEET_ROOT}"
echo
printf '| %-20s | %-34s | %-34s |\n' "Project" "lessons.md" "planning.md"
printf '| %-20s | %-34s | %-34s |\n' "$(printf '%.0s-' {1..20})" "$(printf '%.0s-' {1..34})" "$(printf '%.0s-' {1..34})"
printf '%s' "${ROWS}"
echo

if [[ ${FAILURES} -gt 0 ]]; then
    echo "check-migration-coverage: ${FAILURES} source file(s) fail to parse."
    echo "  A consumer that cannot run the migration script cannot adopt the convention."
    exit 1
fi

echo "check-migration-coverage: every consumer source parses or is already migrated."
exit 0
