# monitoring/

Workflow-effectiveness telemetry. Track gate pass rate, `/code` retry counts, `/review` catch rate, hook execution time per project, drift between tracked and deployed config.

**What goes here:** schema definitions (`schemas/*.json` describing event shapes), collector configuration (`collectors/*.md` describing where each metric is captured — hook? slash command? gate runner?), and report templates (`reports/daily.md`, `reports/weekly.md`).

**What does NOT go here:** the collector implementations themselves (those will live in `hooks/` if they ride a hook event, or as standalone scripts in `scripts/` if they aggregate); per-project metrics (each project tracks its own).

**Deployment:** future spec (`dev-platform-monitoring-spec.md`, R2 on the roadmap). For now this directory exists as a contract so the schema design doesn't drift across the foundation, monitoring, and testing specs.
