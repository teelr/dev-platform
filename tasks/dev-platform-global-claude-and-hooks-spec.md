# Global Claude + Hooks Coverage (R1.5)

## Coding Specification for Implementation

## Design Philosophy

R1 Foundation made `/home/rich/dev/` the canonical source of truth for the dev workflow, language standards, and shared environment elements (commit `957e030`). The Scope + Consistency rules added on top of that (`8b52a41`) declared the policy: dev-platform drives every layer below it. R1.5 closes the last two gaps under that policy: (a) the apex Claude behavior layer at `~/.claude/CLAUDE.md` is currently NOT tracked — it lives independently and can drift from any source-of-truth control; (b) `dev/hooks/` ships only a README contract — no actual hook scripts exist, so the deployment path for hooks is unproven.

This spec tracks the global Claude file as `dev/settings/claude-global.md` (deployed via symlink to `~/.claude/CLAUDE.md`) and ships the first concrete hook script: a PostToolUse heartbeat that appends timestamped tool-call entries to a log file. The heartbeat is intentionally minimal — its job is to validate the hook deployment pipeline (script in `dev/hooks/`, path declaration in `dev/settings/settings.json`, symlink via `install.sh`, verification via `verify.sh`) and to provide the data foundation that R2 Monitoring will later aggregate.

No new infrastructure: every change rides on the symlink-based deploy mechanism R1 already built. The live cutover follows the same pattern as R1 (backup → delete original → install → verify) and accepts the same residual risk: Claude Code may have loaded `~/.claude/CLAUDE.md` at session start and won't re-read the file mid-session, so the symlink is "in place" but its content takes effect on next session. Acceptable — R1's `~/.claude/settings.json` cutover had the same property.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `claude-global.md` | Markdown | Tracked copy of `~/.claude/CLAUDE.md` (Claude Code config format) |
| `post-tool-heartbeat.sh` | Bash | Portable shell hook script; reads stdin JSON, writes log line, exits 0 |
| `settings.json` hooks block | JSON | Claude Code config format (existing) |
| `install.sh` / `verify.sh` extensions | Bash | Existing scripts; minor function-level edits |

## Overview

1. **Phase 1:** Track global Claude behavior layer (Changes 1–4)
2. **Phase 2:** Ship first hook + settings wiring (Changes 5–6)
3. **Phase 3:** Cutover + docs (Changes 7–9)

**Demo:** `~/.claude/CLAUDE.md` is a symlink pointing at `/home/rich/dev/settings/claude-global.md`. After a Bash tool call, `~/.claude/dev-platform-telemetry.log` has a new line `<timestamp> tool=Bash`. `verify.sh` exits 0 with all 12 symlinks healthy (was 11 — adds one for the global Claude file; the heartbeat hook adds the 13th).

---

## Phase 1: Track Global Claude Behavior

### Change 1: Copy `~/.claude/CLAUDE.md` into `dev/settings/claude-global.md`

**Problem:** `~/.claude/CLAUDE.md` (the apex Claude behavior layer that loads into every Claude Code session, dev or not) is currently not tracked anywhere. Per the gateway rule (`dev/CLAUDE.md` → "Scope" + "Primary gateway"), every layer below dev-platform must be driven from dev-platform; this is the highest-impact gap.

**File:** `dev/settings/claude-global.md` (new)

**Implementation:**

```bash
cp ~/.claude/CLAUDE.md /home/rich/dev/settings/claude-global.md
```

**Acceptance test:** `diff -q ~/.claude/CLAUDE.md /home/rich/dev/settings/claude-global.md` exits 0 (byte-identical).

After this change, the source of truth is `dev/settings/claude-global.md`. The original `~/.claude/CLAUDE.md` will be replaced with a symlink in Change 8 (cutover). Until then, both copies exist and are identical — no behavior change.

**Naming rationale:** `settings/` is "anything Claude Code reads at startup" (already houses `settings.json`, `settings.local.json`, future `keybindings.json`). The lowercase `claude-global.md` distinguishes the source-of-truth file from the deployed `~/.claude/CLAUDE.md`. This keeps `dev/CLAUDE.md` (the workspace standards file, 44 KB) unambiguously distinct from the global behavior layer (6 KB).

