# Rich's Development Standards

All development standards for projects in `/home/rich/dev/projects/`. This is the single source of truth.

**Project-specific deep-dive rules and incident rationale:** `/home/rich/dev/docs/RULE_RATIONALE.md`. Read when working in Kermit/PA/ATLAS/Keystone (Kermit-specific rules: kwarg propagation, boundary sweeps, consumer-side schema deps, harness-vs-consumer triage, load-tier gate coverage, duplicate handoff-queue/lessons numbering), or when a rule's reasoning is unclear.

## Scope — dev-platform Is For The Environment, Not The Projects

**CRITICAL — This repo (`teelr/dev-platform`, at `/home/rich/dev/`) exists to care for, maintain, and enhance the development *environments* that drive Rich's projects. It is NOT a workplace for the projects themselves.**

**Primary gateway — VSCode + Claude Code:** This repo is the single entry point for setting up and modifying Rich's VSCode + Claude Code dev environment. Every change to global Claude Code config (slash commands, skills, settings, hooks, keybindings) and global VSCode/IDE config goes through this repo first — written here, deployed via `scripts/install.sh`. **Direct edits to deployed locations (`~/.claude/`, `~/.vscode/`, etc.) are forbidden** — they get overwritten on the next install and split the source of truth in two.

**Belongs here:** Rules (`CLAUDE.md`, `settings/claude-global.md`), slash commands (`commands/`), skills (`skills/`), hooks (`hooks/`), settings (`settings/`), scripts (`scripts/`), IDE config (`extensions/`), scaffolding (`scaffolding/`), monitoring (`monitoring/`), shell helpers (`shell/`), specs/docs for the above (`tasks/`, `docs/`).

**Does NOT belong here:** Project source code, schemas, frontend, tests, deployment configs, or per-project roadmaps under `projects/<name>/` — those live in their own repos. No bug fixes, feature work, or refactors against any project from this session.

**Behavioral rule:** When invoked in `/home/rich/dev/`, assume every request is environment work. If a request would require modifying a file under `projects/`, STOP and ask the user to switch to that project's working directory. Read-only operations across projects (orientation, status surveys, cross-project assessments) ARE allowed.

**Exceptions:**

- `scripts/new-project.sh` may scaffold a new project tree under `projects/<new-name>/`. Conversational Q&A pattern in `docs/NEW-PROJECT.md`.
- `scripts/fleet-install-template.sh` (v0.8+) may write the dev-platform CI integration files (`.github/workflows/dev-platform-gate.yml`) into a project. All other writes to `projects/` remain forbidden.
- `scripts/migrate-workflow-chain.sh` (v0.9 migration tooling) may rewrite the workflow chain line(s) inside a project's `CLAUDE.md`. Detects lines matching a superseded chain pattern — either the legacy `/test`-bearing chain (`/plan → /code → /test`) or any chain that omits the mandatory `/review` gate — and rewrites them to the canonical chain (`/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`). All other content in the project's `CLAUDE.md` is left untouched. Opt-in (`--apply` flag required), dry-run by default, idempotent. Future chain updates require updating this entry — not a general "migration scripts may edit CLAUDE.md" loophole.

## Consistency Across All Projects — Non-Negotiable

**CRITICAL — Every project under `/home/rich/dev/projects/` MUST conform to these standards. Absolute consistency is a hard requirement.**

**What dev-platform owns (no project may diverge):**

- **Dev workflow** — `/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`. `/review` is a mandatory independent review gate on every change. `/code` handles verification, auto-fix, and doc updates internally; `/review` is the independent fresh-eyes pass `/code` cannot be.
- **Workflow taxonomy** — Roadmap Phase → Spec → Spec Phase → Change → Commit. Killed terms (Stage, Sprint, Iteration, Revision, Milestone, Group, Epic, Step, Item, Task) never used as workflow-level labels.
- **Language Architecture Decision Matrix** — network → Go, compute → Rust, AI → Python, frontend → TypeScript.
- **Slash commands** — `/plan`, `/code`, `/test`, `/review`, `/gate`, `/docs`, `/pr`, `/merge`, `/dev`, `/loop`, `/smoke_test`.
- **Skills + settings baseline + hooks** — tracked in `skills/`, `settings/`, `hooks/`.
- **Standard project structure** — described below. New projects MUST start from `docs/PROJECT_CLAUDE_TEMPLATE.md`.
- **Quality-gate contract** — constitutional checks, taxonomy enforcement, gate-fast semantics. Projects extend; they do not replace.
- **Lessons promotion path** — recurring `tasks/lessons/` entries (2-3 of the same shape) consolidate into rules in THIS file; per-project specifics get deleted.

