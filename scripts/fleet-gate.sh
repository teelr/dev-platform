#!/usr/bin/env bash
# scripts/fleet-gate.sh — read-only fleet sweep.
#
# Walks monitoring/projects.json and runs each enabled project's gate command
# in parallel with a per-project timeout. Aggregates per-project results into
# a fleet-level PASS/FAIL summary; exits non-zero if any project's gate fails
# or times out.
#
# Usage:
#   ./scripts/fleet-gate.sh                          # all enabled projects
#   ./scripts/fleet-gate.sh --project <name>         # single project
#   ./scripts/fleet-gate.sh --parallel 2             # cap concurrency (default 4)
#   ./scripts/fleet-gate.sh --timeout 60             # per-project hard timeout (default 300s)
#   ./scripts/fleet-gate.sh --all                    # include enabled:false entries
#   ./scripts/fleet-gate.sh --registry <path>        # override registry path (tests)
#   ./scripts/fleet-gate.sh --help
#
# Exit codes:
#   0 — every invoked gate PASSed
#   1 — at least one gate FAILed or TIMED OUT
#   2 — setup error (missing registry, jq absent, invalid args)

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REPO}/monitoring/projects.json"
PARALLEL=4
TIMEOUT=300
INCLUDE_DISABLED=0
SINGLE_PROJECT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --project requires an argument" >&2; exit 2; }
            SINGLE_PROJECT="$1"
            ;;
        --parallel)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --parallel requires an argument" >&2; exit 2; }
            PARALLEL="$1"
            ;;
        --timeout)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --timeout requires an argument" >&2; exit 2; }
            TIMEOUT="$1"
            ;;
        --all)
            INCLUDE_DISABLED=1
            ;;
        --registry)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --registry requires an argument" >&2; exit 2; }
            REGISTRY="$1"
            ;;
        --help|-h)
            cat <<'HELP'
scripts/fleet-gate.sh — read-only fleet sweep.

Runs each enabled project's gate command in parallel with a per-project
timeout. Aggregates results into a PASS/FAIL/TIMEOUT/SKIP summary; exits
non-zero on any FAIL or TIMEOUT.

Options:
  --project <name>      Only run the named project (single-project sweep).
  --parallel <N>        Cap concurrency (default: 4).
  --timeout <SEC>       Per-project hard timeout (default: 300).
  --all                 Include enabled:false entries (default: skip).
  --registry <path>     Override registry path (for tests).
  --help, -h            Show this help.

Output: markdown table + summary line + per-failing-project log paths.
Telemetry: emits one fleet_gate_run JSONL event per sweep.

Exit:
  0  every invoked gate PASSed
  1  at least one gate FAILed or TIMED OUT
  2  setup error (missing registry, jq absent, invalid args)
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

# Per-sweep log directory
LOG_TS="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="/tmp/fleet-gate.${LOG_TS}"
mkdir -p "${LOG_DIR}"

# Filter: enabled projects only (default), plus optional single-project filter.
filter='.[]'
if [[ ${INCLUDE_DISABLED} -eq 0 ]]; then
    filter="${filter} | select(.enabled == true)"
fi
if [[ -n "${SINGLE_PROJECT}" ]]; then
    filter="${filter} | select(.name == \"${SINGLE_PROJECT}\")"
fi

# Materialize the project list as tab-separated rows.
project_rows="$(jq -r "${filter} | \"\\(.name)\\t\\(.path)\\t\\(.gate_cmd)\"" "${REGISTRY}")"
project_count="$(echo "${project_rows}" | grep -cv "^$" || true)"

if [[ ${project_count} -eq 0 ]]; then
    if [[ -n "${SINGLE_PROJECT}" ]]; then
        echo "ERROR: project '${SINGLE_PROJECT}' not found in registry (or disabled — use --all to include)" >&2
        exit 2
    fi
    echo "ERROR: no projects to gate" >&2
    exit 2
fi

START=$(date +%s)
echo "=== fleet gate ==="
echo ""
echo "Registry: ${REGISTRY#${REPO}/} (${project_count} to sweep)"
echo "Parallel: ${PARALLEL}"
echo "Timeout:  ${TIMEOUT}s"
echo "Logs:     ${LOG_DIR}"
echo ""

# Run gates in parallel, respecting --parallel cap. Each child writes its
# result line to its own per-project tmpfile so the parent can collect them.
results_dir="${LOG_DIR}/results"
mkdir -p "${results_dir}"