### Change 2: Extend `install.sh` `install_settings()` to symlink `claude-global.md`

**Problem:** `install.sh` currently symlinks `settings.json` (always) plus `keybindings.json` and `settings.local.json` (if present). It does not yet handle `claude-global.md`. Without this extension, the file in `dev/settings/` stays disconnected from `~/.claude/CLAUDE.md`.

**File:** `dev/scripts/install.sh` (existing — modify `install_settings()` function around lines 91–105)

**Implementation:**

Inside `install_settings()`, after the existing `settings.json` link line and before the optional `keybindings.json` block, add:

```bash
link_file "${REPO}/settings/claude-global.md" "${HOME_CLAUDE}/CLAUDE.md"
linked="${linked}, claude-global.md"
```

The `link_file` helper already refuses to clobber a real file (added in R1 — see `install.sh:42-51`). So if `~/.claude/CLAUDE.md` is still a real file at first install, the script errors out cleanly with the standard "back up and remove" message.

Final order inside `install_settings()`:
1. `settings.json` (always)
2. `claude-global.md` → `~/.claude/CLAUDE.md` (always, NEW)
3. `keybindings.json` (if present)
4. `settings.local.json` (if present)

**Acceptance test:** Round-trip on a fake `$HOME`:
```bash
FAKE=$(mktemp -d /tmp/r15-c2.XXX)
HOME="$FAKE" bash dev/scripts/install.sh settings
ls -la "$FAKE/.claude/CLAUDE.md"  # must be a symlink to dev/settings/claude-global.md
readlink -f "$FAKE/.claude/CLAUDE.md" | grep -q "/home/rich/dev/settings/claude-global.md"
rm -rf "$FAKE"
```

### Change 3: Extend `verify.sh` to check the new symlink

**Problem:** `verify.sh` currently verifies `settings.json`, optional `keybindings.json`, and optional `settings.local.json`. It does not check `claude-global.md` → `~/.claude/CLAUDE.md`. Without this, drift in the global Claude file would go undetected by `gate fast`-equivalent constitutional checks.

**File:** `dev/scripts/verify.sh` (existing — modify the "Verifying settings..." block around lines 57–64)

**Implementation:**

Inside the `Verifying settings...` block, after the existing `settings.json` check and before the optional `keybindings.json` block, add:

```bash
check_symlink "${REPO}/settings/claude-global.md" "${HOME_CLAUDE}/CLAUDE.md"
```

This follows the existing pattern; no new helper functions needed.

**Acceptance test:** After a successful install, `verify.sh` exits 0 with one additional `OK` line (`OK ~/.claude/CLAUDE.md`).

### Change 4: Update `dev/settings/README.md` to document the file + two-tier model

**Problem:** `settings/README.md` lists `settings.json`, `keybindings.json`, and `*.local.json` as the tracked files. It does not mention `claude-global.md`. A future reader (or future-Rich) needs to understand: (a) the file exists, (b) what it deploys to, (c) how it relates to the workspace `dev/CLAUDE.md`.

**File:** `dev/settings/README.md` (existing — modify "## Files" section around lines 5–9)

**Implementation:**

Add a new bullet to the Files section:

```markdown
- `claude-global.md` — global Claude Code behavior layer, deployed to `~/.claude/CLAUDE.md`. Loads into every Claude Code session, INCLUDING sessions outside `/home/rich/dev/`. Distinct from `/home/rich/dev/CLAUDE.md` which is the workspace dev-standards file (loads only when working under `/home/rich/dev/`). Two-tier model: `claude-global.md` for tool behavior, `dev/CLAUDE.md` for development standards.
```

Also add a one-line note in the "## Editing" section:

```markdown
Editing `claude-global.md` affects Claude Code's behavior in EVERY session. The change takes effect on next session start (Claude Code reads CLAUDE.md once at startup, doesn't re-read mid-session).
```

**Acceptance test:** Read the README; the two-tier model is described in plain language so a new reader understands which file to edit for what.

---

## Phase 2: Ship First Hook + Settings Wiring

### Change 5: Write `dev/hooks/post-tool-heartbeat.sh`

