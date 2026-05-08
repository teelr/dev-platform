# Dev Workflow Manual

## Overview

Four global skills that work across ALL your projects. They inherit workspace-wide standards from `/home/rich/dev/CLAUDE.md` and read each project's `CLAUDE.md` at runtime to adapt to project-specific rules, tech stack, and conventions.

Every new component is evaluated against the **Language Architecture Decision Matrix**:

| Layer | Language | When |
| ----- | -------- | ---- |
| Network-intensive | **Go** | API gateways, WebSocket handlers, message routers, proxy layers, rate limiting |
| Compute-intensive | **Rust** | Embedding pipelines, parsing engines, real-time audio/video, data transformation |
| AI-intensive | **Python** | LLM calls, RAG pipelines, agent logic, document processing |
| UI/Frontend | **TypeScript** | React/Next.js apps, dashboards, browser extensions |

## The Skills

### `/plan` — Planning Agent

Creates a detailed coding spec before any code is written.

**Usage:**

```
/plan add dark mode toggle to the settings panel
/plan rewrite the WebSocket handler in Go for 10K concurrent connections
/plan add PDF annotation support to the document viewer
```

**What it does:**

1. Reads your project's CLAUDE.md and global rules
2. Explores the codebase for existing patterns and reusable code
3. Evaluates each component against the Go/Rust/Python decision matrix
4. Produces a spec file at `tasks/{feature-name}-spec.md`

**What it outputs:**

- Design philosophy and approach
- Language decisions table (which language for each component and why)
- Section-by-section implementation plan with per-task detail, exact file paths and line numbers
- Acceptance tests for every task
- "What NOT to do" section
- File change summary and implementation order
- Verification checklist

**It does NOT write code.** Only the spec.

### `/code` — Coding Agent

Implements a spec file task by task with verification after each step.

**Usage:**

```
/code tasks/dark-mode-spec.md
/code tasks/websocket-go-rewrite-spec.md
```

**What it does:**

1. Reads the spec file
2. Creates a todo list from the spec's sections and tasks
3. Implements each task exactly as described
4. Runs build/typecheck/tests after each change
5. Flags any deviations from the spec

**Key behavior:**

- Follows the spec literally — doesn't improvise or add features
- If the spec is wrong, it stops and tells you instead of silently working around it
- Verifies every change before moving on
- Won't commit unless you explicitly ask

### `/test` — Testing & QC Agent

Validates that an implementation matches its spec and follows all rules.

**Usage:**

```
/test tasks/dark-mode-spec.md
/test tasks/websocket-go-rewrite-spec.md
```

**What it does:**

1. Reads the spec's verification checklist
2. Checks every file in the spec's change summary
3. Runs every acceptance test
4. Checks CLAUDE.md compliance
5. Verifies language architecture decisions
6. Produces a QC report with PASS/FAIL/WARNING per check

**What it outputs:**

A structured QC report with:
- Per-change results (file exists, implementation correct, test passes)
- Standard checks (build, compliance, architecture, code quality, E2E flow)
- Failures that must be fixed
- Warnings that should be fixed
- Recommended next steps

**It does NOT fix issues.** Only reports them. Run `/code` again to fix.

### `/review` — Pre-Commit Code Review

Reviews staged git changes before committing.

**Usage:**

```
/review
```

No arguments needed — it reads your staged git diff automatically.

**What it checks:**

- **SECURITY** — secrets in code, injection, missing auth, XSS
- **BUG** — off-by-one, race conditions, null checks, logic errors
- **ARCHITECTURE** — wrong language for the component type
- **COMPLIANCE** — CLAUDE.md rule violations
- **QUALITY** — unused imports, dead code, inconsistent patterns

**Verdict:**

- APPROVE — good to commit
- APPROVE WITH COMMENTS — minor suggestions, safe to commit
- REQUEST CHANGES — must fix before committing

## Workflow: Full Feature Development

The standard workflow for any feature across any project:

### Step 1: Plan

```
/plan <describe what you want to build>
```

Review the spec at `tasks/{feature}-spec.md`. Edit it if needed.

### Step 2: Code

```
/code tasks/{feature}-spec.md
```

Watch it implement task by task. It will flag any spec issues.

### Step 3: Test

```
/test tasks/{feature}-spec.md
```

Review the QC report. If there are failures, go back to Step 2.

### Step 4: Review

```
/review
```

Stage your changes (`git add`), then run review. Fix any SECURITY or BUG issues.

### Step 5: Commit

Once `/review` gives APPROVE, commit normally.

### Step 6: Push

Push to GitHub. Create a PR if on a feature branch.

## Workflow: Quick Fix (No Spec Needed)

For small bug fixes or trivial changes, skip the spec:

1. Make the fix directly
2. Run `/review` before committing
3. Commit

## Workflow: Existing Codebase Audit

To check an existing project for architecture violations:

```
/review
```

This will flag Python code that should be Go (network-intensive) or Rust (compute-intensive).

## Adding to a New Project

These skills work automatically in any project. For best results:

1. **Create a `CLAUDE.md`** in your project root with project-specific rules
2. **Create a `tasks/` directory** for spec files
3. That's it — the skills detect everything else from your project's files

### Recommended CLAUDE.md Sections

```markdown
# Project Name

## Tech Stack
{languages, frameworks, databases}

## Architecture
{how the system is structured}

## Port Assignments
{if applicable}

## Development Rules
{project-specific coding rules}

## Patterns
{established patterns to follow}
```

## File Locations

```text
~/.claude/CLAUDE.md                    ← Claude behavior (response style, feedback loop)
~/.claude/commands/plan.md             ← /plan skill definition
~/.claude/commands/code.md             ← /code skill definition
~/.claude/commands/test.md             ← /test skill definition
~/.claude/commands/review.md           ← /review skill definition
~/.claude/skills/WORKFLOW_MANUAL.md    ← This file

/home/rich/dev/CLAUDE.md               ← Development standards (THE source of truth)
./CLAUDE.md                            ← Project-specific rules (per project)
./tasks/                               ← Spec files (per project)
```

## Tips

- **Always start with `/plan`** for anything non-trivial. The spec catches issues before code is written.
- **Trust the spec.** If `/code` flags a deviation, it's usually the spec that needs updating, not the code that should silently deviate.
- **Run `/review` before every commit**, even small ones. It catches things you'll miss.
- **The Language Architecture Matrix is enforced everywhere.** If you're starting a new service that handles network traffic, the skills will tell you to write it in Go.
- **Skills adapt to each project.** The same `/plan` produces Python-focused specs for an AI project and TypeScript-focused specs for a web app.
