# Rule Rationale & Project-Specific Deep-Dive Rules

Long-form rationale for rules in `/home/rich/dev/CLAUDE.md`, plus project-specific rules that don't need to be loaded into every dev session. Read sections here when working in the relevant project or when a rule's reasoning is unclear.

## Why dev-platform owns the environment, not the projects

Before v0.1 Foundation, the prior "dev-standards" repo blurred the line — global rules and project-side fixes both landed in the same git history, making it hard to distinguish "what governs every project" from "what was happening in project X that day." v0.1 Foundation expanded this repo to own the full dev-experience surface; the Scope rule pins the corollary — the surface, not the things on top of it. A clean dev-platform history is a precondition for the monitoring (v0.5), testing (v0.4), and migration (v0.9) specs that all assume "this repo describes the environment, period." The two scope exceptions (scaffolding for new-project bootstrap, v0.8 fleet orchestration for CI-template install) are narrow by design — each names the script, the directory, and the filename so future additions require an explicit carve-out paragraph, not a vague "fleet ops are allowed" loophole.

## Why consistency across all projects is non-negotiable

Consistency compounds. Same workflow → a lesson learned in one project applies to all. Same taxonomy → specs are mutually readable. Same language matrix → no team-member surprise about what they find. Inconsistency creates per-project tribal knowledge — the slowest, most fragile mode of operation. The pre-v0.1 world tolerated drift because there was no enforcement layer; v0.1 Foundation built it; the Consistency rule commits to using it. v0.4 (Testing), v0.5 (Monitoring), v0.6 (VSCode), and v0.9 (Migration) all assume this baseline.

## Why "Honesty About What Ships" matters

The v2.20 Kermit Harness exec-SVG audit caught three overstated claims ("auto model downgrade", "tamper-evident audit", "crash recovery") that didn't match the code. Overstating once costs trust permanently — and once a customer or boss pins their plan to a feature that doesn't exist, you have to either ship it under pressure or admit you misled them. Both are bad. The audit habit is cheap; recovery isn't.

## Verify Against Source of Truth — Detailed Incident Examples

Six instances of this bug class logged in PA's `tasks/lessons.md` (L23, L31, L36 + three May-2026 UI-fixes-session catches) before the rule consolidated:

- Spec assumed column was `metadata`; actual schema has `metadata_json`. Should have queried the schema, not the spec.
- HANDOFF_QUEUE row said function lives at `:828-849`; current code is at `:954-1043`. Should have re-greped before quoting.
- `git stash push -- <files>` was assumed to bundle only the work being set aside; actually swallowed Track 1's verified call-site change as collateral. Should have read each modified file before stashing.
- `npx tsc --noEmit; echo "tsc=$?"` reported `tsc=0` because the chained `echo` masks tsc's exit. Should have run tsc as the terminal command.
- Settings dropdown was assumed to render the persisted model. Actual HTML had `<option value={catalogId}>` against `<select value={apiName}>`, silently picking option 0. Should have queried `agents.model` directly.
- Dead `project_agent_models` reads were removed; the surrounding `if my_project_config.get(...)` blocks that USED the local var the read populated were missed. py_compile passed; the very first curl surfaced `name 'my_project_config' is not defined`. Should have run the live request before claiming clean.

Supersedes L23, L31, L36 from PA's `tasks/lessons.md` (deleted in the consolidation commit on 2026-05-06).

## Consumer Audit — Why the rule exists

Two instances of the same omission within 24 hours of dev-platform work (v0.5 Phase 2 and v0.5 Phase 4). Both surfaced eventually — Phase 2 at /test gate-fail, Phase 4 at /review's `git check-ignore` probe — but both could have caused gate-fast to fail on a fresh clone if the omission persisted to commit. The audit is mechanical: five greps takes 30 seconds and eliminates the bug class. Consolidated from two `tasks/lessons.md` entries dated 2026-05-11.

---

# Kermit-Specific Rules

