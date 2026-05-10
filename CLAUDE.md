# Rich's Development Standards

All development standards for projects in `/home/rich/dev/projects/`. This is the single source of truth.

## Scope — dev-platform Is For The Environment, Not The Projects

**CRITICAL — This repo (`teelr/dev-platform`, at `/home/rich/dev/`) exists to care for, maintain, and enhance the development *environments* that drive Rich's projects. It is NOT a workplace for the projects themselves.**

**Primary gateway — VSCode + Claude Code:** This repo is the *single entry point* for setting up and modifying Rich's VSCode + Claude Code development environment. Every change to global Claude Code config (slash commands, skills, settings, hooks, keybindings) and every change to global VSCode/IDE config (user profile, statusline, keybindings) goes through this repo first — written here, then deployed via `scripts/install.sh`. **Direct edits to deployed locations (`~/.claude/`, `~/.vscode/`, etc.) are forbidden** — they get overwritten on the next install and split the source of truth in two.

**Belongs here:**

- Rules (`CLAUDE.md` for workspace dev standards, `settings/claude-global.md` for global Claude behavior), slash commands (`commands/`), skills (`skills/`), hooks (`hooks/`), settings (`settings/`)
- Install / uninstall / verify scripts (`scripts/`), IDE config (`extensions/`), scaffolding templates (`scaffolding/`), workflow telemetry (`monitoring/`), shell helpers (`shell/`)
- Specs and docs about any of the above (`tasks/`, `docs/`, `ROADMAP.md`, `planning.md`, `README.md`)

**Does NOT belong here:**

- Project source code, schemas, frontend, tests, deployment configs, or per-project roadmaps under `projects/<name>/` — those are tracked in their own repos and addressed in their own sessions
- Bug fixes, feature work, or refactors against any project — even when the bug seems "small" or "right here"

**Behavioral rule for the assistant:** when invoked in `/home/rich/dev/`, assume every request is environment work. If a request would require modifying a file under `projects/`, **STOP and ask the user to switch to that project's working directory** — never silently reach into `projects/` from this session. Read-only operations across projects (e.g., `/dev` orientation, end-of-day status surveys, cross-project assessments) ARE allowed — but no edits, commits, or fixes to project code from here.

**Exception — scaffolding:** `scripts/new-project.sh` IS allowed to create the initial tree under `projects/<new-name>/` from a dev-platform session. Scaffolding is a SETUP action via dev-platform tools (templates in `scaffolding/`, the orchestrator in `scripts/`), distinct from project work. Once the project exists, the normal Scope rule resumes — future edits to that project happen in its own session. Bootstrap-only; not a back door for general project work. The conversational Q&A pattern the assistant follows before invoking the script is documented in `docs/NEW-PROJECT.md`.

**Why this rule exists:** before R1 Foundation, the prior "dev-standards" repo had blurred the line — global rules and project-side fixes both landed in the same git history, making it hard to distinguish "what governs every project" from "what was happening in project X that day." R1 Foundation expanded this repo to own the full dev-experience surface; this rule pins the corollary — the surface, not the things on top of it. A clean dev-platform history is a precondition for the monitoring (R2), testing (R3), and migration (R5) specs that all assume "this repo describes the environment, period."

## Consistency Across All Projects — Non-Negotiable

**CRITICAL — dev-platform is the canonical source of truth for the dev workflow, language standards, and every shared element of the development environment. Every project under `/home/rich/dev/projects/` MUST conform to these standards without exception. Absolute consistency across all projects is a hard requirement, not an aspiration.**

**What dev-platform owns (no project may diverge):**

- **Dev workflow** — `/plan → /code → /test → /review → /gate fast → /docs → commit → push`. The sequence, each step's semantics, the discipline (no auto-advance, no commits before `/gate fast`, no commits before `/docs`, no skipping `/test`)
- **Workflow taxonomy** — Roadmap Phase → Spec → Spec Phase → Change → Commit. Killed terms (Stage, Sprint, Iteration, Revision, Milestone, Group, Epic, Step, Item, Task) never used as workflow-level labels
- **Language Architecture Decision Matrix** — network-intensive → Go, compute-intensive → Rust, AI-intensive → Python, frontend → TypeScript. Anti-patterns from the matrix are violations, not preferences
- **Slash commands** — `/plan`, `/code`, `/test`, `/review`, `/gate`, `/docs`, `/dev`, `/loop`, `/smoke_test`. Tracked in `commands/`, deployed via `scripts/install.sh`
- **Skills + settings baseline + hooks** — tracked in `skills/`, `settings/`, `hooks/`
- **Standard project structure** — described in `Standard Project Structure`. New projects MUST start from `docs/PROJECT_CLAUDE_TEMPLATE.md`
- **Quality-gate contract** — constitutional checks, taxonomy enforcement, gate-fast semantics. Projects extend; they do not replace
- **Lessons promotion path** — recurring `tasks/lessons.md` entries (2-3 of the same shape) consolidate into rules in THIS file, then the per-project specifics get deleted

**What projects MAY customize:**

