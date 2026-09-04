#!/usr/bin/env bash
# scripts/fleet-install-template.sh — opt-in per-project install of the
# dev-platform-gate consumer template.
#
# Writes exactly ONE file at exactly ONE path:
#   <project_path>/.github/workflows/dev-platform-gate.yml
#
# Per the Scope-rule carve-out in /home/rich/dev/CLAUDE.md (Exception —
# v0.8 fleet orchestration). That carve-out is the ONLY reason this
# script is allowed to write under projects/. Adding a second mutation
# requires a new carve-out paragraph + spec, not a flag.
#
# Usage:
#   ./scripts/fleet-install-template.sh --project <name>           # dry-run (default)
#   ./scripts/fleet-install-template.sh --project <name> --apply   # write
#   ./scripts/fleet-install-template.sh --project <name> --apply --force  # overwrite existing
#   ./scripts/fleet-install-template.sh --project <name> --pin v0.7
#   ./scripts/fleet-install-template.sh --registry <path>          # tests
#   ./scripts/fleet-install-template.sh --help
#
# Exit codes:
#   0 — dry-run completed, OR --apply wrote the file successfully
#   1 — refuse-to-clobber, project not found, disabled- or frozen-project gate,
#       or similar
#   2 — setup error (jq absent, missing registry, missing args)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REPO_ROOT}/monitoring/projects.json"
SOURCE_TEMPLATE="${REPO_ROOT}/extensions/github-actions/dev-platform-gate.yml"
# Derived from the template rather than hardcoded (v1.26). The template's uses:
# line is the single source of truth for the default pin; a second copy here
# went stale at every bump and turned --pin into an rc=2 error whose own message
# said "Update DEFAULT_PIN in this script" — a maintenance step nobody
# remembered. Derivation Sweep rule: one definition, everything else reads it.
# Pure bash, no sed: this runs before the required-tools gate below, and the
# tools-gate test invokes the script with PATH=/tmp to prove that gate fires —
# any external command here would fail first and mask it.
#
# Guarded with -r: this read happens before the source-template existence check
# further down, which stays authoritative. Without the guard a missing template
# emits a raw bash redirect error here before that clean message ever prints.
DEFAULT_PIN=""
if [[ -r "${SOURCE_TEMPLATE}" ]]; then
    while IFS= read -r _tpl_line; do
        if [[ "${_tpl_line}" =~ taxonomy-check\.yml@(v[0-9]+\.[0-9]+[a-z]?) ]]; then
            DEFAULT_PIN="${BASH_REMATCH[1]}"
            break
        fi
    done < "${SOURCE_TEMPLATE}"
fi

PROJECT=""
APPLY=0
FORCE=0
PIN="${DEFAULT_PIN}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --project requires an argument (project name)" >&2; exit 2; }
            PROJECT="$1"
            ;;
        --apply)
            APPLY=1
            ;;
        --force)
            FORCE=1
            ;;
        --pin)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --pin requires an argument (e.g., v0.7)" >&2; exit 2; }
            PIN="$1"
            ;;
        --registry)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --registry requires an argument (path to projects.json)" >&2; exit 2; }
            REGISTRY="$1"
            ;;
        --help|-h)
            cat <<'HELP'
scripts/fleet-install-template.sh — opt-in install of the dev-platform-gate
consumer template into a single project's .github/workflows/.

Modes:
  (default)   Dry-run: print the plan, write nothing.
  --apply     Actually write the template.

Options:
  --project <name>      Required. Project name from monitoring/projects.json.
  --force               Overwrite existing target (default: refuse-to-clobber).
  --pin <vX.Y>          Pin tag to rewrite into the template.
                        Default is read from the template's own uses: line.
  --registry <path>     Override registry path (for tests).
  --help, -h            Show this help.

The script writes EXACTLY one file at:
  <project_path>/.github/workflows/dev-platform-gate.yml

