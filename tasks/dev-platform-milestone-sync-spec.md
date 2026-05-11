# v0.7 Phase 4 — Milestones Automation

## Coding Specification for Implementation

## Design Philosophy

Phase 4 closes v0.7 by automating the [ROADMAP.md](../ROADMAP.md) ↔ GitHub Milestones sync. Today the mapping is maintained by hand: every new Roadmap Phase entry in `ROADMAP.md` requires a paired `gh api -X POST repos/.../milestones` call to create the matching Milestone. As Roadmap Phases accumulate (v0.7 today, v1.0 soon, v1.1+ later) and as v0.8 (Cross-project orchestration) lights up dashboards that read from Milestones, the manual sync becomes a drift hazard. `scripts/sync-milestones.sh` makes the sync mechanical and idempotent — parse `ROADMAP.md`, fetch current Milestones via `gh api`, plan the diff, optionally apply.

The script's design mirrors the established dev-platform entry-point pattern (`install.sh`, `verify.sh`, `gate_fast.sh`, `report.sh`, `sync-vscode.sh`): Bash, command-line, dry-run-by-default, `--apply` flag to actually mutate. The mock-binary test pattern from v0.6 (`tests/vscode/fixtures/mock-bin/code` — a Bash script that mimics the external CLI via an env-var state file) is the proven testability primitive. Phase 4 reuses it with a mock `gh` so the test suite exercises round-trip ROADMAP → API call sequences without ever touching live GitHub state.

Scope discipline: per the Scope rule in [CLAUDE.md](../CLAUDE.md), Phase 4 touches only files in `dev-platform/` itself — no projects, no cross-project orchestration (that's v0.8). Per the per-Spec-Phase strategy locked in PR #9, this Phase ships as one PR (~350 LOC across 3 files). Per the workflow-extension rule from PR #9, the spec calls out the **post-merge** step — cutting the **v0.7 release tag** at the merge commit SHA and closing the v0.7 GitHub Milestone. The tag-cut is what finally validates the `@v0.7` pin in [extensions/github-actions/dev-platform-gate.yml](../extensions/github-actions/dev-platform-gate.yml) that's been waiting since Phase 2.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/sync-milestones.sh` | Bash | Matches every other entry-point script (`install.sh`, `gate_fast.sh`, `sync-vscode.sh`). Uses `gh api` + `jq` + `awk`. No CPU-bound work; no LLM calls; no concurrency. Bash is the correct (and only sensible) choice. |
| `tests/milestone-sync/run.sh` | Bash | Matches the v0.4 R3 test-suite pattern; auto-discovered by `gate_fast.sh`. |
| `tests/milestone-sync/fixtures/mock-bin/gh` | Bash | Mock CLI. Mirrors `tests/vscode/fixtures/mock-bin/code` from v0.6 (1-to-1 pattern reuse). |

No new code components by language matrix. Phase 4 is one Bash script + one Bash test suite + one Bash mock + a few Markdown / JSONL fixtures.

## Overview

1. **Phase 1:** sync-milestones.sh + test suite + post-merge release-tag cut (Changes 1–3)

Single-Phase Spec — total LOC ≤ ~350 (script ~120 + tests ~150 + mock ~50 + fixtures ~30). Per the v0.6 small-Roadmap-Phase carve-out documented in [tasks/lessons.md](../tasks/lessons.md), under-200-LOC-per-Spec-Phase ships as one combined PR. The work is loosely coupled enough to split into 3 commits (one per Change) but cohesive enough to land as one PR.

---

## Phase 1: ROADMAP ↔ Milestone Sync

### Change 1: `scripts/sync-milestones.sh`

**Problem:** GitHub Milestones must mirror [ROADMAP.md](../ROADMAP.md) entries (one Milestone per `v<MAJOR>.<MINOR>:` line, state = closed if "(complete …)", state = open otherwise, description = the prose after the `**title** *(state)*` block). Today this is maintained manually — every new Roadmap Phase requires a paired `gh api -X POST` call. The hazard is twofold: (a) someone adds a Phase to ROADMAP.md and forgets the Milestone — dashboards built on Milestones miss it; (b) a Phase ships (ROADMAP marked complete) but the Milestone stays open — the team's shared status diverges. `sync-milestones.sh` makes the sync mechanical: parse, fetch, diff, optionally apply.

**File:** `scripts/sync-milestones.sh` (new, ~120 lines)

**Implementation:**

```bash
#!/usr/bin/env bash
# scripts/sync-milestones.sh — mirror ROADMAP.md entries to GitHub Milestones.
#
# Idempotent: each run computes the diff between ROADMAP.md and the repo's
# current Milestone list, then either reports the plan (dry-run, default)
# or applies it (--apply). Closed-and-released Milestones (the ones backing
# shipped release tags) are NEVER reopened or mutated — see Closed handling.
#
# Usage:
#   ./scripts/sync-milestones.sh                       # dry-run against teelr/dev-platform
#   ./scripts/sync-milestones.sh --apply               # actually create/update
#   ./scripts/sync-milestones.sh --repo OWNER/REPO     # different repo
#   ./scripts/sync-milestones.sh --file <ROADMAP.md>   # different source file (tests)
#   ./scripts/sync-milestones.sh --help
#
# Requires: gh CLI authenticated, jq, awk.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROADMAP="${REPO_ROOT}/ROADMAP.md"
GH_REPO="teelr/dev-platform"
APPLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply) APPLY=1 ;;
        --repo)  shift; GH_REPO="$1" ;;
        --file)  shift; ROADMAP="$1" ;;
        --help|-h)
            # Mirror sync-vscode.sh's heredoc help pattern.
            cat <<'HELP'
