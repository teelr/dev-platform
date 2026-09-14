# A dependency ask can propose a mechanism that doesn't exist — verify the capability, not just the problem

Issue #120 (a kermit-v3 dependency ask) proposed "have `/plan` set the session's `ListAgents` name." The *problem* it described was real and easy to confirm — `ListAgents` immediately showed this session as a generic `dev-93` next to peers with the same shape. It would have been easy to take the proposed fix at face value and write a spec Change around "`/plan` sets the ListAgents name," since the problem statement checked out.

The mechanism didn't exist: no CLI flag, config, or tool call lets an agent set its own session's display name — only a human running `/rename`, or accepting a plan in Claude Code's own built-in plan mode. A `claude-code-guide` research pass caught this before it was written into the spec.

**Do this:** when an issue (especially a cross-repo dependency ask, which nobody on this side wrote and can't be assumed to have checked our internals) proposes a *specific mechanism* — not just a problem — verify the mechanism is real before scoping a Change around it. A tool named in passing ("have X set Y") is a claim, not a fact. `ToolSearch` for a plausible tool name is a fast first check; if that comes up empty, a targeted research pass (here, `claude-code-guide`) before committing spec scope is cheap insurance against writing a Change that can never be implemented as described.

**The tell:** the issue confirms the *problem* on the first check and you're tempted to move straight to writing the Change. That's exactly the moment to also confirm the *proposed fix* is real, since the two were verified with equal confidence in the issue's own prose but only one of them was actually checked.
