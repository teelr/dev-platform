# "The file this merge added" quietly assumed there is only one

`/merge`'s Change Summary said to run `git diff HEAD~1 --name-only -- tasks/shipped/`
and use "the file this merge added". `/code` writes exactly one shipped file per
phase, so that held for every merge anyone had run — until kermit-harness merged
its `tasks/shipped/` adoption, which added fourteen. Followed literally, a docs
migration merged 2026-09-07 would have been reported as `v4.24.0`, shipped
2026-05-23. `teelr/dev-platform#115`, found by the consumer, not by us.

The tell is a runbook noun phrase in the singular where the command behind it
returns a list. `git diff --name-only` is a list; "the file" is a claim about its
length that nothing checks. Grepping the runbooks for that shape — a singular
noun fed by a plural command — finds these before a consumer does.

Ran that sweep across `commands/*.md` while fixing this one; no second live
instance. Two near-misses worth knowing: `commands/pr.md:44` reads "if a spec
file is in the diff … read it" off a `grep` that can match several, but then
selects by the branch's `phase-N-` slug, so the plural case resolves correctly —
that filter is what `/merge` lacked. `commands/merge.md:184` says "the spec" for
Tier 2 with no such filter, but it is a fallback tier and picking among several
touched specs degrades to a vaguer summary rather than a wrong one.

What makes this class hard is *when* it fires. The plural case only arises during
adoption, and adoption happens exactly once per project, on a merge that is
usually a boring docs migration nobody reads the summary of. So the common path
gets exercised hundreds of times and the broken path once, quietly, per repo.
When a rule has a one-time branch, that branch deserves the explicit sentence,
because it will never earn attention by frequency.

Fixed by making Tier 1 conditional on the diff returning exactly one file and
falling through to Tier 2 otherwise — degrading to a vaguer but true summary
beats a precise and wrong one. The same sentence existed in three places
(`commands/merge.md`, `CLAUDE.md`, `settings/claude-global.md`); all three were
corrected together, per the Derivation Sweep rule, which applies to prose stating
one rule in several files just as it does to scripts deriving one value.

No checker was added. `/merge` is a runbook an agent follows, so a grep asserting
the guard's wording would pass forever while saying nothing about whether a real
summary was right — the same reasoning that deliberately left the Identifier
Descriptors rule uncheckered.
