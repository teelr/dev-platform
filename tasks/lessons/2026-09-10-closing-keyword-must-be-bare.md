# A GitHub closing keyword must be bare — "Closes issue #N" doesn't auto-close

Wrote a squash commit trailer as "Closes issue #118: ..." intending to auto-close it on merge. GitHub's closing-keyword grammar only recognizes the keyword immediately followed by the bare reference (`Closes #118`, optionally `Closes: #118`) — inserting a word like "issue" breaks the match silently. No error, no warning; the PR just merges and the issue stays open with nothing pointing at what happened.

The mistake came from over-applying CLAUDE.md's citation rule ("every `#<number>` carries a type word — `issue #383`, never bare `#384`") to a context that rule was never meant to cover. That rule governs prose a human reads; GitHub's closing keyword is a literal token GitHub's parser matches, not prose. Checked this repo's own history before writing this lesson: past commits already used the correct bare form consistently (`Closes #77`, `Closes #75:`, `Closes #50:`) — so this was a one-off deviation from an established, correct convention, not a rule that needed fixing.

**Do this:** when a commit or PR body needs to trigger GitHub's auto-close, write the keyword bare — `Closes #118`, `Fixes #118` — with no word between the keyword and the `#`. The type-word citation rule still applies everywhere else that same issue gets mentioned in the same text (a PR body's Summary section, a spec's Design Philosophy) — it just doesn't apply to the literal keyword token itself.

**The tell that it silently failed:** the issue stays open after merge with zero comments and no linked-PR reference in its sidebar. If that's expected, verify it actually happened — `gh issue view <N> --json state,closedAt` — rather than trusting the merged commit message's wording.