**Problem:** `dev/hooks/` contains only `README.md` (the directory contract). No actual hook scripts exist, so the hook deployment path (script → symlink → settings.json → Claude Code event invocation) is unvalidated. The first hook script doubles as a deployment-path validator AND the data-source foundation for R2 Monitoring.

**File:** `dev/hooks/post-tool-heartbeat.sh` (new, executable — `chmod +x`)

**Implementation:**

```bash
#!/usr/bin/env bash
# PostToolUse heartbeat — appends one telemetry line per tool call to a log
# file. Foundation for R2 Monitoring (gate-pass rate, /code retry count,
# /review catch rate aggregation). Trivially safe: writes to log, exits 0,
# never blocks. Reads Claude Code's PostToolUse event JSON from stdin and
# extracts the tool name; degrades gracefully to 'tool=?' on parse failure.

set -euo pipefail

LOG="${HOME}/.claude/dev-platform-telemetry.log"
mkdir -p "$(dirname "${LOG}")"

# Read event payload (best-effort; never error)
event_json="$(cat 2>/dev/null || echo '{}')"

# Extract tool name from PostToolUse payload (degrade gracefully if shape differs)
tool_name="$(echo "${event_json}" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get("tool_name", "?"))
except Exception:
    print("?")
' 2>/dev/null || echo "?")"

# One-line entry: ISO-8601 timestamp + tool name
echo "$(date -Iseconds) tool=${tool_name}" >> "${LOG}"

exit 0
```

**Why PostToolUse, not PreToolUse:** PostToolUse can never block a tool call (the action already happened). A telemetry-grade hook should never have the power to break a session. Pre is reserved for hooks that genuinely need to gate behavior.

**Why a Python one-liner for JSON parsing instead of `jq`:** Python is in `additionalDirectories` allowlist already; `jq` is not guaranteed installed across all of Rich's machines. The Python invocation is wrapped in `try/except` so a malformed payload yields `?`, never an error.

**Acceptance test:**

```bash
# 1. Make executable
chmod +x dev/hooks/post-tool-heartbeat.sh

# 2. Smoke-test the script directly
echo '{"tool_name":"Bash"}' | bash dev/hooks/post-tool-heartbeat.sh
tail -1 ~/.claude/dev-platform-telemetry.log
# Expected: <ISO timestamp> tool=Bash

# 3. Test graceful degradation
echo 'not json' | bash dev/hooks/post-tool-heartbeat.sh
tail -1 ~/.claude/dev-platform-telemetry.log
# Expected: <ISO timestamp> tool=?
```

### Change 6: Add `hooks` block to `dev/settings/settings.json`

**Problem:** `dev/settings/settings.json` currently has no `hooks` key. The hook script in Change 5 will be deployed by `install_hooks()` to `~/.claude/hooks/post-tool-heartbeat.sh`, but Claude Code won't invoke it until `settings.json` declares the registration.

**File:** `dev/settings/settings.json` (existing — add `hooks` key)

**Implementation:**

Add a `hooks` block inside the top-level object, after `"deny"` / `"additionalDirectories"` and before `"enabledPlugins"`. Wait — the current `permissions` block contains `allow`, `deny`, `additionalDirectories`. The `hooks` block is OUTSIDE `permissions`. Place it as a sibling of `permissions`:

```json
{
  "permissions": { ... existing ... },
  "hooks": {
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/rich/.claude/hooks/post-tool-heartbeat.sh"
          }
        ]
      }
    ]
  },
  "enabledPlugins": {},
  "extraKnownMarketplaces": {}
}
```

**Path style decision (Decision 3):** Absolute path `/home/rich/.claude/hooks/post-tool-heartbeat.sh`. Matches the existing `additionalDirectories` style in this file; no env-var-expansion uncertainty. Hardcoded to Rich's `$HOME` is acceptable because Rich uses `/home/rich/` consistently across machines.

**Acceptance test:**

