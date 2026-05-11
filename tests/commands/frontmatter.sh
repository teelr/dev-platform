#!/usr/bin/env bash
# tests/commands/frontmatter.sh — validates each commands/*.md has well-formed
# frontmatter with required fields. Intentionally simple: catches the common
# breakage shapes (missing ---, missing field, empty value, too-long
# description) without trying to be a full YAML parser.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

for cmd in "${REPO}/commands"/*.md; do
    name="$(basename "${cmd}")"
    [[ "${name}" == "README.md" ]] && continue

    # First line must be ---
    first_line="$(head -1 "${cmd}")"
    if [[ "${first_line}" != "---" ]]; then
        record_fail "${name}: first line is not '---' (got: '${first_line}')"
        continue
    fi

    # Closing --- present after line 1
    if ! awk 'NR>1 && $0=="---" {found=1; exit} END {exit !found}' "${cmd}"; then
        record_fail "${name}: missing closing '---' for frontmatter"
        continue
    fi

    # description non-empty (scan only within frontmatter block)
    desc="$(awk 'NR==1 && $0=="---" {in_fm=1; next}
                in_fm && $0=="---" {exit}
                in_fm && /^description:/ {sub(/^description:[[:space:]]*/, ""); print; exit}' "${cmd}")"
    if [[ -z "${desc}" ]]; then
        record_fail "${name}: 'description' field missing or empty"
        continue
    fi
    if (( ${#desc} > 200 )); then
        record_fail "${name}: description too long (${#desc} > 200 chars)"
        continue
    fi

    record_pass "${name}: frontmatter valid (desc: ${desc:0:50}...)"
done
