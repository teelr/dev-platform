# A version number is only safe to write once the version is claimed

Seven code comments in `scripts/`, `monitoring/` and `tests/` cited **v1.30** for work that shipped as chore PRs #101 and #102 — chores have no phase version at all. They were written while v1.29 was the newest tag and v1.30 was the obvious next number: a prediction recorded as fact. When v1.30 was later claimed for an unrelated phase, the same string meant two different things in one repo — the exact ambiguity v1.29 had just shipped a rule against, reappearing in code comments a week later.

Cite a phase version only after `claim_roadmap_version.py` has returned it. For a chore, which never gets one, cite the PR number instead. `grep -rn "v<next>" scripts/ monitoring/ tests/ CLAUDE.md` before claiming a version catches this in one command — the collision is invisible until the number is taken.
