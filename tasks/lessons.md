# Lessons Learned

Patterns from corrections. Reviewed at session start. Consolidated into CLAUDE.md rules when 2-3 similar entries emerge.

## Active Lessons

| Date | Lesson | Project | Status |
| ---- | ------ | ------- | ------ |
| 2026-03-18 | Each project needs its own port series — NVR on 8001 conflicted with Kermit | RICH_NVR | → Rule in dev CLAUDE.md |
| 2026-05-08 | Before a "copy artifacts from external system" spec, audit the source. Foundation Spec assumed `~/.claude/keybindings.json` existed (it didn't), assumed `skills/<name>/` subdirs were populated (they were empty), and treated settings.json as commit-ready (it had 3 plaintext DB passwords + 11 junk one-off entries). Reality only surfaces by reading the source path before /code starts. Three deviations approved at /code intake; would have been three commits to fix if caught later. | dev-platform | active |
| 2026-05-08 | install/deploy scripts MUST refuse to clobber real files. install.sh's `link_file` errors when the target is a real (non-symlink) file, forcing the user to back up + remove first. Without this guardrail, the first install of a symlink-based deploy silently destroys user data — the exact failure mode of every "rename your config dir before installing" tool. | dev-platform | active |
| 2026-05-09 | Hook scripts that read external-tool event payloads MUST degrade gracefully on shape change. The R1.5 heartbeat hook reads Claude Code's PostToolUse JSON via `python3 -c '...try/except...'` and falls back to `tool=?` if the payload schema differs from expectation. The schema is unverified at spec time — Claude Code may evolve its event format. Without try/except, a schema bump would break every tool call's hook silently. Pattern: hooks consuming third-party payloads always use defensive parsing, never assume keys exist. | dev-platform | active |
| 2026-05-09 | /docs MUST NOT write commit hashes for the spec being shipped this session. The chicken-and-egg paradox: /docs runs BEFORE the bundled commit (per Docs Before Commit rule) but the hash for that bundled commit doesn't exist until the commit lands. R1 + R1.5 each forced a small backfill commit (e12a008, e0ba399) two days running. Fix landed in commands/docs.md: planning.md "Recently shipped" entries are now hash-free; `git log` is the authoritative hash record. Also fixed in same pass: the /docs Step 5 was telling people to commit docs separately, conflicting with the bundling rule from dev/CLAUDE.md. /docs now only stages — the bundled feat commit takes both. | dev-platform | → Rule in commands/docs.md |
