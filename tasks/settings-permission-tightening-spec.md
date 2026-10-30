# Settings Permission Tightening

## Coding Specification for Implementation

Roadmap Phase: `v1.39: Settings Permission Tightening` (milestone claimed by `/plan`).
Branch: `worktree-v1.39+phase-1-settings-tightening`. One branch, one PR: the Changes are
not independently shippable (a tightened baseline that the merge cannot apply to the live
file is a no-op, and retract support with nothing to retract is dead code).

## Design Philosophy

A security review of the public repo found no leaked secrets. The real exposure is
`settings/settings.json`, the baseline every install merges into `~/.claude/settings.json`.
Its allowlist includes `Bash(bash *)`, `Bash(sh *)`, `Bash(source *)`, `Bash(xargs *)`,
`Bash(curl *)`, `Bash(ssh *)`, `Bash(scp *)`, unscoped `Bash(git *)`, `Bash(systemctl *)`,
`Bash(apt *)`, `Bash(kill *)`, env-var prefixes with a trailing `*` (`Bash(PGPASSWORD=*)`,
`Bash(HF_TOKEN=*)`), and unrestricted `Read` of `/home/rich/**`. The only deny rules are
two `sudo rm -rf /` literals. A prompt injection into any session inherits all of it.

Verified while planning, and it changes the design: `scripts/merge_settings.py:11-13,
75-80` UNIONS `permissions.allow/deny/ask`, so deleting an entry from the tracked baseline
does not remove it from the live file. Checked against the live file with a throwaway
script: `~/.claude/settings.json` holds 320 allow entries, including `Bash(bash *)`,
`Bash(sh *)`, `Bash(curl *)`, `Bash(ssh *)`, `Bash(scp *)`, `Bash(kill *)`, `Bash(pkill *)`,
`Bash(systemctl *)`, `Bash(apt *)`, `Bash(source *)`, `Bash(xargs *)`, `Bash(tee *)`, and
`defaultMode` is `auto`. The README documents this as a known limitation
(`settings/README.md`, "Deployment model"). So a tightened baseline alone changes nothing
on this machine. The fix is at the source: give the merge a way to retract entries,
driven by a tracked list, rather than hand-editing the live file.

Two mechanisms, used for different jobs:

1. **Retract list** (new, `settings/permissions-retract.json`): exact strings the merge
   removes from the live `allow` list. Used for broad entries that should go back to
   "prompt by default" (`Bash(bash *)`, `Bash(curl *)`, ...).
2. **`deny` and `ask` rules** in the baseline: used where a rule must hold even if a
   one-off "always allow" grant later lands in the live file (force pushes, `~/.ssh`
   reads, `curl | sh`). Rule order (deny, then ask, then allow) is an ASSUMPTION about
   Claude Code and is verified in Change 1 before anything depends on it.

`ask` is NOT used for `bash`, `sh`, `kill` and similar: if `Bash(bash *)` were in `ask`
it would also override the narrow allows for the workflow's own scripts
(`bash ~/.claude/worktree/link-deps.sh` in `commands/plan.md:58` and
`commands/code.md:53`, `bash /home/rich/dev/scripts/check-concurrent-sessions.sh` in
`commands/dev.md:52`). Retract the broad allow and add narrow allows instead.

Honest limit, stated in the README by this spec: `python *`, `node *`, `npm *`, `npx *`,
`pip *`, `go *`, `cargo *` and `./scripts/*` stay allowed and each can run arbitrary code.
No pattern list closes that. The real boundary is Claude Code's sandbox, out of scope here.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| Retract support in `scripts/merge_settings.py` | Python | Extends an existing Python helper; JSON handling, not network or compute heavy |
| Test suite additions | Bash | Matches `tests/merge-settings/run.sh` |
| `settings/*.json` | JSON | Config, not code |

## Overview

Phase 1: Tighten the permission baseline

1. Change 1: Verify rule precedence and `~` matching, record the result
2. Change 2: Retract support in the merge, with fixtures
3. Change 3: Tightened baseline and the retract list
4. Change 4: Keep the workflow's own commands from prompting
5. Change 5: Baseline invariant checks in the gate
6. Change 6: Document the model and the limits

