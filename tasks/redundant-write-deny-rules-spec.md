# Redundant Write Deny Rules

## Coding Specification for Implementation

Roadmap Phase: `v1.45: Redundant Write Deny Rules` (milestone claimed by `/plan`).
Branch: `worktree-v1.45+phase-1-redundant-write-deny-rules`. One branch, one PR. Follow-up to
v1.39 (which added the rules) and to the 2026-11-01 probe session (which surfaced the warning).

## Design Philosophy

Claude Code prints this at startup for each of three entries in `~/.claude/settings.json`:
`Permission deny rule (../.claude/settings.json): Write(//home/rich/.bashrc) is not matched by
file permission checks — only Edit(path) rules are. Use Edit(//home/rich/.bashrc) instead (Edit
rules cover all file-editing tools).` The same warning appears for `.profile` and `.ssh/**`.
The baseline already holds an `Edit(...)` rule for each of the three paths
(`settings/settings.json:179-184`), so the `Write(...)` lines add nothing: the protection is
the `Edit` rules, and the `Write` lines only print the warning. Removing them is cleanup, not a
change in what is blocked.

The catch is deploying it. `scripts/merge_settings.py` unions the baseline into the live file
and its retract mechanism (`--retract settings/permissions-retract.json`) only touches
`permissions.allow`. So deleting the lines from the baseline alone leaves all three in the
live `deny` list forever, and the warning stays. This spec extends the retract file with an
optional `deny` list, handled by the same exact-match removal, rather than hand-editing the live
file (a one-off edit would leave a fresh machine, or the next union, to re-add them if the
baseline ever regressed, and the retract list is the documented way a baseline edit reaches an
already-installed machine). The contradiction guard (an entry in both baseline and retract is an
error) applies to `deny` the same way it applies to `allow`.

## Facts checked while planning

| Claim | Verified by |
| ----- | ----------- |
| Only three `Write(` entries exist in tracked config, all in `settings/settings.json` lines 180, 182, 184 | `grep -rn 'Write(' --include=*.json --include=*.md --include=*.sh --include=*.py .` (excluding `tasks/shipped` and `projects/`) |
| Each has an `Edit(...)` twin on the line before | `sed -n 170,190p settings/settings.json` |
| The live file holds all six entries | `python3` read of `~/.claude/settings.json` `permissions.deny` |
| Retract handles `allow` only; `deny` is a plain union | `scripts/merge_settings.py:11`, `:63-93` (`load_retract`, `apply_retract`) |
| `verify.sh` checks only the `allow` side of the retract list | `scripts/verify.sh:93-107` |
| `tests/settings-baseline` Check 3 (required deny entries) lists no `Write(` entry, and Check 5 only allows `Bash(` / `Read(` shapes in the retract file | `sed -n 40,85p tests/settings-baseline/run.sh` |
| Assumption: an `Edit(path)` deny blocks the `Write` tool too. Stated by the warning text; not tested, because the test would write to `~/.bashrc` or `~/.ssh`. | unverified |
| Assumption: no project under `projects/` ships the same `Write(` deny lines | unverified (cross-project read not done; out of scope to edit regardless) |

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `merge_settings.py` retract change | Python | Existing file; settings tooling, no network or compute load |
| `verify.sh`, test additions | Bash | Existing files |

## Overview

Phase 1: Remove and retract

1. Change 1: Teach the retract file an optional `deny` list
2. Change 2: Remove the three `Write` lines and retract them
3. Change 3: Tests
4. Change 4: README

Phase 2: Close out

5. Change 5: Shipped record and ROADMAP entry

---

## Phase 1: Remove and retract

### Change 1: Teach the retract file an optional `deny` list

**Problem:** `apply_retract` removes entries from `permissions.allow` only, so a baseline `deny`
entry can be deleted from the baseline but never from a machine that already merged it.

**Files:** `scripts/merge_settings.py` (`load_retract` line ~63, `apply_retract` line ~77, the
`--retract` help text line ~131, the module docstring lines 18-29), `scripts/verify.sh`
(lines 93-107).

**Implementation:**

- `load_retract` returns both lists. `allow` stays as is (optional, list of strings). `deny` is
  new, optional (absent means empty), same validation (a list of strings, else exit 2). Keep the
  existing missing-file and malformed-file exits unchanged.
- `apply_retract` takes both lists. Contradiction check: baseline `allow` vs retract `allow`,
  and baseline `deny` vs retract `deny`; either overlap prints the existing style of error
  naming the entries and exits 2. Removal: filter `permissions.allow` by the allow list and
  `permissions.deny` by the deny list, exact match only. An entry in the retract `allow` list is
  never removed from `deny` or the reverse.
- `verify.sh`: the drift check counts leftovers across both lists (retract `allow` against live
  `allow`, retract `deny` against live `deny`) using `.get('deny', [])` so a retract file with no
  `deny` key still works.
- Update the docstring and help text to say the file is `{"allow": [...], "deny": [...]}` and
  that retracting a `deny` entry is for redundant or broken rules, not for loosening protection.

**Acceptance Test:** `bash tests/merge-settings/run.sh` passes with the existing checks
unchanged (an `allow`-only retract file behaves exactly as before), and the new checks in
Change 3 pass.

---

### Change 2: Remove the three `Write` lines and retract them

**Files:** `settings/settings.json` (lines 180, 182, 184 and the trailing comma on the last
remaining entry), `settings/permissions-retract.json`.

**Implementation:**

