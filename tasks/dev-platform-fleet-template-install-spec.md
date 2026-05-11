# v0.8 Phase 3 — Opt-in Drift Correction + Scope Carve-out

## Coding Specification for Implementation

## Design Philosophy

Phase 3 is the **first mutating Phase of v0.8** — the first time dev-platform code deliberately writes to a file under `projects/`. The mutation is narrow by design: ONE filename (`.github/workflows/dev-platform-gate.yml`) in ONE directory (`<project>/.github/workflows/`). Nothing else. The script that performs this write — `scripts/fleet-install-template.sh` — requires explicit `--project <name>` (no `--all` flag exists; never add one) and explicit `--apply` (dry-run is the default, mirroring `sync-milestones.sh` and the pattern in `dev/CLAUDE.md`). This is the v0.8 opt-in adoption path for consumer projects to plug into the dev-platform-gate CI workflow without manually `curl`-ing the template into each project.

The Scope rule in `/home/rich/dev/CLAUDE.md` currently says: "Behavioral rule for the assistant — never silently reach into projects/." Phase 3 carves out a narrow exception that lands in Change 7 BEFORE Change 8 implements the writing code. This ordering matters: per the workflow-extension rule from PR #9, carve-outs must exist in the canonical rule BEFORE the code that depends on them ships. The carve-out is intentionally specific (names the script, names the filename, names the directory) so future v0.8+ writes can't slip in under a vague "fleet operations are allowed" framing — each new mutating script needs an explicit addition to the carve-out.

Tests use the [tests/helpers/mock-project-tree.sh](../tests/helpers/mock-project-tree.sh) helper shipped in Phase 2 + a mock fleet registry written inline in the runner (the Phase 2 fixture-naming + auto-discovery-contract lessons apply: `mock-projects/` not `projects/`; no runnable `.sh` files under `fixtures/`). The fixture-side audit confirms the script writes EXACTLY ONE file at EXACTLY the target path — no other filesystem writes, no other paths touched.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/fleet-install-template.sh` | Bash | Entry-point pattern (`install.sh`, `gate_fast.sh`, `sync-vscode.sh`, `sync-milestones.sh`, `fleet-gate.sh`, `fleet-status.sh`). File-IO + jq registry parsing. No CPU/AI workload. |
| `tests/fleet-install/run.sh` | Bash | Test-suite pattern locked in v0.4; mock-project-tree pattern from v0.8 Phase 2. |

No new code-component category. The Scope-rule update is a Markdown rule edit; the docs/CI-INTEGRATION.md update is also Markdown.

## Overview

1. **Phase 1:** Scope-rule carve-out (Change 1)
2. **Phase 2:** `fleet-install-template.sh` + tests + adoption-guide section (Changes 2–4)

The Spec uses 2 Spec Phases to enforce the "rule lands before code" ordering: Phase 1 (Change 1) MUST be in the same PR as Phase 2 (Changes 2-4), but Change 1 commits FIRST so the carve-out exists when Change 2 lands. Per the per-Spec-Phase strategy with the small-Phase carve-out, both Phases ship as ONE PR (~350 LOC across 4 files — under the per-Spec-Phase threshold).

---

## Phase 1: Scope-rule Carve-out

### Change 1: Update Scope rule in `/home/rich/dev/CLAUDE.md`

**Problem:** Pre-v0.8, the Scope rule's prose is absolute: "no edits, commits, or fixes to project code from here." Phase 3 introduces a narrowly-scoped exception (deploy the dev-platform-CI integration file). The exception MUST land IN the rule, not just IN the spec — future sessions read CLAUDE.md, not this spec, and a one-off "fleet-install-template.sh writes to projects/" without a rule carve-out would re-trigger the very Scope-rule violation the rule exists to prevent.

**File:** `/home/rich/dev/CLAUDE.md` (existing — modify the "Scope — dev-platform Is For The Environment, Not The Projects" section)

**Implementation:**

Locate the existing "Behavioral rule for the assistant:" paragraph (currently around line 22 of CLAUDE.md) and the immediately-following "Exception — scaffolding:" paragraph (around line 24). Add a NEW paragraph after the scaffolding exception, BEFORE the "Why this rule exists:" paragraph (around line 26):

```markdown
**Exception — v0.8 fleet orchestration (mutating subset):** v0.8's
`scripts/fleet-install-template.sh` (and any future v0.8+ script
documented here) IS allowed to write the **dev-platform-CI
integration files** into a project's `.github/workflows/` directory.
Specifically: `dev-platform-gate.yml` from
`extensions/github-actions/`, and any future v0.8-introduced
template equivalents. ALL other writes against `projects/` remain
forbidden from dev-platform sessions: no source code edits, no
schema changes, no business-logic fixes, no spec authorship, no
test additions, no commits made on behalf of a project. The
mutation must be opt-in (explicit `--apply` flag) and reversible
(write the same file the user could `cp` manually). The carve-out
exists because per-project install of the consumer template is
exactly the v0.8 use case that doesn't fit either "stay out
entirely" or "open a session in the project" — adopting the
dev-platform CI integration is a dev-platform operation, not a
per-project feature decision.
```

The paragraph language is taken from the v0.8 parent spec ([tasks/dev-platform-fleet-orchestration-spec.md](dev-platform-fleet-orchestration-spec.md), Change 7). The narrow scope ("ONE filename, ONE directory") is what keeps the carve-out from drifting into a generic "fleet ops are allowed" loophole.

Also update the "Why this rule exists:" paragraph to acknowledge the v0.8 carve-out's place in the rule history (so the rationale stays clear when future readers see two exceptions stacked).

**Acceptance Test:**

```bash
# Carve-out paragraph present
grep -A 3 "Exception — v0.8 fleet orchestration" /home/rich/dev/CLAUDE.md | head -5
# Expect: paragraph text describing the narrowly-scoped exception