---

## Phase 1: Tighten the permission baseline

### Change 1: Verify rule precedence and `~` matching, record the result

**Problem:** Changes 3 and 4 rely on two behaviours of Claude Code that nobody has run
here: that `deny` beats `ask` beats `allow` when several rules match, and that a literal
`~` in a `Bash(...)` pattern matches the literal `~` in the command text. Writing the
baseline on an assumption would ship a "tightened" file that may not tighten anything.

**File:** `settings/README.md` (new "Permission rule behaviour" subsection under
"Deployment model", about line 45)

**Implementation:** Spawn the `claude-code-guide` agent (or read the Claude Code
permissions docs) and ask exactly two questions: (a) when a command matches both an
`allow` and an `ask` rule, and both an `ask` and a `deny` rule, which wins; (b) is `~`
expanded or matched literally inside `Bash(...)` patterns. Write the answers, with the
doc URL or agent quote, into the README. If (a) is not deny > ask > allow, STOP and
re-plan: the `ask` and `deny` design in Change 3 does not hold. If (b) says `~` is not
matched literally, Change 4 uses absolute `/home/rich/.claude/...` patterns and rewrites
the command call sites to match (see Change 4).

**Acceptance Test:** The README subsection exists and cites a source for both answers.
`grep -n "deny" settings/README.md` shows the precedence statement.

---

### Change 2: Retract support in the merge, with fixtures

**Problem:** `merge_settings.py` can add a permission but never remove one, so no
baseline edit can tighten an already-deployed machine.

**File:** `scripts/merge_settings.py` (functions `merge` line ~58 and `main` line ~86)

**Implementation:**

- Add an optional third positional argument `--retract <path>`; when absent behaviour is
  byte-for-byte unchanged (existing fixtures must still pass untouched).
- The retract file is a JSON object `{"allow": ["Bash(...)", ...]}`. After the union step,
  remove from `permissions.allow` every string that matches a retract entry EXACTLY
  (string equality, no globbing: a retract of `Bash(bash *)` must not touch
  `Bash(bash ~/.claude/worktree/*)`).
- A malformed or non-object retract file exits 2 with the same message shape as
  `load_json`. A missing path given explicitly is an error (exit 2), not silently skipped.
- Retract only applies to `allow`. It never removes `deny` or `ask` entries.
- A baseline `allow` entry that is also in the retract list is a contradiction: exit 2
  with the entry named. This keeps the two files from disagreeing silently.
- `--dry-run` prints the result including retraction and writes nothing.
- Update the module docstring's "KNOWN LIMITATION" paragraph to describe the retract
  mechanism instead of telling the reader to edit the live file.

**Acceptance Test:** Extend `tests/merge-settings/run.sh` (auto-discovered by
`scripts/gate_fast.sh`) with fixtures: retract removes only exact matches; narrow entry
survives a broad retract; no `--retract` argument leaves output unchanged; contradiction
exits 2; malformed retract file exits 2; baseline file is never written;
`--dry-run --retract` writes nothing. `bash tests/merge-settings/run.sh` reports all PASS.

---

### Change 3: Tightened baseline and the retract list

**Problem:** The allowlist in `settings/settings.json:3-120` is broader than the tool
set the workflow needs.

**File:** `settings/settings.json` (modify), `settings/permissions-retract.json` (new)

**Implementation:** Start from the reviewed draft at
`/tmp/claude-1000/-home-rich-dev/6e43efef-aed9-4f6c-ba26-e6417af7959f/scratchpad/settings.tightened.json`
(the coder has no access to that path if the scratchpad is gone; the content is
reproduced by these rules) and apply these corrections found during planning:

