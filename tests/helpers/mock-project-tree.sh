# tests/helpers/mock-project-tree.sh — set up a mock fleet for Phase 2+
# test suites. Source it from a test runner; do NOT execute directly.
#
# Pattern: each "project" is a subdirectory under a parent root with
# its own .git, at least one commit, and optional state (uncommitted
# files, tasks/-spec.md with a taxonomy violation, .github/workflows/
# dev-platform-gate.yml consumer template).
#
# Usage:
#   source "${REPO}/tests/helpers/mock-project-tree.sh"
#   ROOT="$(mktemp -d /tmp/fleet-mock.XXXX)"
#   mock_project_init "${ROOT}/pass-1"
#   mock_project_commit "${ROOT}/pass-1" "another commit"
#   mock_project_dirty "${ROOT}/pass-1" "uncommitted-file.txt"
#   mock_project_taxonomy_violation "${ROOT}/pass-1"
#   mock_project_install_template "${ROOT}/pass-1"
#   trap "rm -rf '${ROOT}'" EXIT
#
# Shipped in v0.8 Phase 2 (fleet-dashboard); reused by Phase 3 (drift
# correction) and Phase 4 (pin tracking) test suites.

# Initialize a mock project: mkdir + git init + one empty commit so
# `git log -1` returns something. Uses local-scoped git identity to
# avoid depending on the test runner's global git config.
mock_project_init() {
    local dir="$1"
    mkdir -p "${dir}"
    (
        cd "${dir}" && \
        git init -q -b main && \
        git -c user.email=test@test -c user.name=test \
            commit --allow-empty -q -m "init"
    )
}

# Add another empty commit (use to test last-commit age / multi-commit
# scenarios). Default message: "fixture commit".
mock_project_commit() {
    local dir="$1"
    local msg="${2:-fixture commit}"
    (
        cd "${dir}" && \
        git -c user.email=test@test -c user.name=test \
            commit --allow-empty -q -m "${msg}"
    )
}

# Make the working tree dirty by writing an uncommitted file.
# Default file name: "uncommitted.txt".
mock_project_dirty() {
    local dir="$1"
    local file="${2:-uncommitted.txt}"
    echo "uncommitted content" > "${dir}/${file}"
}

# Drop a ROADMAP.md with a killed Roadmap-Phase prefix into the project,
# triggering check_spec_taxonomy.sh to flag a violation on next scan.
mock_project_taxonomy_violation() {
    local dir="$1"
    mkdir -p "${dir}/tasks"
    cat > "${dir}/ROADMAP.md" <<'EOF'
# Roadmap

- **Sprint K: Foo** *(planned)* — killed-prefix triggers taxonomy violation
EOF
}

# Drop the consumer dev-platform-gate.yml into the project's
# .github/workflows/, triggering the dashboard's "adopted" flag.
mock_project_install_template() {
    local dir="$1"
    mkdir -p "${dir}/.github/workflows"
    cat > "${dir}/.github/workflows/dev-platform-gate.yml" <<'EOF'
name: dev-platform-gate
on: [pull_request]
jobs:
  taxonomy:
    uses: teelr/dev-platform/.github/workflows/taxonomy-check.yml@v0.7
EOF
}
