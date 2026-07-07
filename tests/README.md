# tests/

Constitutional gate-fast fixtures and per-suite runners. Orchestrated by `scripts/gate_fast.sh`.

**What goes here:** per-suite runners (`tests/<suite>/run.sh` or named single-purpose scripts like `frontmatter.sh`), fixtures (`tests/<suite>/<fixture-name>.{json,md,txt,sh}`), and shared helpers in `tests/helpers/`. Each suite is a directory grouping fixtures + the runner that consumes them; the orchestrator discovers runners by name (`run.sh` or `*.sh` at suite root).

**What does NOT go here:** project tests (those live in each project's own `tests/` directory under `projects/<name>/`); build / integration tests requiring network access, slow installs (npm/pip/go), or running infra (deferred to a future `gate_full.sh` spec); test fixtures for arbitrary internal scripts that don't go through `gate_fast.sh`.

**Deployment:** nothing is deployed from `tests/`. The directory is invoked in-place by `scripts/gate_fast.sh`. Runners source `tests/helpers/assert.sh` for shared `record_pass` / `record_fail` / `record_skip` functions; the orchestrator aggregates the counts.

## Suite layout

```text
tests/
├── README.md                       (this file)
├── helpers/
│   └── assert.sh                   shared PASS/FAIL counters
├── hooks/
│   └── post-tool-heartbeat/
│       ├── run.sh                  fixture suite runner
│       ├── valid.json
│       ├── invalid.json
│       ├── empty.txt
│       └── missing-tool-name.json
├── commands/
│   └── frontmatter.sh              validates commands/*.md frontmatter
├── taxonomy/
│   ├── run.sh
│   ├── conformant-spec.md
│   ├── bad-spec-sprint.md
│   ├── bad-spec-step.md
│   └── legitimate-step.md
├── install/
│   └── run.sh                      install → verify → uninstall round-trip
├── scaffold/
│   └── run.sh                      new-project.sh smoke
└── phase-milestones/
    ├── run.sh                      check-phase-milestones.sh detector (offline mock-gh)
    └── fixtures/mock-bin/gh        mock gh CLI for canned milestone responses
```

## Adding a new suite

Create `tests/<suite>/run.sh` (or single-purpose script) that:

1. Sources `tests/helpers/assert.sh` for `record_pass` / `record_fail` / `record_skip`
2. Runs its checks
3. Returns control without `exit`-ing (the orchestrator decides final exit code based on the global FAIL count)

Then re-run `scripts/gate_fast.sh` — the orchestrator discovers new runners automatically by walking `tests/<suite>/`.
