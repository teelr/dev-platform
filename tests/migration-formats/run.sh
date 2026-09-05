#!/usr/bin/env bash
# tests/migration-formats/run.sh — the four entry formats consumers actually use.
#
# check-migration-coverage.sh proves the scripts work against REAL consumer
# files, but those live outside the repo, change without notice, and a CI
# runner's fresh clone cannot see them. This suite is the committed counterpart:
# small fixtures, one per shape, runnable offline.
#
# Each fixture is a reduced copy of a real file that broke the pre-v1.28
# parsers:
#   numbered.md     kermit-v3 / keystone / kermit-pa / OPIE — `## L<N> — title`,
#                   including a markdown table inside a body and a duplicate
#                   L-number (kermit-v3 has six real pairs, keystone 41)
#   dated.md        keystone_prototype — `## Title (YYYY-MM-DD)`
#   categorised.md  SQRL — lessons under category headings at the same level
#   sections.md     kermit-v3 planning.md — `## Ground Truth (...)` blocks
#   shipped-table.md kermit planning.md — | Version | Date | Summary | rows
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 contract. Offline.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

LESSONS="${REPO}/scripts/migrate-lessons.sh"
SHIPPED="${REPO}/scripts/migrate-shipped.sh"

TMP="$(mktemp -d /tmp/migration-formats.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${TMP}'" EXIT

FIX="${TMP}/fixtures"
mkdir -p "${FIX}"

cat > "${FIX}/numbered.md" <<'EOF'
# Lessons

Running log. Capped at roughly 30 entries.

## L1 — A first lesson whose body contains a table

The fix landed in the projection write path.

| Where | Said |
| ----- | ---- |
| Header badge | `Roadmap v0.166` |

That table is body content, not two more lessons.

## L2 — A lesson with a pipe in `cmd | head` inside backticks

Body text for the second lesson.

## L2 — A different lesson that reused the number

Two sessions each appended what they thought was the next number.
EOF

cat > "${FIX}/dated.md" <<'EOF'
# Lessons Learned

## Resize Handles in Flex Layouts (2026-03-30)

CSS-only resize handles fail in flex layouts.

## Cross-Repo Hand-Off (2026-04-29)

Inspect the receiving repo before committing.
EOF

cat > "${FIX}/categorised.md" <<'EOF'
# Lessons

## Sails 0.12 and Waterline

## L14 — An uncaught rejection kills the whole process

Body for L14.

## Billing and domain invariants

## L88 — `req.allParams()` lets the body beat the route param

Body for L88.
EOF

cat > "${FIX}/sections.md" <<'EOF'
# Dev State

Current-state tracker.

## Ground Truth (2026-09-03, v0.197 Duplicate Upload Badge — COMPLETE, milestone #198)

Body of the v0.197 section.

## Ground Truth (2026-08-31, v0.175 Cost Governance — COMPLETE, all 7 Spec Phases)

Body of the v0.175 completion.

## Ground Truth (2026-08-31, v0.175 Cost Governance Spec Phase 6 — IN PROGRESS)

Body of the v0.175 Phase 6 section.

## Ground Truth (2026-09-03, chores: exact harness pin — COMPLETE, no milestone)

Body of the chore section.
EOF

cat > "${FIX}/shipped-table.md" <<'EOF'
# Planning

## Recently shipped

| Version | Date       | Summary |
| ------- | ---------- | ------- |
| v4.120.0 | 2026-08-25 | MINOR: VectorBackend.flush — standalone flush primitive |
| v4.119.1 | 2026-08-25 | PATCH: Anthropic dependency ceiling fix |
EOF

BASELINE="$(cd "${FIX}" && find . -type f | sort)"

# ─── Check 1: bash -n syntax clean ────────────────────────────────
if bash -n "${HERE}/run.sh" 2>/dev/null; then
    record_pass "migration-formats: bash -n syntax clean (runner)"
else
    record_fail "migration-formats: bash -n syntax error (runner)"
fi

# ─── Check 2: numbered format detected; body table does NOT abort ─
# The pre-v1.28 parser read every `| ` line as a lesson row and aborted on the
# table inside L1's body. That is the kermit-v3 failure, reduced.
out="$(LESSONS_FILE="${FIX}/numbered.md" LESSONS_DIR="${TMP}/o1" \
       bash "${LESSONS}" --date-from today 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "format: numbered (3 entries)"; then
    record_pass "migration-formats: numbered detected, table inside a body does not abort"
else
    record_fail "migration-formats: numbered detection failed — rc=${rc}: ${out:0:200}"
fi

# ─── Check 3: duplicate L-number reported, not fatal ──────────────
if echo "${out}" | grep -q "1 duplicate L-number(s) found.*L2"; then
    record_pass "migration-formats: duplicate L-number reported and migrated, not fatal"
else
    record_fail "migration-formats: duplicate L-number not reported: ${out:0:200}"
fi

