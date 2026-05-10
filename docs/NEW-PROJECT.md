# Creating a New Project

When you ask the assistant to create a new project, this is what happens. The assistant runs `scripts/new-project.sh` from `/home/rich/dev/`; you describe what you want, and the assistant fills in the rest by following the Q&A pattern below.

## What the assistant asks before running

The assistant asks a short Q&A — typically four questions — before invoking the script:

### 1. Project name

Derived from your description, but confirmed before the script runs. Validation rules (enforced by `new-project.sh`):

- alphanumeric + dash + underscore only — no slashes, dots, or spaces
- must NOT already exist under `/home/rich/dev/projects/`

If the name conflicts with an existing project or violates the rules, the assistant pushes back before running.

### 2. Description (one sentence)

Drives the template choice via the **Language Architecture Decision Matrix** in `/home/rich/dev/CLAUDE.md`. The assistant proposes a template and explains why; pushback is expected if the proposal doesn't match your intent.

| Signal in your description | Template |
| -------------------------- | -------- |
| API gateway / WebSocket / proxy / many concurrent connections / "fast" service / health monitor | `go-service` |
| LLM call / RAG / agent / MCP server / document processing / kermit-harness consumer | `python-agent` |
| Browser UI / dashboard / web app / "frontend" / Next.js | `next-frontend` |
| Compute-heavy CLI / parsing engine / embedding pipeline / audio/video | (no template yet — `rust-cli` is R4-future) |
| Mixed | Split into multiple projects: one per concern. Don't bundle network and AI into one Python service. |

Anti-patterns the assistant pushes back on:

- "It would be easier in Python" for a 1000+ concurrent-connections handler → recommends Go
- "We can do everything in one Next.js app" for a service that's mostly LLM/agent work → recommends a separate `python-agent`

### 3. Port (if a service)

Picked from the **Port Allocation Registry** in `/home/rich/dev/CLAUDE.md`. The assistant proposes the next available series; you confirm or override.

The script writes `{{PORT}}` as a placeholder — the substitution happens AFTER the scaffold lands, as a manual second pass. Why two-phase: ports come from a hand-maintained registry, and auto-allocation would be fragile.

After scaffold, the assistant walks you through substituting the port across the relevant files (the post-scaffold checklist below lists them).

### 4. GitHub repo (public, private, or skip)

Opt-in. Default behavior: local scaffold + git init only. If you say yes:

- `--gh-repo public` → public repo on GitHub
- `--gh-repo private` → private repo
- The script runs `gh repo create teelr/<name> --<visibility> --source=. --push`

If you say no, the script stops at local git init. You can always run `gh repo create` later by hand.

## What the assistant does after the script runs

The script prints a next-steps checklist; the assistant walks you through it:

1. **Substitute the `{{PORT}}` placeholder.** The script's output lists every file containing `{{PORT}}`. Pick the port from the registry, then either:
   - Use `sed -i "s/{{PORT}}/<port>/g"` across the listed files, or
   - Edit each file by hand if you want different ports for different files (e.g., dev vs prod).
2. **Register the port in `/home/rich/dev/CLAUDE.md` Port Allocation Registry.** This is a separate commit IN THE DEV-PLATFORM REPO, not in the new project's repo. The dev-platform commit captures the new port assignment so it's never reused.
3. **Per-language install step** (template-specific):
   - **`go-service`** — `new-project.sh` now runs `go mod tidy` automatically post-scaffold to generate `go.sum`. After scaffold, `go build ./...` works directly. If you didn't have `go` on PATH at scaffold time, run `go mod tidy` manually before `go build`.
   - **`python-agent`** — `kermit-harness` is a private dependency, NOT on public PyPI. After scaffold:

     ```bash
     cd /home/rich/dev/projects/<name>/
     python3.11 -m venv .venv && source .venv/bin/activate
     # Install kermit-harness from local repo (editable):
     pip install -e /home/rich/dev/projects/kermit/
     # Then install this project + dev deps:
     pip install -e ".[dev]"
     ```

     Without that local install, `pip install -e ".[dev]"` will fail to resolve the harness pin. The pin in `pyproject.toml` is intentional per the Architectural Triage rule (every harness consumer MUST formally declare the dependency).
   - **`next-frontend`** — `npm install` runs automatically on first `bash scripts/start_dev.sh` (the script checks for `node_modules/` and installs if absent). To install eagerly: `cd <project>/ && npm install`.
4. **Run `scripts/gate_fast.sh` in the new project to confirm baseline.** This validates the scaffold works: build passes, lint passes, taxonomy check passes. If `gate_fast.sh` fails on a fresh scaffold, the template has a bug — file an issue.
5. **`/plan` the project's first spec.** Switch to the project's working directory (`cd /home/rich/dev/projects/<name>/`) and start a new Claude Code session there. Per the Scope rule, dev-platform sessions don't continue working IN the new project after scaffold.

## Scope-rule carve-out: what the assistant won't do

The Scope rule in `/home/rich/dev/CLAUDE.md` says the assistant must NOT modify files under `projects/` from a dev-platform session. `new-project.sh` is the explicit exception — scaffolding a new project IS a dev-platform action because it uses dev-platform tools and templates.

But the carve-out is **bootstrap-only**, not a back door:

- The assistant **will not** continue working in the new project from this dev-platform session. Once the scaffold lands, the next request to modify the project means: switch directories, start a new Claude Code session there.
- The assistant **will not** pre-write project-specific code beyond what the template ships. The template gives you the SHAPE; the project's first feature spec writes the actual code.
- The assistant **will not** unilaterally pick the port if the registry has a contention; it asks you to choose.
- The assistant **will not** auto-create a GitHub repo without `--gh-repo`. Default is local-only.

## Refuse-to-clobber

If `projects/<name>/` already exists, the script errors with a clear message and exits non-zero. It never overwrites an existing project. To "redo" a scaffold for an existing project name, back up + remove the existing tree first.

## Available templates

See `scaffolding/<template-name>/README.md` for per-template specifics. As of R4a:

- `scaffolding/go-service/` — Go HTTP service skeleton (chi router, slog logging, distroless Docker image)
- `scaffolding/python-agent/` — Python kermit-harness agent skeleton (pyproject.toml with harness pin, pytest setup, ruff/mypy)
- `scaffolding/next-frontend/` — Next.js 16 + Tailwind 4 + TypeScript skeleton (App Router, strict TS)

Future R4 work may add `rust-cli`, `python-service` (FastAPI without the harness), or others. Each template is added when a real project surfaces the need — never speculatively.