```bash
# Validate JSON
python3 -c "import json; json.load(open('dev/settings/settings.json'))"
# Expected: silent success

# Confirm hooks key + path
python3 -c "
import json
d = json.load(open('dev/settings/settings.json'))
assert 'hooks' in d, 'hooks key missing'
assert d['hooks']['PostToolUse'][0]['hooks'][0]['command'] == '/home/rich/.claude/hooks/post-tool-heartbeat.sh'
print('OK')
"
```

After install + Claude Code session restart, the hook should fire on tool calls and append lines to `~/.claude/dev-platform-telemetry.log`.

---

## Phase 3: Docs + Cutover

### Change 7: Update `dev/CLAUDE.md` "Belongs here" list

**Problem:** The Scope rule's "Belongs here:" list (`dev/CLAUDE.md` ~lines 9–13) implicitly covers `claude-global.md` under "Settings (`settings/`)" but doesn't make the global Claude behavior layer explicit. After R1.5 ships, the gateway rule should call out the apex behavior layer by name so the policy and the implementation match.

**File:** `dev/CLAUDE.md` (existing — modify the Scope rule's "Belongs here:" section)

**Implementation:**

Update the existing line:
```markdown
- Rules (`CLAUDE.md`), slash commands (`commands/`), skills (`skills/`), hooks (`hooks/`), settings (`settings/`)
```

to:
```markdown
- Rules (`CLAUDE.md` for workspace dev standards, `settings/claude-global.md` for global Claude behavior), slash commands (`commands/`), skills (`skills/`), hooks (`hooks/`), settings (`settings/`)
```

**Acceptance test:** Read the updated section; the two-tier CLAUDE.md model is visible in the gateway rule's belongs-here list, not just buried in `settings/README.md`.

### Change 8: Round-trip on fake `$HOME`

**Problem:** Before touching the real `~/.claude/CLAUDE.md`, the install + verify must demonstrate clean behavior on a throwaway fixture. R1 followed this same pattern; R1.5 follows it identically.

**File:** none (procedural verification)

**Implementation:**

```bash
FAKE=$(mktemp -d /tmp/r15-roundtrip.XXX)
echo "FAKE=$FAKE"

# Pre-populate: simulate a real ~/.claude/CLAUDE.md to test refuse-to-clobber
mkdir -p "$FAKE/.claude"
# (skip pre-population; testing fresh install path first)

# Round-trip
HOME="$FAKE" bash dev/scripts/install.sh
HOME="$FAKE" bash dev/scripts/verify.sh                       # expect exit 0
HOME="$FAKE" bash dev/scripts/uninstall.sh
HOME="$FAKE" bash dev/scripts/verify.sh                       # expect exit 1 (drift)
HOME="$FAKE" bash dev/scripts/install.sh                      # idempotent reinstall
HOME="$FAKE" bash dev/scripts/verify.sh                       # expect exit 0

# Refuse-to-clobber test
HOME="$FAKE" bash dev/scripts/uninstall.sh
echo "real content" > "$FAKE/.claude/CLAUDE.md"
HOME="$FAKE" bash dev/scripts/install.sh                      # expect exit 1 with clobber-refusal error
cat "$FAKE/.claude/CLAUDE.md"                                 # expect "real content" (unchanged)

rm -rf "$FAKE"
```

**Acceptance test:** All steps behave as expected (exit codes match, refuse-to-clobber preserves real file).

### Change 9: Live cutover against `~/.claude/CLAUDE.md`

**Problem:** The original `~/.claude/CLAUDE.md` is still a real file. To complete the deployment, it must be backed up, deleted, and replaced with the symlink that `install.sh` produces.

**File:** none (procedural — the actual user environment)

**Implementation:**

```bash
# Backup
BACKUP=~/.claude/r15-pre-cutover.backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP"
cp ~/.claude/CLAUDE.md "$BACKUP/"
ls "$BACKUP/"

# Delete original (forces install.sh to create the symlink)
rm ~/.claude/CLAUDE.md

# Install
bash /home/rich/dev/scripts/install.sh

# Verify
bash /home/rich/dev/scripts/verify.sh                         # expect exit 0, 13 OK lines
ls -la ~/.claude/CLAUDE.md                                    # expect symlink → dev/settings/claude-global.md
readlink -f ~/.claude/CLAUDE.md
# Expected: /home/rich/dev/settings/claude-global.md

# Confirm hook is deployed
ls -la ~/.claude/hooks/post-tool-heartbeat.sh                 # expect symlink
```

**Acceptance test (post-cutover):**

1. `verify.sh` exits 0 with 13 `OK` lines (R1's 11 + new global CLAUDE.md + new hook script).
2. The current Claude Code session is unaffected (it loaded `~/.claude/CLAUDE.md` at session start; symlink replacement mid-session is transparent because content is byte-identical).
3. On next Claude Code session start (after restart): the heartbeat hook fires on the first tool call; `~/.claude/dev-platform-telemetry.log` has at least one entry of the form `<ISO timestamp> tool=<name>`.

---

## Acceptance Criteria

- [ ] `dev/settings/claude-global.md` exists, byte-identical to the original `~/.claude/CLAUDE.md` (Change 1).
- [ ] `dev/scripts/install.sh` `install_settings()` deploys `claude-global.md` (Change 2); fake-HOME round-trip passes.
- [ ] `dev/scripts/verify.sh` checks the new symlink (Change 3); exit 0 after install, exit 1 after uninstall.
- [ ] `dev/settings/README.md` documents the global vs workspace two-tier model (Change 4).
- [ ] `dev/hooks/post-tool-heartbeat.sh` exists, executable, smoke-tests pass with both valid and invalid JSON input (Change 5).
- [ ] `dev/settings/settings.json` is valid JSON with the `hooks` block; absolute path matches the deployed location (Change 6).
- [ ] `dev/CLAUDE.md` "Belongs here:" list mentions `claude-global.md` explicitly (Change 7).
- [ ] Fake-HOME round-trip passes including the refuse-to-clobber check (Change 8).
- [ ] Live cutover against `~/.claude/` completes; `verify.sh` exits 0 with 13 OK lines (Change 9).
- [ ] On next Claude Code session start, the heartbeat hook fires (telemetry log has entries).
- [ ] No file under `dev/projects/` modified.
- [ ] No bypass of dev-platform: `~/.claude/CLAUDE.md` is now a symlink, not a real file.

## Out of Scope (Future Specs)

- **R2 Monitoring** — telemetry aggregation, per-project drift detection, gate-pass rate dashboard. R1.5 ships the heartbeat as the data source; R2 builds the consumers.
- **R3 Testing** — smoke-test fixtures for slash commands and hooks. The heartbeat hook in R1.5 is small enough to test by inspection; R3 builds the test infrastructure.
- **R4 Extensions** — VSCode user settings, keybindings, snippets, extensions list. Same gateway-coverage shape as R1.5 but for the VSCode side. Not bundled here because R4 is a larger surface area and warrants its own spec.
- **Additional hook scripts** — gate-reminder, taxonomy-checker-on-spec-edit, session-start-health-check. R1.5 ships only the heartbeat; future hooks ride the same deployment path with no new infrastructure.
- **Per-project hook templates** — projects under `dev/projects/` may want their own per-project hook scripts. Out of scope per the Scope rule (projects manage their own `.claude/settings.json`).

## What NOT to Do

- **Do not** edit `~/.claude/CLAUDE.md` directly during /code. The whole point of R1.5 is to make `dev/settings/claude-global.md` the source of truth. Edits to `~/.claude/CLAUDE.md` post-cutover would write through the symlink to the tracked file, which is technically fine — but the convention is "edit the source, not the deployment."
- **Do not** widen the `hooks` block in `settings.json` to include speculative future hooks (gate-reminder, etc.). Ship one hook, validate the path, defer the rest to future specs.
- **Do not** rewrite the heartbeat hook to do "more useful" work (e.g., gate-fast reminder, drift detection). The heartbeat is intentionally minimal so it can't break anything; richer behavior belongs in separate hook scripts.
- **Do not** use `${HOME}` or `~` in the `settings.json` hooks command path. Decision 3 chose absolute path; deviating reintroduces env-var-expansion uncertainty.
- **Do not** put `claude-global.md` anywhere other than `dev/settings/`. Decision 1 chose this location to keep `settings/` as the unified home for "anything Claude Code reads at startup"; deviating fragments the convention.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `dev/settings/claude-global.md` | New | Tracked copy of `~/.claude/CLAUDE.md` |
| `dev/scripts/install.sh` | Modify | Extend `install_settings()` to symlink `claude-global.md` |
| `dev/scripts/verify.sh` | Modify | Add `check_symlink` for `claude-global.md` |
| `dev/settings/README.md` | Modify | Document the file + two-tier CLAUDE.md model |
| `dev/hooks/post-tool-heartbeat.sh` | New | First hook script (executable) |
| `dev/settings/settings.json` | Modify | Add `hooks` block referencing the deployed hook path |
| `dev/CLAUDE.md` | Modify | Update "Belongs here:" list to mention `claude-global.md` |
| `~/.claude/CLAUDE.md` | Replace | Real file → symlink (post-cutover) |
| `~/.claude/r15-pre-cutover.backup-*` | New (untracked) | Backup of original `CLAUDE.md` before cutover |
| `~/.claude/dev-platform-telemetry.log` | New (untracked, auto-created) | Heartbeat log file (gitignored, machine-local) |

## Implementation Order

1. **Phase 1** (Changes 1–4): foundational — the global Claude file gets tracked, install/verify learn about it, README documents it. Each Change is independent of subsequent ones.
2. **Phase 2** (Changes 5–6): the hook script + settings wiring. Change 5 (hook script) and Change 6 (settings.json hooks block) are independent and can be done in either order.
3. **Phase 3** (Changes 7–9): docs + cutover. Change 7 (CLAUDE.md update) is independent. Changes 8–9 (round-trip + cutover) MUST come last — they validate everything else.

Within each Phase, Changes can be batched in a single `/code` session.

## Verification Checklist

- [ ] All Changes implemented per the spec.
- [ ] `bash -n` passes on `install.sh`, `uninstall.sh`, `verify.sh`, `post-tool-heartbeat.sh`.
- [ ] `python3 -c "import json; json.load(open('dev/settings/settings.json'))"` succeeds.
- [ ] Fake-HOME round-trip passes (Change 8).
- [ ] Live cutover succeeds (Change 9); `verify.sh` exits 0 with 13 OK lines.
- [ ] Heartbeat hook fires on next Claude Code session start; `~/.claude/dev-platform-telemetry.log` accumulates entries.
- [ ] No file under `dev/projects/` modified.
- [ ] No literal absolute paths leak outside `/home/rich/` (deliberate hardcoding for Rich's machines).
- [ ] Two-tier CLAUDE.md model documented in `settings/README.md` and `dev/CLAUDE.md`.
- [ ] `git status` clean before commit; spec changes bundled with implementation in one atomic commit per the project bundling rule.

## Notes for Implementation

- **Run install.sh after Phase 1+2 complete, NOT before Phase 3 cutover.** Same pattern as R1: the migrated `claude-global.md` and the new hook can sit in `dev/` alongside the still-functioning `~/.claude/CLAUDE.md` — no behavior change until the cutover symlinks the deployed paths to the tracked ones.
- **The cutover is the risky moment.** Backup `~/.claude/CLAUDE.md` first; the install script's `link_file` already refuses to overwrite real files, so you can't accidentally destroy data — but a clean backup before deletion is the safe default.
- **Hook payload schema is unverified.** The heartbeat hook reads `tool_name` from stdin JSON; if Claude Code's actual PostToolUse payload differs in shape, the hook degrades gracefully to `tool=?`. The /test phase should confirm that real session activity produces meaningful tool names (not all `?`).
- **Telemetry log location:** `~/.claude/dev-platform-telemetry.log`. Gitignored by default (anything under `~/.claude/` is gitignored, see `dev/.gitignore` line `~/.claude/` Hard-exclude). R2 Monitoring will define the schema and rotation policy.
- **Two-CLAUDE.md tier collision risk:** after R1.5, `dev/settings/claude-global.md` and `dev/CLAUDE.md` are both tracked source files. `settings/README.md` (Change 4) and `dev/CLAUDE.md` (Change 7) are the only places this distinction is documented; future-Rich opening this repo six months from now will read those for orientation. If the distinction proves confusing, R2 monitoring can surface the gap.
