# check_spec_taxonomy.sh skips the roadmap scan entirely when tasks/ is absent

`scripts/check_spec_taxonomy.sh:39` exits 0 with "no tasks/ directory — skipping" before the roadmap pass runs. So a repo with a `ROADMAP.md` full of killed-term headers but no `tasks/` directory passes the check having scanned nothing, and the reusable workflow reports success to the consumer.

Found while verifying v1.31's CI invocation shape — the probe returned rc=0 where it should have failed, and the cause was the fixture lacking `tasks/`, not the change under test. Surveyed the fleet: all seven consumers have `tasks/`, so this is latent, not live, and it was left unfixed as out of v1.31's scope. Fix it by moving the roadmap pass above the early exit, or by exiting only when both `tasks/` and every roadmap candidate are missing.
