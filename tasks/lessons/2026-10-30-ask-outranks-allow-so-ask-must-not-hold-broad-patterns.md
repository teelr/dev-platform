# An ask rule outranks a narrower allow, so ask must never hold a broad pattern

Claude Code evaluates permission rules deny, then ask, then allow, and the first match wins
regardless of specificity. The first draft of the tightened `settings.json` put `Bash(bash *)`
and `Bash(kill *)` in `ask` to make them prompt, which would also have made the narrow allows
for `bash ~/.claude/worktree/link-deps.sh` prompt on every `/plan` and `/code`. To make a broad
tool prompt while keeping narrow exceptions, drop the broad allow (and retract it from the live
file) and keep the narrow allows; reserve `ask` for patterns with no workflow exception.

A tracked baseline that is union-merged into a live file cannot tighten anything by deleting
lines. Check the live file before assuming a baseline edit takes effect; here it held 320
entries, including every broad one the baseline had just dropped.