- **Remove from `allow`:** `Bash(bash *)`, `Bash(sh *)`, `Bash(source *)`, `Bash(xargs *)`,
  `Bash(tee *)`, `Bash(export *)`, `Bash(set *)`, `Bash(env *)` (keep `Bash(env)`),
  `Bash(curl *)`, `Bash(ssh *)`, `Bash(scp *)`, `Bash(smbclient *)`, `Bash(kill *)`,
  `Bash(pkill *)`, `Bash(systemctl *)` (replace with read-only `systemctl status *`,
  `is-active *`, `list-*`), `Bash(apt *)`, `Bash(dmesg *)`, `Bash(pm2 *)` (replace with
  `list`, `status`, `logs`), `Bash(dpkg *)` (replace with `-l`, `-s`),
  `Bash(tailscale *)` (replace with `status*`), `Bash(code *)` (replace with
  `--list-extensions*` and `--install-extension *`), `Bash(/tmp/*)`,
  `Bash(/home/rich/dev/*)` (replace with `/home/rich/dev/scripts/*`),
  `Bash(PGPASSWORD=*)`, `Bash(HF_TOKEN=*)`, `Bash(PYTHONPATH=*)`,
  `Bash(LD_LIBRARY_PATH=*)`, `Bash(KERMIT_*)`, `Read(//dev/**)`, the `PORT=4002 ...`
  entry, and the `python -c ":*` / `python3 -c ":*` special cases.
- **Add scoped replacements** for the env-var prefixes, e.g. `Bash(PGPASSWORD=* psql *)`,
  `Bash(PYTHONPATH=* python3 *)`.
- **`deny`:** `Bash(git push --force*)`, `Bash(git push -f *)`, `Bash(git push --mirror*)`,
  `Bash(git commit --no-verify*)`, `Bash(curl * | *)`, `Bash(wget * | *)`,
  `Bash(chmod 777*)`, `Bash(chmod -R 777*)`, `rm -rf` on `/`, `/*`, `~*`, `$HOME*`,
  reads of `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.config/gh`, `~/.netrc`,
  `~/.docker/config.json`, `~/.claude/.credentials.json`, `**/.env`, `**/.env.*`, and
  edits/writes of `~/.ssh`, `~/.bashrc`, `~/.profile`. Keep the two existing `sudo rm -rf`
  literals.
- **Do NOT deny `sudo *`** (the draft did). The live file holds roughly a dozen
  `Bash(sudo ...)` grants (`sudo lsof`, `sudo ss -tlnp`, `sudo aa-status`), so the user
  does use it, and a deny would silently kill them. Put `Bash(sudo *)` in `ask`.
- **`ask`:** `Bash(sudo *)`, `Bash(git push *)`, `Bash(git reset --hard*)`,
  `Bash(git clean *)`, `Bash(git branch -D *)`, `Bash(docker rm *)`, `Bash(docker rmi *)`,
  `Bash(docker system prune*)`, `Bash(docker volume rm *)`, `Bash(docker compose down -v*)`,
  `Bash(docker-compose down -v*)`. Do NOT put `bash *`, `rm *`, `kill *` or `curl *` here
  (see Design Philosophy; `rm -f .pr-body.md` in `commands/pr.md:101` must not prompt on
  every PR).
- **`permissions-retract.json`:** one `allow` array listing, as exact strings, every entry
  removed from the baseline above that is also present in the live file, plus the
  accumulated broad ones (`Bash(bash *)`, `Bash(sh *)`, `Bash(source *)`, `Bash(xargs *)`,
  `Bash(tee *)`, `Bash(export *)`, `Bash(set *)`, `Bash(env *)`, `Bash(curl *)`,
  `Bash(ssh *)`, `Bash(scp *)`, `Bash(kill *)`, `Bash(pkill *)`, `Bash(systemctl *)`,
  `Bash(apt *)`). Generate the list by diffing the old baseline against the new one, then
  check each against the live file with a script written to a file (an inline
  `python3 - <<EOF` that mentions `git` is refused by the worktree guard).
- Keep `hooks`, `enabledPlugins`, `extraKnownMarketplaces`, `model`, `additionalDirectories`
  byte-identical.
- Do not touch `~/.claude/settings.json` by hand. The live file changes only through
  `scripts/install.sh settings`, which is run by the user after merge.