These apply when working in any project that builds on `kermit-harness` (Kermit PA, ATLAS, Keystone agents). Not loaded into general dev sessions — read when you're working in one of those projects.

## Public-Helper Kwarg Propagation

**CRITICAL — Every kwarg declared on a public helper function MUST observably affect the wrapped call.**

Applies to every public function in any project's public-API surface (anything a consumer can import — `kermit.api.*`, `kermit.agent.*`, `kermit.rag.*`, `kermit_pa.services.*`, ATLAS public modules, etc.). Helper functions wrap call sites; the kwargs on the wrapper exist to give consumers control over the wrapped call's behavior. A kwarg that doesn't reach the wrapped call is a silent trap — consumers trust the signature, the kwarg does nothing, and the bug surfaces only when someone inspects production behavior.

Two instances of this bug class in 24 hours (v2.25.0 `kermit.agent.classify(max_tokens=2000)` accepted but never threaded; v2.27.0 `runtime.documents.extract(mime=...)` used for audio routing only, silently dropped on the non-audio result side) made this rule mandatory rather than aspirational. Promoted from the harness's L29 lesson on 2026-05-04.

**Three sub-rules:**

1. **Every public-helper kwarg MUST observably affect the wrapped call.** Either threaded as a kwarg to the underlying call, used to construct the call's payload, used to gate behavior before/after the call, or assigned to a captured field that downstream code reads. If a kwarg has no observable downstream effect, it is dead — REMOVE it. Don't keep "future-compatible" kwargs that do nothing today.

2. **Pytest contracts MUST assert kwarg propagation, not just shape.** A test that `helper(..., kwarg=X)` returns the right shape does NOT prove `kwarg=X` was honored. The test MUST inspect the mock call's args/kwargs OR the constructed intermediate object (AgentDefinition, request payload, handler-side `result.mime`, etc.) to verify the value reaches the wrapped call.

3. **Mechanical enforcement: CT88 in the harness.** Static AST check at `tools/check_dead_kwargs.py` scans every public function in `src/kermit/api/`, `src/kermit/agent/`, and `src/kermit/rag/`. For each declared kwarg, it counts `ast.Name(id=kwarg)` references in the function body. Zero references → CT88 FAIL. Other projects (PA, ATLAS, Keystone) should add equivalent checks scanning their own public surfaces.

**Concrete examples:**

```python
# WRONG — max_tokens dead. The wrapped runtime.run_one_shot() call doesn't
# accept max_tokens, and AgentDefinition has no max_tokens field. Silent trap.
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

# RIGHT — option B: drop the kwarg if no thread-through is possible today.
async def classify(runtime, ctx, *, prompt):
    """...max_tokens is governed by KermitConfig, not per-call."""
    ...
```

**/review explicitly checks this pattern.** For every new public helper, /review reads the function body and verifies each documented kwarg has at least one downstream reference. CT88 makes the check mechanical at gate time — /review is the human-readable audit, CT88 is the gate.

**Sister-pattern: documentation MUST match the impl signature.** The v2.25.0 `model_catalog={...}` migration-guide bug (doc said dict, impl took callable) and v2.27.0 `mime=` doc-vs-impl mismatch are the same shape applied to docstrings/migration-guide examples. /review reads docs against the impl signature, flags type mismatches as same-class violations.

**Reference:** harness `tasks/lessons.md` L31 (lazy-construction accessors MUST be reset on lifecycle teardown).

## Boundary Contract Changes Require Both-Sides Sweep

**CRITICAL — Any change to a method's name, signature (including additive kwargs), return type, call path, or `async`/sync declaration at ANY boundary requires a sweep of ALL consuming sites in BOTH `src/` AND `tests/` in the same `/code` session. `src/`-only is NECESSARY but NOT SUFFICIENT.**

Five recurrences in 4 days before promotion (kermit-harness L46–L50, 2026-05-11):

