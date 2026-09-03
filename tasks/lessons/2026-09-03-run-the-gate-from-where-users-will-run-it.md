# Run the gate from every location it will actually be run from

v1.25 made the `~/.claude` deployment always track the main checkout, and shipped a suite proving `install.sh`/`verify.sh` behave correctly from a worktree. It still left the gate red from a worktree: four suites asserted symlink targets against their own `${REPO}`, which is correct from the main checkout and wrong from a worktree. Nothing caught it because every v1.25 gate run was from main, CI runs from a fresh clone, and the one worktree gate run afterwards was a docs-only diff — so v1.14's docs-only skip meant those four suites never executed.

Two things to do differently. When a change alters what a path resolves to, run the whole gate from each location that resolution differs in, not just the tests for the changed scripts. And treat a green gate whose output is mostly SKIP as unverified: 6 PASS / 29 SKIP looked like success and proved nothing about the suites that mattered.
