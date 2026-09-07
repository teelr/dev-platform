# Testing a shared helper is not testing that callers use it

`tests/fleet-worktree/run.sh` had eight checks proving `main_checkout.sh` and
`main_checkout.py` resolve a worktree to the main checkout, plus two end-to-end
checks against `fleet_pins.py`. It went green while `audit-project-drift.sh` and
`migrate-workflow-chain.sh` never called the helper at all — both still built
`projects/<name>` from their own file location, so from a worktree the audit
reported every consumer as `NO_CLAUDE_MD / DRIFT`, and I relayed that as a real
finding about SQRL before checking it.

The v1.27 sweep that extracted the helper fixed five scripts and wrote the suite
around the two helpers it had just created. That framing is the trap: the suite
asserts the primitive is correct, which was never in doubt after the fix, and
says nothing about the population of callers, which is where the bug lives and
where new ones arrive.

**Do this:** when a fix extracts a shared helper, the test that proves the helper
works is table stakes. Add one check per *caller*, exercising it end-to-end from
the broken environment — and verify each fails when you revert that caller alone.
Both checks here caught their own script's mutation and stayed green for the
other, which is what says they discriminate rather than sharing one trigger.

The tell that a suite has this shape: every assertion names the helper, none
names a consumer. Grep the registry-consuming scripts for the helper's own name;
any that never mention it are untested no matter how green the suite is.