**Acceptance Test:** `python3 -c "import json;json.load(open('settings/settings.json'));json.load(open('settings/permissions-retract.json'))"` succeeds.
`python3 scripts/merge_settings.py settings/settings.json ~/.claude/settings.json --retract settings/permissions-retract.json --dry-run`
prints a result with no `Bash(bash *)`, `Bash(curl *)`, `Bash(ssh *)` or `Bash(kill *)` in
`allow`, and with the new `deny` and `ask` entries present. The existing
`PGPASSWORD=[a-z]` secrets scan (`scripts/gate_fast.sh:189`) still passes.

---

### Change 4: Keep the workflow's own commands from prompting

**Problem:** Removing the broad allows makes every `bash ...`, `kill` and `curl` in
`commands/*.md` prompt, including steps that run unattended.

**File:** `settings/settings.json` (add narrow `allow` entries), `commands/*.md` (only if
Change 1 shows `~` does not match literally)

**Implementation:** Run the sweep and list every hit that runs a now-prompting command:

```bash
grep -nE '^\s*(bash|sh|source|xargs|kill|pkill|curl|ssh|scp) ' commands/*.md skills/*/SKILL.md
```

Known hits at planning time: `commands/code.md:53` and `commands/plan.md:58`
(`bash ~/.claude/worktree/link-deps.sh`), `commands/dev.md:52`
(`bash /home/rich/dev/scripts/check-concurrent-sessions.sh`), `commands/merge.md:146`
(`kill "${_pid}"`, inside a worktree-removal loop). For each, add the narrowest allow that
covers the exact call: `Bash(bash ~/.claude/worktree/*)`,
`Bash(bash /home/rich/dev/scripts/*)`, `Bash(bash ./scripts/*)`, `Bash(bash scripts/*)`.
For `kill "${...}"` decide per hit: `merge.md` deliberately stops processes whose cwd is in
the worktree being removed, so allow `Bash(kill \"${_pid}\"*)` only if Change 1 shows
variable text matches literally; otherwise leave it prompting and note it. Do not
re-add a broad allow to make a hit go away. Also re-run the hit sweep from `CLAUDE.md`
("Commands a Worktree Session Runs Must Be Plain Single Commands") on any command text
you edit.

**Acceptance Test:** After a dry-run merge into a scratch copy of the live file, a script
that applies the pattern list to each swept command line (written to a file, run with
`python3 -I`) reports every swept command as matched by an allow entry and not matched
by any `ask` or `deny` entry, except hits recorded as intentionally prompting.

---

### Change 5: Baseline invariant checks in the gate

**Problem:** Nothing stops a later edit from re-adding `Bash(bash *)` to the baseline or
dropping the force-push deny.

**File:** `tests/settings-baseline/run.sh` (new, auto-discovered like the other suites);
`tests/README.md` (list the suite)

**Implementation:** Using `tests/helpers/assert.sh` (`record_pass` / `record_fail`), assert:
the baseline parses; none of a fixed list of dangerous patterns (`Bash(bash *)`,
`Bash(sh *)`, `Bash(curl *)`, `Bash(ssh *)`, `Bash(scp *)`, `Bash(kill *)`,
`Bash(source *)`, `Bash(xargs *)`, `Bash(apt *)`, `Bash(systemctl *)`) appears in
`allow`; the required `deny` entries (force push, `~/.ssh` read, `.env` read,
`curl | sh`) are present; no `allow` entry is also in `permissions-retract.json`; every
retract entry is a string starting with `Bash(` or `Read(`. Consumer audit for the new
file types: `.gitignore` already allows `!settings/*.json` (line 89); probe with
`touch tests/settings-baseline/probe.md && git status --porcelain tests/settings-baseline/`
per the "Consumer Audit" rule and delete the probe. `scripts/install.sh` and
`scripts/verify.sh` need edits, see below.

- `scripts/install.sh:158` — pass `--retract "${REPO}/settings/permissions-retract.json"`.
  Also grep for other callers of `merge_settings.py` (Derivation Sweep rule):
  `git grep -n merge_settings.py`.
- `scripts/verify.sh:132` `check_local_settings` — also report drift if any retract entry
  is still present in the live `allow` list, so an un-redeployed machine shows up.

