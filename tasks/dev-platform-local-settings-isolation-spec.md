# v1.6: Local Settings Isolation

## Coding Specification for Implementation

## Design Philosophy

The bug is structural and one sentence long: **a settings file that Claude Code
writes to at runtime is symlinked into a tracked git repo.** `~/.claude/settings.json`
is a symlink to `settings/settings.json`, so every "always allow" grant Claude
persists writes straight through the symlink into the tracked dev-platform repo.
This has produced the `settings/settings.json` drift that's been left unstaged on
every commit this session. The same trap exists for `~/.claude/settings.local.json`
(symlinked to `settings/settings.local.json`, an untracked local file that also
holds plaintext DB passwords).

The Claude Code docs do **not** document where "always allow" grants are written,
whether `~/.claude/settings.local.json` is read at all, or any way to redirect the
write target (researched via the claude-code-guide agent, 2026-06-28 — questions 2,
3, 4, 6 all came back "NOT DOCUMENTED"). What the docs DO confirm: permissions
**merge (union) across settings files**, and there is no supported knob to point
grant-writes at a non-symlinked file. And what direct observation confirms: the
grants land in `~/.claude/settings.json` (that's the file the recurring drift flows
through). So we cannot rely on redirecting the write — we have to make the write
target a real local file.

The fix sidesteps the documentation gap entirely: **stop symlinking any
runtime-writable settings file into the repo.** `~/.claude/settings.json` and
`~/.claude/settings.local.json` become real local files. The repo keeps the curated
baseline as a *seed* and deploys it by **merging** (union the permission arrays,
baseline wins on config keys) instead of symlinking — so baseline edits still
propagate on re-install (honoring the "edit in repo, re-run install" contract),
runtime grants accumulate only in the local file, and the tracked repo never
receives a grant again. This is robust no matter which user-level file a future
Claude version writes to, because neither is a repo symlink. There's precedent for
non-symlink deployment here: `install.sh vscode` already copy-deploys rather than
symlinking. Everything else (`commands/`, `skills/`, `hooks/`, `claude-global.md`)
stays symlinked — those are not runtime-writable.

