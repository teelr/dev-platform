---
description: Create a detailed implementation spec for a feature or task. Use when starting new work that needs planning before coding.
argument-hint: "<feature description>"
allowed-tools: Read, Grep, Glob, Write, Bash, WebSearch, WebFetch, TodoWrite, EnterWorktree
---

# Planning Agent

You are a planning agent. Your job is to produce a **self-contained coding specification** that a separate coding agent can execute without any additional context. You do NOT write code — you write the spec.

## Input

The user wants to plan: **$ARGUMENTS**

## Step 1: Gather Context

Read the project's rules and understand the environment:

1. Read `./CLAUDE.md` (project-specific rules — MANDATORY)
2. Read `~/.claude/CLAUDE.md` (global rules — MANDATORY, contains the Language Architecture Decision Matrix)
3. Read `./planning.md` if it exists (development roadmap)
4. Read `./README.md` if it exists (project overview)
5. Scan `tasks/` directory for existing spec files to match their format
6. Check `package.json`, `pyproject.toml`, `Cargo.toml`, or `go.mod` to identify the tech stack

## Step 2: Derive the Feature Slug + Create the Branch (or Worktree)

Do this now, before exploring the codebase — this is the moment you've decided what to build, and claiming an isolated branch here (rather than waiting for `/code`) means two concurrent `/plan` sessions never collide writing `tasks/*.md` or `planning.md` on the same shared branch.