- Domain logic, data model, agents, frontend components, deployment topology
- Project-specific permissions and hook scripts (additive — must not shadow canonical commands or settings)
- Project-internal taxonomies that legitimately use the word "Phase" (e.g., Keystone's lifecycle Lead → Pursuit → ... → Close Out). These MUST qualify with the project name (`Keystone Phase`); bare `Phase` in any dev context always means Spec Phase
- Project-specific lessons in their own `tasks/lessons.md` until they promote upward

**What projects MUST NOT customize:**

- Slash command names or core contracts. `/plan` always produces a Spec. `/code` always implements one or more Changes. `/test` always validates against the spec. `/gate fast` always blocks commit on failure. No project re-defines these
- The workflow sequence. No project invents a new step or skips an existing one
- The language matrix. A 1,000-connection handler is Go; a tight CPU loop is Rust; LLM logic is Python — "it was easier in X" is not a justification
- The killed-term taxonomy. Don't use `Sprint`, `Stage`, `Step` as a workflow-level label even if it feels natural

**Drift detection:**

- `scripts/check_spec_taxonomy.sh` — wired into every project's `gate fast` (or equivalent pre-commit hook) to block taxonomy drift mechanically
- `/review` — verifies slash command and workflow contracts on staged changes
- Cross-project audits (manual today via `/dev` or status surveys; R2 Monitoring will automate drift counts, gate-pass rates, and lesson-promotion candidates)

**Drift correction:**

- The fix lands in dev-platform FIRST (the rule, the script, the command, the gate check)
- Each project re-runs `scripts/install.sh` from this repo to pick up the change
- Project-side conformance is each project's responsibility; dev-platform-side correctness is THIS repo's responsibility. Drift in either direction is a bug

**Why this rule exists:** consistency compounds. Same workflow → a lesson learned in one project applies to all. Same taxonomy → specs are mutually readable. Same language matrix → no team-member surprise about what they find. Inconsistency creates per-project tribal knowledge — the slowest, most fragile mode of operation. The pre-R1 world tolerated drift because there was no enforcement layer; R1 Foundation built it; this rule commits to using it. The R2/R3/R4/R5 specs all assume this baseline.

## Response Style — GET TO THE POINT

**Verbosity is a bug. Dev-project responses must be tight.**

- Lead with the answer in the first sentence. No preamble, no recap, no "let me think about this" framing.
- **No multi-tier feature audits unless explicitly asked.** When the user asks "what's next" or "what should I test", give 3–5 items max with one line each. Do NOT volunteer Tier 2 / Tier 3 / "can wait" / "my suggestion" sections. The user can ask for more.
- **Cut suggestion sections.** Drop "If you want my pick", "Bonus", "Nice-to-have", "Worth a test" trailing paragraphs. The user invokes follow-ups; don't pre-stage them.
- **End-of-step summaries: 1–2 sentences.** What changed, what's next workflow-wise. Nothing else.
- **NEVER include time estimates.** No "~3 days", "~2 hours", "ETA", "estimated effort". Not in plans, specs, FOLLOW_ONS rows, conversation, status updates, summaries, or PR descriptions. The work takes as long as it takes.
- When referencing code, include `file_path:line_number`.
- No emojis unless explicitly asked.

**Failure mode this rule fights:** padding answers with extensive context, multiple option-trees, and self-prioritized tier lists when the user asked one question. If the user wanted three tiers they would have asked for tiers.

## Honesty About What Ships

**CRITICAL — NEVER EVER overstate what a project actually has.**

This applies to every artifact a human will read: marketing copy, exec
one-pagers, feature lists, SVGs, README sections, slide decks, demo scripts,
PR descriptions, status updates, anything that describes capability. Before
claiming a feature is "shipping" or "consumer-ready":

1. **Grep the codebase** for the named primitive — if it doesn't exist in code,
   it doesn't exist.
2. **Confirm a test enforces it** — a CT, smoke test, or compat test. No test
   means no claim.
3. **Label targets vs. proven** — "designed for X / proven at Y" is honest;
   "supports X" implies you ran it at X.
4. **Label optional/opt-in features** — if it requires a config flag or env
   var, say so.
5. **Roadmap items go on the roadmap** — never in a "Delivers" section.
6. **Discovered gaps go on the project's follow-on queue immediately**
   (`tasks/HARNESS_FOLLOW_ONS.md` for harness, equivalent file per project).

Reason: consumers and stakeholders build expectations on what we say. The
v2.20 Kermit Harness exec-SVG audit caught three overstated claims ("auto
model downgrade", "tamper-evident audit", "crash recovery") that didn't match
the code. Overstating once costs trust permanently — and once a customer or
boss pins their plan to a feature that doesn't exist, you have to either ship
it under pressure or admit you misled them. Both are bad. The audit habit is
cheap; recovery isn't.

If you catch yourself writing "supports", "delivers", "provides", "guarantees",
or any flavor of certainty about a feature — STOP and verify against the code
before the artifact ships.

## Public-Helper Kwarg Propagation

**CRITICAL — Every kwarg declared on a public helper function MUST
observably affect the wrapped call.**

This rule applies to every public function in any project's
public-API surface (anything a consumer can import — `kermit.api.*`,
`kermit.agent.*`, `kermit.rag.*`, `kermit_pa.services.*`, ATLAS
public modules, etc.). Helper functions wrap call sites; the kwargs
on the wrapper exist to give consumers control over the wrapped
call's behavior. A kwarg that doesn't reach the wrapped call is a
silent trap — consumers trust the signature, the kwarg does
nothing, and the bug surfaces only when someone inspects production
behavior.

Two instances of this bug class in 24 hours (v2.25.0
`kermit.agent.classify(max_tokens=2000)` accepted but never
threaded; v2.27.0 `runtime.documents.extract(mime=...)` used for
audio routing only, silently dropped on the non-audio result side)
made this rule mandatory rather than aspirational. Promoted from
the harness's L29 lesson on 2026-05-04 after the second recurrence.

**Three sub-rules:**

1. **Every public-helper kwarg MUST observably affect the wrapped
   call.** Either it's threaded as a kwarg to the underlying call,
   used to construct the call's payload, used to gate behavior
   before/after the call, or assigned to a captured field that
   downstream code reads. If a kwarg has no observable downstream
   effect, it is dead — REMOVE it before ship. Don't keep
   "future-compatible" kwargs that do nothing today; that's the
   exact pattern this rule prohibits.

2. **Pytest contracts MUST assert kwarg propagation, not just
   shape.** A test that `helper(..., kwarg=X)` returns the right
   shape does NOT prove `kwarg=X` was honored. The test MUST
   inspect the mock call's args/kwargs OR the constructed
   intermediate object (AgentDefinition, request payload,
   handler-side `result.mime`, etc.) to verify the value reaches
   the wrapped call.

3. **Mechanical enforcement: CT88 in the harness.** Static AST
   check at `tools/check_dead_kwargs.py` scans every public
   function in `src/kermit/api/`, `src/kermit/agent/`, and
   `src/kermit/rag/`. For each declared kwarg, it counts
   `ast.Name(id=kwarg)` references in the function body. Zero
   references → CT88 FAIL. Other projects (PA, ATLAS, Keystone)
   should add equivalent checks scanning their own public
   surfaces.

**Concrete examples:**

```python
# WRONG — max_tokens dead. The wrapped runtime.run_one_shot()
# call doesn't accept max_tokens, and AgentDefinition has no
# max_tokens field. The kwarg is a silent trap.
async def classify(runtime, ctx, *, prompt, max_tokens=2000):
    agent_def = AgentDefinition(temperature=0.0)  # max_tokens NOT here
    return await runtime.run_one_shot(ctx, agent_def, message)
    # max_tokens never referenced again — DEAD.

# RIGHT — option A: thread through to the wrapped call.
async def classify(runtime, ctx, *, prompt, max_tokens=2000):
    agent_def = AgentDefinition(
        temperature=0.0,
        max_tokens=max_tokens,  # observable effect
    )
    return await runtime.run_one_shot(ctx, agent_def, message)

# RIGHT — option B: drop the kwarg if no thread-through is
# possible today. Document where the cap actually comes from.
async def classify(runtime, ctx, *, prompt):
    """...max_tokens is governed by KermitConfig, not per-call."""
    ...
```

**/review explicitly checks this pattern.** For every new public
helper, /review reads the function body and verifies each
documented kwarg has at least one downstream reference. CT88
makes the check mechanical at gate time — /review is the
human-readable audit, CT88 is the gate.

**Sister-pattern: documentation MUST match the impl signature.**
The v2.25.0 `model_catalog={...}` migration-guide bug (doc said
dict, impl took callable) and v2.27.0 `mime=` doc-vs-impl
mismatch are the same shape applied to docstrings/migration-
guide examples. /review reads docs against the impl signature,
flags type mismatches as same-class violations.

**Reference:** harness `tasks/lessons.md` L31 (lazy-construction
accessors MUST be reset on lifecycle teardown) — the v2.27.0
release surfaced this rule's recurrence + a fresh
accessor-cleanup bug in the same /review pass; both fixed
before commit.

## Consumer-Side Schema / Infrastructure Dependencies

**CRITICAL — When adding or modifying a public method, declare what the consumer's
environment needs. Don't ship a fix and find out from a prod incident.**

This applies to any project where a library / service / API is consumed by
external code (Kermit Harness consumed by PA / Keystone / ATLAS; any internal
SDK consumed by another service; any platform exposed to clients). Before
shipping a public-method change, the spec MUST include:

1. **Schema dependencies** — what does the new code READ or WRITE that the
   consumer's environment must already have provisioned?
   - DB columns / tables / indexes (point at the migration file).
   - Config keys with required values.
   - Env vars with required values.
   - Container services + ports.
   - OS packages, binaries, files.

2. **Migration path** — if the consumer doesn't have the infra yet, how do
   they get it? Auto-migration runner? Opt-in flag? Manual setup? If the
   answer is "they have to read the changelog and run SQL by hand," that's
   a process gap — fix it before shipping.

3. **Cold-start integration test** — every public method change MUST have an
   integration test that exercises the method against a from-scratch consumer
   environment (fresh containers, fresh venv, import only from public
   surface). If you can't write that test, you don't yet understand what the
   consumer needs to make the method work.

`/plan` refuses to produce a spec without (1) and (2). `/code` refuses to
implement without them. `/review` flags any PR that touches public methods
and lacks (3).

**Reason:** Three Kermit Harness patches in 24 hours (v2.20.1 Milvus flush
storm, v2.20.2 behavioral_model API gap, v2.20.3 migration runner) all
shipped, all consumer-surfaced, all the same root cause — the harness team
didn't ask "what does the consumer's environment need for this to work" before
the patch went out. PA was the first consumer to actually exercise each path
and hit each wall. Process discipline at intake (this rule) plus mechanical
enforcement at gate time (the cold-start integration test) retire the bug
class. One without the other is half a fix.

This rule reads like overhead until you've shipped 3 patches in a day to
close gaps a single integration test would have caught.

## Development Workflow

**CRITICAL — DO NOT ADVANCE STEPS WITHOUT EXPLICIT USER INVOCATION.**

Each step in the workflow requires the user to explicitly invoke it. Completing `/plan` does NOT
mean start `/code`. Completing `/code` does NOT mean start `/test`. Do not infer "natural next
step" and proceed. Stop after each step and wait for the user's command.

**After completing any step: report results only. Do NOT mention, suggest, or hint at the next step. Not even "ready for X when you are." Silence is correct.**

**For any feature touching multiple files or adding a new service:**

```text
/plan → /code → /test → /review → /gate fast → /docs → commit → push
```

- **`/plan`** — Spec before code. Catches missing layers BEFORE implementation.
- **`/code`** — Implements spec task by task. Follows the spec literally — doesn't improvise.
- **`/test`** — Validates with real data. "It compiles" is NOT "it works."
- **`/review`** — Pre-commit code review on staged changes.
- **`/gate fast`** — CRITICAL: runs constitutional checks + unit tests + smoke_fast. Must PASS before commit. A failing gate blocks the commit — fix it first.
- **`/docs`** — CRITICAL: update ALL project docs BEFORE commit. Updates planning.md, ROADMAP.md, README.md, tasks/lessons.md, and any feature-specific docs. Must run after `/gate fast` and before commit.
- **commit** — Conventional commits AFTER `/gate fast` PASS and AFTER `/docs` has updated all project docs. Feature code + doc updates go into ONE atomic commit — not separate "feat" and "docs" commits.
- **push** — Push to GitHub. Create PR if on a branch.

**NEVER commit before `/gate fast` passes. The gate is the last line of defense before the commit lands in history.**

**NEVER commit before `/docs` has run.** Splitting a feature across a "feat" commit and a follow-up "docs" commit pollutes history — a reader browsing `feat:` commits sees stale planning/roadmap state. Bundle docs with the feature they describe.

**Quick fixes (single-file, trivial):** Fix → `/review` → `/gate fast` → commit. No `/docs` needed if no project docs changed.

**Plan mode default:** Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions). If something goes sideways, STOP and re-plan — don't keep pushing. Write detailed specs upfront to reduce ambiguity.

**Verification before done:** Never mark a task complete without proving it works. Ask: "Would a staff engineer approve this?" Run tests, check logs, demonstrate correctness.

## Development Terminology

**These terms are the standard across ALL projects. Use them consistently in specs, docs, commits, and conversation.**

| Level | Term | Definition | Workflow trigger |
| ----- | ---- | ---------- | ---------------- |
| 1 | **Roadmap Phase** | Major product milestone with exit criteria (Roadmap Phase 1.0, 1.1, 2). Tracked in `ROADMAP.md` / `tasks/{project}-roadmap.md`. | Roadmap planning |
| 2 | **Spec** | Demoable milestone within a Roadmap Phase; the output of `/plan`. Artifact at `tasks/{descriptive-name}-spec.md`. | `/plan` |
| 3 | **Spec Phase** | Group of related Changes inside one Spec. Section header `## Phase N: <title>`. | Spec structure |
| 4 | **Change** | Atomic implementation step inside a Spec. Header `### Change N: <title>`. Numbered CONTINUOUSLY across the whole Spec — Change 1 is in Phase 1, Change 7 might be in Phase 3, etc. `/code` implements one or more Changes per invocation. | `/code` |
| 5 | **Commit** | Git record — feature code + doc updates bundled as one atomic commit. | `git commit` |

**Rules:**

- Roadmap Phase → Spec → Spec Phase → Change → Commit. Always. Every project.
- A Roadmap Phase has exit criteria. A Spec has a demo. A Change has a commit-shaped diff.
- `/plan` produces a Spec. `/code` implements one or more Changes. No other granularities.
- Specs reference atomic steps by number: "Change 7" — not "Task 7", "Step 7", "Item 7".
- Section headers inside a spec use `## Phase N: <title>`; atomic steps use `### Change N: <title>` with N continuous across the entire spec.
- Progress tables in specs track Changes. Roadmaps track Roadmap Phases.
- Spec files are named descriptively: `tasks/foundation-spec.md`, `tasks/auth-layer-spec.md` — not `stage-a-spec.md` or `sprint-1-spec.md`.
- Change numbering starts at 1 within each Spec and increments through every Phase in that Spec.

**Killed terms (never use as workflow-level labels):** Stage, Sprint, Iteration, Revision, Milestone, Group, Epic, Step, Item, Task.

**Disambiguation:** "Phase" alone means *Spec Phase* (the section header inside a spec). "Roadmap Phase" is the qualified form for product-milestone scope. Project-specific business hierarchies that ALSO use "Phase" (e.g., Keystone's Global → Project → Phase → Task → Sub-Task domain model) qualify with the project name: "Keystone Phase". Bare "Phase" in development context always means the spec-internal section.

**Reference specs:** `/home/rich/dev/keystone/tasks/atlas-*.md` and `/home/rich/dev/projects/atlas/tasks/*-spec.md` are the canonical examples of this taxonomy.

**Enforcement:** `/home/rich/dev/scripts/check_spec_taxonomy.sh` scans `tasks/*-spec.md` in any project and exits 1 on killed-term headers. Wire it into your project's `gate fast` (or equivalent pre-commit gate) to block drift automatically. The check ignores killed-term headers under non-Phase parents (so workflow-runner descriptions like `## gate fast` → `### Step N: ...` are allowed).

```bash
# from any project root
/home/rich/dev/scripts/check_spec_taxonomy.sh
```

## Workflow Principles

**Autonomous bug fixing:** When given a bug report, just fix it. Don't ask for hand-holding. Point at logs, errors, failing tests — then resolve them. Zero context switching required from the user.

**Subagent strategy:** Use subagents to keep main context window clean. Offload research, exploration, and parallel analysis. One task per subagent for focused execution. For complex problems, throw more compute at it.

**Simplicity first:** Make every change as simple as possible. Impact minimal code. No over-engineering — don't add features, refactoring, or "improvements" beyond what was asked.

**No laziness:** Find root causes. No temporary fixes. Senior developer standards.

**Use official SDKs — NEVER hand-roll protocol implementations.** Before building ANY protocol handler, server, or client: check if an official SDK exists. If it does, USE IT. The SDK is maintained by the people who wrote the spec — it is always more correct, more complete, and more maintainable than a custom implementation. Specifically: `a2a-sdk` for A2A protocol, `mcp`/`fastmcp` for MCP protocol, `claude-agent-sdk` for Anthropic agent runtime. Search PyPI/npm/Go modules before writing protocol code.

## Verification Requirements

**You MUST run these checks and fix any issues before marking work complete:**

- Run tests after code changes — all tests must pass
- Run build/typecheck before committing — no errors allowed
- For API changes, test endpoints with curl or the dev server
- For UI changes, start dev server and verify visually in browser
- For any CRUD feature: verify the delete path cleans up ALL storage layers (database, filesystem, cache, search index, in-memory state, message references)
- For any new endpoint: verify it's reachable end-to-end (UI → service call → proxy route → backend endpoint → storage)
- For any delete operation: verify the resource is actually gone (query DB, check filesystem, check indexes — not just "endpoint returned 200")
- For any batch processing: verify the TARGET store has the data, not just the status field. A database status of "complete" is a claim — query the actual destination (ChromaDB, filesystem, API) to confirm.
- For any multi-step pipeline: don't mark step N complete until step N+1's target confirms receipt. Status fields lie when processes crash between writes.

Do not skip verification. If a check fails, fix it before proceeding.

## Verify Against Source of Truth, Not Derived State

Before claiming a fix works, the verification command must directly
touch the system being changed. Never trust an intermediate signal — a
memo, a queue row, a chained-command exit code, "the read is gone so
the function should compile." Run the live tool. Curl the running
backend. Re-grep the actual file. Query the actual database row.

Six instances of this bug class logged in PA's `tasks/lessons.md`
(L23, L31, L36 + three May-2026 UI-fixes-session catches) before
this rule consolidated:

- Spec assumed column was `metadata`; actual schema has `metadata_json`.
  Should have queried the schema, not the spec.
- HANDOFF_QUEUE row said function lives at `:828-849`; current code is
  at `:954-1043`. Should have re-greped before quoting.
- `git stash push -- <files>` was assumed to bundle only the work being
  set aside; actually swallowed Track 1's verified call-site change as
  collateral. Should have read each modified file before stashing.
- `npx tsc --noEmit; echo "tsc=$?"` reported `tsc=0` because the
  chained `echo` masks tsc's exit. Should have run tsc as the terminal
  command.
- Settings dropdown was assumed to render the persisted model. Actual
  HTML had `<option value={catalogId}>` against `<select value={apiName}>`,
  silently picking option 0. Should have queried `agents.model`
  directly.
- Dead `project_agent_models` reads were removed; the surrounding
  `if my_project_config.get(...)` blocks that USED the local var the
  read populated were missed. py_compile passed; the very first curl
  surfaced `name 'my_project_config' is not defined`. Should have run
  the live request before claiming clean.

**Forcing function:** the verification command must touch the actual
system. No echo chains hiding the real exit code. No "it should work
because X." If you cannot run the live test, mark the check
**UNTESTED** in the QC report — never PASS.

This rule supersedes L23, L31, and L36 from PA's `tasks/lessons.md`
(deleted in the consolidation commit on 2026-05-06).

## Workflow Discipline / Pre-commit Gate Coverage

**Asymmetric gate coverage is mandatory. `/gate fast` MUST stay surgical for inner-loop velocity; load-tier coverage MUST run before any release.**

Three load-tier-only catches in three months (v2.7.2 `d1d99ff`, v2.19.1 cluster fix, v2.19.2 OllamaAdapter EBADF) made this a mechanical rule rather than a per-incident lesson.

The asymmetric split:

| Gate | Scope | Cycle time | Trigger |
| ---- | ----- | ---------- | ------- |
| `/gate fast` | constitutional + unit + smoke-fast | ~5s–3 min | every commit |
| `/gate full` | + load-tier smokes (L1/L3/L4 smoke) for any change touching threads, asyncio interop, ContextVar/Token state, shared-client adapter glue, or backend integration paths | ~10–35 min | after structural change |
| Pre-merge gate | load-tier smokes MUST PASS before PR merges to main | ~10 min | every PR merge |
| `/gate release` | full L1/L3/L4 (1K/1K/2.5K tenants) | ~3+ hours | every `__api_version__` minor or major bump |

**Why fast-tier stays surgical:** adding load-tier to `/gate fast` inflates inner-loop cost from ~5s to ~10 min. Kills velocity. Catches no bugs that the asymmetric split doesn't catch elsewhere.

**Why load-tier MUST run before release:** the recurring pattern is "a feature touching threads or shared clients passes every fast-tier and infra-smoke cycle, then crashes the first time it hits per-tenant teardown or 1K-agent fan-out." Examples:

- v2.7.2 (load-test fix shipped without re-running L1)
- v2.19.1 (2 v2.15.0-latent bugs masked behind each other under L3 100-tenant teardown)
- v2.19.2 (httpx pool exhaustion under L1 1K-agent single-process)

The bug class is "concurrency-shaped state that only opens its window at scale."

**Mechanical guidance for `/code` agents:** whenever a `/code` session touches files in `kermit/adapters/`, `kermit/core/runtime_impl.py`, `kermit/core/governance/`, or any module that imports `asyncio.create_task`, `threading.Thread`, `loop.call_soon_threadsafe`, or `ContextVar.set/.reset`, the implementing agent MUST run `make load-l1-smoke && make load-l3-smoke && make load-l4-smoke` as the in-spec acceptance check before `/test`. Three sub-3-minute runs catch the bug class.

**Project lesson lineage:** see `/home/rich/dev/projects/kermit/tasks/lessons.md` L15 (v2.19.1 — pattern noted, masking corollary) and L16 (v2.19.2 — httpx pool exhaustion + the 3rd-recurrence trigger).

## Language Architecture Decision Matrix

**Every new component MUST be evaluated against this matrix. No exceptions.**

| Layer | Language | When to Use | Examples |
| ----- | -------- | ----------- | -------- |
| **Network-intensive** | **Go** | High concurrency, many connections, request routing, real-time | API gateways, WebSocket handlers, proxies, CLI tools, health monitors |
| **Compute-intensive** | **Rust** | CPU-bound processing, data transformation, performance-critical | Embedding pipelines, parsing engines, audio/video, compression |
| **AI-intensive** | **Python** | LLM integration, ML workflows, rapid prototyping | RAG pipelines, agent logic, document processing, prompt engineering |
| **UI/Frontend** | **TypeScript** | User interfaces, browser applications | React/Next.js apps, dashboards, browser extensions |

**Decision Rules:**

1. Network-intensive → **Go**
2. Compute-intensive → **Rust**
3. AI-intensive → **Python**
4. Mixed → Split: Go/Rust for I/O and transport, Python for intelligence
5. When in doubt → Python first, rewrite hot path when performance data justifies it

**Anti-patterns to flag:**

- Python handling 1000+ concurrent connections (should be Go)
- Python doing CPU-bound transformation in a tight loop (should be Rust)
- Go/Rust calling LLM APIs directly (should delegate to Python)
- Monolithic services mixing network routing with AI logic (should be split)

## Code Quality

- Many small files over few large files (200-400 lines typical, 800 max)
- No console.log in production code
- Proper error handling with try/catch
- Input validation for all user inputs
- No over-engineering — don't add features beyond what was asked

## Planning Requirements

**Before writing ANY new code:**

- Search the codebase for existing implementations (use Grep/Glob)
- Check if similar functionality already exists
- Identify reusable components, hooks, or utilities
- Follow patterns from existing implementations

Do not reinvent what already exists. Reuse first.

## Architectural Triage — Harness vs Consumer (Mandatory Before `/plan`)

For any project that builds on top of `kermit-harness` (Kermit PA, ATLAS,
Keystone agents, future Kermit-based products), every spec session starts
with the architectural triage gate **BEFORE** invoking `/plan`.

**Answer in one sentence each:**

1. **What is this work?** (one-line summary)
2. **Would another harness consumer need a different implementation if they
   wrote it themselves?**
3. **If no → does this belong in the harness or in the consumer?** (almost
   always: harness)
4. **If split (logic in harness, schema/policy in consumer): write two
   specs, not one.**

**Skipping this triage is a CLAUDE.md violation.** A consumer-only spec for
harness-shaped work needs an explicit "Why this can't wait for the harness"
justification.

### Signal patterns — almost always belong in the harness

| If the work is… | …it belongs upstream |
| --- | --- |
| A pure algorithm (chunking, dedup, retry, drain, regex intent detection) | yes |
| An adapter for an external service (LLM, embedding, vector store, reranker) | yes |
| A wrapper that only translates one shape to another (truncation heuristic, dict-to-string normalization) | yes — and the underlying gap is what the harness should fix |
| Lifecycle / orchestration (graceful drain, state machines, restart recovery) | yes |
| LLM-universal response fields (`stop_reason`, token counts, cost) | yes |

### Signal patterns — correctly stay in the consumer

| If the work is… | …it stays in the consumer |
| --- | --- |
| Schema, migrations, ORM models | consumer |
| Frontend components | consumer |
| Consumer-specific business logic, agent personas, domain workflows | consumer |
| Filter policies (tenant scope, project_id, privacy_tier) | consumer |
| MCP tool surfaces specific to the consumer's domain | consumer |

### When consumer-side work is harness-shaped but ships in the consumer anyway

When the harness doesn't yet expose the primitive and waiting blocks user
work, the consumer ships it anyway BUT appends an entry to a per-consumer
handoff queue file (e.g. `tasks/HARNESS_HANDOFF_QUEUE.md`) before the
commit lands. Each entry: feature, where it lives, why it's harness-shaped,
migration plan once the primitive ships.

The handoff queue makes the technical debt explicit and trackable instead
of buried in commit messages. A long Pending list signals that consumer
projects are carrying weight that should be upstream.

### Why this rule exists

Without architectural triage at intake, "build it where the bug surfaced"
becomes the default — and consumers accumulate slightly-different
reimplementations of the same primitives. The Kermit PA April 26 2026
session shipped roughly 40% harness-shaped code in PA before the pattern
was caught (recency intent detection, truncation heuristic, in-flight
task registry, dedup helpers, cascade delete, async/sync wrap pattern).
Every other consumer would have built each one slightly differently.
Triage at intake stops the drift.

## Git Workflow

- Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`
- Small, focused commits
- Run tests before committing
- `/review` before every commit

## Data Lifecycle & Wiring Rules

**These rules exist because the same failures keep repeating: features built vertically (happy path works) but never wired horizontally (cleanup paths missing, delete doesn't cascade, endpoints unreachable from UI).**

### Rule 1: CRUD Completeness — If You Build Create, You MUST Build Delete

Every data operation must have its inverse. When implementing any create/store/upload operation, implement the corresponding delete/cleanup/remove operation in the SAME work session. The delete MUST clean up ALL storage layers the create touched.

Before marking a CRUD feature complete, answer these three questions:

- If I create this record, what deletes it?
- If I delete this record, is it gone from EVERY storage system? (database, file system, cache, search index, in-memory state, message references)
- If a parent is deleted, what happens to children? (cascade delete, orphan intentionally, or block with error?)

### Rule 2: One Operation, One Code Path

**Never build two functions that do the same thing partially.**

If two endpoints delete the same type of data, they MUST share the same cleanup function. Not `delete_foo()` that cleans A+B and `remove_foo()` that cleans B+C. One canonical `_cleanup_foo()` that cleans A+B+C, called by both.

Before adding a new endpoint for an existing operation, search for existing endpoints that do the same thing. Extend the existing one — don't duplicate.

### Rule 3: Horizontal Wiring Verification

**Every new endpoint must be traceable from UI to storage and back.**

When adding any new feature, trace the complete chain and verify every link:

```text
UI component → Frontend service call → Proxy route → Backend endpoint → Storage layer → Response → UI update
```

If ANY link in this chain is missing, the feature is not done.

### Rule 4: Delete Verification Test

**After implementing any delete operation, verify the thing is GONE.**

1. Query the database — record should not exist
2. Check the filesystem — file should not exist
3. Check any search/vector indexes — documents/chunks should not exist
4. Check in-memory caches — entry should be cleared
5. Try to access the deleted resource via its original endpoint — should get 404

### Rule 5: No Phantom Features

**If a feature cannot be triggered from the UI end-to-end, it does not exist.**

### Rule 6: Status/Enum Consistency

**Every status field must have a defined set of valid values, and code must ONLY use those values.** Need a new value? Add it to the model definition FIRST.

## Keystone Server Environment

Headless Ubuntu server at `192.168.1.101`. NO monitor, NO keyboard. All development is remote.

**Power schedule:** Server shuts down nightly at 9pm and restarts at 4am for power saving. If services are unreachable, check whether the server is simply powered off. After each restart, containers with `restart: unless-stopped` come back automatically — but manually-stopped containers do not. If a site or service is down after 4am, start the relevant container with `docker compose up -d` from its prod directory.

| Context | Use | Example |
| ------- | --- | ------- |
| Service binding | `0.0.0.0` | `uvicorn --host 0.0.0.0` or `chi.ListenAndServe(":8200", r)` |
| Service-to-service | `127.0.0.1` | `http://127.0.0.1:8001/api/endpoint` |
| Browser / client | `192.168.1.101` | `NEXT_PUBLIC_API_URL=http://192.168.1.101:8001` |

**WRONG:** `localhost` as default or fallback in any service. This is a headless server — `localhost` is unreachable from remote clients.

## Port Allocation Registry

Each project gets its own port series. No overlap. Check this table before assigning ports.

| Series | Project | Ports |
| ------ | ------- | ----- |
| 3000 | Kermit frontend | 3000 |
| 4000s | SQRL | 4001 (backend), 4002 (frontend) |
| 5000s | Portal | 5000 (frontend), 5100 (backend) |
| 8000s | Kermit backend | 8001-8020 (PA backend, agents, MCPs) |
| 8021 | Kermit Harness trigger webhook | Default for `KermitConfig.trigger_webhook_port`; consumers SHOULD override per their own port series (e.g., Keystone Platform → 8188 in its 8100s allocation). The default exists for inner-loop test runs and single-deployment cases. |
| 8090 | Keystone Dashboard | 8090 |
| 8100s | Keystone Platform | 8100-8190 |
| 8200s | NVR Dashboard | 8200 (backend), 8210 (frontend), 8889 (WebRTC) |
| 8300 | TIS Standalone App (ATLAS Mode 2) | 8300 |
| 9000 | SQRL splash | 9000 |
| 15400s | **Kermit Harness test infra** | 15401 (chromadb), 15418 (mongodb), 15424 (nats), 15432 (milvus gRPC), 15436 (postgres), 15480 (redis), 15493 (milvus health) |

**Next available series:** 8400s

**Why 15400s for Harness test infra:** the test stack used to live at the
"prod-port + offset" scatter (5436, 6380, 27018, 19532, 4224, 8101) which
collided with ATLAS dev (`atlas-dev-postgres:5436`) and any other dev
environment using the standard offsets. Relocated to a dedicated
contiguous range (Track 4 follow-up, 2026-04-27) so `make test-infra-up`
can never conflict with sibling dev stacks again. See
`/home/rich/dev/projects/kermit/docs/PORT_MAPPING.md`.

## Production Deployment Pattern

All production services follow this pattern:

- **Dev:** `/home/rich/dev/projects/X/`
- **Prod:** `/home/rich/prod/X/` (Docker + Traefik)

Infrastructure:

- Traefik reverse proxy on ports 80/443 (`/home/rich/prod/traefik-global/`)
- Let's Encrypt SSL via HTTP challenge (certresolver: `letsencrypt`)
- Cloudflare DNS → Keystone public IP
- Each service joins `traefik-global` network for external routing
- Each service has its own internal network for databases (never exposed on traefik-global)
- Portal ForwardAuth middleware (`kermit-auth@file`) for protected apps

## Standard Project Structure

Based on Kermit pattern. All projects SHOULD have:

```text
project-name/
├── CLAUDE.md              ← Project-specific rules (see template)
├── .markdownlint.json     ← {"default": false}
├── .gitignore
├── .env.example           ← Environment variable template (if env vars used)
├── README.md              ← Purpose, quick start, architecture
├── backend/               ← Backend code (Go/Python/Rust)
├── frontend/              ← Frontend code (Next.js/TypeScript)
├── config/                ← Configuration files
├── docs/                  ← Architecture, API docs, guides
├── scripts/               ← Dev/deploy scripts
├── tasks/                 ← Spec files from /plan, lessons.md
├── tests/                 ← Test files
├── logs/                  ← Application logs (gitignored)
├── docker-compose.yml     ← Dev Docker compose
├── Dockerfile.backend     ← Production backend image
└── Dockerfile.frontend    ← Production frontend image
```

## Project CLAUDE.md Standard

Every project CLAUDE.md should follow the template at `docs/PROJECT_CLAUDE_TEMPLATE.md`.

Rules:

- **Max 200 lines.** API docs, UI design, troubleshooting → `docs/` directory.
- Required sections: description, architecture, tech stack, build & run, configuration, ports, file structure, rules, patterns.
- No duplicating rules from THIS file — project files ADD to these standards, not repeat them.

## Repo Structure

This repo (`teelr/dev-platform`, at `/home/rich/dev/`) owns the full dev-experience surface. Each directory has a `README.md` with its contract — read it before adding files.

| Directory | Purpose |
| --------- | ------- |
| `commands/` | Slash command definitions (`/plan`, `/code`, etc.) |
| `skills/` | User skills + `WORKFLOW_MANUAL.md` taxonomy reference |
| `settings/` | Global Claude Code config (`settings.json`, optional `keybindings.json`) |
| `hooks/` | Claude Code hook scripts |
| `extensions/` | IDE config — populated by future extensions spec |
| `scaffolding/` | New-project templates — populated by future extensions spec |
| `monitoring/` | Workflow telemetry — populated by future monitoring spec |
| `shell/` | Shell helpers, git-hook templates |
| `scripts/` | Install / uninstall / verify; spec-taxonomy checker |
| `tasks/` | Spec files (output of `/plan`) |
| `docs/` | Architecture and how-to docs |

## Install / Deploy

The repo is the source of truth; `~/.claude/` is a *deployment* of it. `scripts/install.sh [category]` symlinks tracked files into the user environment (categories: `commands`, `skills`, `settings`, `hooks`, or `all`). `scripts/uninstall.sh` removes the symlinks (leaves `~/.claude/projects/` untouched). `scripts/verify.sh` reports drift between tracked and deployed. Edit the file in this repo and re-run install — never edit under `~/.claude/` directly.

## Adding a New Workflow Artifact

For a new slash command / skill / hook / setting: (1) write the file in the correct directory per its README contract, (2) extend `scripts/install.sh` only if you're adding a *new top-level category* (existing-category files are auto-globbed), (3) update `scripts/verify.sh` for the same case, (4) smoke-test manually until the testing spec (R3) lands.

## Patterns

- **Single cleanup path** — One canonical cleanup function per data type, called by all endpoints that delete that type.
- **Cascade verification** — Parent delete handles all children (deleted, orphaned intentionally, or blocked with error).
- **Horizontal tracing** — Every endpoint traced through all layers before marking complete. Missing links = not done.
- **Create and delete together** — Delete path implemented in the same work session as create.
- **Dev workflow** — `/plan → /code → /test → /review → /gate fast → /docs → commit → push` for features. Fix → `/review` → `/gate fast` → commit for quick fixes.
