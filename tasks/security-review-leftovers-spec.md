# Security Review Leftovers

## Coding Specification for Implementation

Roadmap Phase: `v1.43: Security Review Leftovers` (milestone claimed by `/plan`).
Branch: `worktree-v1.43+phase-1-security-review-leftovers`. One branch, one PR. Closes the
unchecked dev-platform items of `issue #131`, except the two that need a decision from the user
(see "Out of scope").

## Design Philosophy

After v1.42, `issue #131` has five unchecked items. Two need no code: the `tests/install`
failures do not reproduce (see Verified state), and `kill` prompting inside `/merge` is correct
behaviour, so the fix is a note, not a permission. The one real piece of work is the live
`~/.claude/settings.json`, which holds 311 allow entries of which 207 are not in the tracked
baseline. `settings/permissions-retract.json` is the wrong tool for them: it is a tracked file in
a public repo, so retracting a one-off grant there would publish its text (PIDs, keystone worktree
paths, a token-file path), and it only helps on machines that ran the old grant.

So this phase adds a small read-only-by-default tool that lists one-off grants in the live file
and, with `--apply`, removes them after taking a backup. Which grants count as one-off is
decided by a few explicit rules (PID-specific `kill`, any `sudo`, grants naming a scratchpad
path under `/tmp/claude-*`, grants with `GH_TOKEN=$(cat ...)` inline), not a judgement call, so
the output is predictable and testable. The tool never edits the tracked baseline and never
touches grants it has no rule for; the remaining ~129 "other" grants are only listed.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/prune_live_grants.py` | Python | Reads and writes JSON; same language and shape as the sibling `scripts/merge_settings.py`. Not network, compute, or UI. |
| `tests/prune-live-grants/run.sh` | Bash | Matches every other suite under `tests/`. |

## Verified state

| Claim | Verified by |
| ----- | ----------- |
| Live `permissions.allow` has 311 entries; 207 are not in `settings/settings.json` | python3 one-liner over `~/.claude/settings.json` and `settings/settings.json` at planning time |
| Of the 207: 56 contain `GH_TOKEN`, 17 contain `kill` or `sudo`, 5 contain `/tmp/claude-`, 129 match none of those | same one-liner, categorized with `re.search` |
| `kill -9 665269`, `kill 2288548` and several `sudo ...` paths into keystone worktrees are in the live file | same one-liner, printed the kill/sudo group |
| `tests/install/run.sh` passes 9 of 9 in this worktree and on an extracted `git archive HEAD` copy | ran both at planning time; "verify-after-install" and "re-install idempotent" both PASS |
| `kill "${_pid}"` is at `commands/merge.md:146`; `Bash(kill *)` and `Bash(pkill *)` are in `settings/permissions-retract.json:20-21` | `grep -n kill commands/merge.md settings/*.json` |
| `merge_settings.py` takes `baseline_path live_path [--retract PATH] [--dry-run]` | `python3 scripts/merge_settings.py --help` |
| `${VAR}` in a `Bash(...)` pattern is recorded as UNTESTED | `settings/README.md:72` |
| Assumption: the `issue #131` install failures came from a copy that included an untracked or stale file. Not reproduced, cause unknown. | Only the two runs above |

## Overview

Phase 1: Live grant pruning tool

1. Change 1: `scripts/prune_live_grants.py`
2. Change 2: `tests/prune-live-grants/run.sh`
3. Change 3: Docs — `settings/README.md` hygiene section, `commands/merge.md` kill note

Phase 2: Close out

4. Change 4: Shipped record, ROADMAP entry, `issue #131` update

---

## Phase 1: Live grant pruning tool

### Change 1: `scripts/prune_live_grants.py`

**Problem:** About 200 accumulated grants sit in the live settings file with no way to review or
remove them except hand-editing JSON.

**File:** `scripts/prune_live_grants.py` (new)

**Implementation:**

- Usage: `prune_live_grants.py BASELINE LIVE [--apply]`. Default is list-only; it writes nothing.
- Read `permissions.allow` from both files. Candidates are live entries not present in the
  baseline. Classify each with ordered rules, first match wins, and print one line per entry
  with its class:
  1. `pid-kill`: `Bash(kill ` followed by an optional `-<signal>` and digits only.
  2. `sudo`: starts with `Bash(sudo `.
  3. `scratch-path`: contains `/tmp/claude-`.
  4. `inline-token`: contains `GH_TOKEN=`.
  5. `unclassified`: everything else (listed, never removed).
- `--apply`: write a backup first (`<LIVE>.bak-<UTC timestamp>`, mode 0600, same directory), then
  remove only classes 1 to 4 from `permissions.allow`, preserving order and every other key.
  Print counts removed and the backup path. Exit 2 on malformed JSON, matching
  `merge_settings.py`.
- Never print more than the first 100 characters of an entry, since entries can embed paths and
  token-file names. Never write the baseline path.
- Reuse the JSON load and error handling pattern from `scripts/merge_settings.py`; do not
  re-implement a different one.

**Acceptance Test:**

```bash
python3 scripts/prune_live_grants.py settings/settings.json ~/.claude/settings.json | tail -8
```

Expect per-class counts that add up to 207 (56 GH_TOKEN-bearing entries may overlap other
classes; counts follow rule order, so report the numbers the tool prints, not these).

---

### Change 2: `tests/prune-live-grants/run.sh`

**Problem:** A tool that deletes permissions needs proof it deletes only what it should.

**File:** `tests/prune-live-grants/run.sh` (new; auto-discovered by `scripts/gate_fast.sh`)

**Implementation:** Follow `tests/merge-settings/run.sh` (sources `tests/helpers/assert.sh`, uses
`mktemp -d` and a trap). Fixtures are built at runtime. Checks:

- Module parses.
- List mode writes nothing (live file hash unchanged, no `.bak-*` created).
- Each class is detected: a PID `kill`, `kill -9 N`, a `sudo` entry, a `/tmp/claude-` entry, a
  `GH_TOKEN=` entry; each is also shown able to fail (a non-matching entry such as
  `Bash(kill *)` or `Bash(git status)` is classified `unclassified`).
- `--apply` removes only classes 1 to 4, keeps baseline entries and `unclassified` ones, keeps
  order, keeps non-permission keys such as `hooks`.
- `--apply` creates a backup whose contents equal the pre-run file.
- Baseline file is byte-identical after `--apply`.
- Malformed live JSON exits 2.

**Acceptance Test:** `bash tests/prune-live-grants/run.sh` prints only PASS lines.

---

### Change 3: Docs

**Problem:** The Hygiene section of `settings/README.md` tells the reader to prune by hand, and
`/merge` prompts on `kill` with no explanation.

**Files:** `settings/README.md` (Hygiene section), `commands/merge.md:146` (comment above the
`kill` line), `scripts/README.md` if it lists scripts (check with `grep -n merge_settings scripts/README.md`).

**Implementation:**

- README Hygiene: replace "Prune the live file periodically" with the tool's two commands and a
  sentence that it never touches unclassified grants.
- `commands/merge.md`: add one comment line above the `kill` line saying a permission prompt here
  is expected, because `Bash(kill *)` was retracted in v1.39 and a PID-specific allow cannot be
  written ahead of time. Keep the block free of new variables or compound commands (see
  "Commands a Worktree Session Runs Must Be Plain Single Commands" in `CLAUDE.md`); comments
  inside the existing block are fine.

**Acceptance Test:** `bash tests/commands/frontmatter.sh` and `./scripts/gate_fast.sh` pass.

---

## Phase 2: Close out

### Change 4: Shipped record and issue update

**Files:** `tasks/shipped/2026-11-01-v1.43-security-review-leftovers.md` (new), `ROADMAP.md`,
a `tasks/lessons/` file only if something went wrong during `/code`.

**Implementation:** Follow the v1.42 shipped file. State plainly that the `tests/install` item
was not reproduced and the cause is unknown, and that `${VAR}` in a pattern remains UNTESTED.
After merge, tick the items this phase closes in `issue #131` with a comment (ask the user before
editing the issue body).

**Acceptance Test:** `scripts/check-phase-milestones.sh` reports nothing for v1.43 after the
post-merge step.

---

## Out of scope (needs the user)

- **Running `--apply` on the live file.** The tool ships; the user reviews the list and runs it.
- **Sandbox trial** (`tasks/sandbox-trial-spec.md`, milestone `v1.40: Sandbox Trial`): run or
  drop. Needs AppArmor changes (root) and a decision.
- **Enabling the secret pre-commit hook** in the 18 projects (0 enabled), the Google Maps key,
  tracked `.env` files, and browser-only account checks. Per-project or console actions.
- **`${VAR}` in a permission pattern:** cannot be tested without an interactive permission
  prompt, and no shipped rule depends on it.

## What NOT to Do

- Do not add one-off grants to `settings/permissions-retract.json`; it is public and tracked.
- Do not let `--apply` remove `unclassified` entries or edit anything outside `permissions.allow`.
- Do not edit `~/.claude/settings.json` from `/code`; only the user runs `--apply`.
- Do not add a broad `Bash(kill *)` back to make `/merge` quiet.
- Do not write to any project under `projects/`.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/prune_live_grants.py` | New | List and prune one-off live grants |
| `tests/prune-live-grants/run.sh` | New | Fixture suite |
| `settings/README.md` | Modify | Hygiene section uses the tool |
| `commands/merge.md` | Modify | Comment explaining the expected `kill` prompt |
| `tasks/shipped/2026-11-01-v1.43-security-review-leftovers.md` | New | Shipped record |
| `ROADMAP.md` | Modify | v1.43 entry |

## Implementation Order

1. Change 1, then Change 2 (tests need the script).
2. Change 3 (independent).
3. Change 4 last.

## Verification Checklist

- [ ] `bash tests/prune-live-grants/run.sh` all PASS, each check also shown able to fail
- [ ] List mode against the real live file writes nothing (`ls ~/.claude/settings.json.bak-*` empty)
- [ ] `./scripts/gate_fast.sh` passes
- [ ] Probe that `tests/prune-live-grants/` and `scripts/prune_live_grants.py` are tracked
      (`touch` probe and `git status --porcelain`, per the Consumer Audit rule)
- [ ] `scripts/install.sh` and `scripts/verify.sh` need no change (no new category); confirm
- [ ] Language architecture matrix followed
