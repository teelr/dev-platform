# Rich's Development Standards

All development standards for projects in `/home/rich/dev/projects/`. This is the single source of truth.

**Project-specific deep-dive rules and incident rationale:** `/home/rich/dev/docs/RULE_RATIONALE.md`. Read when working in Kermit/PA/ATLAS/Keystone (Kermit-specific rules: kwarg propagation, boundary sweeps, consumer-side schema deps, harness-vs-consumer triage, load-tier gate coverage), or when a rule's reasoning is unclear.

## Scope — dev-platform Is For The Environment, Not The Projects

**CRITICAL — This repo (`teelr/dev-platform`, at `/home/rich/dev/`) exists to care for, maintain, and enhance the development *environments* that drive Rich's projects. It is NOT a workplace for the projects themselves.**

**Primary gateway — VSCode + Claude Code:** This repo is the single entry point for setting up and modifying Rich's VSCode + Claude Code dev environment. Every change to global Claude Code config (slash commands, skills, settings, hooks, keybindings) and global VSCode/IDE config goes through this repo first — written here, deployed via `scripts/install.sh`. **Direct edits to deployed locations (`~/.claude/`, `~/.vscode/`, etc.) are forbidden** — they get overwritten on the next install and split the source of truth in two.

**Belongs here:** Rules (`CLAUDE.md`, `settings/claude-global.md`), slash commands (`commands/`), skills (`skills/`), hooks (`hooks/`), settings (`settings/`), scripts (`scripts/`), IDE config (`extensions/`), scaffolding (`scaffolding/`), monitoring (`monitoring/`), shell helpers (`shell/`), specs/docs for the above (`tasks/`, `docs/`).

**Does NOT belong here:** Project source code, schemas, frontend, tests, deployment configs, or per-project roadmaps under `projects/<name>/` — those live in their own repos. No bug fixes, feature work, or refactors against any project from this session.

**Behavioral rule:** When invoked in `/home/rich/dev/`, assume every request is environment work. If a request would require modifying a file under `projects/`, STOP and ask the user to switch to that project's working directory. Read-only operations across projects (orientation, status surveys, cross-project assessments) ARE allowed.

**Exceptions:**

- `scripts/new-project.sh` may scaffold a new project tree under `projects/<new-name>/`. Conversational Q&A pattern in `docs/NEW-PROJECT.md`.
- `scripts/fleet-install-template.sh` (v0.8+) may write the dev-platform CI integration files (`.github/workflows/dev-platform-gate.yml`) into a project. All other writes to `projects/` remain forbidden.
- `scripts/migrate-workflow-chain.sh` (v0.9 migration tooling) may rewrite the workflow chain line(s) inside a project's `CLAUDE.md`. Detects lines matching the old chain pattern (`/plan → /code → /test`) and rewrites them to the canonical chain (`/plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge`). All other content in the project's `CLAUDE.md` is left untouched. Opt-in (`--apply` flag required), dry-run by default, idempotent. Future chain updates require updating this entry — not a general "migration scripts may edit CLAUDE.md" loophole.

## Consistency Across All Projects — Non-Negotiable

**CRITICAL — Every project under `/home/rich/dev/projects/` MUST conform to these standards. Absolute consistency is a hard requirement.**

**What dev-platform owns (no project may diverge):**

- **Dev workflow** — `/plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge`. `/review` optional for risky changes. `/code` handles verification, auto-fix, and doc updates internally.
- **Workflow taxonomy** — Roadmap Phase → Spec → Spec Phase → Change → Commit. Killed terms (Stage, Sprint, Iteration, Revision, Milestone, Group, Epic, Step, Item, Task) never used as workflow-level labels.
- **Language Architecture Decision Matrix** — network → Go, compute → Rust, AI → Python, frontend → TypeScript.
- **Slash commands** — `/plan`, `/code`, `/test`, `/review`, `/gate`, `/docs`, `/pr`, `/merge`, `/dev`, `/loop`, `/smoke_test`.
- **Skills + settings baseline + hooks** — tracked in `skills/`, `settings/`, `hooks/`.
- **Standard project structure** — described below. New projects MUST start from `docs/PROJECT_CLAUDE_TEMPLATE.md`.
- **Quality-gate contract** — constitutional checks, taxonomy enforcement, gate-fast semantics. Projects extend; they do not replace.
- **Lessons promotion path** — recurring `tasks/lessons.md` entries (2-3 of the same shape) consolidate into rules in THIS file; per-project specifics get deleted.