This is the ONLY mutation v0.8 performs against projects/, governed by the
Scope-rule carve-out in /home/rich/dev/CLAUDE.md ("Exception — v0.8 fleet
orchestration"). NO --all flag exists; per-project opt-in only.
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
[[ -f "${SOURCE_TEMPLATE}" ]] || { echo "ERROR: source template not found at ${SOURCE_TEMPLATE}" >&2; exit 2; }
[[ -n "${PROJECT}" ]] || { echo "ERROR: --project <name> is required" >&2; exit 2; }

# Registry entries' relative paths (`projects/<name>`) resolve against the MAIN
# checkout — `projects/` is gitignored, so it exists nowhere else. Without this
# a worktree run would CREATE projects/<name>/.github/workflows/ inside the
# worktree and write a template nobody's CI reads. REPO_ROOT stays the worktree
# for this repo's own files. See scripts/lib/main_checkout.sh.
#
# Deliberately placed AFTER the required-tools gate above, not with the other
# path assignments at the top. REPO_ROOT is built with `dirname`, an external
# command, so under the tools-gate test's PATH=/tmp it comes out empty — and
# sourcing from an empty REPO_ROOT then fails first and masks the jq error the
# gate is there to report. Same trap the DEFAULT_PIN derivation documents below.
# shellcheck source=lib/main_checkout.sh
source "${REPO_ROOT}/scripts/lib/main_checkout.sh" || {
    echo "ERROR: missing ${REPO_ROOT}/scripts/lib/main_checkout.sh" >&2
    exit 2
}
FLEET_ROOT="$(resolve_main_checkout "${REPO_ROOT}")"

# Resolve the project from the registry.
match="$(jq --arg n "${PROJECT}" '.[] | select(.name == $n)' "${REGISTRY}")"
if [[ -z "${match}" ]]; then
    echo "ERROR: project '${PROJECT}' not found in registry (${REGISTRY})" >&2
    exit 1
fi

project_path="$(echo "${match}" | jq -r '.path')"
project_enabled="$(echo "${match}" | jq -r '.enabled')"
project_frozen="$(echo "${match}" | jq -r '.frozen // false')"

if [[ "${project_enabled}" != "true" ]]; then
    echo "ERROR: project '${PROJECT}' is disabled in the registry — refusing to install" >&2
    exit 1
fi

# Kept as a SEPARATE check with its own message rather than folded into the
# condition above. The two states are different and the messages are the whole
# value: a reader hitting the refusal needs to know which one stopped them.
# `enabled: false` is already handled above, so reaching here means the project
# is enabled — `frozen` only ever qualifies an enabled project.
#
# This is the one mutating fleet operation (Scope-rule carve-out), and on a
# frozen project the mutation is pointless: dev-platform-gate fires only on
# pull requests, and a repo nobody will develop raises none. Installing a
# freshly pinned template there gates PRs that will never exist.
if [[ "${project_frozen}" == "true" ]]; then
    echo "ERROR: project '${PROJECT}' is frozen in the registry — refusing to install" >&2
    echo "       Frozen means deployed but no longer developed. dev-platform-gate runs" >&2
    echo "       only on pull requests, and this project will raise none, so a freshly" >&2
    echo "       pinned template would gate nothing." >&2
    echo "       See the project's \`notes\` in ${REGISTRY#"${REPO_ROOT}"/} for why." >&2
    exit 1
fi

# Compute the target path. HARD-CODED to enforce the Scope-rule carve-out:
# ONE filename in ONE directory, nowhere else. No flag, env var, or branch
# can change this format. Registry entries may use either absolute paths
# (used by tests via mktemp) or paths relative to FLEET_ROOT, the main
# checkout (the production convention — see monitoring/projects.json).
if [[ "${project_path}" == /* ]]; then
    target_dir="${project_path}/.github/workflows"
else
    target_dir="${FLEET_ROOT}/${project_path}/.github/workflows"
fi
target_path="${target_dir}/dev-platform-gate.yml"

# Read the source template (in-memory). The --pin rewrite happens on this
# string only — the source file at extensions/github-actions/ stays
# untouched. Uses word-boundary (\b) rather than end-of-line ($) so a
# future template change that adds a trailing comment to the `uses:` line
# won't silently no-op the rewrite. After rewriting, assert the content
# actually changed — catches a regression where the source template stops
# using `@${DEFAULT_PIN}` and the rewrite becomes a no-op.
template_content="$(cat "${SOURCE_TEMPLATE}")"
if [[ -z "${DEFAULT_PIN}" ]]; then
    echo "ERROR: no pinned taxonomy-check.yml@<tag> found in the source template" >&2
    echo "       (source: ${SOURCE_TEMPLATE}). The uses: line must carry a tag." >&2
    exit 2
fi
if [[ "${PIN}" != "${DEFAULT_PIN}" ]]; then
    rewritten="$(echo "${template_content}" | sed "s|@${DEFAULT_PIN}\b|@${PIN}|g")"
    if [[ "${rewritten}" == "${template_content}" ]]; then
        echo "ERROR: --pin ${PIN} requested but source template contains no @${DEFAULT_PIN} reference" >&2
        echo "       (source: ${SOURCE_TEMPLATE}) — unexpected, since the default is read from it." >&2
        exit 2
    fi
    template_content="${rewritten}"
fi

# Pre-flight: refuse to clobber existing target unless --force.
# Only fires at write boundary (--apply). Dry-run falls through so the
# user sees the full plan + the "would overwrite with --force" diff
# branch below — that informational output is the dry-run mode's whole
# purpose per the spec ("users see exactly what would change before
# committing to it").
if [[ -f "${target_path}" && ${FORCE} -eq 0 && ${APPLY} -eq 1 ]]; then
    echo "ERROR: target already exists: ${target_path}" >&2
    echo "       Use --force to overwrite, or remove the file first." >&2
    exit 1
fi

# Dry-run output (always shown; informative).
echo "fleet-install-template — project=${PROJECT}"
echo "  Source: ${SOURCE_TEMPLATE#${REPO_ROOT}/}"
echo "  Target: ${target_path}"
echo "  Pin:    @${PIN}"
echo "  Mode:   $([[ ${APPLY} -eq 1 ]] && echo "APPLY" || echo "dry-run")"

if [[ -f "${target_path}" ]]; then
    if diff -q <(echo "${template_content}") "${target_path}" >/dev/null 2>&1; then
        echo "  Diff:   (target matches source — no change needed)"
    else
        echo "  Diff:   (target exists; would overwrite with --force)"
    fi
fi

outcome="dry-run"

if [[ ${APPLY} -eq 1 ]]; then
    mkdir -p "${target_dir}"
    echo "${template_content}" > "${target_path}"
    bytes="$(wc -c < "${target_path}")"
    echo ""
    echo "Wrote ${bytes} bytes to ${target_path}"
    outcome="success"
else
    echo ""
    echo "Dry-run — re-run with --apply to write."
fi

# Emit fleet_install_template telemetry event. Best-effort.
TELEMETRY_LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${TELEMETRY_LOG}")" 2>/dev/null || true
python3 - "${PWD}" "${PROJECT}" "${target_path}" "${PIN}" "${APPLY}" "${outcome}" >> "${TELEMETRY_LOG}" 2>/dev/null <<'PY' || true
import sys, json
from datetime import datetime, timezone

cwd, project, target, pin, apply, outcome = sys.argv[1:7]

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
    "event": "fleet_install_template",
    "session_id": "fleet-install-template",
    "project": project_for(cwd),
    "target_project": project,
    "target_path": target,
    "pin": pin,
    "dry_run": apply == "0",
    "outcome": outcome,
}
print(json.dumps(event))
PY

exit 0