This spec does NOT try to prune the baseline's 113 accumulated allow entries — they
already work and pruning is judgment-heavy, separate, lower-priority work. The goal
is to stop *future* pollution, not to perfectly curate the past.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/merge_settings.py` | Python (stdlib `json`) | JSON deep-merge with array-union — needs a real JSON parser, not `sed`/`jq` gymnastics. Matches the bash+Python3 convention already used across `scripts/` (verify-remotes.sh, fleet-*.sh, comms_delivery.py). Per the matrix: config tooling → Python. |
| `scripts/install.sh`, `verify.sh`, `uninstall.sh` | Bash | Existing deploy scripts; this extends them. |
| `settings/settings.local.json.example`, READMEs | JSON / Markdown | Seed template + docs. |

## Overview

**Phase 1 — Make runtime-writable settings local**

1. Change 1 — `scripts/merge_settings.py`: JSON deep-merge helper (baseline → live, union permissions, baseline wins config keys)
2. Change 2 — `install_settings()` in `install.sh`: merge-deploy `settings.json` as a real file (with symlink→real cutover); seed `settings.local.json` as a real local file; stop symlinking both
3. Change 3 — `settings/settings.local.json.example` (sanitized, no secrets) + `.gitignore` re-include for `*.example`

**Phase 2 — Verify + uninstall + docs**

4. Change 4 — `verify.sh`: replace the symlink check for `settings.json` with a "real file, not a repo symlink, superset of baseline" check; drop the `settings.local.json` symlink check
5. Change 5 — `uninstall.sh` + `settings/README.md` + `README.md`: confirm uninstall leaves the real local files; document the merge/seed deploy model

**Phase 3 — Cutover + lessons close-out**

6. Change 6 — Cutover (convert the live symlinks to real files preserving current grants; clean the repo) + lessons.md consolidation (37→~30) + new lesson + memory note update

---

## Phase 1: Make runtime-writable settings local

### Change 1: `scripts/merge_settings.py` — JSON deep-merge helper

**Problem:** Deploying `settings.json` as a real file (not a symlink) needs a way
to push baseline updates into the live file without clobbering the runtime grants
already accumulated there. A union-merge does exactly that.

**File:** `scripts/merge_settings.py` (new file)

**Implementation:**

Stdlib-only (`json`, `sys`, `argparse`, `pathlib`). Signature:
`merge_settings.py <baseline_path> <live_path> [--dry-run]`.

Merge rules (baseline = `settings/settings.json`, live = `~/.claude/settings.json`):

- **`permissions.allow` / `permissions.deny` / `permissions.ask`** (and
  `permissions.additionalDirectories`) → **union**: `sorted(set(baseline ∪ live))`.
  Preserves runtime grants in live AND adds any new baseline entries. (Documented
  limitation, state it in a docstring + the README: a union-merge can ADD but not
  REMOVE a permission — to retract one, edit the live file or add a `deny`.)
- **Every other key** (`hooks`, `model`, `enabledPlugins`, `extraKnownMarketplaces`,
  any future top-level key) → **baseline wins** (baseline value overwrites live).
  These are dev-platform-managed config, not runtime state.
- If `live_path` does not exist or is empty → result is the baseline verbatim
  (first-install seed).
- Write the merged JSON to `live_path` with `indent=2` + trailing newline. Never
  write to `baseline_path`. `--dry-run` prints the merged result to stdout and
  writes nothing.

Resolve nothing relative to a hardcoded home — operate purely on the two path args.
Exit 0 on success, 2 on malformed JSON in either file (print which file).

Pattern reference: the inline-Python registry parsers in `scripts/verify-remotes.sh`
and the structure of `monitoring/comms_delivery.py` (argparse + `load`/`main`).

**Acceptance Test:**

```bash
python3 -c "import ast; ast.parse(open('scripts/merge_settings.py').read()); print('parses')"