| L | Change | What silently broke | Caught by |
| - | ------ | ------------------- | --------- |
| L46 | Method deprecated/renamed | test mocks called old name; AsyncMock never fired | `pytest` TypeError on un-awaited MagicMock |
| L47 | Producer returned `tuple`; consumer expected `list` | vision images silently dropped | live PA adoption |
| L48 | Private method extracted; call path re-routed | old-path mocks dead + new method unmocked (two-direction trap) | `ConfigError` at test + dead mock in /review |
| L49 | `async def` body ran sync CPU-bound code | event loop blocked 254 s; concurrent request dropped | live PA adoption |
| L50 | ABC gained additive kwarg | 25 test-mock subclasses raised `TypeError` | `/test` full suite |

**Mechanical sweep after any boundary change:**

```bash
# After rename / deprecation:
grep -rn "old_method_name" tests/

# After kwarg added to ABC or public method:
grep -rn "def method_name" tests/     # find every override

# After private method extracted:
grep -rn "old_path\|new_method" tests/  # dead mocks + missing mocks

# After async/sync flip:
grep -rn "def method_name" src/ tests/   # every override + call site
```

**`async def` / sync body (L49):** a function that declares `async def` promises callers that awaiting it yields the event loop. A body that calls synchronous CPU/GPU-bound code without `asyncio.to_thread` breaks that promise silently. The fix is always at the AWAITER level — wrapping the sync call in `asyncio.to_thread`. Making the called function `async def` just moves the violation one frame deeper.

**Default-value backward-compatibility protects CALLERS, not OVERRIDERS (L50):** adding a kwarg with a default to an ABC method is backward-compatible for every CALL SITE. But every OVERRIDE in a subclass that spells out the old explicit signature now rejects the new kwarg. `grep -rn "def initialize" tests/` is mandatory after any ABC signature change.

## Consumer-Side Schema / Infrastructure Dependencies

**CRITICAL — When adding or modifying a public method, declare what the consumer's environment needs. Don't ship a fix and find out from a prod incident.**

Applies to any project where a library / service / API is consumed by external code (Kermit Harness consumed by PA / Keystone / ATLAS; any internal SDK consumed by another service; any platform exposed to clients). Before shipping a public-method change, the spec MUST include:

1. **Schema dependencies** — what does the new code READ or WRITE that the consumer's environment must already have provisioned?
   - DB columns / tables / indexes (point at the migration file).
   - Config keys with required values.
   - Env vars with required values.
   - Container services + ports.
   - OS packages, binaries, files.

2. **Migration path** — if the consumer doesn't have the infra yet, how do they get it? Auto-migration runner? Opt-in flag? Manual setup? If the answer is "they have to read the changelog and run SQL by hand," that's a process gap — fix it before shipping.

3. **Cold-start integration test** — every public method change MUST have an integration test that exercises the method against a from-scratch consumer environment (fresh containers, fresh venv, import only from public surface). If you can't write that test, you don't yet understand what the consumer needs to make the method work.

`/plan` refuses to produce a spec without (1) and (2). `/code` refuses to implement without them. `/review` flags any PR that touches public methods and lacks (3).

**Reason:** Three Kermit Harness patches in 24 hours (v2.20.1 Milvus flush storm, v2.20.2 behavioral_model API gap, v2.20.3 migration runner) all shipped, all consumer-surfaced, all the same root cause — the harness team didn't ask "what does the consumer's environment need for this to work" before the patch went out. PA was the first consumer to exercise each path and hit each wall. Process discipline at intake plus mechanical enforcement at gate time (the cold-start integration test) retire the bug class. One without the other is half a fix.

## Workflow Discipline / Pre-commit Gate Coverage (Harness)

**Asymmetric gate coverage is mandatory. `/gate fast` MUST stay surgical for inner-loop velocity; load-tier coverage MUST run before any release.**

Three load-tier-only catches in three months (v2.7.2 `d1d99ff`, v2.19.1 cluster fix, v2.19.2 OllamaAdapter EBADF) made this mechanical.