scripts/sync-milestones.sh — sync ROADMAP.md entries to GitHub Milestones.

Modes:
  (default)   Dry-run: print the plan, make no API changes.
  --apply     Actually create/update Milestones.

Options:
  --repo <owner/repo>   Operate against a different repo (default: teelr/dev-platform).
  --file <path>         Read entries from a non-default ROADMAP.md (for tests).
  --help, -h            Show this help.

Idempotency:
  Each run computes the diff between ROADMAP.md and the repo's Milestone list:
    CREATE   ROADMAP entry has no matching Milestone — create it.
    UPDATE   Milestone exists but state or description differs — patch.
    SKIP     Milestone matches ROADMAP exactly — no-op.
    LOCKED   Milestone is already closed — leave untouched (release tag exists).

  Re-running with --apply after a successful run yields all SKIPs and LOCKED.
HELP
            exit 0
            ;;
        *) echo "ERROR: unknown arg: $1" >&2; exit 1 ;;
    esac
    shift
done

command -v gh >/dev/null || { echo "ERROR: gh CLI required (https://cli.github.com)" >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq required" >&2; exit 1; }
[[ -f "${ROADMAP}" ]] || { echo "ERROR: ROADMAP.md not found at ${ROADMAP}" >&2; exit 1; }

# Parse ROADMAP.md entries: lines like
#   - **v0.5: Monitoring** *(complete — 2026-05-11, `tasks/...`)* — first phase…
#
# Extract: title (the bold-wrapped "v<N>.<N>[a-z]?: <Title>") and state
# (closed if the *italicized* block contains "complete", open otherwise) and
# description (rest of the bullet line, used as the Milestone description).
#
# Output: tab-separated "title<TAB>state<TAB>description" per matched line.
parse_entries() {
    awk '
        /^- \*\*v[0-9]+\.[0-9]+[a-z]?: / {
            line = $0
            # Title: between leading "- **" and the closing "**"
            title = line
            sub(/^- \*\*/, "", title)
            sub(/\*\* .*/, "", title)

            # State: detect "(complete" or "(complete —" anywhere in line
            state = "open"
            if (line ~ /\*\(complete[ —]/) state = "closed"

            # Description: strip the leading "- **title** " then the trailing
            # *(...)* italicized status block, then leading " — " separator.
            desc = line
            sub(/^- \*\*[^*]+\*\* /, "", desc)
            sub(/\*\(.*\)\*[ ]*—?[ ]*/, "", desc)
            # Truncate to 500 chars (GitHub Milestone description hard limit
            # is 1024 — leave headroom for future prose growth).
            if (length(desc) > 500) desc = substr(desc, 1, 497) "..."

            print title "\t" state "\t" desc
        }
    ' "${ROADMAP}"
}

# Fetch all existing Milestones (state=all, per_page=100 — well above the
# foreseeable Roadmap-Phase count). Emit one JSON object per line for
# downstream jq-by-title lookup.
fetch_milestones() {
    gh api "repos/${GH_REPO}/milestones?state=all&per_page=100" \
        --jq '.[] | {number, title, state, description}'
}

existing="$(fetch_milestones | jq -s .)"

# Plan/execution loop.
create_count=0
update_count=0
skip_count=0
locked_count=0

echo "Syncing ROADMAP.md → Milestones at ${GH_REPO}"
echo ""

while IFS=$'\t' read -r title state desc; do
    [[ -z "${title}" ]] && continue

    # Lookup by title.
    match="$(echo "${existing}" | jq --arg t "${title}" '.[] | select(.title == $t)')"
    existing_number="$(echo "${match}" | jq -r '.number // empty')"
    existing_state="$(echo "${match}" | jq -r '.state // empty')"
    existing_desc="$(echo "${match}" | jq -r '.description // empty')"

    if [[ -z "${existing_number}" ]]; then
        action="CREATE"
        create_count=$((create_count + 1))
        if [[ ${APPLY} -eq 1 ]]; then
            gh api "repos/${GH_REPO}/milestones" -X POST \
                -f title="${title}" -f state="${state}" -f description="${desc}" >/dev/null
        fi
    elif [[ "${existing_state}" == "closed" ]]; then
        # Closed Milestones back released tags — NEVER mutate. Even if the
        # ROADMAP entry's prose drifts, the closed Milestone is the historical
        # record. Edit history goes through `gh release edit`, not here.
        action="LOCKED (already closed)"
        locked_count=$((locked_count + 1))
    elif [[ "${existing_state}" == "${state}" && "${existing_desc}" == "${desc}" ]]; then
        action="SKIP (in sync)"
        skip_count=$((skip_count + 1))
    else
        action="UPDATE (state=${state})"
        update_count=$((update_count + 1))
        if [[ ${APPLY} -eq 1 ]]; then
            gh api "repos/${GH_REPO}/milestones/${existing_number}" -X PATCH \
                -f state="${state}" -f description="${desc}" >/dev/null
        fi
    fi
    echo "  ${action}: ${title}"
done < <(parse_entries)

echo ""
echo "Summary: ${create_count} create, ${update_count} update, ${skip_count} skip, ${locked_count} locked"
if [[ ${APPLY} -eq 0 ]]; then
    echo ""
    echo "Dry-run — no changes made. Re-run with --apply to commit."
fi
```

Key design notes:

- **Dry-run by default.** Following the `sync-vscode.sh` and consumer-template philosophy: tools that mutate shared state require an explicit `--apply`.
- **LOCKED-on-closed.** A closed Milestone backs a released version (its release tag exists). Mutating a closed Milestone destroys the historical record — explicitly forbidden by the spec. Edits to old Phases go through `gh release edit` instead.
- **ROADMAP.md is the source of truth.** When state or description diverges, the Milestone is updated to match ROADMAP, never the other way. Manual GitHub-UI edits to open Milestones are transient — the next sync overwrites them.
- **`--file` override for tests.** Mirror sync-vscode.sh's pattern from v0.6's /review fix — testability is built in from day one.
- **Title parsing reuses Phase 1's regex shape.** The `^- \*\*v[0-9]+\.[0-9]+[a-z]?: ` anchor is the same family as `scripts/check_spec_taxonomy.sh`'s killed-prefix detector — same source of truth, no divergence.

**Acceptance Test:**

```bash
# Help renders without API calls
./scripts/sync-milestones.sh --help | grep -q "sync ROADMAP.md entries"

# Dry-run against the real repo — should report all SKIPs and LOCKEDs (no
# pending diffs after Phase 4 work is implemented; closed Phases stay LOCKED)
./scripts/sync-milestones.sh 2>&1 | tee /tmp/sync-dry.txt
grep -q "Dry-run — no changes" /tmp/sync-dry.txt   # expect dry-run banner
grep -q "^  LOCKED.*v0.1: Foundation" /tmp/sync-dry.txt   # v0.1 already closed
grep -q "^  SKIP\|^  UPDATE: v0.7" /tmp/sync-dry.txt   # v0.7 is open

# Hard-error paths
PATH=/tmp ./scripts/sync-milestones.sh 2>&1 | grep -q "gh CLI required"
./scripts/sync-milestones.sh --file /nonexistent 2>&1 | grep -q "ROADMAP.md not found"
```

### Change 2: `tests/milestone-sync/fixtures/` + mock `gh` binary

**Problem:** The sync script parses [ROADMAP.md](../ROADMAP.md) with an awk regex and calls `gh api` for read/write — both are brittle (regex can regress, `gh api` payload shape can drift). A fixture suite catches regressions WITHOUT making real GitHub API calls or relying on the live `ROADMAP.md`.

**File:** `tests/milestone-sync/fixtures/sample-roadmap.md` (new), `tests/milestone-sync/fixtures/mock-bin/gh` (new)

**Implementation:**

`tests/milestone-sync/fixtures/sample-roadmap.md` — three entries exercising the parser:

```markdown
# Test Roadmap

- **v0.1: Foundation** *(complete — 2026-05-08, `tasks/foundation-spec.md`)* — first shipped Phase; demonstrates the `(complete …)` state detection
- **v0.5: Monitoring** *(in flight)* — Phase implemented on branch; demonstrates `(in flight)` → open
- **v0.7: Team Enablement** *(planned)* — Phase not started; demonstrates `(planned)` → open
- **v0.4a: Hotfix** *(complete — 2026-05-09)* — letter-suffix Phase (v0.4a not v0.4); demonstrates `[a-z]?` regex branch

Other lines should be ignored — they're NOT Roadmap entries even if they mention "v0.5" inline.
```

`tests/milestone-sync/fixtures/mock-bin/gh` — Bash mock of the `gh` CLI. Mirrors [tests/vscode/fixtures/mock-bin/code](../tests/vscode/fixtures/mock-bin/code) from v0.6.

```bash
#!/usr/bin/env bash
# Mock gh CLI for tests/milestone-sync/run.sh.
#
# Supports the gh-api invocations sync-milestones.sh uses:
#   gh api repos/X/milestones?state=all&per_page=N   → emit state from $MOCK_MILESTONES_FILE
#   gh api repos/X/milestones -X POST -f title=... -f state=... -f description=...
#                                                    → append to $MOCK_API_CALLS_FILE
#   gh api repos/X/milestones/<id> -X PATCH ...      → append to $MOCK_API_CALLS_FILE
#
# State:
#   MOCK_MILESTONES_FILE — JSON array of existing milestones (read-side mock)
#   MOCK_API_CALLS_FILE  — log of write calls (one line per call, "<METHOD> <path> <args>")
#
# Failure injection: gh-api against a non-API path returns exit 1.

set -uo pipefail

: "${MOCK_MILESTONES_FILE:?MOCK_MILESTONES_FILE must be set in env}"
: "${MOCK_API_CALLS_FILE:?MOCK_API_CALLS_FILE must be set in env}"
touch "${MOCK_API_CALLS_FILE}"

# First positional arg should be `api`. Everything else is the gh api spec.
if [[ "${1:-}" != "api" ]]; then
    echo "mock-gh: only 'api' subcommand supported, got '${1:-}'" >&2
    exit 1
fi
shift

# Parse: <path> [-X METHOD] [-f key=value]... [--jq <expr>]
path=""
method="GET"
jq_expr=""
form_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -X)        shift; method="$1" ;;
        -f)        shift; form_args+=("$1") ;;
        --jq)      shift; jq_expr="$1" ;;
        *)
            if [[ -z "${path}" ]]; then
                path="$1"
            fi
            ;;
    esac
    shift
