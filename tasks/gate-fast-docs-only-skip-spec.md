# v1.14: Gate-Fast Docs-Only Diff Skip

## Coding Specification for Implementation

## Design Philosophy

`/gate fast`'s expensive checks exist to verify CODE — test suites, lint, type checks, builds. A diff that changes zero code files cannot fail any of them, so paying the full wall time for e.g. a 2-line `ROADMAP.md` close-out edit is pure waste. kermit-v3 proved this live: PR #367 (merged `a007d03`, 2026-08-16) taught its own `scripts/gate_fast.sh` to detect an all-docs diff vs. `main` and skip `pytest`/`bandit`/frontend `eslint`+`typecheck`/`go build` — pytest alone is ~90% of that gate's ~3min wall time. Keystone's own gate script picked up the identical pattern the same day. [teelr/dev-platform#68](https://github.com/teelr/dev-platform/issues/68) — filed by Rich after seeing both — asks that this propagate to every project's `gate_fast.sh`, not stay a kermit-v3/Keystone-only trick, per dev-platform's own "Quality-gate contract... projects extend, they do not replace" rule.

**Scope, per the Scope rule.** dev-platform doesn't own project code, so this spec does NOT edit `projects/keystone/scripts/gate_fast.sh` or any other project's gate script — those already have the pattern (Keystone) or need their own session's `/code` to port it (SQRL, OPIE, kanban, keystone_prototype). What dev-platform *does* own is the shared pattern itself: a reusable, documented, testable detector that (a) becomes the reference implementation in dev-platform's own `scripts/gate_fast.sh` — dev-platform dogfoods its own contract like every other gate-fast rule — and (b) is written up in `docs/RULE_RATIONALE.md` clearly enough that another project's session can port it in one read. Actually rolling it out to the other five projects happens from their own sessions; this spec's Post-merge step files the handoff issues (see below) rather than touching their trees.

**Resolving the issue's open question — pattern vs. shared script.** dev-platform does not distribute `gate_fast.sh` to consumers at all today; every project vendors its own copy, hand-written to its own check list (pytest here, `go build` there, `npm run lint` elsewhere). The only thing dev-platform *does* distribute at runtime is the CI taxonomy-check YAML (`docs/CI-INTEGRATION.md`, pinned by release tag) — a fundamentally different mechanism (a reusable GitHub Actions `workflow_call`, not a locally-run shell script). There's no equivalent distribution channel for gate-fast internals, and inventing one (e.g. consumers `curl`-ing a shared script at gate time) is a bigger, riskier change than this issue asks for. So: this ships as a **documented pattern to copy and adjust**, not a literal script other repos source. To keep the copy-paste surface as small as possible, the truly generic part — computing "is every changed file a doc file" — is extracted into one small, self-contained file (`scripts/lib/docs_only_diff.sh`) that a consuming project can drop in verbatim and only needs to override two knobs (base ref, doc-path allowlist) if its layout differs from dev-platform's own. The project-specific part (which checks are "expensive/code-verifying" and how to skip each one) is necessarily bespoke per project and stays out of the shared file.