The asymmetric split:

| Gate | Scope | Cycle time | Trigger |
| ---- | ----- | ---------- | ------- |
| `/gate fast` | constitutional + unit + smoke-fast | ~5s–3 min | every commit |
| `/gate full` | + load-tier smokes (L1/L3/L4 smoke) for any change touching threads, asyncio interop, ContextVar/Token state, shared-client adapter glue, or backend integration paths | ~10–35 min | after structural change |
| Pre-merge gate | load-tier smokes MUST PASS before PR merges to main | ~10 min | every PR merge |
| `/gate release` | full L1/L3/L4 (1K/1K/2.5K tenants) | ~3+ hours | every `__api_version__` minor or major bump |

**Why fast-tier stays surgical:** adding load-tier to `/gate fast` inflates inner-loop cost from ~5s to ~10 min. Kills velocity. Catches no bugs that the asymmetric split doesn't catch elsewhere.

**Why load-tier MUST run before release:** the recurring pattern is "a feature touching threads or shared clients passes every fast-tier and infra-smoke cycle, then crashes the first time it hits per-tenant teardown or 1K-agent fan-out." Examples: v2.7.2 (load-test fix shipped without re-running L1); v2.19.1 (2 v2.15.0-latent bugs masked behind each other under L3 100-tenant teardown); v2.19.2 (httpx pool exhaustion under L1 1K-agent single-process). The bug class is "concurrency-shaped state that only opens its window at scale."

**Mechanical guidance for `/code` agents:** whenever a `/code` session touches files in `kermit/adapters/`, `kermit/core/runtime_impl.py`, `kermit/core/governance/`, or any module that imports `asyncio.create_task`, `threading.Thread`, `loop.call_soon_threadsafe`, or `ContextVar.set/.reset`, the implementing agent MUST run `make load-l1-smoke && make load-l3-smoke && make load-l4-smoke` as the in-spec acceptance check before `/test`. Three sub-3-minute runs catch the bug class.

**Project lesson lineage:** see `/home/rich/dev/projects/kermit/tasks/lessons.md` L15 (v2.19.1 — pattern noted, masking corollary) and L16 (v2.19.2 — httpx pool exhaustion + the 3rd-recurrence trigger).

## Architectural Triage — Harness vs Consumer

For any project that builds on top of `kermit-harness` (Kermit PA, ATLAS, Keystone agents, future Kermit-based products), every spec session starts with the architectural triage gate **BEFORE** invoking `/plan`.

**Answer in one sentence each:**

1. **What is this work?** (one-line summary)
2. **Would another harness consumer need a different implementation if they wrote it themselves?**
3. **If no → does this belong in the harness or in the consumer?** (almost always: harness)
4. **If split (logic in harness, schema/policy in consumer): write two specs, not one.**

**Skipping this triage is a CLAUDE.md violation.** A consumer-only spec for harness-shaped work needs an explicit "Why this can't wait for the harness" justification.

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

When the harness doesn't yet expose the primitive and waiting blocks user work, the consumer ships it anyway BUT appends an entry to a per-consumer handoff queue file (e.g. `tasks/HARNESS_HANDOFF_QUEUE.md`) before the commit lands. Each entry: feature, where it lives, why it's harness-shaped, migration plan once the primitive ships. The handoff queue makes the technical debt explicit and trackable instead of buried in commit messages. A long Pending list signals that consumer projects are carrying weight that should be upstream.

### Why this rule exists

Without architectural triage at intake, "build it where the bug surfaced" becomes the default — and consumers accumulate slightly-different reimplementations of the same primitives. The Kermit PA April 26 2026 session shipped roughly 40% harness-shaped code in PA before the pattern was caught (recency intent detection, truncation heuristic, in-flight task registry, dedup helpers, cascade delete, async/sync wrap pattern). Every other consumer would have built each one slightly differently. Triage at intake stops the drift.