done

# Log the call (write-side mocks see this; read-side just returns canned data)
if [[ "${method}" != "GET" ]]; then
    echo "${method} ${path} ${form_args[*]:-}" >> "${MOCK_API_CALLS_FILE}"
fi

# Read: emit canned Milestone list. Apply --jq if requested (matches gh's CLI behavior).
if [[ "${path}" == repos/*/milestones* ]] && [[ "${method}" == "GET" ]]; then
    if [[ -n "${jq_expr}" ]]; then
        jq "${jq_expr}" "${MOCK_MILESTONES_FILE}"
    else
        cat "${MOCK_MILESTONES_FILE}"
    fi
    exit 0
fi

# Write: echo nothing (sync-milestones.sh discards >/dev/null on POST/PATCH)
exit 0
```

Plus 2 small JSON fixtures for canned state:

`tests/milestone-sync/fixtures/empty-milestones.json` (no existing milestones):

```json
[]
```

`tests/milestone-sync/fixtures/existing-milestones.json` (3 existing, 1 closed):

```json
[
  {"number": 1, "title": "v0.1: Foundation", "state": "closed", "description": "first shipped Phase; demonstrates the (complete …) state detection"},
  {"number": 5, "title": "v0.5: Monitoring", "state": "open", "description": "Phase implemented on branch; demonstrates (in flight) → open"},
  {"number": 7, "title": "v0.7: Team Enablement", "state": "open", "description": "OUTDATED description — should trigger UPDATE"}
]
```

**Consumer Audit (mandatory):**

- `tests/milestone-sync/fixtures/sample-roadmap.md` — covered by existing `!tests/**/*.md` allow-list ✓
- `tests/milestone-sync/fixtures/empty-milestones.json`, `existing-milestones.json` — covered by `!tests/**/*.json` ✓
- `tests/milestone-sync/fixtures/mock-bin/gh` — extension-less file under `tests/`; covered by Phase 4's [tests/**/mock-bin/* re-include from v0.6](../.gitignore#L113) ✓

Run `git check-ignore -v` on each new file after creating — confirm `!` re-include rule matches. If any file shows up as ignored, the spec is wrong; STOP and report rather than silently fix.

**Acceptance Test:**

```bash
test -f tests/milestone-sync/fixtures/sample-roadmap.md
test -f tests/milestone-sync/fixtures/empty-milestones.json
test -f tests/milestone-sync/fixtures/existing-milestones.json
test -x tests/milestone-sync/fixtures/mock-bin/gh

# Mock gh binary executes (no real API)
MOCK_MILESTONES_FILE="tests/milestone-sync/fixtures/empty-milestones.json" \
MOCK_API_CALLS_FILE=/tmp/gh-calls-$$.log \
tests/milestone-sync/fixtures/mock-bin/gh api repos/x/y/milestones?state=all >/dev/null
# Expect: exit 0, emits "[]"

# Consumer Audit on every new file
for f in tests/milestone-sync/fixtures/sample-roadmap.md \
         tests/milestone-sync/fixtures/empty-milestones.json \
         tests/milestone-sync/fixtures/existing-milestones.json \
         tests/milestone-sync/fixtures/mock-bin/gh; do
    git check-ignore -v "$f" 2>&1 | head -1
done
```

### Change 3: `tests/milestone-sync/run.sh`

**Problem:** Without a runner asserting the script's behavior, every change to `sync-milestones.sh` risks silent regression of the parse / fetch / plan / apply flow. The runner closes the loop: feeds fixtures into the script, asserts the right calls fire (or don't, in dry-run), exits non-zero on mismatch. Auto-discovered by `gate_fast.sh` per the v0.4 contract.

**File:** `tests/milestone-sync/run.sh` (new, ~150 lines)

**Implementation:**

Mirror the v0.6 [tests/vscode/run.sh](../tests/vscode/run.sh) structure exactly:

- Sourced `tests/helpers/assert.sh` for `record_pass` / `record_fail`
- `MOCK_BIN`-on-PATH trick to substitute the mock `gh` for the real one
- `MOCK_MILESTONES_FILE` + `MOCK_API_CALLS_FILE` per-test cleanup via `trap`
- One `record_*` per assertion — counts feed back to the orchestrator via `_GATE_COUNTS_FILE`

Required assertions (the gate count grows by exactly this many from 66 → target):

1. **bash -n** — `scripts/sync-milestones.sh` syntax clean.
2. **`--help`** — renders without making API calls; mentions `sync ROADMAP.md entries`.
3. **Required-tools gate** — running with `PATH=/tmp` triggers the `gh CLI required` error message and exit 1.
4. **Missing-ROADMAP gate** — `--file /nonexistent` triggers `ROADMAP.md not found` and exit 1.
5. **Parse-only** — feed `fixtures/sample-roadmap.md` + empty mock milestones; dry-run output contains exactly 4 `CREATE` lines (v0.1, v0.5, v0.7, v0.4a) — confirms the 4-entry parser handles letter-suffix and the `state=` mapping.
6. **State detection: complete → closed** — for `v0.1: Foundation` in the dry-run plan, the CREATE entry's state is `closed` (the script's plan output includes state as part of the action label OR a side-write to a parsable plan file). Implementation detail: have `--apply` write `${METHOD} <path> -f title=... -f state=...` to `MOCK_API_CALLS_FILE` so the test can assert state value.
7. **State detection: planned/in-flight → open** — `v0.7: Team Enablement` planned/in-flight maps to `state=open`.
8. **SKIP when in sync** — feed `existing-milestones.json` where v0.5 description matches the parsed ROADMAP description; expect SKIP for v0.5.
9. **UPDATE on description drift** — feed `existing-milestones.json` where v0.7 description is "OUTDATED"; expect UPDATE for v0.7 in the dry-run plan.
10. **LOCKED on closed** — feed `existing-milestones.json` where v0.1 is already closed; expect LOCKED (not UPDATE) even though the test fixture's ROADMAP entry has a different description. Closed-and-released Milestones are immutable.
11. **No write-side calls in dry-run** — after a dry-run, `MOCK_API_CALLS_FILE` is empty (the dry-run produces zero POST/PATCH calls).
12. **Write-side calls fire under --apply** — under `--apply` against empty mock milestones, `MOCK_API_CALLS_FILE` contains 4 lines all starting with `POST` and including the correct title.

Test structure (excerpt):

```bash
# Check 5: parse sample-roadmap.md against empty mock milestones
mock_milestones="${ROUND_TRIP_TMP}/milestones-5.json"
calls="${ROUND_TRIP_TMP}/calls-5.log"
echo '[]' > "${mock_milestones}"

PATH="${MOCK_BIN}:${PATH}" \
    MOCK_MILESTONES_FILE="${mock_milestones}" \
    MOCK_API_CALLS_FILE="${calls}" \
    bash "${REPO}/scripts/sync-milestones.sh" --file "${HERE}/fixtures/sample-roadmap.md" \
    > "${ROUND_TRIP_TMP}/out-5.txt" 2>&1

create_count=$(grep -c "^  CREATE: " "${ROUND_TRIP_TMP}/out-5.txt")
if [[ ${create_count} -eq 4 ]]; then
    record_pass "milestone-sync: parses 4 entries from sample-roadmap (v0.1, v0.5, v0.7, v0.4a)"
else
    record_fail "milestone-sync: expected 4 CREATE lines, got ${create_count}"
fi
```

Use the same `mktemp -d` + `trap "rm -rf '${tmp}'" EXIT` pattern as v0.6's run.sh for cleanup.

**Acceptance Test:**

```bash
bash tests/milestone-sync/run.sh
# Expect: 12 PASS, 0 FAIL

# Auto-discovered by gate_fast.sh
./scripts/gate_fast.sh 2>&1 | grep -q "tests/milestone-sync/run.sh"
# Expect: present in gate output

# Gate count grows by 12 (was 66 → 78 after Phase 4)
./scripts/gate_fast.sh 2>&1 | tail -3 | grep -q "78 PASS"
```

---

## Post-merge step (deferred, in spec — runs after PR squash-merges)

**This is the LAST post-merge step in the v0.7 Roadmap Phase — it CLOSES v0.7.**

After PR #11 (Phase 4) squash-merges to `main`:

### 1. Run `sync-milestones.sh --apply` once.

Validates the script against real-world state and brings any stale Milestone descriptions into sync (e.g., v0.7's open Milestone description currently doesn't reference Phases 1–4's actual shipped state).

**Pre-step — rename the v0.6 Milestone to match ROADMAP.md.** The existing Milestone is titled `v0.6: VSCode Coverage` (initial seed); ROADMAP.md says `v0.6: VSCode Coverage (Server-Side)`. The script's title-keyed lookup can't auto-rename — without this pre-step, `--apply` would CREATE a duplicate Milestone. One-shot rename:

```bash
gh api -X PATCH "repos/teelr/dev-platform/milestones/6" \
    -f title="v0.6: VSCode Coverage (Server-Side)"
```

Verify the rename took:

```bash
gh api repos/teelr/dev-platform/milestones/6 --jq '.title'
# Expect: "v0.6: VSCode Coverage (Server-Side)"
```

**Then run `--apply`:**

```bash
./scripts/sync-milestones.sh --apply
# Expect AFTER the rename: 0 CREATE, 1 UPDATE (v0.7 description refresh; v0.8/v0.9/v1.0
# also UPDATE if their descriptions have drifted from the initial seed), 6 LOCKED
# (v0.1-v0.6 closed and immutable). Eyeball the dry-run output BEFORE --apply
# to confirm the planned description changes match ROADMAP.md intent.
```

### 2. Cut the v0.7 release tag at the merge commit.

The merge commit closes v0.7. Cutting `v0.7` here validates the `@v0.7` pin in [extensions/github-actions/dev-platform-gate.yml](../extensions/github-actions/dev-platform-gate.yml) that's been waiting since Phase 2.

```bash
# Capture the merge commit SHA from `git log` after pulling main.
git checkout main && git pull --ff-only
MERGE_SHA=$(git rev-parse HEAD)

# Cut the release tag at that SHA, with a body summarizing v0.7.
gh release create v0.7 --target "${MERGE_SHA}" \
    --title "v0.7: Team Enablement" \
    --notes "$(cat <<'NOTES'
v0.7 closes the team-scale transition for dev-platform: mechanical
enforcement of the taxonomy + workflow standards via GitHub Actions
CI, a hosted docs site with linkable glossary, and automated
Milestone sync.

**Phases shipped:**
- Phase 1 (PR #7) — Taxonomy enforcement extended to ROADMAP.md + planning.md
- Phase 2 (PR #8) — GitHub Actions CI workflows (gate-fast on every PR + reusable taxonomy-check for consumers) + consumer adoption guide
- Phase 3 (PR #10) — GitHub Pages docs site at https://teelr.github.io/dev-platform/ + GLOSSARY.md (35 terms)
- Phase 4 (PR #11) — Milestones automation (scripts/sync-milestones.sh + tests/milestone-sync/)
- Plus chore PR #9 — extended canonical workflow chain to PR → CI → merge → post-merge

**Branch protection on main** now requires the gate-fast CI check before any merge.

**Next:** v0.8 Cross-project orchestration.
NOTES
    )"
```

### 3. Close the v0.7 GitHub Milestone.

The release tag now exists; the Milestone can close. Done via `gh`:

```bash
gh api -X PATCH "repos/teelr/dev-platform/milestones/7" -f state=closed
```

Or re-run `sync-milestones.sh --apply` AFTER updating ROADMAP.md's v0.7 entry to `*(complete — 2026-05-11, …)*` — the script will detect the new state and PATCH the Milestone closed for us.

### 4. Verification:

```bash
# Tag exists, points at the right SHA
git fetch --tags
git show v0.7 --stat | head -3
# Expect: tag commit IS the merge commit

# Release page exists
gh release view v0.7 --json tagName,publishedAt,url --jq '.url'
# Expect: https://github.com/teelr/dev-platform/releases/tag/v0.7

# v0.7 Milestone closed
gh api repos/teelr/dev-platform/milestones/7 --jq '.state'
# Expect: "closed"

# The @v0.7 pin in extensions/github-actions/dev-platform-gate.yml now resolves
gh api repos/teelr/dev-platform/contents/extensions/github-actions/dev-platform-gate.yml?ref=v0.7 --jq '.path'
# Expect: "extensions/github-actions/dev-platform-gate.yml"
```

---

## What NOT to Do

- **Do NOT mutate closed Milestones.** A closed Milestone backs a released version (its release tag exists). Editing it destroys the historical record. The script's `LOCKED` action enforces this; do not "fix" the LOCKED handling to also UPDATE.
- **Do NOT add a `--force` flag** to override LOCKED. Closed Milestones are intentionally immutable. If a closed Milestone's prose needs editing, do it via `gh release edit` against the release notes, not the Milestone description.
- **Do NOT run `--apply` automatically from `gate_fast.sh` or any other workflow.** This is a mutating script — manual invocation only. Auto-running risks accidental Milestone churn if the parser regresses.
- **Do NOT add a third state ("in_progress" or "blocked") beyond GitHub's two-state open/closed.** GitHub Milestones don't support custom states; mapping to anything other than open/closed creates drift. If a Roadmap Phase needs richer state, that lives in `planning.md` (the "In flight" section), not the Milestone.
- **Do NOT skip the mock `gh` and just-run-against-the-real-repo.** The test suite MUST be hermetic — running it against the real GitHub API would (a) require network, (b) require credentials, (c) potentially mutate live Milestones, (d) make the test non-reproducible.
- **Do NOT auto-cut release tags.** Release tags are intentional human decisions — they signal a Roadmap Phase has shipped. Cutting them via a script bypasses the deliberate-by-design ceremony. The post-merge `gh release create` is a manual step for the human to verify the merge commit is the right tag target.
- **Do NOT modify the live ROADMAP.md from within `sync-milestones.sh`.** The script is one-directional: ROADMAP.md → Milestones. The reverse (Milestone edits → ROADMAP.md) is out of scope. Manual UI edits to Milestone descriptions ARE transient and will be overwritten on next sync — that's by design.
- **Do NOT add Linear / Jira / external-tracker sync.** Deferred per the original v0.7 spec — out of scope until a tracker is chosen.
- **Do NOT skip the dry-run default.** Tools that mutate shared state MUST require an explicit `--apply` for any write. This is a global pattern across the dev-platform scripts.
- **Do NOT add a markdown lint step to gate_fast.sh** to catch MD051/MD032 in spec files. Out of scope for Phase 4; future cleanup if it becomes a recurring drag.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/sync-milestones.sh` | New | ROADMAP.md → GitHub Milestones sync; dry-run default, `--apply` to mutate, LOCKED on closed |
| `tests/milestone-sync/run.sh` | New | 12-assertion fixture suite (auto-discovered by gate_fast.sh) |
| `tests/milestone-sync/fixtures/sample-roadmap.md` | New | 4-entry roadmap fixture (complete + in flight + planned + letter-suffix) |
| `tests/milestone-sync/fixtures/empty-milestones.json` | New | Canned empty-state for "everything CREATE" scenarios |
| `tests/milestone-sync/fixtures/existing-milestones.json` | New | Canned partial-state for SKIP/UPDATE/LOCKED scenarios |
| `tests/milestone-sync/fixtures/mock-bin/gh` | New | Mock `gh` CLI (no extension; mirrors v0.6's mock `code`) |

No `.gitignore` extension needed — every new file type is already in the allow-list:
- `tests/**/*.md` — sample-roadmap.md ✓
- `tests/**/*.json` — milestones JSON fixtures ✓
- `tests/**/*.sh` — run.sh ✓
- `tests/**/mock-bin/*` — extension-less mock `gh` ✓ (added v0.6)
- `scripts/*.sh` — sync-milestones.sh ✓

Consumer Audit applies but only to confirm — no new allow-list rules to add.

## Implementation Order

1. **Change 1** (`scripts/sync-milestones.sh`) — write the script with `--help` first to confirm the arg-parsing shape, then layer in parse / fetch / plan / apply.
2. **Change 2** (fixtures + mock `gh`) — fixtures before runner so the runner has data to assert against.
3. **Change 3** (`tests/milestone-sync/run.sh`) — runner depends on Change 2 fixtures AND Change 1 script being callable.
4. **Local verification** — run `bash tests/milestone-sync/run.sh` directly (expect 12 PASS), then `./scripts/gate_fast.sh` to confirm auto-discovery + total grows 66 → 78.
5. **Post-merge** — three steps after PR squash-merge: `sync-milestones.sh --apply`, `gh release create v0.7`, close v0.7 Milestone. v0.7 Roadmap Phase fully shipped.

## Verification Checklist

- [ ] `scripts/sync-milestones.sh` exists, bash-syntax clean, executable
- [ ] `./scripts/sync-milestones.sh --help` exits 0 without API calls
- [ ] `./scripts/sync-milestones.sh` (dry-run, real repo) reports plan with `Dry-run` banner; exits 0
- [ ] `./scripts/sync-milestones.sh` reports LOCKED for v0.1-v0.5 closed Milestones AND surfaces the v0.6 title drift (existing Milestone titled `v0.6: VSCode Coverage` vs ROADMAP.md's `v0.6: VSCode Coverage (Server-Side)`) as a CREATE plan — to be resolved at post-merge by renaming the existing Milestone via `gh api -X PATCH` BEFORE running `--apply`
- [ ] `./scripts/sync-milestones.sh` reports the expected open-Milestone plan (likely SKIP / UPDATE for v0.7-v1.0)
- [ ] 4 fixture files exist in `tests/milestone-sync/fixtures/`
- [ ] Mock `gh` binary executable, mirrors v0.6's mock `code` shape
- [ ] `bash tests/milestone-sync/run.sh` → 12 PASS / 0 FAIL
- [ ] `./scripts/gate_fast.sh` → 78 PASS / 0 FAIL / 0 SKIP (was 66, +12 from milestone-sync)
- [ ] `./scripts/check_spec_taxonomy.sh` clean — spec uses Phase 1 / Change N format
- [ ] No file under `projects/` modified
- [ ] Consumer Audit: every new file `git check-ignore -v`'d, all show re-include rules
- [ ] **Post-merge:** `./scripts/sync-milestones.sh --apply` reports successful state changes (no errors)
- [ ] **Post-merge:** `gh release create v0.7 --target <merge-sha>` succeeds; release page at `github.com/teelr/dev-platform/releases/tag/v0.7` reachable
- [ ] **Post-merge:** v0.7 GitHub Milestone closed (`gh api .../milestones/7 --jq '.state'` returns `"closed"`)
- [ ] **Post-merge:** the `@v0.7` pin in `extensions/github-actions/dev-platform-gate.yml` resolves on GitHub (`gh api repos/.../contents/...?ref=v0.7` returns 200)

## Out of Scope (Future Specs)

- **Two-way sync (Milestones → ROADMAP.md edits).** Out of scope; ROADMAP.md is the source of truth.
- **External tracker sync (Linear, Jira, etc.).** Deferred until a tracker is picked.
- **Auto-cut release tags.** Manual ceremony intentionally; out of scope.
- **Multi-repo Milestone sync across `projects/`.** v0.8 (Cross-project orchestration) territory.
- **Markdown lint enforcement in gate_fast.sh** for MD051/MD032 warnings surfaced by the IDE in the Phase 3 spec. Optional future cleanup.
- **`@v0.7` → `@v1.0` pin migration sweep** in consumer projects (kermit, atlas, etc.). Each consumer bumps their own pin per the CI-INTEGRATION.md upgrade flow.

## Notes for Implementation

- **The `--apply` post-merge step probably surfaces 1-2 UPDATE actions** (the v0.7 Milestone's description doesn't yet reflect Phases 1-4's shipped state; the script will sync it). UPDATEs against open Milestones are safe — only LOCKED on closed.
- **The release-cut step assumes the merge commit IS the right tag target.** If multiple commits land on main between the merge and the release-cut, the tag could point at a non-Phase-4 commit. Fix: capture the merge commit SHA IMMEDIATELY after `gh pr merge` (it's the next commit on main).
- **Mock `gh` test pattern is 1:1 with v0.6's mock `code` pattern** — if anything diverges, lean toward the v0.6 shape; that pattern survived a /review + /test cycle. See [tests/vscode/fixtures/mock-bin/code](../tests/vscode/fixtures/mock-bin/code) and [tests/vscode/run.sh](../tests/vscode/run.sh) for the canonical templates.
- **`gh api`'s `--jq` flag**: the mock binary must support `--jq <expr>` because `sync-milestones.sh` uses it on the read-side. Implement the jq pass-through in the mock (run `jq "${jq_expr}" "${MOCK_MILESTONES_FILE}"` if `--jq` is set).
- **Failure mode for `gh auth`**: the script doesn't explicitly check `gh auth status`. If `gh` is unauthenticated, the first API call fails with an actionable `gh auth login` error. Document this in the `--help` but don't add a redundant pre-check.
- **Description-truncation at 500 chars**: GitHub's hard limit is 1024 but lengthy descriptions are dispreferred. The awk truncation rule (`substr(desc, 1, 497) "..."`) is conservative.
- **The single-Phase-Spec choice**: total LOC ≈ 350 places this near the threshold where per-Spec-Phase would otherwise apply. The work is tightly coupled (script + tests + fixtures are mutually dependent — splitting creates artificial PR boundaries) so single-Phase Spec is correct here. Document the choice in the spec's Overview so future /code agents know one branch is right.