**Why the skip is safe.** The checks that stay on regardless (dev-platform's "lift checks": taxonomy enforcement, bash syntax, JSON validity, secrets scan, live `~/.claude/` verify) are the CT-*/structural equivalent Keystone/kermit-v3 always keep running. In particular, `scripts/check_spec_taxonomy.sh` re-scans the real, live `ROADMAP.md`/`planning.md`/`tasks/*.md` content directly on every gate run — it is not a cached fixture, so doc/roadmap *content* correctness is never actually skipped, only the auto-discovered `tests/*/` suite loop (which exercises SCRIPT behavior via fixtures) gets skipped, and only when zero scripts changed. If a diff touches even one `.sh`/`.py` file, the skip disables itself for the whole diff — the exact "any non-doc file disables it" contract Keystone/kermit-v3 use.

**Honest scope note on savings.** dev-platform's own `gate_fast.sh` already runs in ~15-30s (228 checks) — nowhere near Keystone/kermit-v3's ~3min pytest-heavy gate. The time saved by this change, applied to dev-platform itself, is real but modest; dev-platform's role here is to be the reference implementation and prove the pattern generalizes, not to claim a dramatic local speedup. The bigger win is for the five other projects once they port it from their own sessions.

**Not in scope:** widening the `actions/checkout` fetch depth in `.github/workflows/gate.yml` so CI can diff against `main`. `actions/checkout@v4` defaults to a shallow, single-commit checkout, so `git diff --name-only main...HEAD` finds no local `main` ref in CI and returns empty — which the detector already treats as "not docs-only, run everything" (never infer docs-only from missing information). That's the correct, safe behavior, not a bug: the skip is a **local dev-loop optimization**, and CI already runs unattended in the background where wall-clock matters far less than it does for someone waiting on `/gate fast` at their terminal. Widening fetch depth to shave CI time is a distinct, separately-justified change with its own cost (slower checkout on every run) — do not bundle it in here.

**Branching:** single Phase, single PR. Diff is small (one new ~40-line helper, one new ~90-line test suite, a ~15-line wiring change to the existing gate script, two doc edits) — same "small Roadmap Phase" shape as v0.6/v1.12/v1.13.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/lib/docs_only_diff.sh` | Bash | Sourced by `scripts/gate_fast.sh`, an existing bash orchestrator — matching language, no new runtime dependency. |
| `tests/docs-only-skip/run.sh` | Bash | Matches every other `tests/<suite>/run.sh` in this repo. |

No network I/O, no LLM calls, no UI — a local git-diff detector is squarely a bash scripting task, not a candidate for the Language Matrix's Go/Rust/Python tiers.

## Overview

1. **Phase 1 — Gate-Fast Docs-Only Diff Skip** (Changes 1–5): ship the reusable detector, prove it with a unit-test suite, wire it into dev-platform's own `gate_fast.sh` as the reference implementation, and document the pattern (+ the resolved "pattern vs. shared script" question) for other projects to port.

---

## Phase 1: Gate-Fast Docs-Only Diff Skip

### Change 1: `scripts/lib/docs_only_diff.sh` — reusable detector (new file)

**Problem:** The docs-only-diff detection logic (diff vs. a base ref, unioned with working-tree changes, matched against a doc-path allowlist) is the one genuinely reusable piece of the pattern. It needs to live somewhere sourceable and independently testable, with both its base ref and its allowlist overridable — dev-platform's own repo layout (`ROADMAP.md`/`planning.md` at root, `docs/`, `tasks/`) won't match every consumer's.

**File:** `scripts/lib/docs_only_diff.sh` (new; new `scripts/lib/` directory)

**Implementation:**

```bash
#!/usr/bin/env bash
# scripts/lib/docs_only_diff.sh — reusable docs-only-diff detector.
#
# Sourced by scripts/gate_fast.sh to skip expensive code-verifying checks
# (test suites, lint, build — whatever a project's own gate considers
# "expensive") when every changed file is pure documentation. Portable to
# any project's own gate_fast.sh — see docs/RULE_RATIONALE.md "Gate-Fast
# Docs-Only Diff Skip" for the adoption guide and why this ships as a
# pattern to copy in, not a script consumers source at runtime.
#
# Conservative by construction: any file outside the allowlist disables the
# skip for the WHOLE diff, and an empty diff (nothing changed, or no local
# base ref — e.g. a shallow CI checkout) also disables it. Never infer
# "docs-only" from missing information.
#
# Usage:
#   source this file, optionally override the knobs below, then call
#   compute_docs_only_diff. Sets, in the CALLER's shell:
#     DOCS_ONLY_DIFF          0 or 1
#     DOCS_ONLY_CHANGED_FILES newline-separated changed-file list (may be empty)
#
# Override before calling compute_docs_only_diff if your project's default
# branch or doc-file layout differs from dev-platform's own:
#   DOCS_ONLY_BASE_REF="main"
#   DOCS_ONLY_ALLOW_PATTERNS=("*.md" "docs/*" "tasks/*")

: "${DOCS_ONLY_BASE_REF:=main}"
if [[ -z "${DOCS_ONLY_ALLOW_PATTERNS+x}" ]]; then
    DOCS_ONLY_ALLOW_PATTERNS=("*.md" "docs/*" "tasks/*")
fi

compute_docs_only_diff() {
    local changed
    changed=$( { git diff --name-only "${DOCS_ONLY_BASE_REF}...HEAD" 2>/dev/null; \
                  git status --porcelain --untracked-files=all 2>/dev/null | awk '{print $2}'; } \
                | sort -u)

    DOCS_ONLY_CHANGED_FILES="${changed}"
    DOCS_ONLY_DIFF=0

    # Empty diff — nothing changed, or the base ref isn't locally resolvable
    # (e.g. a shallow CI checkout with no local `main`). Never guess.
    [[ -z "${changed}" ]] && return 0

    DOCS_ONLY_DIFF=1
    local f pattern matched
    while IFS= read -r f; do
        [[ -z "${f}" ]] && continue
        matched=0
        for pattern in "${DOCS_ONLY_ALLOW_PATTERNS[@]}"; do
            # shellcheck disable=SC2053
            if [[ "${f}" == ${pattern} ]]; then
                matched=1
                break
            fi
        done
        if [[ "${matched}" -eq 0 ]]; then
            DOCS_ONLY_DIFF=0
            break
        fi
    done <<< "${changed}"
}
```

Note the `[[ -z "${DOCS_ONLY_ALLOW_PATTERNS+x}" ]]` guard (not `:=`) — bash's `${arr[@]:-default}` on an unset array does NOT split `default` into multiple elements the way you'd want; the explicit "is it unset, then assign the whole array" form is the correct default-array idiom here. Don't simplify this to a one-line `:=`.

**Acceptance Test:**

```bash
bash -n scripts/lib/docs_only_diff.sh && echo "OK: syntax clean"
```

(Full behavioral coverage is Change 2's job.)

---

### Change 2: `tests/docs-only-skip/run.sh` — unit-test suite (new file)

**Problem:** Change 1's detector needs proof it's correct across the real cross product of states before anything wires it into the live gate — committed vs. uncommitted changes, docs-only vs. mixed, empty diff, and both override knobs. Model this on `tests/version-collision/run.sh`'s pattern of building a real, disposable local git repo rather than mocking `git` itself (the goal is to test real `git diff`/`git status` behavior, not a stand-in for it) — but simpler: no bare "origin" remote is needed here, since `compute_docs_only_diff` diffs against a local ref (`DOCS_ONLY_BASE_REF`, default `main`), not `origin/main`.

**File:** `tests/docs-only-skip/run.sh` (new; new `tests/docs-only-skip/` directory — auto-discovered by `scripts/gate_fast.sh`'s existing suite loop, no orchestrator edit needed)

**Implementation:**

```bash
#!/usr/bin/env bash
# tests/docs-only-skip/run.sh — unit suite for scripts/lib/docs_only_diff.sh.
# Builds a disposable local git repo per assertion (main + feature branch),
# sources the detector directly, and checks DOCS_ONLY_DIFF / _CHANGED_FILES.
#
# Auto-discovered by scripts/gate_fast.sh (tests/<suite>/run.sh).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"
# shellcheck disable=SC1091
source "${REPO}/scripts/lib/docs_only_diff.sh"

TMP="$(mktemp -d /tmp/docs-only-skip.XXXXXX)"
trap 'rm -rf "${TMP}"' EXIT

# new_repo <name> — creates $TMP/<name> with an initial commit on main
# (README.md + a placeholder scripts/x.sh), returns the path via stdout.
new_repo() {
    local dir="${TMP}/$1"
    git init -q "${dir}"
    (
        cd "${dir}"
        git checkout -q -b main
        echo "# seed" > README.md
        mkdir -p scripts
        echo "#!/usr/bin/env bash" > scripts/x.sh
        git add README.md scripts/x.sh
        git -c user.email=t@t -c user.name=t commit -q -m seed
    )
    echo "${dir}"
}

run_case() {
    local description="$1" dir="$2" expected="$3"
    (
        cd "${dir}"
        # shellcheck disable=SC2034
        unset DOCS_ONLY_BASE_REF DOCS_ONLY_ALLOW_PATTERNS
        compute_docs_only_diff
        [[ "${DOCS_ONLY_DIFF}" -eq "${expected}" ]]
    )
    if [[ $? -eq 0 ]]; then
        record_pass "${description}"
    else
        record_fail "${description}"
    fi
}

# 1. Committed docs-only diff → 1
d="$(new_repo case1)"
(cd "${d}" && git checkout -q -b feature && echo "x" >> README.md && mkdir -p docs && echo "y" > docs/z.md && git add -A && git -c user.email=t@t -c user.name=t commit -q -m docs)
run_case "committed docs-only diff -> DOCS_ONLY_DIFF=1" "${d}" 1

# 2. Committed diff includes one non-doc file → 0
d="$(new_repo case2)"
(cd "${d}" && git checkout -q -b feature && echo "x" >> README.md && echo "code" >> scripts/x.sh && git add -A && git -c user.email=t@t -c user.name=t commit -q -m mixed)
run_case "committed diff with one non-doc file -> DOCS_ONLY_DIFF=0" "${d}" 0

# 3. No diff at all (still on main) → 0 (never infer docs-only from nothing)
d="$(new_repo case3)"
(cd "${d}" && git checkout -q -b feature)
run_case "empty diff -> DOCS_ONLY_DIFF=0" "${d}" 0

# 4. Committed docs-only diff, but an uncommitted non-doc change contaminates it → 0
d="$(new_repo case4)"
(cd "${d}" && git checkout -q -b feature && echo "x" >> README.md && git add -A && git -c user.email=t@t -c user.name=t commit -q -m docs && echo "dirty" >> scripts/x.sh)
run_case "docs-only commit + uncommitted non-doc change -> DOCS_ONLY_DIFF=0" "${d}" 0

# 5. No commits yet, but uncommitted docs-only changes (staged + untracked) → 1
d="$(new_repo case5)"
(cd "${d}" && git checkout -q -b feature && echo "x" >> README.md && git add README.md && echo "untracked" > NOTES.md)
run_case "uncommitted docs-only changes only -> DOCS_ONLY_DIFF=1" "${d}" 1

# 6. DOCS_ONLY_BASE_REF override — diff against a non-"main" ref
d="$(new_repo case6)"
(cd "${d}" && git checkout -q -b baseline && git checkout -q -b feature && echo "x" >> README.md && git add -A && git -c user.email=t@t -c user.name=t commit -q -m docs)
(
    cd "${d}"
    DOCS_ONLY_BASE_REF="baseline"
    unset DOCS_ONLY_ALLOW_PATTERNS
    compute_docs_only_diff
    [[ "${DOCS_ONLY_DIFF}" -eq 1 ]]
)
if [[ $? -eq 0 ]]; then record_pass "DOCS_ONLY_BASE_REF override diffs against custom ref"; else record_fail "DOCS_ONLY_BASE_REF override diffs against custom ref"; fi

# 7. DOCS_ONLY_ALLOW_PATTERNS override — a custom project layout
d="$(new_repo case7)"
(cd "${d}" && git checkout -q -b feature && mkdir -p spec && echo "y" > spec/w.txt && git add -A && git -c user.email=t@t -c user.name=t commit -q -m custom-docs)
(
    cd "${d}"
    unset DOCS_ONLY_BASE_REF
    DOCS_ONLY_ALLOW_PATTERNS=("spec/*")
    compute_docs_only_diff
    [[ "${DOCS_ONLY_DIFF}" -eq 1 ]]
)
if [[ $? -eq 0 ]]; then record_pass "DOCS_ONLY_ALLOW_PATTERNS override respects custom allowlist"; else record_fail "DOCS_ONLY_ALLOW_PATTERNS override respects custom allowlist"; fi

echo ""
echo "docs-only-skip: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL, ${SKIP_COUNT} SKIP"
[[ "${FAIL_COUNT}" -eq 0 ]]
```

Make the file executable (`chmod +x tests/docs-only-skip/run.sh`) — the gate's suite loop only runs files with the execute bit set (see `scripts/gate_fast.sh`'s existing `[[ -x "${runner}" ]]` check).

**Acceptance Test:**

```bash
bash tests/docs-only-skip/run.sh   # expect 7 PASS, 0 FAIL
```

---

### Change 3: `scripts/gate_fast.sh` — wire in the detector as the reference implementation

**Problem:** Dev-platform's own gate needs to actually use Change 1's detector — both to prove the pattern end-to-end and because dev-platform dogfoods every gate-fast rule it asks other projects to follow.

**File:** `scripts/gate_fast.sh`, lines 20-30 (sourcing block) and lines 101-130 (test-suite loop)

**Implementation:**

After the existing `source "${_LOCK_HELPER}"` line (line 30), before `START=$(date +%s)` (line 32), add:

```bash

# Docs-only diff detection (v1.14) — skip the expensive test-suite loop below
# when every changed file is pure documentation. Lift checks above/below this
# block (taxonomy, syntax, JSON, secrets, live verify) always still run — see
# docs/RULE_RATIONALE.md "Gate-Fast Docs-Only Diff Skip" for why that's safe.
# shellcheck disable=SC1091
source "${REPO}/scripts/lib/docs_only_diff.sh"
compute_docs_only_diff
```

Replace the `echo "--- test suites ---"` line (line 102) and the blank line before it with:

```bash
echo ""
echo "--- test suites ---"
if [[ "${DOCS_ONLY_DIFF}" -eq 1 ]]; then
    echo "  docs-only diff detected — skipping test suites (structural lift checks above still ran)"
    echo "  changed: ${DOCS_ONLY_CHANGED_FILES//$'\n'/ }"
fi
```

Inside the suite-discovery `while` loop (lines 118-125), replace:

```bash
    while IFS= read -r runner; do
        found_any=1
        echo "  suite: ${runner#${REPO}/}"
        if [[ -x "${runner}" ]]; then
            bash "${runner}" || true   # PASS/FAIL captured via assert.sh helpers
        else
            record_fail "${suite_name}: ${runner#${REPO}/} not executable"
        fi
    done < <(find "${suite_dir}" -type f -name "*.sh" \
                ! -path "*/fixtures/*" \
                2>/dev/null)
```

with:

```bash
    while IFS= read -r runner; do
        found_any=1
        echo "  suite: ${runner#${REPO}/}"
        if [[ "${DOCS_ONLY_DIFF}" -eq 1 ]]; then
            record_skip "${suite_name}: ${runner#${REPO}/} (docs-only diff)"
        elif [[ -x "${runner}" ]]; then
            bash "${runner}" || true   # PASS/FAIL captured via assert.sh helpers
        else
            record_fail "${suite_name}: ${runner#${REPO}/} not executable"
        fi
    done < <(find "${suite_dir}" -type f -name "*.sh" \
                ! -path "*/fixtures/*" \
                2>/dev/null)
```

This preserves per-suite visibility (each runner still gets its own line, now `SKIP` instead of running) and leaves `found_any` detection untouched.

**Acceptance Test:**

```bash
./scripts/gate_fast.sh
```

This spec's own diff touches `scripts/gate_fast.sh`, `scripts/lib/docs_only_diff.sh`, and `tests/docs-only-skip/run.sh` — all non-doc files — so `DOCS_ONLY_DIFF` MUST correctly evaluate to `0` for this PR's own gate run, and the full test-suite loop must still execute (all suites `PASS`, none `SKIP` for this reason). That's the live proof of "any non-doc file disables the skip for the whole diff," for free, without a throwaway commit. (Change 2's unit suite is the authoritative proof of the positive/skip path — it doesn't depend on this PR's own diff shape.)

---

### Change 4: `docs/RULE_RATIONALE.md` — document the pattern

**Problem:** Other projects' sessions need to be able to port this in one read, and the issue's own open triage question (documented pattern vs. shared script) needs a recorded, explicit answer — not just an implicit one buried in code comments.

**File:** `docs/RULE_RATIONALE.md`, insert after the existing "## Consumer Audit — Why the rule exists" section (ends line 32), before the `---` + `# Kermit-Specific Rules` divider (lines 34-36).

**Implementation:**

```markdown
## Gate-Fast Docs-Only Diff Skip

`/gate fast`'s expensive checks exist to verify CODE — pytest, SAST, frontend lint/typecheck, `go build`. A diff that changes zero code files cannot fail any of them, so paying their full wall time (often the majority of gate-fast's runtime — pytest alone is ~90% of Keystone's and kermit-v3's ~3min gate) for e.g. a 2-line `ROADMAP.md` close-out edit is pure waste. First proven live on kermit-v3 (`scripts/gate_fast.sh`, PR #367, merged 2026-08-16) and Keystone's own gate script the same day, then adopted into dev-platform's own `scripts/gate_fast.sh` (v1.14) as the reference implementation — [teelr/dev-platform#68](https://github.com/teelr/dev-platform/issues/68) asked for it to propagate everywhere gate-fast exists.

**The pattern:** compute the diff vs. the default branch (committed) unioned with any uncommitted working-tree change (staged/unstaged/untracked) — a local mid-work run needs to reflect the working tree, not just the last commit. If every changed file matches a doc-path allowlist (default: `*.md`, `docs/*`, `tasks/*`), skip the check(s) that verify code; anything CT-*/structural (taxonomy, isolation, version-collision, etc. — checks that validate the CONTENT of docs/roadmap/spec files, not code behavior) always still runs. Conservative by construction, in two directions: any single non-doc file in the diff disables the skip for the WHOLE diff, and an empty diff also runs the full suite — never infer "docs-only" from the absence of information (a shallow CI checkout with no local base-ref to diff against degrades to "diff is empty" and correctly runs everything, rather than misreading "can't tell" as "docs-only").

**Why this is safe:** the structural/CT-* checks that stay on typically re-validate the real committed files directly (dev-platform's own `check_spec_taxonomy.sh` scans the live `ROADMAP.md`/`planning.md`/`tasks/*.md`, not a cached fixture) — so doc-content correctness is never actually skipped, only the SCRIPT/CODE-behavior checks that a docs-only diff cannot possibly break.

**Adoption in another project:** dev-platform ships the reusable detector at `scripts/lib/docs_only_diff.sh` — copy it into your own repo, source it from your own `gate_fast.sh`, call `compute_docs_only_diff`, and wrap your project's own expensive/code-verifying checks (whatever they are — `pytest`, `go build`, `npm run lint`, etc.) in `if [[ "${DOCS_ONLY_DIFF}" -eq 1 ]]; then <record a skip>; else <run the check>; fi`. There is no runtime distribution mechanism for `gate_fast.sh` internals (unlike the CI YAML template in `docs/CI-INTEGRATION.md`, which consumers pin via a release tag) — each project vendors its own gate script, so this ships as a **documented pattern to copy and adjust**, not a shared script consumers source directly. Override `DOCS_ONLY_BASE_REF` or `DOCS_ONLY_ALLOW_PATTERNS` before calling `compute_docs_only_diff` if your project's default branch or doc-file layout differs from dev-platform's own.
```

**Acceptance Test:**

```bash
grep -n "Gate-Fast Docs-Only Diff Skip" docs/RULE_RATIONALE.md   # expect 1 match (the heading)
```

---

### Change 5: `CLAUDE.md` — one-line pointer under Gate Tiers

**Problem:** `CLAUDE.md`'s "Gate Tiers" section is the canonical, always-loaded contract description of what `/gate fast` does — it should say the skip exists, with a pointer to the full write-up, the same way it already points to `docs/RULE_RATIONALE.md` for other gate-tier detail.

**File:** `CLAUDE.md`, end of the "## Gate Tiers" section (immediately after the existing "Why asymmetric..." paragraph).

**Implementation:**

Append this paragraph after the existing "Why asymmetric: ... Project-specific gate-tier detail in `docs/RULE_RATIONALE.md`." sentence:

```markdown
`/gate fast` additionally skips its expensive code-verifying checks (test suites, lint, build) when the diff vs. the default branch touches only `.md`/`docs/*`/`tasks/*` files — structural/taxonomy checks always still run. Reusable detector + adoption guide: `scripts/lib/docs_only_diff.sh` + `docs/RULE_RATIONALE.md` → "Gate-Fast Docs-Only Diff Skip".
```

**Acceptance Test:**

```bash
grep -n "docs_only_diff.sh" CLAUDE.md   # expect >= 1 match
```

---

## What NOT to Do

- **Do not edit any other project's `gate_fast.sh`.** Keystone already has its own copy of the pattern; SQRL/OPIE/kanban/keystone_prototype need to port it from their own sessions. Writing into `projects/<name>/` from this session violates the Scope rule — see Post-merge below for the sanctioned handoff (filed issues, not code).
- **Do not widen `actions/checkout`'s fetch depth in `.github/workflows/gate.yml`.** Out of scope — see Design Philosophy's "Not in scope" paragraph. The skip is a local dev-loop optimization; CI already fails safe to "run everything" on a shallow checkout, which is correct, not a bug to fix.
- **Do not skip any of the existing lift checks** (taxonomy, bash syntax, JSON validity, secrets scan, live `~/.claude/` verify) on a docs-only diff. They're the structural/CT-* equivalent and must always run — several exist specifically to catch doc/roadmap-content mistakes.
- **Do not hardcode the doc-path allowlist inside `compute_docs_only_diff`'s body.** It must stay overridable via `DOCS_ONLY_ALLOW_PATTERNS` so a consuming project with a different doc layout can adjust without editing the shared file's logic.
- **Do not attempt to distribute `scripts/lib/docs_only_diff.sh` as something consumers `curl`/source at runtime.** No such mechanism exists for `gate_fast.sh` (unlike the CI YAML template). It's copy-paste-and-adjust — say so explicitly in the docs, don't silently imply otherwise.
- **Do not skip the "does NOT skip itself" proof.** Change 3's acceptance test — this spec's own `./scripts/gate_fast.sh` run correctly reporting NOT docs-only — is load-bearing evidence the wiring is correct, not optional.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/lib/docs_only_diff.sh` | New | Reusable docs-only-diff detector (overridable base ref + allowlist) |
| `tests/docs-only-skip/run.sh` | New | 7-assertion unit suite for the detector |
| `scripts/gate_fast.sh` | Modify | Source the detector; skip the test-suite loop (per-suite `SKIP`) when docs-only; lift checks unaffected |
| `docs/RULE_RATIONALE.md` | Modify | New "Gate-Fast Docs-Only Diff Skip" section — resolves the issue's pattern-vs-script question |
| `CLAUDE.md` | Modify | One-line pointer under "Gate Tiers" |

## Implementation Order

1. Change 1 (`scripts/lib/docs_only_diff.sh`) — no dependents, do first.
2. Change 2 (`tests/docs-only-skip/run.sh`) — depends on Change 1; prove the detector correct before wiring it into the live gate.
3. Change 3 (`scripts/gate_fast.sh` wiring) — depends on Change 1 (and is validated in practice by Change 2 already passing).
4. Change 4 (`docs/RULE_RATIONALE.md`) — depends on Changes 1-3 existing so the write-up is accurate.
5. Change 5 (`CLAUDE.md` pointer) — depends on Change 4 existing (the doc it points to).

## Post-merge (coordination — NOT dev-platform code)

1. **Close the issue.** Comment on [teelr/dev-platform#68](https://github.com/teelr/dev-platform/issues/68) summarizing what shipped (link this spec + the merged PR + the new `docs/RULE_RATIONALE.md` section) and explicitly stating the resolved triage question (documented pattern + a small shared detector file to copy in; not a script consumers source at runtime). Close the issue.
2. **File the handoff issues** — one per project below, title `Port gate-fast docs-only-diff skip pattern from dev-platform`, body linking to `docs/RULE_RATIONALE.md`'s "Gate-Fast Docs-Only Diff Skip" section (GitHub blob URL, e.g. `https://github.com/teelr/dev-platform/blob/main/docs/RULE_RATIONALE.md#gate-fast-docs-only-diff-skip`) and to `scripts/lib/docs_only_diff.sh` as the file to copy in, noting Keystone already has an equivalent (their own session can decide whether to swap to the shared detector or leave their existing inline version):
   - `gh issue create --repo teelr/keystone_prototype ...`
   - `gh issue create --repo Osigin-LLC/SQRL ...`
   - `gh issue create --repo teelr/OPIE ...`
   - `gh issue create --repo teelr/kanban ...`
   - (Keystone itself: a lighter-touch note, not a full port ask — comment on or link from the same round, since `teelr/keystone` already has the pattern; optional whether that's a new issue or just a mention in its own next gate-related PR.)
3. **Standard Roadmap-Phase completion.** This spec is v1.14's only Phase — its merge completes the Roadmap Phase. Mark `v1.14` complete in `ROADMAP.md` + `planning.md` (today's date + status), close milestone #25 (`gh api -X PATCH repos/teelr/dev-platform/milestones/25 -f state=closed`), and verify with `./scripts/check-phase-milestones.sh`.

## Verification Checklist

- [ ] `scripts/lib/docs_only_diff.sh` exists, sets `DOCS_ONLY_DIFF` + `DOCS_ONLY_CHANGED_FILES`, base ref and allowlist both overridable before calling `compute_docs_only_diff`
- [ ] `bash tests/docs-only-skip/run.sh` → 7 PASS, 0 FAIL
- [ ] `scripts/gate_fast.sh` sources the detector; each discovered suite runner is recorded `SKIP` (not run) when `DOCS_ONLY_DIFF=1`; lift checks (taxonomy, syntax, JSON, secrets, live verify) run unconditionally either way
- [ ] `./scripts/gate_fast.sh` run against this spec's own diff reports NOT docs-only (diff touches `scripts/`/`tests/`) and the full suite executes, all PASS (233 + 7 new − any dropped = expect 235 PASS from 228 baseline + 7 new suite assertions)
- [ ] `docs/RULE_RATIONALE.md` has the new "Gate-Fast Docs-Only Diff Skip" section, explicitly resolving "documented pattern vs. shared script"
- [ ] `CLAUDE.md` Gate Tiers section has the one-line pointer to the detector + doc
- [ ] No hardcoded doc-path allowlist inside `compute_docs_only_diff`'s body — overridable via `DOCS_ONLY_ALLOW_PATTERNS`
- [ ] No file written under `projects/<name>/` in this diff
- [ ] Language architecture matrix followed (bash only, matches the existing `gate_fast.sh`/test-suite convention, no new component crossing the matrix)
- [ ] `/security-review` — N/A (no auth/credentials/external input/new endpoints; a local git-diff detector). Skip unless `/code` surfaces something unexpected.