# Union preserves live grants + adds baseline entries; baseline wins on config.
tmp=$(mktemp -d)
printf '{"permissions":{"allow":["Bash(a)","Bash(b)"]},"model":"opusplan"}' > "$tmp/base.json"
printf '{"permissions":{"allow":["Bash(b)","Bash(LOCAL_GRANT)"]},"model":"OLD"}' > "$tmp/live.json"
python3 scripts/merge_settings.py "$tmp/base.json" "$tmp/live.json"
python3 -c "
import json; d=json.load(open('$tmp/live.json'))
assert set(d['permissions']['allow'])=={'Bash(a)','Bash(b)','Bash(LOCAL_GRANT)'}, d
assert d['model']=='opusplan', d   # baseline wins on config
print('merge OK — grants preserved, baseline config wins')
"
# First-install seed (no live file):
rm "$tmp/live.json"; python3 scripts/merge_settings.py "$tmp/base.json" "$tmp/live.json"
python3 -c "import json; assert json.load(open('$tmp/live.json'))['model']=='opusplan'; print('seed OK')"
rm -rf "$tmp"
```

---

### Change 2: Rewrite `install_settings()` — merge-deploy, no symlink

**Problem:** `install_settings()` (`scripts/install.sh:94-110`) symlinks both
`settings.json` and `settings.local.json` into `~/.claude/`, making them
write-through into the repo. They must become real local files.

**File:** `scripts/install.sh` (existing, `install_settings()` at line 94)

**Implementation:**

Keep `claude-global.md` and `keybindings.json` as symlinks (not runtime-writable).
Change ONLY the two runtime-writable files:

1. **`settings.json` — merge-deploy as a real file.** Replace
   `link_file "${REPO}/settings/settings.json" "${HOME_CLAUDE}/settings.json"` with:
   - **Cutover:** if `${HOME_CLAUDE}/settings.json` is currently a symlink, capture
     its resolved content first (`cat` follows the link), `rm` the symlink, and
     write that captured content as the initial real `${HOME_CLAUDE}/settings.json`.
     This preserves the grants currently living in the symlinked repo file.
   - Then run `python3 "${REPO}/scripts/merge_settings.py"
     "${REPO}/settings/settings.json" "${HOME_CLAUDE}/settings.json"` to union the
     repo baseline into the live file.
   - Net: first run materializes a real file seeded with current content; every run
     unions baseline → live. Grants stay local; baseline edits propagate.

2. **`settings.local.json` — seed-if-absent as a real local file.** Replace the
   `if [[ -f settings/settings.local.json ]]; then link_file ...` block with: if
   `${HOME_CLAUDE}/settings.local.json` does NOT exist, copy
   `${REPO}/settings/settings.local.json.example` to it (a real file, no symlink).
   If it exists, leave it untouched (never clobber local grants/secrets). Do NOT
   merge — this file is purely local.
   - Cutover: if `${HOME_CLAUDE}/settings.local.json` is currently a symlink,
     capture its content, `rm` the symlink, write the content as a real file (so the
     existing local entries survive the cutover).

3. Update the `linked=` status string to reflect "settings.json (merged),
   settings.local.json (local)".

Use the existing `require_safe_target` guard. Do NOT use `link_file` for these two.

**Acceptance Test:**

```bash
# Dry-run against a temp HOME-CLAUDE to prove no symlink is created for settings.json.
# (Run the real install, then assert the deployed file is a regular file, not a link.)
./scripts/install.sh settings
test ! -L ~/.claude/settings.json && echo "settings.json is a real file (not symlink) ✓"
test ! -L ~/.claude/settings.local.json && echo "settings.local.json is a real file ✓"
# Baseline keys present in the live merged file:
python3 -c "
import json; d=json.load(open('$HOME/.claude/settings.json'))
base=json.load(open('settings/settings.json'))
assert set(base['permissions']['allow']).issubset(set(d['permissions']['allow'])), 'baseline allow not a subset of live'
print('live settings.json is a superset of baseline ✓')
"
# claude-global.md / keybindings stay symlinks:
test -L ~/.claude/CLAUDE.md && echo "claude-global.md still symlinked ✓"
```

---

### Change 3: `settings/settings.local.json.example` + gitignore

**Problem:** `install_settings` now seeds `settings.local.json` from a tracked
`.example` template. That template must exist, must contain NO secrets, and must be
git-tracked (the live `settings/*.local.json` stays ignored per `.gitignore:139`).

**File:** `settings/settings.local.json.example` (new file), `.gitignore` (modify)

**Implementation:**

- Create `settings/settings.local.json.example` — a minimal, **secret-free** seed:

  ```json
  {
    "permissions": {
      "allow": []
    }
  }
  ```

  Add a `_comment` key (or a sibling `settings/README.md` note) explaining this is
  the seed for the machine-local `~/.claude/settings.local.json`; real per-machine
  grants and any secret-bearing command allowlists live ONLY in the deployed local
  file, never in the repo.

- **Consumer Audit** (new `.example` extension under `settings/`):
  `git check-ignore -v settings/settings.local.json.example`. Current `.gitignore`
  has `!settings/*.json` (line 65) and `!settings/*.md` (line 66) but `.example` is
  neither. Add `!settings/*.example` AFTER the `settings/**` exclude (line 42) and
  BEFORE/after the existing re-includes so the example is tracked. Verify the live
  `settings/settings.local.json` is STILL ignored (line 139 `settings/*.local.json`
  must still win — confirm `.example` re-include doesn't accidentally re-admit it;
  `*.local.json` ≠ `*.example`, so they don't collide, but check with
  `git check-ignore`).

**Acceptance Test:**

```bash
git check-ignore -q settings/settings.local.json.example && echo "IGNORED — fix" || echo "example tracked ✓"
git check-ignore -q settings/settings.local.json && echo "live local file ignored ✓" || echo "LEAK — settings.local.json would be tracked"
python3 -c "import json; d=json.load(open('settings/settings.local.json.example')); assert 'PGPASSWORD' not in json.dumps(d), 'secret in example'; print('example is secret-free ✓')"
```

---

## Phase 2: Verify + uninstall + docs

### Change 4: `verify.sh` — real-file superset check, not symlink

**Problem:** `verify.sh` checks `settings.json` and `settings.local.json` with
`check_symlink` (lines 58, 64). After Change 2 they are real files, so those checks
would report false drift. The new invariant: `settings.json` is a real file, NOT a
symlink into the repo, and a superset of the baseline.

**File:** `scripts/verify.sh` (existing, lines ~57-65)

**Implementation:**

- Add a `check_local_settings()` function near `check_symlink` (line ~18): given the
  baseline path and the deployed path, assert the deployed path (a) exists, (b) is
  NOT a symlink (`! -L`) — and specifically NOT a symlink into `${REPO}` (the exact
  regression this spec fixes), (c) its `permissions.allow` is a superset of the
  baseline's (reuse a Python one-liner like Change 2's acceptance test). Print `OK` /
  `X` lines matching the existing `check_symlink` output style; increment the shared
  error counter on failure.
- Replace line 58 `check_symlink ".../settings.json" ...` with
  `check_local_settings "${REPO}/settings/settings.json" "${HOME_CLAUDE}/settings.json"`.
- Remove the `settings.local.json` symlink check (lines 63-65) — it's a purely local
  file now; verify only that IF it exists it is NOT a repo symlink (a one-line guard),
  with no content assertion.
- Leave `claude-global.md` / `keybindings.json` on `check_symlink` (unchanged).

**Acceptance Test:**

```bash
./scripts/install.sh settings   # establish the real-file state
./scripts/verify.sh             # expect: settings section OK, exit 0, no drift
echo "exit: $?"
# Regression guard: a symlinked settings.json must be flagged.
mv ~/.claude/settings.json ~/.claude/settings.json.bak
ln -s "${PWD}/settings/settings.json" ~/.claude/settings.json
./scripts/verify.sh; test $? -ne 0 && echo "verify correctly flags a repo-symlinked settings.json ✓"
rm ~/.claude/settings.json; mv ~/.claude/settings.json.bak ~/.claude/settings.json
```

---

### Change 5: `uninstall.sh` + docs

**Problem:** `uninstall.sh` removes repo-pointing symlinks. After Change 2,
`settings.json` / `settings.local.json` are real local files holding grants (and
secrets) — uninstall must leave them. It already only removes symlinks into `${REPO}`
(`remove_repo_symlinks`, line 17), so real files are safe — but the contract should be
made explicit, and the docs must describe the new model.

**Files:** `scripts/uninstall.sh` (existing, ~line 17), `settings/README.md`
(existing), `README.md` (existing, install/verify sections)

**Implementation:**

- `uninstall.sh`: no behavioral change needed (it skips non-symlinks), but add a
  comment near `remove_repo_symlinks` noting that `settings.json` /
  `settings.local.json` are intentionally real files post-v1.6 and are left in place
  (they hold per-machine grants + secrets). If the current cutover left a stale
  `.bak`, mention nothing — out of scope.
- `settings/README.md`: document the deploy split — `claude-global.md` /
  `keybindings.json` are **symlinked** (live edits); `settings.json` is
  **merge-deployed** as a real file via `merge_settings.py` (baseline unions into the
  live file; runtime grants stay local; baseline can add-but-not-remove a permission);
  `settings.local.json` is **seeded once** from `.example` and never touched again.
  State plainly: never edit `~/.claude/settings.json` expecting the repo to capture
  it — the repo holds the baseline only.
- `README.md`: in the install/verify section, note `settings.json` is copy/merge-
  deployed (not symlinked) so runtime "always allow" grants never reach the repo;
  mention `scripts/merge_settings.py`.

**Acceptance Test:**

```bash
./scripts/uninstall.sh
test -f ~/.claude/settings.json && ! -L ~/.claude/settings.json 2>/dev/null; echo "settings.json survives uninstall as a real file ✓"
grep -q "merge_settings" settings/README.md && grep -q "merge_settings\|merge-deploy" README.md && echo "docs updated ✓"
./scripts/install.sh   # restore full deployment
```

---

## Phase 3: Cutover + lessons close-out

### Change 6: Cutover, lessons consolidation, memory note

**Problem:** The live environment still has the symlinked settings + the unstaged
`settings/settings.json` working-tree drift. Cutover must convert to real files
without losing grants and leave the repo clean. Plus the deferred housekeeping:
`tasks/lessons.md` is at 37 rows (cap ~30).

**Files:** live `~/.claude/` (cutover, no repo write), `settings/settings.json`
(working-tree restore), `tasks/lessons.md`, `planning.md`, `ROADMAP.md`, the memory
note `project_settings_drift_followon`

**Implementation:**

1. **Cutover** (operational, run during `/code`): run `./scripts/install.sh settings`
   (Change 2 logic) so `~/.claude/settings.json` becomes a real file seeded with the
   CURRENT live content (baseline + the working-tree drift, which is what the machine
   uses today) — no grants lost. Then `git restore settings/settings.json` to drop the
   working-tree drift so the tracked baseline returns to its clean committed state.
   Verify `git status` shows `settings/settings.json` clean.
2. **lessons.md consolidation** (37 → ~30): delete the already-promoted Consumer-Audit
   *specifics* — the 2026-05-11 rows explicitly marked `→ Rule in dev/CLAUDE.md` (the
   `hooks/_emit_event.py`, the "2nd instance", the v0.6 "fired twice" rows) whose
   lesson now lives in the CLAUDE.md "Consumer Audit" rule. Keep ONE representative
   Consumer-Audit row if useful for context; delete the redundant duplicates. Do NOT
   delete active, un-promoted lessons. Target ≤ 31 rows.
3. **New lesson** (this fix): "A settings/config file that the tool writes to at
   runtime must never be a symlink into a tracked repo — deploy it as a real local
   file seeded/merged from a tracked baseline. Symlinking `~/.claude/settings.json` →
   repo made every 'always allow' grant pollute the public repo for months."
4. **Memory note:** update `project_settings_drift_followon` to record the fix landed
   in v1.6 (status: resolved), or note it in the body.
5. **planning.md / ROADMAP.md:** v1.6 entry (honest scope: stops future pollution; does
   not prune the existing 113-entry baseline; union-merge can't retract a permission).

**Acceptance Test:**

```bash
# Cutover left the repo clean:
git status --porcelain settings/settings.json   # expect: empty (clean)
test ! -L ~/.claude/settings.json && echo "live settings.json is a real file ✓"
# lessons within cap:
n=$(grep -cE '^\| 202[0-9]-' tasks/lessons.md); echo "lessons rows: $n"; [ "$n" -le 31 ] && echo "within cap ✓"
# Roadmap entry present:
grep -q "v1.6: Local Settings Isolation" ROADMAP.md && echo "roadmap updated ✓"
./scripts/check_spec_taxonomy.sh
```

---

## What NOT to Do

- **Do not try to redirect Claude's grant-write target via a settings key.** No such
  knob is documented (researched 2026-06-28). The fix is structural: make the write
  target a real local file, not a repo symlink.
- **Do not keep `settings.json` symlinked "but add a guard."** Any symlink into the
  repo is the bug. It must become a real file.
- **Do not clobber `~/.claude/settings.local.json` on install.** It holds per-machine
  grants and secret-bearing command allowlists. Seed-if-absent only.
- **Do not commit secrets.** `settings/settings.local.json.example` must be secret-free
  (no PGPASSWORD values). The live `settings/settings.local.json` stays gitignored.
- **Do not prune the 113-entry baseline in this spec.** Out of scope — they work;
  pruning is separate, judgment-heavy, lower-priority.
- **Do not union-merge `settings.local.json`.** Only `settings.json` merges from the
  baseline; the local file is purely local (seed-once).
- **Do not delete active, un-promoted lessons** during the consolidation — only the
  duplicates already promoted to the CLAUDE.md Consumer-Audit rule.
- **Do not write merged output back to `settings/settings.json`.** `merge_settings.py`
  writes to the LIVE path only; the repo baseline is read-only input.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/merge_settings.py` | New | JSON deep-merge: union permissions, baseline wins config keys; writes live only |
| `scripts/install.sh` | Modify | `install_settings()` — merge-deploy `settings.json` as a real file (symlink→real cutover); seed `settings.local.json` real local; stop symlinking both |
| `settings/settings.local.json.example` | New | Secret-free seed for the machine-local settings.local.json |
| `.gitignore` | Modify | `!settings/*.example` re-include; confirm `settings/*.local.json` still ignored |
| `scripts/verify.sh` | Modify | `check_local_settings()` — real file, not a repo symlink, superset of baseline; drop settings.local.json symlink check |
| `scripts/uninstall.sh` | Modify | Comment: real local settings files are left in place |
| `settings/README.md` | Modify | Document the merge/seed deploy model |
| `README.md` | Modify | Note settings.json is merge-deployed, not symlinked |
| `tasks/lessons.md` | Modify | Consolidate 37→≤31 (delete promoted Consumer-Audit dups); add the symlink-write lesson |
| `planning.md`, `ROADMAP.md` | Modify | v1.6 entry |
| memory `project_settings_drift_followon` | Modify | Mark resolved in v1.6 |

## Implementation Order

1. Change 1 (`merge_settings.py`) — foundation; install depends on it.
2. Change 3 (`.example` + gitignore) — install's seed depends on the example existing.
3. Change 2 (`install_settings` rewrite) — run the cutover during its acceptance test.
4. Change 4 (`verify.sh`) — verify the new real-file state.
5. Change 5 (`uninstall.sh` + docs).
6. Change 6 (cutover finalize + lessons + memory + roadmap).

Single branch `v1.6/local-settings-isolation` — the changes are tightly coupled
(merge helper ↔ install ↔ verify all describe one deploy model) and small. Per the
v0.6/v1.4 "tightly coupled → single branch" carve-out.

## Verification Checklist

- [ ] `scripts/merge_settings.py`: parses; union preserves live grants + adds baseline; baseline wins config keys; first-install seeds verbatim
- [ ] After `install.sh settings`: `~/.claude/settings.json` and `settings.local.json` are real files (`! -L`); `claude-global.md`/`keybindings.json` stay symlinks
- [ ] Live `settings.json` is a superset of the baseline's `permissions.allow`
- [ ] `settings/settings.local.json.example` is tracked + secret-free; live `settings/settings.local.json` stays gitignored
- [ ] `verify.sh` passes on the real-file state AND flags a repo-symlinked settings.json (regression guard)
- [ ] `uninstall.sh` leaves the real local settings files in place
- [ ] Cutover: `git status` shows `settings/settings.json` clean; no grants lost from the live file
- [ ] `tasks/lessons.md` ≤ 31 rows; new symlink-write lesson present; no active lesson deleted
- [ ] `settings/README.md` + `README.md` document the merge/seed model
- [ ] `./scripts/gate_fast.sh` green; `./scripts/check_spec_taxonomy.sh` clean
- [ ] Memory note `project_settings_drift_followon` marked resolved
- [ ] No secrets committed; baseline not pruned; `merge_settings.py` never writes the repo baseline
- [ ] `/security-review` — recommended: this touches credential-bearing local settings + a secret-free example. Run before `/gate fast`.
```