# ─── Check 4: duplicate number yields two distinct files ──────────
LESSONS_FILE="${FIX}/numbered.md" LESSONS_DIR="${TMP}/o1" \
    bash "${LESSONS}" --date-from today --apply >/dev/null 2>&1
n="$(find "${TMP}/o1" -name '*.md' | wc -l | tr -d ' ')"
if [[ "${n}" -eq 3 ]]; then
    record_pass "migration-formats: 3 numbered lessons → 3 files (duplicate number de-duped by name)"
else
    record_fail "migration-formats: expected 3 files, got ${n}"
fi

# ─── Check 5: every body preserved verbatim ───────────────────────
# The no-content-loss contract, asserted mechanically rather than trusted.
if grep -rqF 'That table is body content, not two more lessons.' "${TMP}/o1" \
   && grep -rqF 'cmd | head' "${TMP}/o1" \
   && grep -rqF 'Two sessions each appended what they thought was the next number.' "${TMP}/o1"; then
    record_pass "migration-formats: every lesson body preserved verbatim, pipes intact"
else
    record_fail "migration-formats: a lesson body was lost or mangled"
fi

# ─── Check 6: dated format; date comes from the heading ───────────
out="$(LESSONS_FILE="${FIX}/dated.md" LESSONS_DIR="${TMP}/o2" \
       bash "${LESSONS}" --apply 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && [[ -f "${TMP}/o2/2026-03-30-resize-handles-in-flex-layouts.md" ]]; then
    record_pass "migration-formats: dated format parsed, filename dated from the heading"
else
    record_fail "migration-formats: dated format wrong — rc=${rc}, files: $(ls "${TMP}/o2" 2>/dev/null | tr '\n' ' ')"
fi

# ─── Check 7: --date-from refused on a format that has dates ──────
out="$(LESSONS_FILE="${FIX}/dated.md" LESSONS_DIR="${TMP}/o3" \
       bash "${LESSONS}" --date-from today 2>&1)"; rc=$?
if [[ ${rc} -eq 2 ]] && echo "${out}" | grep -q "meaningless for the 'dated' format"; then
    record_pass "migration-formats: --date-from refused where every entry already has a date"
else
    record_fail "migration-formats: --date-from not refused on dated — rc=${rc}"
fi

# ─── Check 8: numbered without --date-from refuses to guess ───────
out="$(LESSONS_FILE="${FIX}/numbered.md" LESSONS_DIR="${TMP}/o4" \
       bash "${LESSONS}" 2>&1)"; rc=$?
if [[ ${rc} -ne 0 ]] && echo "${out}" | grep -q "pass --date-from"; then
    record_pass "migration-formats: numbered without --date-from refuses rather than guessing"
else
    record_fail "migration-formats: numbered guessed a date — rc=${rc}"
fi

# ─── Check 9: category heading aborts without --ignore-heading ────
# SQRL's shape. A naive split on `^## ` would invent 2 lessons here.
out="$(LESSONS_FILE="${FIX}/categorised.md" LESSONS_DIR="${TMP}/o5" \
       bash "${LESSONS}" --date-from today 2>&1)"; rc=$?
if [[ ${rc} -ne 0 ]] && echo "${out}" | grep -q "## Sails 0.12 and Waterline" \
   && echo "${out}" | grep -q "## Billing and domain invariants"; then
    record_pass "migration-formats: category headings abort and are named, not silently dropped"
else
    record_fail "migration-formats: category heading not surfaced — rc=${rc}: ${out:0:200}"
fi

# ─── Check 10: --ignore-heading parses and lists what it ignored ──
out="$(LESSONS_FILE="${FIX}/categorised.md" LESSONS_DIR="${TMP}/o6" \
       bash "${LESSONS}" --date-from today \
       --ignore-heading '^## (Sails|Billing)' 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "format: numbered (2 entries)" \
   && echo "${out}" | grep -q "2 heading(s) ignored"; then
    record_pass "migration-formats: --ignore-heading parses 2 lessons and lists both ignored headings"
else
    record_fail "migration-formats: --ignore-heading wrong — rc=${rc}: ${out:0:200}"
fi

# ─── Check 11: --format override forces a parser and can fail ─────
out="$(LESSONS_FILE="${FIX}/numbered.md" LESSONS_DIR="${TMP}/o7" \
       bash "${LESSONS}" --format table --date-from today 2>&1)"; rc=$?
if [[ ${rc} -ne 0 ]]; then
    record_pass "migration-formats: --format table on a numbered file fails loudly"
else
    record_fail "migration-formats: --format override ignored — rc=${rc}"
fi

# ─── Check 12: shipped sections; repeated version, chore, filenames ─
out="$(PLANNING_FILE="${FIX}/sections.md" SHIPPED_DIR="${TMP}/o8" \
       bash "${SHIPPED}" --apply 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "format: sections (3 phase, 1 chore)" \
   && echo "${out}" | grep -q "v0.175×2"; then
    record_pass "migration-formats: Ground Truth sections parsed; repeated version flagged as normal"