1. Derive the slug from the feature description: kebab-case (e.g. "add image generation" → `image-generation`). This is the same slug used for the spec filename in Step 5 below — derive it once, here, and reuse it.
2. Check the current branch: `git branch --show-current`. If it's already something other than `main` — a prior `/plan` or `/code` already put you on a feature branch or in a worktree this session — skip straight to Step 3. Don't create anything new.
3. If on `main`, this is a new Roadmap Phase — claim its version number atomically instead of reading one and hoping it's free (two concurrent `/plan` sessions can otherwise both read the same "next" number, as happened twice in one afternoon on kermit-v3). First derive a short Title-Cased feature title from the same feature description used for the slug in sub-step 1 (e.g. slug `image-generation` → title "Image Generation") — this exact title is reused verbatim as the milestone title AND, later in Step 5, as the ROADMAP.md `## v<X.Y>: <Title>` header, so the two never drift apart (a title mismatch between them is precisely what `check_version_collision.py` flags as a collision). Then derive the major version from the highest `v<N>.<M>:` Roadmap Phase entry in `ROADMAP.md` — entries appear as either `- **v<N>.<M>: <Title>**` (list form, dev-platform's own convention) or `## v<N>.<M>: <Title>` (heading form); both are valid. (Legacy fallback, for a project whose `ROADMAP.md` has no versioned entries: `planning.md`'s Active Roadmap Phase line, e.g. `**Active Roadmap Phase:** **v1.10 SHIPPED**` → major `1`. Projects with a `tasks/shipped/` directory no longer carry that line at all.) Run:

   ```bash
   python3 /home/rich/dev/scripts/claim_roadmap_version.py "<Title-Cased feature title>" --major <N>
   ```

   This fetches `origin/main`'s `ROADMAP.md` AND every GitHub milestone (open + closed) to find the true highest-claimed minor version, creates the milestone for the next one, and retries forward if another session's milestone appears mid-claim. On success it prints `Claimed v<X.Y> — milestone #<N>: <title>` — parse `v<X.Y>` from that line and use it for the rest of this Step, the branch name, and the spec. **If the script exits non-zero** (no `gh` auth, repo detection failed, or 5 consecutive collisions), STOP and report the error verbatim — do NOT fall back to guessing a version number; that defeats the entire point of claiming it here. A brand-new spec always starts at Phase 1, so the branch name is `v<X.Y>/phase-1-<slug>` using the claimed version.
4. Pick the mode the same way `/code` does:

   ```bash
   test -f .claude/worktree-deps && echo "worktree mode" || echo "branch mode"
   ```

   - **Branch mode** (no marker — the default, including dev-platform itself): `git checkout -b v<X.Y>/phase-1-<slug>`.
   - **Worktree mode** (marker present — opted-in multi-chat projects): call the **`EnterWorktree`** tool with `name` set to `v<X.Y>/phase-1-<slug>`. It creates `.claude/worktrees/v<X.Y>/phase-1-<slug>` off `origin/<default>` and re-roots this session into it — do NOT run `git worktree add` by hand. Then link the project's heavy git-ignored deps:

     ```bash
     bash ~/.claude/worktree/link-deps.sh
     ```

   **Run it exactly as written — no arguments, no variables.** A worktree-isolated
   session's command guard analyses commands statically and refuses any it cannot
   verify stays inside the worktree; `"${HOME}"`, `"${MAIN}"`, `"$(pwd)"` and
   `"${PWD}"` all trip it. Adding arguments back gets the command refused outright
   and the linking step silently never runs. The script derives both paths itself
   for this reason (`shell/worktree/link-deps.sh`).

5. Rename the current tmux window to the slug so the tab tracks the work. **Two
   separate commands, not one** — the guard described in sub-step 4 refuses a
   compound command (`&&`, `||`, `;`) just as it refuses a variable-built path,
   so the one-liner this step used to prescribe was refused outright and the
   rename silently never happened. First check:

   ```bash
   echo "TMUX=${TMUX:-unset}"
   ```

   Then, only if that printed a value other than `unset`, rename:

   ```bash
   tmux rename-window <slug>
   ```

   If it printed `unset`, you are not inside tmux — skip the rename silently. No
   error, no tab rename.

Report the branch/worktree path and (if renamed) the new tmux window name, then continue.

## Step 3: Explore the Codebase

Before proposing ANY changes, search thoroughly:

1. **Grep** for existing implementations related to the feature
2. **Glob** for relevant files by name patterns
3. Identify reusable components, utilities, hooks, or patterns
4. Map the data flow: UI → API → Backend → Database → Response
5. Note exact file paths and line numbers for everything relevant

**Do NOT propose building something that already exists.** Reuse first.

## Step 4: Language Architecture Evaluation

**CRITICAL**: For every new component in the spec, evaluate against the Language Architecture Decision Matrix from `~/.claude/CLAUDE.md`:

- **Network-intensive components** (API gateways, WebSocket handlers, message routers, proxy layers, rate limiting) → **Go**
- **Compute-intensive components** (data transformation, parsing engines, embedding pipelines, real-time audio/video) → **Rust**
- **AI-intensive components** (LLM calls, RAG pipelines, agent logic, document processing, ML workflows) → **Python**
- **UI/Frontend components** → **TypeScript**

Include a "Language Decisions" section in the spec explaining why each new component uses its chosen language. Flag any existing code that violates the matrix as a future refactoring opportunity (but do NOT refactor it in this spec unless requested).

## Step 5: Write the Spec

Create the spec file at `tasks/{slug}-spec.md`, using the same slug derived in Step 2, with this structure.

**Taxonomy (locked in `/home/rich/dev/CLAUDE.md`):** A spec is broken into **Phases**, each Phase contains numbered **Changes**. Change numbering is continuous across the whole spec (Change 1, Change 2, … Change N) — NOT reset per Phase. One Change becomes one commit when implemented. NEVER use the killed terms: "Section", "Task", "Step", "Item", "Sprint", "Stage", "Iteration", "Milestone", "Group", "Epic".

```markdown
# {Feature Name}

## Coding Specification for Implementation

## Design Philosophy

{2-3 paragraphs explaining the approach, constraints, and key decisions. Reference project CLAUDE.md rules.}

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| {component} | {Go/Rust/Python/TypeScript} | {why} |

## Overview

{Numbered list of all Changes, grouped by Phase}

---

## Phase N: {Phase Name}

### Change N: {Change Title}

**Problem:** {What problem does this solve}

**File:** `{exact/file/path.ext}` (new file | existing file line ~NNN)

**Implementation:**

{Detailed description of what to implement. Include code patterns from the existing codebase. Reference exact function names, class names, and line numbers.}

**Acceptance Test:**

{How to verify this change works — curl commands, build checks, UI verification steps}

---

## What NOT to Do

- {Anti-patterns specific to this feature}
- {Common mistakes to avoid}
- {Things that look tempting but violate project rules}

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `path/to/file` | New/Modify | {what changes} |

## Implementation Order

{Numbered list of changes in the order they should be implemented, with dependencies noted}

## Verification Checklist

- [ ] {Each testable acceptance criterion}
- [ ] All builds pass (frontend: `npm run build`, backend: type checks)
- [ ] No hardcoded settings (all config from database/env)
- [ ] No console.log in production code
- [ ] Language architecture matrix followed for all new components
- [ ] End-to-end data flow works: UI → API → Backend → Response → UI
{If this spec touches auth, credentials, external input, or new endpoints:}
- [ ] `/security-review` run before `/gate fast`
```

## Step 6: Verify the Milestone (fallback only)

If Step 2 already claimed a version via `claim_roadmap_version.py` (the normal path for any brand-new Roadmap Phase), its milestone already exists — skip this step entirely.

This step only fires for the two cases Step 2 doesn't cover: (a) a hand-authored spec added to `tasks/` without going through `/plan`'s branch-creation flow, or (b) a later Spec Phase of the SAME Roadmap Phase added via a fresh `/plan` invocation on an EXISTING feature branch. Case (b) should almost never actually find a missing milestone — Change 3's Step 2 already created it when Phase 1 of the same Roadmap Phase ran — so hitting the "no milestone exists" branch below in case (b) is a signal something already drifted, not a normal occurrence.

Derive the version prefix from the spec filename or branch name, then check:

```bash
PREFIX="v<X.Y>"   # substitute actual major.minor
gh api repos/{owner}/{repo}/milestones?state=all \
    --jq ".[] | select(.title | startswith(\"${PREFIX}:\")) | .title"
```

Derive `{owner}/{repo}` from `git remote get-url origin`.

- **If the milestone exists:** note its title and move on.
- **If no milestone exists:** claim one the same race-safe way Step 2 does — do NOT create it directly via `gh api ... POST` (that path has no collision protection, which is the exact bug this spec exists to fix):

```bash
python3 /home/rich/dev/scripts/claim_roadmap_version.py "<Title from spec or ROADMAP.md>" --major <N>
```

`claim_roadmap_version.py` always claims the NEXT free minor version — it does not accept a specific target number. If the branch/spec already commits to an exact `v<X.Y>` that turns out to be missing its milestone, and the script would claim a DIFFERENT number, STOP and report to the user rather than silently claiming a mismatched number under the hood — that mismatch is itself worth a human looking at.

This prevents the "No vX.Y milestone exists" warning that surfaces later at `/pr` time.

## Rules

- Reference exact file paths and line numbers — no vague "somewhere in the codebase"
- Include code patterns copied from existing implementations, not invented patterns
- Every change must have an acceptance test
- The spec must be executable by someone (or an agent) with no additional context
- Do NOT write actual implementation code — write the spec that describes what to implement
- Include a "What NOT to Do" section to prevent common mistakes
- If the project has existing spec files in `tasks/`, match their format and detail level
- Flag any CLAUDE.md rule violations that the feature might accidentally introduce
