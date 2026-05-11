# Glossary

Definitions for every project-specific term in active use across dev-platform docs and PRs. Alphabetized (case-insensitive). Each entry links to authoritative sources when relevant.

This file is read by people landing on the [Pages site](https://teelr.github.io/dev-platform/) for the first time — every term here actually appears somewhere in this repo's tracked Markdown. Speculative future vocabulary intentionally stays out (per the Honesty rule in [CLAUDE.md](../CLAUDE.md)).

## Terms

### Auto-discovery

The contract `scripts/gate_fast.sh` enforces: it walks `tests/*/` and runs every `*.sh` runner under each subdir. Adding a new test suite drops a directory and a `run.sh` into it — the orchestrator picks it up automatically with no edit. Landed in v0.4 Testing.

### Change

Atomic implementation step inside a [Spec](#spec). Header format: `### Change N: <title>`. Numbered continuously across the whole Spec (Change 1 in Phase 1, Change 7 might be in Phase 3 — the number doesn't reset). One Change becomes one commit when implemented. See [CLAUDE.md > Development Terminology](../CLAUDE.md).

### CI green / CI red

The result of the [`gate-fast`](#gate-fast) workflow on a [PR](#pr-pull-request). Green = pass, red = fail. The rule **no merge before CI green** is canonical from PR #9 (the workflow-doc extension). Red CI means fix on the branch and re-push — never merge around a red gate.

### Commit

Git record bundling feature code + doc updates into one atomic unit, per the Docs-Before-Commit rule. Splitting a feature across a `feat:` commit and a follow-up `docs:` commit pollutes history — `git log feat:` would show stale planning/roadmap state. See [CLAUDE.md > Development Workflow](../CLAUDE.md).

### Consumer Audit

Five-point checklist run when introducing a new file type in a glob-managed directory: (1) `.gitignore` allow-list, (2) install / deploy scripts, (3) verify / check scripts, (4) directory README, (5) test orchestrators. Promoted to [CLAUDE.md](../CLAUDE.md) as PR #5 after recurring 2026-05-11 omissions. Surfaces silent gitignore drops and missing deploy paths before a PR lands.

### Cut release

Tag a GitHub Release (`v0.6`, `v0.7`, etc.) at the merge commit that closes a [Roadmap Phase](#roadmap-phase). Done via `gh release create` with `--target` set to the merge commit SHA. v0.7's release tag cuts at Phase 4 completion (the last Spec Phase in the v0.7 Roadmap Phase).

### Deploy

Running `scripts/install.sh` to symlink tracked files from this repo into `~/.claude/`. The tracked file in the repo is the source of truth; `~/.claude/` is the deployment. Compare [Live cutover](#live-cutover) (the first deploy of a new artifact) and [Symlink deploy](#symlink-deploy) (the underlying mechanism).

### Drift

Divergence between the tracked file in this repo and its deployed copy under `~/.claude/`. Detected by `scripts/verify.sh`. The [Gate](#gate-fast)'s `live ~/.claude/ verify` lift check blocks local commits when drift exists on Rich's machine; the same check SKIPs on CI runners where `~/.claude/` doesn't exist (fix landed in PR #8).

### Gate

Shorthand for "the constitutional check that must pass before something advances." Three tiers exist for dev-platform; see [Gate fast](#gate-fast), [Gate full](#gate-full), [Gate release](#gate-release). Other projects under `/home/rich/dev/projects/` have their own gates with the same three-tier shape per [CLAUDE.md > Consistency Across All Projects](../CLAUDE.md).

### Gate fast

The inner-loop gate run before every commit (`./scripts/gate_fast.sh` in dev-platform). [Lift checks](#lift-checks) + per-suite test runners. ~5–20s. The MUST-pass gate before commit, and the only gate currently wired into CI as of PR #8. The "fast" tier is intentionally surgical for inner-loop velocity.

### Gate full

The outer-loop gate run after structural changes. Adds load-tier smokes for projects that have them. ~10–35 min. In dev-platform there's no `gate_full.sh` yet — fast covers everything until cross-project orchestration (v0.8) needs more.

### Gate release

The pre-release gate. Adds full load tests (1K agents, 1K tenants × 10 reqs, 2.5K horizontal). ~3+ hours. Only run before tagging a release. Captured for parity with Kermit projects in [CLAUDE.md > Workflow Discipline](../CLAUDE.md).

### GitHub Milestone

Repo-level container 1:1 with a [Roadmap Phase](#roadmap-phase). Title matches the Phase header (`v0.7: Team Enablement`). Closed when the Phase ships. v0.7 Phase 4's `scripts/sync-milestones.sh` automates mirroring `ROADMAP.md` → Milestones.

### In flight

A [Spec Phase](#spec-phase) that's implemented on a feature branch but not yet merged. Tracked in [planning.md](../planning.md)'s "In flight" section. Distinct from "merged" (commit landed but post-merge tasks may still be pending) and from [Ship](#ship) (Phase fully closed including post-merge).

### Land

Synonym for merge: a commit squash-merged into `main`. "PR #8 landed at `a551d95`." Distinct from [Ship](#ship) — landing is the commit hitting `main`; shipping includes any [Post-merge](#post-merge) tasks the Spec deferred.

### Lift checks

The five top-of-gate checks in [scripts/gate_fast.sh](../scripts/gate_fast.sh): spec taxonomy enforcement, bash syntax, JSON validity, secrets scan, live `~/.claude/` verify. Run before the per-suite test runners under `tests/`. Named "lift" because they hoist the whole gate's PASS/FAIL on five fast checks before any expensive suite runs.

### Live cutover

The first deploy of a new artifact onto Rich's machine, where the tracked file becomes the live source of truth for that artifact. v0.1 Foundation's live cutover migrated existing `~/.claude/` content into the repo and replaced the originals with symlinks. Subsequent cutovers happen each time a new tracked file deploys for the first time.

### Mock binary

Testability pattern: an extension-less executable script under `tests/<suite>/fixtures/mock-bin/` that mimics an external CLI (`code`, `gh`, `python`, etc.) via an env-var state file (`MOCK_STATE_FILE`). The test runner prepends the mock-bin dir to `PATH` so the mock takes precedence. Lets round-trip tests run without touching live state. Pattern landed v0.6.

### Per-Spec-Phase strategy

Branching convention adopted v0.5+: each [Spec Phase](#spec-phase) → one feature branch (`v0.7/phase-2-github-actions`) → one [PR](#pr-pull-request) assigned to the [Roadmap Phase](#roadmap-phase)'s [Milestone](#github-milestone) → squash-merge to `main`. Small Spec Phases (~250 LOC total) can ship as a single combined PR per the v0.6 small-Phase carve-out documented in [tasks/lessons.md](../tasks/lessons.md).

### Post-merge

The workflow step running deferred actions a Spec called out: branch-protection updates that require the workflow to exist on `main` first (v0.7 Phase 2's Change 6), release-tag cuts (when a Roadmap Phase closes), one-time `gh api` setup calls (v0.7 Phase 3's Pages-enable). The Spec lists what's deferred; `post-merge` runs those. No-op if the Spec defers nothing. Locked into the canonical workflow chain by PR #9.

### PR (Pull Request)

GitHub primitive that bundles a feature branch into a merge proposal against `main`. Opened with `gh pr create`. The PR boundary is where CI runs (via the [`gate-fast`](#gate-fast) workflow on every PR ref). Required for all merges to `main` under the branch protection live since v0.7 Phase 2's [Post-merge](#post-merge) Change 6.

### Reusable workflow

A GitHub Actions workflow with a `workflow_call:` trigger that other workflows invoke via `uses:`. Used by consumer projects to call dev-platform's `taxonomy-check.yml` without vendoring the script. See [.github/workflows/taxonomy-check.yml](../.github/workflows/taxonomy-check.yml). The reusable workflow checks out the caller's repo at `inputs.ref` and dev-platform at `github.workflow_sha` — see the `workflow_call / workflow_sha` entry below for why NOT `workflow_ref`.

### Roadmap Phase

Major product milestone (`v0.5: Monitoring`, `v0.7: Team Enablement`). Format `v<MAJOR>.<MINOR>[<letter>]: <Title>`, enforced by [scripts/check_spec_taxonomy.sh](../scripts/check_spec_taxonomy.sh). Each maps 1:1 to a GitHub [Milestone](#github-milestone). Distinct from [Spec Phase](#spec-phase) (smaller granularity, inside a Spec).

### Seed

Populate something with initial data. "Seed GitHub Milestones from `ROADMAP.md`" means create one Milestone per Roadmap Phase entry. v0.7 Phase 4's `scripts/sync-milestones.sh` is the canonical seeder for Milestones.

### Sentinel

A fixed string or value used in test fixtures to prove an operation didn't run. Example: [tests/scaffold/run.sh](../tests/scaffold/run.sh) writes a sentinel into a pre-existing file then asserts the install-refuse-to-clobber path preserved it (vs overwrote it). Different from a regular fixture in that the assertion is "this is unchanged" rather than "this matches expected new state."

### Ship

Verb for "shipped a Spec Phase": the [per-Spec-Phase PR](#per-spec-phase-strategy) merged AND any [Post-merge](#post-merge) tasks ran. Distinct from "merged" (commit landed but post-merge may still be pending). "v0.7 Phase 1 shipped 2026-05-11" means PR #7 merged AND nothing was deferred (vs Phase 2 which had Change 6 to run post-merge before fully shipping).

### Spec

`tasks/{name}-spec.md` file produced by [`/plan`](../CLAUDE.md). An implementation specification a separate `/code` agent can execute without additional context. The spec is the contract between planning and coding.

### Spec Phase

Group of related Changes inside one [Spec](#spec). Header format: `## Phase N: <title>`. Distinct from [Roadmap Phase](#roadmap-phase). Bare "Phase" in dev context = Spec Phase. Project-specific business hierarchies that ALSO use "Phase" (e.g., Keystone's domain model) qualify with the project name ("Keystone Phase").

### Squash merge

Merge strategy where all PR commits are squashed into one commit on `main`. The dev-platform default. Tool: `gh pr merge <N> --squash --delete-branch`. Combined with the per-Spec-Phase PR strategy, every merge to `main` is one squashed commit representing one Spec Phase.

### Symlink deploy

`scripts/install.sh`'s deploy mechanism: every tracked file in `commands/`, `hooks/`, `settings/`, `skills/` is symlinked into the corresponding `~/.claude/` location. The tracked file in the repo is the source of truth; `~/.claude/` is the deployment. Editing under `~/.claude/` directly is forbidden — the next install overwrites it.

### The gate

Informal for [Gate fast](#gate-fast). "Did the gate pass?" always means gate-fast unless qualified. "Gate green" / "gate red" → see [CI green / CI red](#ci-green--ci-red).

### Tracked file

A file in this repo (committed to `git`). Opposite of `deployed copy` under `~/.claude/`. The tracked file is the source of truth; `scripts/verify.sh` flags drift between the tracked file and its deployed copy.

### `v<MAJOR>.<MINOR>: <Title>`

[Roadmap Phase](#roadmap-phase) header format (e.g. `v0.5: Monitoring`). Enforced by [scripts/check_spec_taxonomy.sh](../scripts/check_spec_taxonomy.sh) against `ROADMAP.md` and `planning.md` (Phase 1 of the v0.7 Roadmap Phase). Killed prefixes flagged include legacy `R<N>:`, `Sprint X:`, `Stage Y:`, quarter buckets. See [CLAUDE.md > Development Terminology](../CLAUDE.md).

### Wired-in

A feature is "wired in" when its full data path (UI → API → backend → storage → response) exists end-to-end. Per [CLAUDE.md > Data Lifecycle & Wiring Rules](../CLAUDE.md): every new feature must be traceable end-to-end before being marked done. A backend endpoint with no frontend caller is NOT wired in.

### `workflow_call` / `workflow_sha`

GitHub Actions context primitives. `workflow_call` is a [reusable workflow](#reusable-workflow) trigger (the only way another workflow can `uses:` your workflow). `github.workflow_sha` is the commit SHA of the running workflow — used in `.github/workflows/taxonomy-check.yml` to check out dev-platform at the consumer's pinned ref. Do **NOT** use `github.workflow_ref` for the same purpose — it returns the full ref-path string (`owner/repo/.github/...@refs/tags/v0.7`), which `actions/checkout`'s `ref:` cannot resolve. See [tasks/lessons.md](../tasks/lessons.md) 2026-05-11.

---

## See also

- [CLAUDE.md](../CLAUDE.md) — full development standards (workflow, taxonomy, language matrix, port registry, project structure)
- [ROADMAP.md](../ROADMAP.md) — Roadmap Phase sequence v0.1 → v1.0
- [CI Integration Guide](CI-INTEGRATION.md) — how to plug your repo into dev-platform's taxonomy gate
- [tasks/lessons.md](../tasks/lessons.md) — accumulated gotchas and corrections