**What projects MAY customize:** Domain logic, data model, agents, frontend components, deployment topology. Project-specific permissions and hook scripts (additive, must not shadow canonical). Project-internal taxonomies that legitimately use "Phase" (e.g., Keystone's lifecycle Lead → Pursuit → ...) — qualify with project name (`Keystone Phase`). Project-specific lessons until they promote.

**What projects MUST NOT customize:** Slash command names or core contracts. The workflow sequence. The language matrix. The killed-term taxonomy.

**Drift detection:** `scripts/check_spec_taxonomy.sh` (wired into every project's gate fast). `/review` (slash command + workflow contracts on staged changes). Cross-project audits via `/dev` or status surveys.

**Drift correction:** Fix lands in dev-platform FIRST. For deployed artifacts (commands, skills, settings, hooks, vscode) each project re-runs `scripts/install.sh` to pick up the change. Rule text in THIS file (dev workflow, taxonomy, language matrix) needs no install step — Claude Code auto-loads `CLAUDE.md` from every parent directory of a session's cwd, so a fix here is live for any session under `/home/rich/dev/` immediately.

## Response Style — GET TO THE POINT

**Verbosity is a bug.**

- Lead with the answer in the first sentence. No preamble, no recap, no "let me think about this".
- **No multi-tier feature audits unless explicitly asked.** Give 3–5 items max with one line each. No Tier 2 / Tier 3 / "can wait" / "my suggestion" sections.
- **Cut suggestion sections.** Drop "If you want my pick", "Bonus", "Nice-to-have", "Worth a test" trailing paragraphs.
- **End-of-step summaries: 1–2 sentences.** What changed, what's next workflow-wise. Nothing else.
- **NEVER include time estimates.** No "~3 days", "~2 hours", "ETA", "estimated effort". Not anywhere.
- When referencing code, include `file_path:line_number`.
- No emojis unless explicitly asked.

### Plain Language — No Jargon, No Cute BS

Write the way an experienced engineer talks in a PR review or a standup: plain, concrete, unadorned. This applies to chat replies AND to anything a human reads (PR bodies, reports, status updates).

- **Use real words and standard terms.** "a branch", "its own copy of the repo", "a lock so two don't run at once", "the test database". Not coined or capitalized labels for ordinary things.
- **Name the actual thing.** "the backend on 8402", "the Postgres on 5436", "two chats editing the same folder" — not "the shared persistence layer" or "concurrent session contention".
- **No invented vocabulary and no cute framing.** Drop "Goldilocks", "the honest truth is", playful section headers, and marketing adjectives ("powerful", "elegant", "seamless", "robust", "first-class").
- **Define a term only if the reader might not know it** — one short clause the first time, then use it plainly. Don't explain terms a working dev already knows.
- **Read it back before sending.** If a sentence sounds like a product page or a whitepaper, rewrite it the way you'd say it out loud to a teammate.

(Note: this targets prose and chat. The locked workflow taxonomy — Roadmap Phase, Spec, Change, etc. — stays; those are defined terms enforced by tooling, not cute coinings.)

## Honesty About What Ships

**CRITICAL — NEVER overstate what a project actually has.**

Applies to every artifact a human will read: marketing copy, exec one-pagers, feature lists, SVGs, README sections, PR descriptions, status updates. Before claiming a feature ships:

1. **Grep the codebase** for the named primitive — if it doesn't exist in code, it doesn't exist.
2. **Confirm a test enforces it** — a CT, smoke test, or compat test. No test means no claim.
3. **Label targets vs. proven** — "designed for X / proven at Y" is honest; "supports X" implies you ran it at X.
4. **Label optional/opt-in features** — if it requires a config flag or env var, say so.
5. **Roadmap items go on the roadmap** — never in a "Delivers" section.
6. **Discovered gaps go on the project's follow-on queue immediately** (`tasks/HARNESS_FOLLOW_ONS.md` for harness, equivalent per project).

If you catch yourself writing "supports", "delivers", "provides", "guarantees" — STOP and verify against the code first.

## Consumer Audit — New File Types in Glob-Managed Directories

When you add `<dir>/<newfile>.<newext>` in a glob-managed directory (`hooks/`, `tests/`, `commands/`, `skills/`, `scaffolding/`, `monitoring/`, `settings/`, etc.), audit:

1. **`.gitignore` allow-list** — verify the file is actually tracked, with a probe: `touch <dir>/probe.md && git status --porcelain <dir>/`. It must print the file. Do NOT rely on `git check-ignore -v` for this: it exits 0 when the last matching pattern is a NEGATION, so its status cannot distinguish "ignored" from "explicitly re-included". A new SUBDIRECTORY under a `**`-ignored tracked dir needs two rules — the directory re-include first, then the file pattern — because a file-pattern rule alone cannot unignore a file inside an ignored directory. This trap has fired three times: v1.18 (`shell/profile.d/`), v1.21 (`scripts/lib/*.py`), v1.23 (`tasks/lessons/`).
2. **install / deploy scripts** — does `scripts/install.sh` glob `<newext>`?
3. **verify / check scripts** — does `scripts/verify.sh` glob `<newext>`?
4. **Directory README** — mention `<newext>` in its contract.
5. **Test orchestrators** — `tests/<suite>/run.sh`, `scripts/gate_fast.sh`, or per-project equivalents.

## Derivation Sweep — Fix Every Script That Derives the Same Value

When you change how a value is **derived** from the environment — a git remote, a config path, a filename convention, an env var — grep for every other script that derives the same value and fix them together, or extract one shared helper and point them all at it.

The tell is two functions with the same name and nearly the same body in different files. Fixing only the one an issue names leaves the others broken, and the next consumer finds them the hard way.

This has cost three Roadmap Phases: **v1.12** (the Roadmap-version regex matched only one `ROADMAP.md` form, in two scripts), **v1.13** (`ROADMAP_PATH` needed adding to a third script the issue never mentioned, with the identical bug), **v1.21** (owner/repo derivation hardcoded `github.com` in three scripts). Every one was found by a consumer hitting it in production, never by the change that had just edited a sibling script. One `grep` before writing code finds all of them — that is the entire cost of the rule. Rationale and incident lineage: `docs/RULE_RATIONALE.md`.

## Commands a Worktree Session Runs Must Be Plain Single Commands

**A command that is BOTH compound and variable-bearing is refused by a worktree-isolated session's guard.** Either alone is fine. The guard analyses commands statically, and a refusal is silent in the worst way: the step just doesn't happen, and whatever it was meant to establish keeps its default value.

The boundary, established by probe rather than assumption (v1.27):

| Command | Verdict |
| ------- | ------- |
| `echo a && echo b` | allowed — compound, no variables |
| `test -f .claude/worktree-deps && echo A \|\| echo B` | allowed — compound, literal relative path |
| `echo "TMUX=${TMUX:-unset}"` | allowed — variable, single command |
| `[[ -n "${TMUX:-}" ]] && echo hi` | **refused** — compound + variable |
| `if [[ "$(git rev-parse --show-toplevel)" == *x* ]]` | **refused** — compound + substitution |
| `cat > f <<EOF` whose body contains `git ...` | **refused** — heredoc bodies are scanned |

So when writing a command block in `commands/*.md`: keep variables and substitutions out of compound commands. Where a step needs a derived value, prescribe a plain command, have the agent read the output, and type the literal into the next command — do not nest the derivation. Write `~/...`, never `"${HOME}/..."`. Prefer `gh ... --body-file` over `--body "$(cat <<EOF ...)"`.

Three instances, all one-liners that looked too small to check: **v1.26** (`link-deps.sh` invoked with `"${HOME}"` and `"$(pwd)"` — dependency linking silently never ran; fixed by making the script derive its own paths), **v1.27** (`/plan`'s `[[ -n "${TMUX:-}" ]] && tmux rename-window` — window rename silently never ran), and **v1.27** again (`/merge`'s `if [[ ... && ... ]]` worktree detection — refused, leaving `IN_WORKTREE=0`, which sends the merge down the branch-mode path `commands/merge.md` itself documents as failing the entire `gh pr merge`). The first fix was local to its own script and left every other command file unexamined, which is why the other two survived to be found by hand.

The sweep is one command — `grep -n '&&\|||\|\${\|\$(' commands/*.md` — then check each hit for the *combination*, since most hits are one or the other and fine. Run it whenever a guard refuses anything, and when adding a command block to a command file. Incident detail: `tasks/lessons/2026-09-03-worktree-guard-refuses-variable-paths.md`.

## Development Workflow

**CRITICAL — DO NOT ADVANCE STEPS WITHOUT EXPLICIT USER INVOCATION.**

Each step requires the user to invoke it. Completing one step does NOT mean start the next. Stop and wait. End-of-step "Ready for X" format is defined in `settings/claude-global.md`. **Two exceptions:** `/code` → `/review` does NOT stop — `/code` runs `/review` itself as its own final step, no separate invocation (see below); and `/merge` → post-merge does NOT stop — `/merge` runs post-merge itself, no separate invocation (see below). Every other step boundary in the chain still stops and waits — critically, the boundary immediately AFTER `/review` (before `/gate fast`) is unaffected by the first exception: `/code` and `/review` combine into one turn, but that combined turn still stops before `/gate fast` runs.

**Standard chain:**

```text
/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge
```

- **`/plan`** — Spec before code. Auto-creates the feature branch.
- **`/code`** — Implements Change by Change with auto-fix. Updates project docs (a new `tasks/shipped/` file where that convention exists — `planning.md` on legacy projects — plus ROADMAP.md, README.md, and a `tasks/lessons/` file) as its final step, **then runs `/review` itself in the same turn** — no separate invocation needed. Feature code + doc updates commit together.
- **`/review`** — Independent fresh-eyes pass on the staged (or unstaged, if nothing's staged) diff. Catches logic errors that still compile, edge cases, and security issues a green build won't surface. Auto-fixes SECURITY / BUG / COMPLIANCE / QUALITY; surfaces ARCHITECTURE for user decision. **Mandatory on every `/code` turn** — normally auto-run by `/code`, same turn (see the exception above); also invokable standalone for a fresh pass.
- **`/gate fast`** — Constitutional checks + unit tests + smoke_fast. Must PASS before commit. (dev-platform: `./scripts/gate_fast.sh`)
- **commit** — One atomic commit. Conventional format: `feat:`, `fix:`, etc.
- **push** — Push the feature branch.
- **`/pr`** — Opens PR against `main`. Auto-derives title, milestone, body.
- **CI** — Wait for `gate-fast` to go GREEN. If red, fix on the branch and re-push.
- **`/merge`** — Squash-merges after verifying CI green. Refuses on red/pending/conflicts. **Then runs post-merge itself, same turn, no separate invocation** — the standing exception to "STOP and wait," because post-merge has followed every merge in practice and the extra invocation was pure friction.
- **post-merge** (run automatically by `/merge`, not invoked separately) — Bespoke deferred steps from the spec. No-op if the spec named none. **One sub-step is standard, not bespoke: Roadmap-Phase completion.** When a merge ships the **last Change of a Roadmap Phase** — whether the phase goal was satisfied by shipped code OR closed by an explicit scope decision (e.g. a planned item dropped as over-engineering) — always: (1) mark the phase complete in `ROADMAP.md` and `planning.md` with today's date and status, (2) close its GitHub milestone (`gh api -X PATCH repos/:owner/:repo/milestones/<n> -f state=closed`, or `scripts/sync-milestones.sh --apply` where the project ships it — it reads the now-`complete` ROADMAP entry and closes the milestone), and (3) **cut the release tag** at the squash-merge commit that completed the phase, named exactly as the phase version (`gh release create v<X.Y> --target <merge-sha>`, or `git tag v<X.Y> <merge-sha> && git push origin v<X.Y>`). The tag is what consumers pin; skipping it leaves the phase unpinnable, which is how tagging silently stopped at v1.13 and left twelve phases unreachable — freezing every consumer at `@v1.12` or `@v1.13`, the newest tags that existed, with nothing newer for Dependabot to bump them to. Verify afterward with `scripts/check-phase-milestones.sh` (flags a milestone left `open` with 0 open issues) and `scripts/check-phase-tags.sh` (flags a complete phase with no tag). A mid-phase merge that does NOT complete the phase skips this sub-step. A bespoke post-merge action well outside this normal shape (prod deploy, credential rotation, shared-infra changes) still gets a heads-up and a pause before running, per the general rule on hard-to-reverse actions. A second standard (non-bespoke) sub-step, unconditional on phase completion: **Change Summary.** Every `/merge` invocation ends its report with a short **Problem/Opportunity → What shipped** summary — chat-report only, no new file, no CHANGELOG, no GitHub Release/PR comment. Derived from context already available at merge time, in order: (1) the `tasks/shipped/` file this merge added (`git diff HEAD~1 --name-only -- tasks/shipped/` on the just-synced `main` — the narrative `/code` already wrote pre-commit; legacy projects without the directory: the lines the merge added to `planning.md`'s "Recently shipped" section); (2) if neither was touched, the merged spec's Problem/Design-Philosophy framing + Change titles; (3) if no spec was touched at all, the PR title/body via `gh pr view`. This step runs even when the merge is a chore with no spec and no phase completion — it is the ONE thing post-merge always does.

**Optional steps:**

- **`/security-review`** — For changes touching auth, credentials, external input, or new endpoints: between `/review` and `/gate fast`.
- **`/test`** — Standalone spec validation. Not required when `/code` verifies as it goes.
- **`/docs`** — Standalone doc update. Recovery only — `/code` handles it normally.

**NEVER commit before `/gate fast` passes. NEVER merge before CI green.**

**Quick fixes:** fix → `/review` → `/gate fast` → commit → push → `/pr` → CI → `/merge`.

**Trivial edits (zero behavior change):** A single-line or few-line addition to a registry, table, or doc — no effect on code behavior, not read programmatically by any script or test (e.g., a new Port Allocation Registry row, a typo fix, a broken link) — skips the chain: `./scripts/gate_fast.sh` (or the project's equivalent), then commit straight to `main`. No branch, no `/plan`, no `/review`, no PR, no CI wait. NOT trivial — use Quick fixes instead — if the edit: touches `commands/`, `skills/`, `hooks/`, `scripts/`, or any file a script/test parses; changes a rule that alters behavior (workflow chain, taxonomy, gate contract); or spans more than ~5 lines. When in doubt, treat it as a quick fix, not a trivial edit.

**Plan mode default:** Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions). If something goes sideways, STOP and re-plan.

**Verification before done:** Never mark a task complete without proving it works. Ask: "Would a staff engineer approve this?" Run tests, check logs, demonstrate correctness.

**Per-Spec-Phase branching decision rule:** Default to one feature branch + one PR per Spec Phase (2–5 Changes), each assigned to the matching GitHub Milestone. Deviate to a single branch for the whole spec when either: (a) a Spec Phase is small (fits in ~150–200 LOC diff) — splitting would make per-PR ceremony exceed per-PR content, or (b) the Phases are NOT independently shippable/testable (e.g. one Phase creates a resource, the next tears it down — shipping the first alone leaves an untested half-feature). Call out the chosen strategy explicitly in the spec's Design Philosophy or Implementation Order section so `/code` knows whether to create one branch or many. Promoted from three recurring dev-platform lessons (v0.5 adoption, v0.6 small-Phase deviation, v1.4 tightly-coupled-Phase deviation).

## Development Terminology

| Level | Term | Definition |
| ----- | ---- | ---------- |
| 1 | **Roadmap Phase** | Major product milestone. Header format: `v<MAJOR>.<MINOR>: <Title>`. Tracked in `ROADMAP.md`. Matches a GitHub Milestone. |
| 2 | **Spec** | Demoable milestone within a Roadmap Phase; output of `/plan`. File: `tasks/{descriptive-name}-spec.md`. |
| 3 | **Spec Phase** | Group of related Changes inside one Spec. Header: `## Phase N: <title>`. |
| 4 | **Change** | Atomic implementation step. Header: `### Change N: <title>`. Numbered CONTINUOUSLY across the whole Spec. |
| 5 | **Commit** | Git record — feature code + doc updates bundled atomically. |

**Rules:**

- Roadmap Phase → Spec → Spec Phase → Change → Commit. Always. Every project.
- `/plan` produces a Spec. `/code` implements one or more Changes.
- Roadmap Phase headers MUST use `v<MAJOR>.<MINOR>: <Title>` (e.g., `v0.5: Monitoring`). Each Roadmap Phase has a matching GitHub Milestone. Bare `Phase N`, `Sprint X`, `R<N>`, or quarter buckets at the roadmap level are violations — the `v` prefix is what distinguishes a Roadmap Phase from a Spec Phase.
- Section headers inside a spec use `## Phase N:`; atomic steps use `### Change N:` with N continuous across the whole spec.
- Spec files named descriptively: `tasks/foundation-spec.md` — not `stage-a-spec.md`.

**Killed terms (never use as workflow-level labels):** Stage, Sprint, Iteration, Revision, Milestone, Group, Epic, Step, Item, Task.

**Disambiguation:** "Phase" alone means *Spec Phase*. "Roadmap Phase" is qualified. Project-specific business hierarchies (e.g., Keystone's lifecycle) qualify with project name: "Keystone Phase".

**Enforcement:** `/home/rich/dev/scripts/check_spec_taxonomy.sh` scans `tasks/*-spec.md` and exits 1 on killed-term headers. Wired into every project's gate-fast.

## Which Identifier To Cite

Three identifiers reference shipped work, and **all three can carry the same string `v1.25` while meaning different things** — which is exactly why this rule exists.

| Identifier | What it is | Cite it when |
| ---------- | ---------- | ------------ |
| **Roadmap Phase version** — `v1.25` | The unit of planned work, claimed atomically at `/plan`, matching a GitHub Milestone | **Always, by default.** This is the canonical reference in prose, reports, commit bodies, and anything a human reads. |
| **PR number** — `#92` | A GitHub artifact, numbered sequentially and sharing a number space with issues | **Provenance only**, in parentheses after the phase, when the exact commit matters. Never as the primary reference: `#325` alone does not even say whether it is a PR or an issue. |
| **Release tag** — `v1.25` | A git tag at the merge commit closing a Roadmap Phase — the only identifier a consumer can pin (`taxonomy-check.yml@v1.25`) | Only when discussing what a consumer depends on. The phase is the *work*; the tag is the *artifact*. |

Cutting the tag is a mechanical post-merge sub-step, not a thing to remember — see the post-merge bullet below. It previously lived only in `docs/GLOSSARY.md`, a reference doc nobody executes from, and consequently stopped after v1.13 — which pinned every consumer to `@v1.13` or older, because a tag that does not exist cannot be pinned or Dependabot-bumped. `scripts/check-phase-tags.sh` is the backstop.

## Workflow Principles

- **Autonomous bug fixing** — given a bug report, just fix it. Don't ask for hand-holding.
- **Subagent strategy** — offload research, exploration, parallel analysis. One task per subagent.
- **Simplicity first** — minimal code, no over-engineering, no features beyond what was asked.
- **No laziness** — find root causes, no temporary fixes. Senior developer standards.
- **Use official SDKs — NEVER hand-roll protocol implementations.** `a2a-sdk`, `mcp`/`fastmcp`, `claude-agent-sdk`. Search PyPI/npm/Go modules before writing protocol code.
- **NEVER write code in another project's directory from the current session.** If work in Project A requires a change in Project B, STOP — communicate the need (handoff note, GitHub issue, user instruction to switch sessions) and let Project B's own session make the change under its own gate and review discipline. Cross-project writes bypass the target project's gate, leave no commit context, and are invisible to that project's team. The only exceptions are the narrow opt-in carve-outs in this file (`fleet-install-template.sh`, `migrate-workflow-chain.sh`) — those are tools the user runs explicitly, not license for general cross-project editing.
- **Dependency asks go upstream as GitHub issues.** When a consumer project (PA, Keystone, ATLAS) needs a change in a dependency it doesn't own (e.g. the Kermit Harness), STOP per the rule above and **file the ask as a GitHub issue on the upstream repo** (`gh issue create --repo <owner>/<repo>`, title prefixed `[<Consumer>]`, with a consumer label) — creating an issue is the sanctioned cross-repo comm (it does NOT write to the upstream repo's files) and is the **single source of truth** for whether an ask is open. The consumer's in-repo communique file and handoff/queue entry are **local, agent-readable receipts and tracking — not the transport**, and should link the issue URL. Relaying communique files into a dependency's in-repo inbox is **deprecated as a transport**: it's lossy — an ask filed locally but never hand-relayed never reaches the upstream team (PA's 2026-06-28 OllamaAdapter ask sat unrelayed while the harness reported "no open PA asks"). The **outbound** direction (dependency → consumers, announcing versions) uses **GitHub Releases + release notes**, with consumers watching the repo or running Dependabot/Renovate (template: `extensions/github-actions/dependabot-consumer-template.yml`) — not broadcast docs relayed into a consumer inbox. `scripts/check-comms-delivery.sh` checks that every post-2026-06-28 ask-communique links a live upstream issue. Full protocol + rationale: [`docs/CROSS-REPO-COMMS.md`](docs/CROSS-REPO-COMMS.md).

## Verification Requirements

Run these checks and fix any issues before marking work complete:

- Tests pass after code changes.
- Build/typecheck clean before commit.
- API changes: test endpoints with curl or dev server.
- UI changes: start dev server, verify visually in browser.
- CRUD: delete path cleans up ALL storage layers (DB, FS, cache, search index, in-memory, message refs).
- New endpoints: reachable end-to-end (UI → service → proxy → backend → storage).
- Delete operations: verify the resource is actually gone (query DB, check FS, check indexes — not just "endpoint returned 200").
- Batch processing: verify the TARGET store has data, not just the status field.
- Multi-step pipelines: don't mark step N complete until step N+1's target confirms receipt.

## Verify Against Source of Truth, Not Derived State

Before claiming a fix works, the verification command must directly touch the system being changed. Never trust an intermediate signal — a memo, a queue row, a chained-command exit code, "the read is gone so the function should compile." Run the live tool. Curl the running backend. Re-grep the actual file. Query the actual database row.

**Forcing function:** the verification command must touch the actual system. No echo chains hiding the real exit code. No "it should work because X." If you cannot run the live test, mark the check **UNTESTED** in the QC report — never PASS.

(Detailed incident examples: `docs/RULE_RATIONALE.md`.)

## Language Architecture Decision Matrix

**Every new component MUST be evaluated against this matrix.**

| Layer | Language | When to Use |
| ----- | -------- | ----------- |
| **Network-intensive** | **Go** | High concurrency, many connections, request routing, real-time |
| **Compute-intensive** | **Rust** | CPU-bound processing, data transformation, performance-critical |
| **AI-intensive** | **Python** | LLM integration, ML workflows, rapid prototyping |
| **UI/Frontend** | **TypeScript** | User interfaces, browser applications |

**Decision rules:** Network → Go. Compute → Rust. AI → Python. Mixed → split: Go/Rust for I/O and transport, Python for intelligence. When in doubt → Python first, rewrite hot path when performance data justifies it.

**Anti-patterns:** Python handling 1000+ concurrent connections (should be Go). Python doing CPU-bound work in a tight loop (should be Rust). Go/Rust calling LLM APIs directly (should delegate to Python). Monolithic services mixing network routing with AI logic (should be split).

## Code Quality

- Many small files over few large files (200-400 lines typical, 800 max).
- No console.log in production code.
- Proper error handling with try/catch.
- Input validation for all user inputs.
- No over-engineering — don't add features beyond what was asked.

## Public API Contracts

**Apply to any project shipping a library/service consumed by external code.**

- **Kwarg propagation** — Every kwarg declared on a public helper MUST observably affect the wrapped call. A kwarg with no downstream reference is dead — REMOVE it. Test contracts MUST assert propagation, not just shape. Mechanical check: AST-scan public functions for unreferenced kwargs.
- **Boundary changes require both-sides sweep** — Any rename, signature change (including additive kwargs), return-type change, call-path change, or async/sync flip at a public boundary requires sweeping ALL consuming sites in BOTH `src/` AND `tests/` in the same `/code` session. `src/`-only is necessary but NOT sufficient. After any ABC signature change: `grep -rn "def method_name" tests/`.
- **Consumer-side schema/infra dependencies** — Public method changes MUST declare what the consumer's environment needs (DB columns, config keys, env vars, container services), MUST provide a migration path (auto-runner, opt-in flag, manual setup), and MUST have a cold-start integration test against a from-scratch consumer environment. `/plan` refuses specs without schema deps + migration path; `/code` refuses without them; `/review` flags PRs touching public methods without the cold-start test.

→ Full examples and incident lineage: `docs/RULE_RATIONALE.md`.

## Gate Tiers

Asymmetric coverage by design:

- **`/gate fast`** — constitutional + unit + smoke-fast. Surgical, ~5s–3 min. Every commit.
- **`/gate full`** — adds load-tier smokes for changes touching threads, async interop, ContextVar state, shared-client adapters, or backend integration. After structural change.
- **`/gate release`** — full load-tier coverage. Before any minor/major version bump.

Why asymmetric: adding load-tier to fast-tier kills inner-loop velocity (~5s → ~10 min). But "concurrency-shaped state that only opens its window at scale" recurs often enough that load-tier coverage MUST run before release. Project-specific gate-tier detail in `docs/RULE_RATIONALE.md`.

`/gate fast` additionally skips its expensive code-verifying checks (test suites, lint, build) when the diff vs. the default branch touches only root markdown / `docs/*` / `tasks/*` files — structural/taxonomy checks always still run, and `commands/*.md`/`skills/**/*.md` deliberately do NOT count as docs here (`tests/commands/frontmatter.sh` validates them live). Reusable detector + adoption guide: `scripts/lib/docs_only_diff.sh` + `docs/RULE_RATIONALE.md` → "Gate-Fast Docs-Only Diff Skip".

## Planning Requirements

Before writing ANY new code: search the codebase for existing implementations (Grep/Glob), check if similar functionality exists, identify reusable components, follow existing patterns. Reuse first.

## Git Workflow

- Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`.
- Small, focused commits.
- Run tests before committing.

## Data Lifecycle & Wiring Rules

1. **CRUD Completeness** — Build delete in the same session as create. Delete cleans up ALL storage layers (DB, FS, cache, indexes, in-memory, message refs). Define cascade behavior for parent-child relationships (cascade delete, orphan intentionally, or block with error).
2. **One Operation, One Code Path** — Never two functions that partially do the same thing. One canonical cleanup function per data type, called by all endpoints that delete it.
3. **Horizontal Wiring** — Every new endpoint traceable UI → service → proxy → backend → storage → response → UI. Missing links = not done.
4. **Delete Verification** — Query DB, check FS, check indexes, check caches, confirm endpoint returns 404.
5. **No Phantom Features** — If a feature cannot be triggered from the UI end-to-end, it does not exist.
6. **Status/Enum Consistency** — Every status field has a defined set of valid values; code only uses those values. Add new values to the model definition FIRST.

## neurX Server Environment

Headless Ubuntu server at `192.168.1.101`. NO monitor, NO keyboard. All development remote.

**Power schedule:** Runs 24/7. The nightly 9pm shutdown / 4am RTC wake was removed on 2026-07-25 — it was the root cause of five backup bugs, all jobs racing a fixed power-off deadline. Do NOT assume the box is powered off when services are unreachable; diagnose the service. The shutdown/wake scripts remain in `~/neurX_sysops/scripts/power-management/` for manual use (maintenance, travel), and that directory's README is the source of truth for re-enabling. After any reboot, containers with `restart: unless-stopped` come back automatically; manually-stopped ones don't — start with `docker compose up -d`. tmux sessions do NOT survive a reboot (`cc` protects against the VS Code server exiting, not the machine restarting).

| Context | Use | Example |
| ------- | --- | ------- |
| Service binding | `0.0.0.0` | `uvicorn --host 0.0.0.0` |
| Service-to-service | `127.0.0.1` | `http://127.0.0.1:8001/api/endpoint` |
| Browser / client | `192.168.1.101` | `NEXT_PUBLIC_API_URL=http://192.168.1.101:8001` |

**WRONG:** `localhost` as default or fallback in any service. Headless server — `localhost` is unreachable from remote clients.

## Port Allocation Registry

Each project gets its own port series. Check before assigning.

| Series | Project | Ports |
| ------ | ------- | ----- |
| 3000 | Kermit frontend | 3000 |
| 4000s | SQRL | 4001 (backend), 4002 (frontend) |
| 5000s | Portal | 5000 (frontend), 5100 (backend) |
| 8000s | Kermit backend | 8001-8020 (PA backend, agents, MCPs) |
| 8021 | Kermit Harness trigger webhook | Default for `KermitConfig.trigger_webhook_port`; consumers override per their port series. |
| 8090 | Keystone Dashboard | 8090 |
| 8100s | Keystone Platform | 8100-8190 |
| 8200s | NVR Dashboard | 8200 (backend), 8210 (frontend), 8889 (WebRTC) |
| 8300 | TIS Standalone App (ATLAS Mode 2) | 8300 |
| 8400 | kanban | 8400 (Next.js app — frontend + API routes, own Postgres) |
| 6000s | OPIE | 6001 (frontend), 6002 (backend) |
| 7000s | kermit-v3 | 7000 (backend), 7001 (frontend), 7002 (trigger webhook), 7003 (PTY WS), 7010 (storage) |
| 9000 | SQRL splash | 9000 |
| 15400s | Kermit Harness test infra | 15401 (chromadb), 15418 (mongodb), 15424 (nats), 15432 (milvus gRPC), 15436 (postgres), 15480 (redis), 15493 (milvus health) |

**Next available series:** 8500s

## Production Deployment Pattern

- **Dev:** `/home/rich/dev/projects/X/`
- **Prod:** `/home/rich/prod/X/` (Docker + Traefik)

Traefik reverse proxy on 80/443 (`/home/rich/prod/traefik-global/`). Let's Encrypt via HTTP challenge (`letsencrypt` certresolver). Cloudflare DNS → Keystone public IP. Services join `traefik-global` network for external routing; databases on internal networks (never exposed). Portal ForwardAuth middleware (`kermit-auth@file`) for protected apps.

## Standard Project Structure

```text
project-name/
├── CLAUDE.md              ← Project-specific rules (see template)
├── .markdownlint.json     ← {"default": false}
├── .gitignore
├── .env.example
├── README.md
├── backend/
├── frontend/
├── config/
├── docs/
├── scripts/
├── tasks/                 ← Specs, lessons.md
├── tests/
├── logs/                  ← gitignored
├── docker-compose.yml
├── Dockerfile.backend
└── Dockerfile.frontend
```

## Project CLAUDE.md Standard

Every project CLAUDE.md follows `docs/PROJECT_CLAUDE_TEMPLATE.md`.

- **Max 200 lines.** API docs, UI design, troubleshooting → `docs/`.
- Required sections: description, architecture, tech stack, build & run, configuration, ports, file structure, rules, patterns.
- No duplicating rules from THIS file — project files ADD, don't repeat.

## Repo Structure

| Directory | Purpose |
| --------- | ------- |
| `commands/` | Slash command definitions |
| `skills/` | User skills + `WORKFLOW_MANUAL.md` |
| `settings/` | Global Claude Code config |
| `hooks/` | Hook scripts |
| `extensions/` | IDE config (`vscode/server-extensions.json` is the tracked extension list; `scripts/install.sh vscode` reinstalls them all; `scripts/sync-vscode.sh` is the capture/deploy/diff helper) |
| `scaffolding/` | New-project templates |
| `monitoring/` | Workflow telemetry |
| `shell/` | Shell helpers, git-hook templates, worktree-isolation tooling (`shell/worktree/`; dev-platform is worktree-mode as of v1.25, and new projects scaffold with the marker — existing projects opt in per project), sourced shell functions (`shell/profile.d/` — `cc`) |
| `scripts/` | Install / uninstall / verify; `gate_fast.sh` orchestrator; spec-taxonomy checker |
| `tests/` | Constitutional gate-fast fixtures + per-suite runners |
| `tasks/` | Spec files |
| `docs/` | Architecture and how-to docs (incl. `RULE_RATIONALE.md`) |

## Install / Deploy

Repo is source of truth; `~/.claude/` is a *deployment* that always tracks the **main checkout** — `install.sh` and `verify.sh` resolve there via `git-common-dir` regardless of which worktree runs them (v1.25), so symlinks never dangle after `/merge` removes a worktree; the trade-off is that worktree edits to `commands/`/`skills/` go live only after merge. `scripts/install.sh [category]` symlinks tracked files (`commands`, `skills`, `settings`, `hooks`, `vscode`, `managed`, `git-hooks`, `worktree`, `shell`, or `all`). The `vscode` category runs `code --install-extension` for every entry in `extensions/vscode/server-extensions.json` (skips gracefully when the `code` CLI is absent, and when it is present but cannot reach a VSCode server — a shell that outlives a VSCode reconnect holds a stale `$VSCODE_IPC_HOOK_CLI`, which used to fail the whole install; see [issue #84](https://github.com/teelr/dev-platform/issues/84)). `scripts/uninstall.sh` removes symlinks (leaves `~/.claude/projects/` untouched). `scripts/verify.sh` reports drift. Edit in this repo and re-run install — never edit `~/.claude/` directly.

## Adding a New Workflow Artifact

For a new slash command / skill / hook / setting: (1) write the file in the correct directory per its README contract, (2) extend `scripts/install.sh` only if adding a new top-level category (existing-category files are auto-globbed), (3) update `scripts/verify.sh` for the same case, (4) smoke-test.

## Patterns

- **Single cleanup path** — One canonical cleanup function per data type, called by all endpoints that delete it.
- **Cascade verification** — Parent delete handles all children explicitly.
- **Horizontal tracing** — Every endpoint traced through all layers before marking complete.
- **Create and delete together** — Same work session.
- **Dev workflow** — `/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge` for features. Quick fixes: `/review → /gate fast` → commit → push → `/pr` → CI → `/merge`. `/review` is mandatory on every change. Trivial edits (zero behavior change, ≤5 lines, no script/test reads the file): `/gate fast` → commit straight to `main` — no branch, no review, no PR.