- Delete `Write(//home/rich/.ssh/**)`, `Write(//home/rich/.bashrc)` and
  `Write(//home/rich/.profile)` from `permissions.deny`. Keep the three `Edit(...)` entries.
  The file must still parse (check the comma on the last element).
- Add a `"deny"` key to `settings/permissions-retract.json` holding the same three exact
  strings. The `allow` list stays as is.

**Acceptance Test:**

```bash
python3 -c "import json; json.load(open('settings/settings.json')); json.load(open('settings/permissions-retract.json'))"
grep -c 'Write(' settings/settings.json
```

The first prints nothing; the second prints `0`.

---

### Change 3: Tests

**Files:** `tests/merge-settings/run.sh`, `tests/settings-baseline/run.sh`.

**Implementation:**

- `tests/merge-settings/run.sh`, following the style of checks 8-12 (fixtures built under
  `${TMP}`): (a) a retract file with a `deny` list removes exactly those strings from the live
  `deny` and leaves other deny entries and all `allow` entries alone; (b) a `deny` entry that is
  also in the baseline `deny` exits 2; (c) a `deny` value that is not a list of strings exits 2;
  (d) an `allow`-only retract file leaves `deny` untouched.
- `tests/settings-baseline/run.sh`: a check that the baseline `deny` holds no `Write(` entry
  (they are never matched) and that every `Edit(...)` deny entry is present for the three
  paths. Extend Check 5's shape test to the `deny` list, allowing `Write(` there since that is
  what is being retracted. Per the v1.44 practice, show each new check failing against a
  mutated copy of the baseline before relying on it, and record that in the shipped file.

**Acceptance Test:** `bash tests/merge-settings/run.sh` and `bash tests/settings-baseline/run.sh`
both end with 0 FAIL, and the shipped record lists the mutation each new check was shown
failing against.

---

### Change 4: README

**File:** `settings/README.md` (line 8 for the retract file description, line 68 for the merge
description, "Permission rule behaviour").

**Implementation:** Line 8 and line 68 say the retract file holds `allow` only; update both to
describe the optional `deny` list. Add one bullet to "Permission rule behaviour": a `Write(...)`
permission rule is never matched, `Edit(path)` covers every file-editing tool, and Claude Code
prints a warning for each `Write(` rule it finds. State that the `Edit` coverage of `Write` is
taken from that warning, not tested.

**Acceptance Test:** `./scripts/gate_fast.sh` passes (the markdown checks run there).

---

## Phase 2: Close out

### Change 5: Shipped record and ROADMAP entry

**Files:** `tasks/shipped/<date>-v1.45-redundant-write-deny-rules.md` (new), `ROADMAP.md`, a
`tasks/lessons/` file only if something went wrong during `/code`.

**Implementation:** Follow `tasks/shipped/2026-11-01-v1.44-docker-fuser-grants.md`. State the
three removed entries, that the `Edit` twins are what protect the paths, and that
`Edit`-blocks-`Write` is untested.

**Acceptance Test:** `scripts/check-phase-milestones.sh` reports nothing for v1.45 after merge.

---

## Post-merge step

Needs the user's go-ahead first: it changes the live settings file.

1. `./scripts/install.sh settings`, then `./scripts/verify.sh`. Verify reports any retracted
   entry still in the live file, on both lists.
2. `python3` read of the live `permissions.deny`: the three `Write(` entries are gone and the
   three `Edit(` entries remain.
3. After a Claude Code restart, start a session and confirm the `Write` deny-rule warnings no
   longer print.

## What NOT to Do

- Do not remove the `Edit(...)` deny entries. They are the protection.
- Do not test the block by writing to `~/.bashrc`, `~/.profile` or `~/.ssh`.
- Do not edit `~/.claude/settings.json` from `/code`; the install does it, after the user agrees.
- Do not use the retract `deny` list to remove protective rules; it exists for redundant or
  broken ones, and the docstring says so.
- Do not touch any project's own settings from this session.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/merge_settings.py` | Modify | Retract file accepts an optional `deny` list |
| `scripts/verify.sh` | Modify | Drift check covers retracted `deny` entries |
| `settings/settings.json` | Modify | Remove three `Write(` deny entries |
| `settings/permissions-retract.json` | Modify | Add `deny` list with the same three |
| `tests/merge-settings/run.sh` | Modify | Checks for deny retract behaviour |
| `tests/settings-baseline/run.sh` | Modify | No `Write(` in baseline deny; `Edit` twins present |
| `settings/README.md` | Modify | Retract description and a behaviour bullet |
| `tasks/shipped/<date>-v1.45-redundant-write-deny-rules.md` | New | Shipped record |
| `ROADMAP.md` | Modify | v1.45 entry |

## Implementation Order

1. Change 1 (nothing else works without the `deny` handling).
2. Change 2 (depends on Change 1 for the retract file to be accepted).
3. Change 3 (after Changes 1 and 2).
4. Change 4, then Change 5.

## Verification Checklist

- [ ] `grep -c 'Write(' settings/settings.json` prints `0`; the three `Edit(` entries remain
- [ ] `bash tests/merge-settings/run.sh` and `bash tests/settings-baseline/run.sh` 0 FAIL
- [ ] Each new check shown failing against a mutated fixture
- [ ] An `allow`-only retract file still works (existing checks unchanged)
- [ ] `./scripts/gate_fast.sh` passes
- [ ] No new top-level category, so `scripts/install.sh` needs no change; confirm
- [ ] Post-merge: warnings gone after install and restart, or marked UNTESTED
- [ ] Language architecture matrix followed
- [ ] `/security-review` run before `/gate fast` (touches the permission baseline and the merge script)