else
    record_fail "migration-formats: sections wrong — rc=${rc}: ${out:0:200}"
fi

# ─── Check 13: repeated version gets distinct, self-describing names ─
# Both keep the heading's qualifier, so neither needs a bare -2 suffix and a
# reader can tell them apart from the filename alone.
v175="$(find "${TMP}/o8" -name '2026-08-31-v0.175-*.md' | wc -l | tr -d ' ')"
if [[ "${v175}" -eq 2 ]] \
   && find "${TMP}/o8" -name '*spec-phase-6*' | grep -q . \
   && ! find "${TMP}/o8" -name '*-2.md' | grep -q .; then
    record_pass "migration-formats: two v0.175 sections get distinct self-describing filenames"
else
    record_fail "migration-formats: v0.175 filenames not distinct: $(ls "${TMP}/o8" | tr '\n' ' ')"
fi

# ─── Check 14: chore section takes the version-less filename shape ─
if find "${TMP}/o8" -name '2026-09-03-chores*.md' | grep -q .; then
    record_pass "migration-formats: version-less chore section uses <date>-<slug>.md"
else
    record_fail "migration-formats: chore filename wrong: $(ls "${TMP}/o8" | tr '\n' ' ')"
fi

# ─── Check 15: kermit's shipped TABLE inside Recently shipped ─────
out="$(PLANNING_FILE="${FIX}/shipped-table.md" SHIPPED_DIR="${TMP}/o9" \
       bash "${SHIPPED}" --apply 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "format: table (2 phase, 0 chore)" \
   && find "${TMP}/o9" -name '2026-08-25-v4.120.0-*.md' | grep -q . \
   && find "${TMP}/o9" -name '2026-08-25-v4.119.1-*.md' | grep -q .; then
    record_pass "migration-formats: shipped table parsed, version-bearing filenames"
else
    record_fail "migration-formats: shipped table wrong — rc=${rc}, files: $(ls "${TMP}/o9" 2>/dev/null | tr '\n' ' ')"
fi

# ─── Check 16: PATH-GUARD — fixtures never written to ─────────────
CURRENT="$(cd "${FIX}" && find . -type f | sort)"
if [[ "${BASELINE}" == "${CURRENT}" ]]; then
    record_pass "migration-formats: source fixtures untouched (scripts only read them)"
else
    record_fail "migration-formats: a script wrote into the fixture directory"
fi

# ─── Check 17: --date-from git dates an APPENDED entry ────────────
# The regression. `--date-from git` used to pass --diff-filter=A, which filters
# on the FILE's status: `A` means "commits where this file was Added", i.e. the
# one commit that created lessons.md. Combined with the -S pickaxe it could only
# ever match entries present in that first commit, so every entry appended later
# resolved to nothing and silently fell through to TODAY.
#
# Every check above this one used --date-from today or asserted a refusal, so
# the git path had no coverage at all — which is how it shipped. Measured on
# kermit-v3: 214 of 214 entries missed, and the migration would have stamped
# every lesson with the migration date.
#
# Two commits on different dates: entry A ships with the file, entry B is
# appended later. B is the one that used to break.
GITFIX="${TMP}/gitrepo"
mkdir -p "${GITFIX}"
(
    cd "${GITFIX}" || exit 1
    git init -q -b main
    printf '# Lessons\n\n## L1 — first lesson, present when the file was created\n\nBody A.\n' > lessons.md
    git add lessons.md
    GIT_AUTHOR_DATE="2026-01-02T10:00:00" GIT_COMMITTER_DATE="2026-01-02T10:00:00" \
        git -c user.email=t@t -c user.name=t commit -qm "add lessons.md"
    printf '\n## L2 — second lesson, appended in a LATER commit\n\nBody B.\n' >> lessons.md
    git add lessons.md
    GIT_AUTHOR_DATE="2026-03-04T10:00:00" GIT_COMMITTER_DATE="2026-03-04T10:00:00" \
        git -c user.email=t@t -c user.name=t commit -qm "append a lesson"
) >/dev/null 2>&1

out="$(LESSONS_FILE="${GITFIX}/lessons.md" LESSONS_DIR="${TMP}/o10" \
       bash "${LESSONS}" --date-from git --apply 2>&1)"; rc=$?
today="$(date +%F)"
if [[ ${rc} -eq 0 ]] \
   && find "${TMP}/o10" -name '2026-01-02-*.md' | grep -q . \
   && find "${TMP}/o10" -name '2026-03-04-*.md' | grep -q . \
   && ! echo "${out}" | grep -q "no introducing commit" \
   && ! find "${TMP}/o10" -name "${today}-*.md" | grep -q .; then
    record_pass "migration-formats: --date-from git dates an appended entry from its own commit, not today"
else
    record_fail "migration-formats: --date-from git wrong — rc=${rc}, files: $(ls "${TMP}/o10" 2>/dev/null | tr '\n' ' '), out: ${out}"
fi
