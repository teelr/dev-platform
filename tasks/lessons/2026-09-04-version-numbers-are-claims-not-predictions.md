# A version number is only safe to write once the version is claimed

Seven code comments in `scripts/`, `monitoring/` and `tests/` cited **v1.30** for work that shipped as chore PRs #101 and #102 — chores have no phase version at all. They were written while v1.29 was the newest tag and v1.30 was the obvious next number: a prediction recorded as fact. When v1.30 was later claimed for an unrelated phase, the same string meant two different things in one repo — the exact ambiguity v1.29 had just shipped a rule against, reappearing in code comments a week later.

Cite a phase version only after `claim_roadmap_version.py` has returned it. For a chore, which never gets one, cite the PR number instead.

**Sweep for any version at or beyond the newest tag, not just the one being claimed.** The original sweep grepped `v1.30` — the number then in hand — and therefore missed two more instances that said **`v1.31`**, written by PR #105 as a guess two versions out. They surfaced only when v1.32 came to edit the same files. The grep that finds all of them:

```bash
grep -rn "v1\.3[2-9]\|v1\.[4-9][0-9]" scripts/ monitoring/ tests/ commands/ docs/ CLAUDE.md \
  | grep -v "kermit\|keystone\|harness\|v4\."
```

Adjust the range to "newest tag and above" each time. A prediction is wrong in both directions: the work may never get a phase number at all (chores do not), and the number guessed will belong to something else.