run_one() {
    local name="$1"
    local path="$2"
    local gate_cmd="$3"
    local log="${LOG_DIR}/${name}.log"
    local result_file="${results_dir}/${name}"
    local target_path
    target_path="$([[ "${path}" == "." ]] && echo "${REPO}" || echo "${REPO}/${path}")"

    local start end duration
    start=$(date +%s)

    if [[ ! -d "${target_path}" ]]; then
        end=$(date +%s)
        duration=$((end - start))
        printf "MISSING\t%s\n" "${duration}" > "${result_file}"
        return
    fi

    # `timeout` exits 124 on timeout, otherwise propagates the command's exit.
    (cd "${target_path}" && timeout "${TIMEOUT}" bash -c "${gate_cmd}") >"${log}" 2>&1
    local rc=$?
    end=$(date +%s)
    duration=$((end - start))

    if [[ ${rc} -eq 0 ]]; then
        printf "PASS\t%s\n" "${duration}" > "${result_file}"
    elif [[ ${rc} -eq 124 ]]; then
        printf "TIMEOUT\t%s\n" "${duration}" > "${result_file}"
    else
        printf "FAIL\t%s\n" "${duration}" > "${result_file}"
    fi
}

# Launch with parallel cap. We rely on `wait -n` (bash 4.3+) for first-to-finish
# semantics; fall back to plain `wait` when -n isn't supported (graceful degrade).
running=0
while IFS=$'\t' read -r name path gate_cmd; do
    [[ -z "${name}" ]] && continue
    run_one "${name}" "${path}" "${gate_cmd}" &
    running=$((running + 1))
    if [[ ${running} -ge ${PARALLEL} ]]; then
        wait -n 2>/dev/null || wait
        running=$((running - 1))
    fi
done <<< "${project_rows}"
wait

# Build the summary table.
echo "| Project           | Result   | Duration |"
echo "| ----------------- | -------- | -------- |"
pass_count=0
fail_count=0
timeout_count=0
skip_count=0
fail_names=()

while IFS=$'\t' read -r name path gate_cmd; do
    [[ -z "${name}" ]] && continue
    if [[ -f "${results_dir}/${name}" ]]; then
        IFS=$'\t' read -r result duration < "${results_dir}/${name}"
        printf "| %-17s | %-8s | %6ss   |\n" "${name}" "${result}" "${duration}"
        case "${result}" in
            PASS)    pass_count=$((pass_count + 1)) ;;
            FAIL)    fail_count=$((fail_count + 1)); fail_names+=("${name}") ;;
            TIMEOUT) timeout_count=$((timeout_count + 1)); fail_names+=("${name}") ;;
            MISSING) skip_count=$((skip_count + 1)) ;;
        esac
    fi
done <<< "${project_rows}"

END=$(date +%s)
TOTAL=$((END - START))

echo ""
echo "=== summary ==="
echo "${pass_count} PASS  ${fail_count} FAIL  ${timeout_count} TIMEOUT  ${skip_count} SKIP  (${TOTAL}s total)"

if [[ ${#fail_names[@]} -gt 0 ]]; then
    echo ""
    echo "Failing logs:"
    for n in "${fail_names[@]}"; do
        echo "  ${n}: ${LOG_DIR}/${n}.log"
    done
fi

# Emit fleet_gate_run telemetry event. Best-effort — failure here doesn't
# affect the gate's own exit code.
TELEMETRY_LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${TELEMETRY_LOG}")" 2>/dev/null || true
outcome="pass"
[[ ${fail_count} -gt 0 || ${timeout_count} -gt 0 ]] && outcome="fail"
python3 - "${PWD}" "${outcome}" "${pass_count}" "${fail_count}" "${timeout_count}" "${skip_count}" "${project_count}" "${TOTAL}" >> "${TELEMETRY_LOG}" 2>/dev/null <<'PY' || true
import sys, json
from datetime import datetime, timezone

cwd, outcome, p, f, t, s, total, d = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6]), int(sys.argv[7]), int(sys.argv[8])

def project_for(cwd):
    if cwd.startswith("/home/rich/dev/projects/"):
        parts = cwd.split("/")
        if len(parts) >= 6 and parts[5]:
            return parts[5]
    if cwd == "/home/rich/dev" or cwd.startswith("/home/rich/dev/"):
        return "dev-platform"
    return "other"

event = {
    "v": 1,
    "ts": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
    "event": "fleet_gate_run",
    "session_id": "fleet-gate",
    "project": project_for(cwd),
    "outcome": outcome,
    "pass_count": p,
    "fail_count": f,
    "timeout_count": t,
    "skip_count": s,
    "project_count": total,
    "duration_s": d,
}
print(json.dumps(event))
PY

echo ""
if [[ ${fail_count} -gt 0 || ${timeout_count} -gt 0 ]]; then
    echo "FLEET GATE: FAIL"
    exit 1
fi
echo "FLEET GATE: PASS"
