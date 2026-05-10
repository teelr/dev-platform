#!/usr/bin/env bash
# scripts/new-project.sh — scaffold a new project under projects/<name>/
# from one of the templates in scaffolding/.
#
# Per the Scope-rule scaffolding carve-out in /home/rich/dev/CLAUDE.md:
# this script IS allowed to write under projects/ from a dev-platform
# session because scaffolding is a SETUP action, distinct from project work.
# Once the project exists, normal Scope rule resumes.
#
# Usage:
#   ./scripts/new-project.sh <template> <project-name> [--gh-repo public|private]
#
# Templates (R4a): go-service | python-agent | next-frontend
#
# Examples:
#   ./scripts/new-project.sh go-service nvr-v2
#   ./scripts/new-project.sh python-agent text-cleanup --gh-repo private
#   ./scripts/new-project.sh next-frontend portal-v3 --gh-repo public

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    cat <<EOF
Usage: $0 <template> <project-name> [--gh-repo public|private]

Templates available:
$(ls -d "${REPO}/scaffolding"/*/ 2>/dev/null | xargs -n1 basename | sed 's/^/  /')

See docs/NEW-PROJECT.md for the conversational Q&A pattern.
EOF
    exit 1
}

# Argument parsing
TEMPLATE="${1:-}"
PROJECT_NAME="${2:-}"
GH_REPO_FLAG="${3:-}"
GH_REPO_VISIBILITY="${4:-}"

[[ -z "${TEMPLATE}" || -z "${PROJECT_NAME}" ]] && usage

# Template existence
TEMPLATE_DIR="${REPO}/scaffolding/${TEMPLATE}"
if [[ ! -d "${TEMPLATE_DIR}" ]]; then
    echo "ERROR: template '${TEMPLATE}' not found at ${TEMPLATE_DIR}" >&2
    echo "Available templates:" >&2
    ls -d "${REPO}/scaffolding"/*/ 2>/dev/null | xargs -n1 basename | sed 's/^/  /' >&2
    exit 1
fi

# Project-name validation: alphanumeric + dash + underscore only
if [[ ! "${PROJECT_NAME}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "ERROR: invalid project name '${PROJECT_NAME}'" >&2
    echo "       allowed: alphanumeric, dash, underscore (no slashes, dots, spaces)" >&2
    exit 1
fi

# Refuse-to-clobber: project must not already exist
PROJECT_DIR="${REPO}/projects/${PROJECT_NAME}"
if [[ -e "${PROJECT_DIR}" ]]; then
    echo "ERROR: ${PROJECT_DIR} already exists." >&2
    echo "       Pick a different name, or back up + remove first." >&2
    exit 1
fi

# Optional --gh-repo flag validation
GH_REPO_ENABLED=0
if [[ -n "${GH_REPO_FLAG}" ]]; then
    if [[ "${GH_REPO_FLAG}" != "--gh-repo" ]]; then
        echo "ERROR: unknown flag '${GH_REPO_FLAG}' (expected --gh-repo)" >&2
        exit 1
    fi
    if [[ "${GH_REPO_VISIBILITY}" != "public" && "${GH_REPO_VISIBILITY}" != "private" ]]; then
        echo "ERROR: --gh-repo requires 'public' or 'private' (got '${GH_REPO_VISIBILITY}')" >&2
        exit 1
    fi
    GH_REPO_ENABLED=1
fi

# Copy template
echo "1. Copying template '${TEMPLATE}' → projects/${PROJECT_NAME}/"
mkdir -p "${REPO}/projects"
cp -a "${TEMPLATE_DIR}/." "${PROJECT_DIR}/"

# Substitute {{PROJECT_NAME}} placeholder across template content
echo "2. Substituting {{PROJECT_NAME}} → ${PROJECT_NAME}"
find "${PROJECT_DIR}" -type f \
    \( -name "*.md" -o -name "*.json" -o -name "*.toml" -o -name "*.mod" \
       -o -name "*.sh" -o -name "*.go" -o -name "*.py" -o -name "*.ts" \
       -o -name "*.tsx" -o -name "*.mjs" -o -name "*.css" -o -name "*.yml" \
       -o -name "*.yaml" -o -name "*.example" -o -name "Dockerfile*" \
       -o -name ".gitignore" -o -name ".env.example" \) \
    -print0 | xargs -0 sed -i "s/{{PROJECT_NAME}}/${PROJECT_NAME}/g"

# Language-specific post-substitute setup. Runs BEFORE git init so generated
# files (go.sum, etc.) land in the initial commit. Failures are non-fatal —
# the scaffold completes either way; user re-runs the step manually if needed.
cd "${PROJECT_DIR}"
if [[ -f go.mod ]]; then
    echo "3a. go mod tidy (generates go.sum)"
    if command -v go >/dev/null 2>&1; then
        go mod tidy 2>&1 | sed 's/^/    /' || echo "    WARN: 'go mod tidy' failed; run it manually before 'go build'"
    else
        echo "    WARN: 'go' not on PATH; run 'go mod tidy' manually before 'go build'"
    fi
fi

# Initialize git
echo "3. git init + initial commit"
git init -q -b main
git add .
git -c user.email="noreply@dev-platform" \
    -c user.name="dev-platform" \
    commit -q -m "feat: initial scaffold from ${TEMPLATE} template

Scaffolded by /home/rich/dev/scripts/new-project.sh from the
${TEMPLATE} template under scaffolding/. Pre-configured for the
dev-platform standard project structure."

# Optional GitHub repo creation
if [[ "${GH_REPO_ENABLED}" -eq 1 ]]; then
    echo "4. Creating GitHub repo teelr/${PROJECT_NAME} (${GH_REPO_VISIBILITY})"
    gh repo create "teelr/${PROJECT_NAME}" --"${GH_REPO_VISIBILITY}" --source=. --push
fi

# Next-steps checklist
cat <<EOF

Project scaffolded at ${PROJECT_DIR}

Next steps (per docs/NEW-PROJECT.md):
  1. Pick a port from /home/rich/dev/CLAUDE.md Port Allocation Registry,
     then substitute it for the {{PORT}} placeholder. Files containing it:
EOF
grep -rl "{{PORT}}" "${PROJECT_DIR}" 2>/dev/null | sed "s|^|       - |" || true
cat <<EOF
  2. Register the chosen port in /home/rich/dev/CLAUDE.md Port Allocation
     Registry (separate commit in the dev-platform repo).
  3. Run scripts/gate_fast.sh in the new project to confirm baseline.
  4. /plan the project's first spec.
EOF

if [[ "${GH_REPO_ENABLED}" -eq 1 ]]; then
    echo "  5. GitHub: https://github.com/teelr/${PROJECT_NAME}"
fi