**What projects MAY customize:** Domain logic, data model, agents, frontend components, deployment topology. Project-specific permissions and hook scripts (additive, must not shadow canonical). Project-internal taxonomies that legitimately use "Phase" (e.g., Keystone's lifecycle Lead → Pursuit → ...) — qualify with project name (`Keystone Phase`). Project-specific lessons until they promote.

**What projects MUST NOT customize:** Slash command names or core contracts. The workflow sequence. The language matrix. The killed-term taxonomy.

**Drift detection:** `scripts/check_spec_taxonomy.sh` (wired into every project's gate fast). `/review` (slash command + workflow contracts on staged changes). Cross-project audits via `/dev` or status surveys.

**Drift correction:** Fix lands in dev-platform FIRST; each project re-runs `scripts/install.sh` to pick up the change.

## Response Style — GET TO THE POINT

**Verbosity is a bug.**

- Lead with the answer in the first sentence. No preamble, no recap, no "let me think about this".
- **No multi-tier feature audits unless explicitly asked.** Give 3–5 items max with one line each. No Tier 2 / Tier 3 / "can wait" / "my suggestion" sections.
- **Cut suggestion sections.** Drop "If you want my pick", "Bonus", "Nice-to-have", "Worth a test" trailing paragraphs.
- **End-of-step summaries: 1–2 sentences.** What changed, what's next workflow-wise. Nothing else.
- **NEVER include time estimates.** No "~3 days", "~2 hours", "ETA", "estimated effort". Not anywhere.
- When referencing code, include `file_path:line_number`.
- No emojis unless explicitly asked.

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

1. **`.gitignore` allow-list** — `git check-ignore -v <newfile>` to verify it's not silently ignored.
2. **install / deploy scripts** — does `scripts/install.sh` glob `<newext>`?
3. **verify / check scripts** — does `scripts/verify.sh` glob `<newext>`?
4. **Directory README** — mention `<newext>` in its contract.
5. **Test orchestrators** — `tests/<suite>/run.sh`, `scripts/gate_fast.sh`, or per-project equivalents.

## Development Workflow

**CRITICAL — DO NOT ADVANCE STEPS WITHOUT EXPLICIT USER INVOCATION.**

Each step requires the user to invoke it. Completing one step does NOT mean start the next. Stop and wait. End-of-step "Ready for X" format is defined in `settings/claude-global.md`.

**Standard chain:**

```text
/plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge
```

- **`/plan`** — Spec before code. Auto-creates the feature branch.
- **`/code`** — Implements Change by Change with auto-fix. Updates project docs (planning.md, ROADMAP.md, README.md, lessons.md) as its final step. Feature code + doc updates commit together.
- **`/gate fast`** — Constitutional checks + unit tests + smoke_fast. Must PASS before commit. (dev-platform: `./scripts/gate_fast.sh`)
- **commit** — One atomic commit. Conventional format: `feat:`, `fix:`, etc.
- **push** — Push the feature branch.
- **`/pr`** — Opens PR against `main`. Auto-derives title, milestone, body.
- **CI** — Wait for `gate-fast` to go GREEN. If red, fix on the branch and re-push.
- **`/merge`** — Squash-merges after verifying CI green. Refuses on red/pending/conflicts.
- **post-merge** — Bespoke deferred steps from the spec. No-op if the spec named none.

**Optional steps:**

- **`/review`** — For risky/large changes: between `/code` and `/gate fast`.
- **`/test`** — Standalone spec validation. Not required when `/code` verifies as it goes.
- **`/docs`** — Standalone doc update. Recovery only — `/code` handles it normally.

**NEVER commit before `/gate fast` passes. NEVER merge before CI green.**

**Quick fixes:** fix → `/gate fast` → commit → push → `/pr` → CI → `/merge`.

**Plan mode default:** Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions). If something goes sideways, STOP and re-plan.

**Verification before done:** Never mark a task complete without proving it works. Ask: "Would a staff engineer approve this?" Run tests, check logs, demonstrate correctness.

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

## Workflow Principles

- **Autonomous bug fixing** — given a bug report, just fix it. Don't ask for hand-holding.
- **Subagent strategy** — offload research, exploration, parallel analysis. One task per subagent.
- **Simplicity first** — minimal code, no over-engineering, no features beyond what was asked.
- **No laziness** — find root causes, no temporary fixes. Senior developer standards.
- **Use official SDKs — NEVER hand-roll protocol implementations.** `a2a-sdk`, `mcp`/`fastmcp`, `claude-agent-sdk`. Search PyPI/npm/Go modules before writing protocol code.

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

## Keystone Server Environment

Headless Ubuntu server at `192.168.1.101`. NO monitor, NO keyboard. All development remote.

**Power schedule:** Shuts down nightly at 9pm, restarts at 4am. If services are unreachable, check whether the server is powered off. After restart, containers with `restart: unless-stopped` come back automatically. Manually-stopped containers don't — start with `docker compose up -d`.

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
| 9000 | SQRL splash | 9000 |
| 15400s | Kermit Harness test infra | 15401 (chromadb), 15418 (mongodb), 15424 (nats), 15432 (milvus gRPC), 15436 (postgres), 15480 (redis), 15493 (milvus health) |

**Next available series:** 8400s

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
| `shell/` | Shell helpers, git-hook templates |
| `scripts/` | Install / uninstall / verify; `gate_fast.sh` orchestrator; spec-taxonomy checker |
| `tests/` | Constitutional gate-fast fixtures + per-suite runners |
| `tasks/` | Spec files |
| `docs/` | Architecture and how-to docs (incl. `RULE_RATIONALE.md`) |

## Install / Deploy

Repo is source of truth; `~/.claude/` is a *deployment*. `scripts/install.sh [category]` symlinks tracked files (`commands`, `skills`, `settings`, `hooks`, `vscode`, or `all`). The `vscode` category runs `code --install-extension` for every entry in `extensions/vscode/server-extensions.json` (skips gracefully when `code` CLI is absent). `scripts/uninstall.sh` removes symlinks (leaves `~/.claude/projects/` untouched). `scripts/verify.sh` reports drift. Edit in this repo and re-run install — never edit `~/.claude/` directly.

## Adding a New Workflow Artifact

For a new slash command / skill / hook / setting: (1) write the file in the correct directory per its README contract, (2) extend `scripts/install.sh` only if adding a new top-level category (existing-category files are auto-globbed), (3) update `scripts/verify.sh` for the same case, (4) smoke-test.

## Patterns

- **Single cleanup path** — One canonical cleanup function per data type, called by all endpoints that delete it.
- **Cascade verification** — Parent delete handles all children explicitly.
- **Horizontal tracing** — Every endpoint traced through all layers before marking complete.
- **Create and delete together** — Same work session.
- **Dev workflow** — `/plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge` for features. Quick fixes: `/gate fast` → commit → push → `/pr` → CI → `/merge`. `/review` optional for risky changes.