**Acceptance Test:** `bash tests/settings-baseline/run.sh` all PASS; re-adding
`"Bash(bash *)"` to the baseline makes it FAIL; `./scripts/verify.sh` on this machine
BEFORE `install.sh settings` reports the retract drift, and AFTER it reports clean.

---

### Change 6: Document the model and the limits

**Problem:** `settings/README.md` still says a permission cannot be removed, and nothing
tells a reader that interpreters stay allowed.

**File:** `settings/README.md` (Deployment model section, line ~45; "Hygiene"),
`scripts/README.md` if it describes `merge_settings.py`

**Implementation:** Replace the "can ADD but not REMOVE" limitation with the retract
mechanism and the file name. Add a "What this does and does not protect" paragraph naming
the interpreters that remain allowed, the sandbox as the real boundary, and that prefix
patterns can be bypassed with chaining or substitution. Add `permissions-retract.json` to
the Files list. Update the `fewer-permission-prompts` guidance in "Hygiene" so it does not
suggest re-adding retracted entries.

**Acceptance Test:** `grep -n "ADD but not REMOVE" settings/README.md scripts/merge_settings.py`
returns nothing; markdown lint rules from the global instructions hold (blank line after
headings, fenced blocks have a language).

---

## What NOT to Do

- Do not edit `~/.claude/settings.json` directly. It changes only through `install.sh`.
- Do not use `deny` for `sudo *`; it would break the user's existing sudo grants.
- Do not put `bash *`, `rm *`, `kill *` or `curl *` in `ask`: `ask` outranks `allow` and
  would defeat the narrow allows the workflow depends on.
- Do not re-add a broad allow to silence one prompting command; add the narrowest entry.
- Do not claim this stops prompt injection. Interpreters remain allowed (see README).
- Do not prune the other ~300 accumulated live grants (one-off `kill -9 <pid>` entries,
  keystone worktree sudo paths) in this phase. File that as a follow-on.
- Do not touch anything under `projects/`.
- Do not change `hooks`, `model` or `additionalDirectories`.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `settings/settings.json` | Modify | Tightened allow list; new `ask` and `deny` entries; narrow allows for workflow scripts |
| `settings/permissions-retract.json` | New | Exact `allow` strings the merge removes from the live file |
| `scripts/merge_settings.py` | Modify | `--retract` support, contradiction check, docstring |
| `scripts/install.sh` | Modify | Pass the retract file to the merge (line ~158) |
| `scripts/verify.sh` | Modify | Flag retract entries still present in the live file (line ~132) |
| `tests/merge-settings/run.sh` | Modify | Retract fixtures |
| `tests/settings-baseline/run.sh` | New | Baseline invariant suite |
| `tests/README.md` | Modify | List the new suite |
| `settings/README.md` | Modify | Retract mechanism, rule behaviour, limits |
| `commands/*.md` | Modify (conditional) | Only if Change 1 shows `~` or variable text does not match |
| `tasks/shipped/<date>-v1.39-settings-permission-tightening.md` | New | Written by `/code`'s doc step |
| `ROADMAP.md` | Modify | v1.39 entry |

## Implementation Order

1. Change 1 first. Its result can change Changes 3 and 4 (or stop the plan).
2. Change 2 (merge support) before Change 3, so the retract list can be exercised.
3. Change 3, then Change 4 (needs the final entry list to sweep against).
4. Change 5 after Change 3 (asserts on the final baseline); Change 6 last.

## Verification Checklist

- [ ] Precedence and `~` behaviour verified and cited in `settings/README.md`
- [ ] `bash tests/merge-settings/run.sh` and `bash tests/settings-baseline/run.sh` PASS
- [ ] Dry-run merge into the live file removes the broad entries and keeps the narrow ones
- [ ] Every command in `commands/*.md` that ran without a prompt before still does, or is
      listed as intentionally prompting
- [ ] `./scripts/gate_fast.sh` passes
- [ ] `bash scripts/check_spec_taxonomy.sh` passes
- [ ] `install.sh settings` run by the user after merge; `./scripts/verify.sh` clean
- [ ] No file under `projects/` modified
- [ ] `/security-review` run before `/gate fast` (this change edits credential and
      permission handling)