# Gate still passes after the rule edit (CLAUDE.md content doesn't change gate behavior)
./scripts/gate_fast.sh 2>&1 | tail -1
# Expect: GATE FAST: PASS
```

---

## Phase 2: Install Script + Tests + Docs

### Change 2: `scripts/fleet-install-template.sh` — opt-in consumer adoption

**Problem:** The v0.7 Phase 2 consumer template at [extensions/github-actions/dev-platform-gate.yml](../extensions/github-actions/dev-platform-gate.yml) is copy-paste-ready, but copy-paste is manual per-project work. A fleet-level script that resolves the project via the registry, checks adoption state, and writes the template into the project (via `--apply --project <name>`) makes the integration scale across the fleet without each consumer manually `curl`-ing the file.

**File:** `scripts/fleet-install-template.sh` (new, ~120 lines)

**Implementation:**

Bash entry point. Args:

- `--project <name>` (required; explicit per-project opt-in — NO `--all` flag exists)
- `--apply` (default is dry-run)
- `--force` (overwrite existing target; default is refuse-to-clobber)
- `--pin <vX.Y>` (override the `@v0.7` default to a different tag, e.g., `--pin v0.8` once v0.8 cuts)
- `--registry <path>` (override for tests)
- `--help`

Argparse-robustness per the v0.7 Phase 4 lesson: every value-taking arg has an explicit `[[ $# -eq 0 ]] && exit 2` guard.

Algorithm:

1. **Resolve project from registry.** Read `monitoring/projects.json` via `jq`. Find entry where `.name == "${PROJECT}"`. If not found OR `.enabled` is false (without `--apply`-style override), error out. The path field becomes the project's filesystem root.
2. **Source template.** Read `extensions/github-actions/dev-platform-gate.yml` from the dev-platform repo root.
3. **Optional pin rewrite.** If `--pin <vX.Y>` is set, sed the `@v0.7` reference in the template to `@<pin>` before writing. The source template stays untouched (writes go to the project's copy).
4. **Compute target path.** `"${project_path}/.github/workflows/dev-platform-gate.yml"`. **Hardcode this format** — do not derive it from a CLI flag or env var. This is the Scope-rule carve-out's literal constraint: ONE filename in ONE directory, nowhere else.
5. **Pre-flight check.** If target exists AND `--force` not set, refuse with actionable error message. Mirrors [scripts/install.sh](../scripts/install.sh)'s `link_file` refuse-to-clobber discipline.
6. **Dry-run mode (default).** Print:
   - Source path (where the template comes from)
   - Target path (where it would be written)
   - Pin in effect (the `@vX.Y` line)
   - Diff vs existing target if any (so the user sees what would change)
   - Final line: `Dry-run — re-run with --apply to write.`
7. **Apply mode.** `mkdir -p "$(dirname "${target}")"` then write the (possibly pin-rewritten) template bytes. Echo success: `Wrote ${BYTES} bytes to ${target}`.
8. **Telemetry.** Emit a `fleet_install_template` JSONL event to `~/.claude/dev-platform-telemetry.log` (same emitter pattern as `fleet-gate.sh`'s `fleet_gate_run`). Fields: `project`, `target_path`, `pin`, `dry_run` (bool), `outcome` (`success`/`refused`/`error`). Best-effort: telemetry failure does NOT abort the install.

**Hard-coded safety**: the script's target-path computation is a single line that builds `<project_path>/.github/workflows/dev-platform-gate.yml`. There is no flag, env var, or branch in the code that lets the path become anything else. If a future spec needs a different target, it amends the Scope-rule carve-out AND adds a new path to this script — both in lockstep.

**Acceptance Test:**

```bash
test -x scripts/fleet-install-template.sh
bash -n scripts/fleet-install-template.sh
./scripts/fleet-install-template.sh --help | grep -q "fleet-install-template"

# Argparse robustness — every value-taking arg
./scripts/fleet-install-template.sh --project 2>&1 | grep -q "requires an argument"
./scripts/fleet-install-template.sh --pin 2>&1 | grep -q "requires an argument"
./scripts/fleet-install-template.sh --registry 2>&1 | grep -q "requires an argument"

# Required tools
PATH=/tmp ./scripts/fleet-install-template.sh 2>&1 | grep -qE "jq required|registry not found"

# Dry-run against a known-non-adopted project (mock or live)
./scripts/fleet-install-template.sh --project atlas
# Expect: dry-run output naming the planned target path; exit 0; NO file written
test ! -f projects/atlas/.github/workflows/dev-platform-gate.yml
```

### Change 3: `tests/fleet-install/run.sh` — fixture suite

**Problem:** The install script writes into `projects/<name>/.github/workflows/` — the only mutating operation v0.8 performs against projects. It must NEVER write outside that path, and it must respect the refuse-to-clobber + dry-run-default discipline. Hermetic tests with a mock project tree prove both. Without this suite, future edits to the script could relax the path guard or remove the dry-run default and ship undetected.

**File:** `tests/fleet-install/run.sh` (new, ~180 lines)

**Implementation:**

Source `tests/helpers/assert.sh` + `tests/helpers/mock-project-tree.sh` (shipped in Phase 2). Build a mock project tree under `mktemp -d`:

- `mock-projects/clean-1/` — no `.github/workflows/dev-platform-gate.yml` (template will be CREATED)
- `mock-projects/already-1/` — pre-existing `dev-platform-gate.yml` (template install will REFUSE without `--force`)
- `mock-projects/disabled-1/` — registry entry has `enabled: false`

Write a mock registry inline (same pattern as Phase 2's `tests/fleet-dashboard/run.sh`):

```json
[
  {"name": "clean-1", "path": "${MOCK_ROOT}/clean-1", "gate_cmd": "true", "enabled": true},
  {"name": "already-1", "path": "${MOCK_ROOT}/already-1", "gate_cmd": "true", "enabled": true},
  {"name": "disabled-1", "path": "${MOCK_ROOT}/disabled-1", "gate_cmd": "true", "enabled": false}
]
```

Required assertions (≥ 12):

1. **bash -n** — script syntax clean
2. **`--help`** — renders without writes, mentions `fleet-install-template`
3. **`--project` required** — running with no `--project` arg → error + non-zero exit
4. **Argparse robustness** — `--project` / `--pin` / `--registry` each emit "requires an argument" + exit 2 when value missing
5. **Required-tools gate** — `jq` missing (sandbox-PATH pattern) → error + exit 2
6. **Dry-run is default** — `--project clean-1` (no `--apply`) → no file written; dry-run banner in output
7. **`--apply` writes the file** — target exists at `mock-projects/clean-1/.github/workflows/dev-platform-gate.yml` after invocation; file contents match the source template
8. **Refuse-to-clobber** — `--apply` against `already-1` (without `--force`) → error + exit 1; target file content UNCHANGED
9. **`--force` overwrites** — `--apply --force` against `already-1` → success; target file content matches source template
10. **`--pin v0.6` rewrites the tag** — `--apply --pin v0.6 --project clean-1` → written file contains `@v0.6`, NOT `@v0.7`
11. **Disabled-project gate** — `--project disabled-1` → error + exit 1 (the script refuses to operate on disabled entries)
12. **Path-guard contract** — script never writes outside `<project>/.github/workflows/`. Test: invoke `--apply --project clean-1`, then audit the mock-projects tree for any files created OUTSIDE `clean-1/.github/workflows/dev-platform-gate.yml`. None should exist.
13. **Telemetry event emitted on `--apply`** — redirect `HOME` so the script writes to a tmpfile mock telemetry log; grep for `fleet_install_template` JSONL line.

Test runner uses `mktemp -d` + `trap` cleanup. Auto-discovered by `gate_fast.sh`.

**Acceptance Test:**

```bash
bash tests/fleet-install/run.sh
# Expect: 13 PASS / 0 FAIL

./scripts/gate_fast.sh 2>&1 | grep -q "tests/fleet-install/run.sh"
# Expect: present in output

# Gate count grows by 13 (was 100 → 113 after Phase 3)
```

### Change 4: Update `docs/CI-INTEGRATION.md` with the automated-install path

**Problem:** Phase 2's [docs/CI-INTEGRATION.md](../docs/CI-INTEGRATION.md) instructs consumers to manually `curl` the template into their project. With Change 2 shipped, there's now an automated path. The guide should mention it without removing the manual instructions (which remain valid for non-Rich consumers who don't have shell access to the dev-platform repo).

**File:** `docs/CI-INTEGRATION.md` (existing — append a new section)

**Implementation:**

Add a new section "Automated install (Rich's own projects)" after the existing "Adoption — 3 steps" section (around line 50 of the file):

```markdown
## Automated install (Rich's own projects)

If your project is in dev-platform's
[project registry](../monitoring/projects.json), use the v0.8 fleet
helper instead of the manual `curl`:

​```bash
# From the dev-platform repo root
./scripts/fleet-install-template.sh --project <name>           # dry-run
./scripts/fleet-install-template.sh --project <name> --apply   # write
./scripts/fleet-install-template.sh --project <name> --apply --pin v0.7
​```

Functionally identical to the manual `curl` flow — same file, same target
path. The helper just walks the registry so you don't repeat the project
path each time. Per the v0.8 Scope-rule carve-out (see
[dev/CLAUDE.md](../CLAUDE.md) → "Exception — v0.8 fleet orchestration"),
this is the ONLY write the fleet helper performs against your project;
everything else in this guide stays manual.

If your project is NOT in dev-platform's registry, use the manual `curl`
flow above. Adding a project to the registry is a one-line edit to
`monitoring/projects.json`.
```

**Acceptance Test:**

```bash
grep -q "## Automated install" docs/CI-INTEGRATION.md
grep -q "fleet-install-template" docs/CI-INTEGRATION.md

# Markdown still parses cleanly (no malformed code fences from the heredoc)
# Spot-check by rendering with `glow` or similar; alternatively just
# verify the structure: the new section has a heading + a code block + a
# paragraph.
```

---

## Post-merge step (deferred, in spec — runs after PR squash-merges)

**Adopt the template into 1-2 active consumer projects.** From the dev-platform session (still permitted under the new carve-out):

```bash
./scripts/fleet-install-template.sh --project atlas              # dry-run first
./scripts/fleet-install-template.sh --project atlas --apply      # write
./scripts/fleet-install-template.sh --project kermit-pa --apply  # second consumer
```

After each adoption: switch to the consumer's repo session and open a PR there adding the dev-platform-gate.yml (the consumer commits + pushes, not dev-platform). Confirm the dev-platform-gate workflow appears on the consumer's next PR and reports green.

**No release tag** (that's Phase 4's job — Phase 4 closes v0.8 with the release-tag cut). **No Milestone close** (v0.8 Milestone stays open until Phase 4 ships).

---

## What NOT to Do

- **Do NOT add an `--all` flag** to `fleet-install-template.sh`. Per-project opt-in is the carve-out's load-bearing constraint. An `--all` flag would let one bad invocation pollute every consumer's `.github/workflows/`. Even with `--dry-run`, the auditability of "I deployed exactly this to exactly that project" goes away.
- **Do NOT compute the target path from a CLI flag or env var.** The script's target is HARD-CODED as `<project_path>/.github/workflows/dev-platform-gate.yml`. Per the Scope-rule carve-out, this is the only path v0.8 is allowed to write. A flag-driven target would let a future caller (or a typo) target arbitrary paths under `projects/`.
- **Do NOT remove the dry-run default.** Tools that mutate shared state require explicit `--apply`. Same discipline as `sync-milestones.sh`. The dry-run output is the auditability mechanism — users see exactly what would change before committing to it.
- **Do NOT remove refuse-to-clobber.** `--apply` against an existing target REFUSES unless `--force` is set. This is the v0.1 Foundation `link_file` safety discipline applied to a different mutation. Removing it would let a script run silently overwrite a consumer's hand-edited copy of the template.
- **Do NOT write outside `.github/workflows/dev-platform-gate.yml`** from any v0.8 script. The Scope-rule carve-out is exactly ONE filename in ONE directory. Adding a second exception requires a new spec + a new carve-out paragraph, not a flag.
- **Do NOT skip the path-guard test (Change 3, assertion 12).** That test mechanically enforces "no other files created in mock-projects/" — it's the gate that catches future drift where a script change accidentally writes a `.bak` file or a `.swp` artifact next to the template.
- **Do NOT auto-deploy the consumer template from any CI workflow.** This is a manual Rich-invoked operation. Auto-running from dev-platform's CI would deploy the template on every push to main; auto-running from a consumer's CI would re-introduce the cross-project coupling v0.8 is intentionally limited.
- **Do NOT add a "Phase 3 closes v0.8" framing.** Phase 4 (pin tracking) closes v0.8 with the release-tag cut. Phase 3 ships the FIRST mutating Phase but is NOT the closing Phase.
- **Do NOT extend the Scope-rule carve-out's "ALL other writes... remain forbidden" clause.** The carve-out is intentionally NARROW. If a future v0.8+ spec needs another mutation (e.g., delete an obsolete workflow file from consumers), it gets its OWN carve-out paragraph naming the new script + filename + directory. Don't relax this paragraph's wording.
- **Do NOT name fixture subdirectories `projects/`** under `tests/fleet-install/fixtures/`. Use `mock-projects/` per the Phase 1 lesson. (The lesson is already a "What NOT to Do" entry in the parent v0.8 spec; restated here because Phase 3 also creates a fixture tree.)

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `/home/rich/dev/CLAUDE.md` | Modify | Add the v0.8 fleet-orchestration carve-out paragraph to the Scope section |
| `scripts/fleet-install-template.sh` | New | Opt-in per-project template install (dry-run default, refuse-to-clobber, `--pin` override) |
| `tests/fleet-install/run.sh` | New | 13-assertion fixture suite using mock-project-tree helper |
| `docs/CI-INTEGRATION.md` | Modify | New "Automated install (Rich's own projects)" section |

No `.gitignore` extensions needed — every file type already in the allow-list:

- `scripts/*.sh` covers fleet-install-template.sh ✓
- `tests/**/*.sh` covers run.sh ✓
- `docs/*.md` covers CI-INTEGRATION.md ✓ (existing file)
- CLAUDE.md tracked via `!CLAUDE.md` ✓

Consumer Audit reduces to confirming `git check-ignore -v` on every new file.

## Implementation Order

1. **Change 1** (Scope-rule carve-out) — MUST land before Change 2 implements writing into `projects/`. Same workflow-extension pattern as PR #9.
2. **Change 2** (`scripts/fleet-install-template.sh`) — main deliverable.
3. **Change 3** (`tests/fleet-install/run.sh`) — depends on Change 2 + the mock-project-tree helper from Phase 2.
4. **Change 4** (`docs/CI-INTEGRATION.md` update) — depends on Change 2 existing.
5. **Local verification** — `bash tests/fleet-install/run.sh` → 13/13, then `./scripts/gate_fast.sh` → 113/0/0.
6. **Post-merge** — adopt the template into 1-2 active consumer projects from a dev-platform session.

## Verification Checklist

- [ ] `/home/rich/dev/CLAUDE.md` contains the v0.8 fleet-orchestration carve-out paragraph
- [ ] `scripts/fleet-install-template.sh` exists, bash-syntax clean, executable
- [ ] `--help` renders without writes
- [ ] Argparse robustness: `--project` / `--pin` / `--registry` each emit "requires an argument" + exit 2 when value missing
- [ ] Required-tools gate (sandbox PATH without jq) → "jq required" + exit 2
- [ ] Missing-project gate (`--project nonexistent`) → error + non-zero
- [ ] Disabled-project gate (`--project disabled-1`) → error + non-zero
- [ ] Dry-run is default — no file written, dry-run banner in output
- [ ] `--apply` writes the template to `<project_path>/.github/workflows/dev-platform-gate.yml`
- [ ] Refuse-to-clobber: `--apply` against existing target → error, target unchanged
- [ ] `--force` overrides refuse-to-clobber
- [ ] `--pin v0.6` rewrites the `@v0.7` to `@v0.6` in the written file
- [ ] **Path-guard contract**: script never writes outside `<project>/.github/workflows/dev-platform-gate.yml`
- [ ] Telemetry event emitted on `--apply`
- [ ] `bash tests/fleet-install/run.sh` → 13 PASS / 0 FAIL
- [ ] `./scripts/gate_fast.sh` → **113 PASS** / 0 FAIL / 0 SKIP (was 100 + 13 fleet-install assertions)
- [ ] `./scripts/check_spec_taxonomy.sh` clean
- [ ] `docs/CI-INTEGRATION.md` has the new "Automated install" section
- [ ] No file under `projects/` modified (DURING this PR's /code; post-merge IS allowed to install the template)
- [ ] Consumer Audit: every new file `git check-ignore -v`'d, all show re-include rules
- [ ] **Post-merge**: template adopted into 1-2 active consumer projects via `--apply`; dev-platform-gate workflow appears on each consumer's next PR

## Out of Scope (Future Specs)

- **Auto-deploy to all consumers** — never. `--all` flag is explicitly forbidden by the carve-out's narrow language.
- **Removing the template from consumers** — would need its own Scope-rule carve-out + a separate script. Out of v0.8 scope.
- **Two-way diff/merge between consumer-side edits and the source template** — speculative. If consumers hand-edit their copy (e.g., add a custom job), v0.8 doesn't try to merge. `--force` overwrites; refuse-to-clobber preserves. That's the contract.
- **Version-bump automation** — bumping a consumer's `@vX.Y` pin to the latest dev-platform release. Out of Phase 3. Phase 4's pin-tracking surfaces stale pins; Phase 3 doesn't auto-bump them.
- **Webhook notification when a consumer adopts** — out of scope; the post-merge step is manual verification.
- **A `--reset` flag that restores the source template's `@v0.7` pin** — speculative. Consumers can re-run `--apply --force` to overwrite.

## Notes for Implementation

- **Change 1 commits BEFORE Change 2.** When implementing, write Change 1 first, then Change 2-4. The git-history record (squash-merged into one commit) doesn't show the ordering, but the in-spec ordering matters for the same reason PR #9's workflow extension shipped before the v0.7 Phase 2 CI that depended on it.
- **The `--pin` rewrite uses `sed -i` on the in-memory template content**, NOT on the source file. The source `extensions/github-actions/dev-platform-gate.yml` stays committed with `@v0.7`. The pin-rewrite happens after the script reads the source into a Bash string variable and before it writes the target.
- **The path-guard test (Change 3, assertion 12) is load-bearing.** Any future change to `fleet-install-template.sh` that introduces a second write path WILL be caught by this test. Keep it specific: enumerate every file in `mock-projects/<X>/` after `--apply` and assert the set is exactly `{.github/workflows/dev-platform-gate.yml}`. Don't relax to "no .py / no .json" or similar — the assertion is "no other files at all."
- **The telemetry event uses the same pattern as `fleet-gate.sh`'s `fleet_gate_run`** — same JSONL shape, same `~/.claude/dev-platform-telemetry.log` destination, same best-effort failure mode.
- **The argparse-robustness pattern** is mandatory: every value-taking flag MUST emit "ERROR: --<flag> requires an argument" + exit 2 when value missing. Test it explicitly per assertion 4.
- **The Scope-rule update in Change 1 is the ONLY edit to `/home/rich/dev/CLAUDE.md` this PR makes.** Don't add other rule changes alongside it — keep the diff focused. If other CLAUDE.md edits are needed, they ship as a separate chore PR (like PR #14's boundary-contract rule).
- **The mock-project-tree helper from Phase 2 covers init/dirty/taxonomy/template-install** — but for Phase 3's tests, we ALSO need a pre-installed-template scenario (the `already-1` mock project). Use `mock_project_install_template` from the helper to create it BEFORE running the script under test.
- **The default pin is `@v0.7`** — that's what the source template at `extensions/github-actions/dev-platform-gate.yml` currently uses. Phase 4 (which closes v0.8 with the release-tag cut) will rev the default to `@v0.8` AFTER v0.8 ships its release tag. Don't update the default in this Phase.
