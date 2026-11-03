# Link Deps Trailing Slash

## Coding Specification for Implementation

Fixes issue #154. Roadmap Phase v1.49: Link Deps Trailing Slash. One Spec Phase, one branch, one PR: the three source changes share one manifest-parsing rule and the parity test fails if they land separately.

## Design Philosophy

`shell/worktree/link-deps.sh` prints `linked` for an entry whether or not the link was made. Probed on 2026-11-03 (scratch fixtures, script run with explicit main and worktree paths):

- `a/node_modules/`, `a/node_modules//` and `node_modules/` all fail: `ln: failed to create symbolic link '.../wt/a/node_modules/': No such file or directory`. The script still prints `[link-deps] linked a/node_modules/`, counts it (`1 linked, 0 missing`) and exits 0. Nothing exists in the worktree afterwards.
- The same failure happens for an unrelated reason: when `mkdir -p "$(dirname "${dst}")"` fails (probed with a read-only worktree directory; also when a path component is a regular file, `mkdir -p` exits 1 with `File exists`), the `mkdir` error is ignored, `ln` then fails, and the script still prints `linked`. So the defect is "the result of `mkdir` and `ln` is never checked", and the trailing slash is one way to trigger it.
- The entry `/` alone is accepted: `src` and `dst` become `${MAIN}//` and `${WT}//`, it prints `linked /`, and `ln` links inside the existing worktree directory. After stripping slashes this entry is empty and must be rejected.

User decision (issue #154 pick-up, 2026-11-03): strip trailing slashes, and report `ln` failures honestly. Both are done in `link-deps.sh`. `scripts/check-dep-install-needed.sh` (v1.48) copies the manifest parsing inline because `link-deps.sh` runs from the deployed `~/.claude/worktree/` path where `scripts/lib/` does not exist, so it cannot share. Its copy must strip the same way, or it would stop naming a directory that now links. `tests/dep-install-notice/run.sh` already runs one manifest through both scripts; its expectations change here, and it is the check that the two copies agree.

Exit status: a failed link now makes the script exit 1 (it exited 0 before). This is a contract change to `Exit: 0 linked (or nothing to link), 2 usage/derivation error` in the usage text. A missing source stays a warning with exit 0, as documented. Callers (`commands/plan.md:58`, `commands/code.md:53`, `commands/merge.md:223`) run the script as a plain command and read its output, so a non-zero exit shows up as a failed command instead of a line nobody reads. Whether kermit-v3 or any other consumer wraps the script and treats a non-zero exit specially is unverified.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `shell/worktree/link-deps.sh`, `scripts/check-dep-install-needed.sh`, tests | Bash | Edits to existing Bash scripts; thin filesystem glue. No new component. |

## Overview

Phase 1: Report link failures and strip trailing slashes

1. `link-deps.sh`: strip trailing slashes, reject an empty entry, check `mkdir` and `ln`, count and report failures, exit 1 on failure.
2. `check-dep-install-needed.sh`: strip trailing slashes the same way.
3. Tests: new cases in `tests/worktree/run.sh`; flip the trailing-slash expectations in `tests/dep-install-notice/run.sh`.
4. Docs: `shell/worktree/README.md`, usage text, comments that describe the old behaviour.

---

## Phase 1: Report link failures and strip trailing slashes

### Change 1: link-deps.sh strips trailing slashes and reports failures

**Problem:** A manifest entry with a trailing slash silently fails to link, and any `mkdir` or `ln` failure is reported as `linked`.

**File:** `shell/worktree/link-deps.sh` (existing; manifest loop at lines 95-113, usage text at lines 32-46, header comment at lines 1-4)

**Implementation:**

1. After the existing trim of trailing whitespace (line 100) and before the `[[ -z "${line}" ]] && continue` check (line 101), strip every trailing `/`:

   ```bash
   while [[ "${line}" == */ ]]; do line="${line%/}"; done
   ```

   Keep the order: comment strip, trim leading whitespace, trim trailing whitespace, strip trailing slashes, skip if empty. An entry that was only slashes (`/`, `//`) becomes empty. A truly blank line must still be skipped silently, so detect the slash-only case BEFORE stripping: remember `[[ -n "${line}" ]]` prior to the loop, and if the line was non-empty but is empty after stripping, print `[link-deps] WARN invalid entry (no path): <original>` to stderr, count it as failed, and `continue`.
2. Check the results. Replace lines 109-112 so that a failed `mkdir -p "$(dirname "${dst}")"` or a failed `ln -sfn "${src}" "${dst}"` prints `[link-deps] WARN could not link: <line>` to stderr, increments a new `failed` counter, and `continue`s without printing `linked` or incrementing `linked`. Keep the tool's own error text visible (do not redirect `mkdir`/`ln` stderr to /dev/null). The script has `set -uo pipefail` and no `-e`; do not add `-e`, the loop must carry on after a failure so one bad entry does not hide the others.
3. Print the entry in its stripped form in the `linked` line (`linked a/node_modules`). Declare `failed=0` next to `linked=0` and `missing=0` (lines 95-96).
4. Summary line (line 115): keep `[link-deps] N linked, M missing` exactly when `failed` is 0 (existing tests grep `"1 linked, 0 missing"`, `"2 linked, 0 missing"`). When `failed` is above 0, print `[link-deps] N linked, M missing, K failed`.
5. Exit status: `exit 1` when `failed` is above 0, else `exit 0` (line 116). Update the usage text `Exit:` line (line 44) to `0 linked (or nothing to link), 1 one or more links failed, 2 usage/derivation error`. Add one sentence to the usage text and the file header: trailing slashes on an entry are ignored.

**Acceptance Test:**

```bash
bash -n shell/worktree/link-deps.sh
# fixtures as in tests/worktree/run.sh (mktemp -d, <main>/.claude/worktree-deps, <wt>):
#   manifest "a/node_modules/" with <main>/a/node_modules present
#   -> exit 0, "linked a/node_modules", "1 linked, 0 missing", <wt>/a/node_modules is a symlink to <main>/a/node_modules
#   manifest "a/node_modules//" and "node_modules/" -> same, linked
#   manifest "/" -> WARN invalid entry, exit 1
#   <wt>/a is a regular file, manifest "a/node_modules" then ".env" ->
#       "linked .env" only, WARN could not link: a/node_modules, "1 linked, 0 missing, 1 failed", exit 1
```

---

### Change 2: check-dep-install-needed.sh strips trailing slashes the same way

**Problem:** After Change 1, `frontend/node_modules/` links. The v1.48 notice script, which deliberately does not strip, would stop reporting that directory.

**File:** `scripts/check-dep-install-needed.sh` (existing; manifest loop at lines 99-114, comment at lines 36-46)

**Implementation:**

1. Add the same `while [[ "${line}" == */ ]]; do line="${line%/}"; done` after the trailing-whitespace trim (line 102) and before `[[ -z "${line}" ]] && continue` (line 103). The notice script has no stderr warnings for bad entries (it must stay quiet and exit 0), so a slash-only line simply becomes empty and is skipped. Do not print anything for it.
2. Rewrite the comment block at lines 36-44. It currently says the copy does not drop a trailing `/` because `link-deps.sh` does not. New text: the copy strips trailing slashes exactly as `link-deps.sh` does, `link-deps.sh` is the source of truth, and `tests/dep-install-notice/` runs both over one manifest so they cannot drift. Keep the sentences about why it cannot share code (deployed path, no `scripts/lib/`) and about the main-checkout derivation.

**Acceptance Test:**

```bash
bash -n scripts/check-dep-install-needed.sh
# repo whose manifest is "frontend/node_modules/", commit changing frontend/package.json
# -> prints "frontend/: package.json" and the install command (before this change: nothing)
```

---

### Change 3: Tests

**Problem:** Nothing exercises a trailing slash or a failed link, which is how both bugs survived.

**File:** `tests/worktree/run.sh` (existing; link-deps cases at lines 40-165) and `tests/dep-install-notice/run.sh` (existing; messy manifest at line 192, check 9 at lines 195-203, parity at lines 205-224)

**Implementation:**

1. `tests/worktree/run.sh`: add cases after Test 4 (line 83), following the existing pattern (`mktemp -d`, extend the `trap` list, `record_pass`/`record_fail`):
   - Trailing slash links: manifest `frontend/node_modules/` plus `frontend/node_modules//`, both sources present, assert exit 0, `-L` on `<wt>/frontend/node_modules`, `readlink` equals `<main>/frontend/node_modules`, output has `1 linked, 0 missing` (the two lines name the same path, so use two separate fixtures or two different directories; do not assert a count that depends on `ln -sfn` replacing an existing link).
   - Root `node_modules/` links as `<wt>/node_modules`.
   - Failure is reported: `<wt>/a` created as a regular file (`: > "${wt}/a"`), manifest `a/node_modules` then `.env`, both sources present. Assert: exit 1; output (stdout+stderr) contains `WARN could not link: a/node_modules`; contains `1 linked, 0 missing, 1 failed`; does NOT contain `linked a/node_modules`; `<wt>/.env` is a symlink (the loop kept going). This case does not depend on file permissions, so it works when the gate runs as root.
   - Slash-only entry: manifest `/`, assert exit 1 and `WARN invalid entry`.
   - A normal run still prints exactly `N linked, M missing` with no `failed` suffix (the existing "1 linked, 0 missing" and "2 linked, 0 missing" assertions already cover it; leave them untouched).
2. `tests/dep-install-notice/run.sh`: change check 9 (lines 198-203). The messy manifest keeps its `dispatch/node_modules/` line, and the assertion changes from `! has "dispatch/"` to `has "dispatch/: package.json"`; update the `record_pass`/`record_fail` text ("trailing-slash entry recognised"). The parity block (lines 205-224) needs no code change: `dispatch` is now both linked and recognised, so the two sets are `frontend server dispatch root`. Update the comments around it (lines 190-192 and the header of check 9) that say a trailing-slash entry is not recognised.
3. Mutation proof, one mutation per tool call, restore from a saved copy and `diff` to confirm identical: (a) remove the slash-stripping loop from `link-deps.sh` -> the new trailing-slash cases and check 9/parity must fail; (b) remove the `ln` result check -> the failure case must fail; (c) remove the slash-stripping loop from `check-dep-install-needed.sh` only -> check 9 and parity must fail (this proves the parity test guards the two copies); (d) keep `exit 0` at the end -> the failure case must fail.

**Acceptance Test:**

```bash
bash tests/worktree/run.sh        # via the gate; all new cases PASS
./scripts/gate_fast.sh            # 594 PASS before this change; expect that plus the new cases, 0 FAIL
```

---

### Change 4: Docs

**Problem:** `shell/worktree/README.md:40` tells people to write entries without a trailing slash, and says the script prints `linked` on failure. Both stop being true.

**File:** `shell/worktree/README.md` (existing; line 40), `docs/CONCURRENT-DEV.md` (existing), `ROADMAP.md`, new `tasks/shipped/<date>-v1.49-link-deps-trailing-slash.md`

**Implementation:**

1. `shell/worktree/README.md:40`: remove the sentence `Write entries without a trailing slash: ... still prints linked.` Replace with: trailing slashes on an entry are ignored (`frontend/node_modules/` is the same as `frontend/node_modules`); an entry that cannot be linked prints `WARN could not link: <entry>` and the script exits 1 after trying the rest. Update the sentence about `/merge` watching `node_modules` entries only if it now reads wrongly (it does not mention slashes).
2. `docs/CONCURRENT-DEV.md`: grep for `trailing` and `link-deps` first (a v1.48 `grep` found no trailing-slash text in this file, 2026-11-03); add a line only if the "Turning it on" section describes the manifest format in a way that needs the exit-status note. If nothing needs changing, leave the file alone and say so in the shipped record.
3. `ROADMAP.md`: add the v1.49 entry in the existing list form after v1.48, `(complete — <date>, ...)`, with a scope-honesty sentence. `tasks/shipped/`: new file with the problem, what shipped, verification (gate count, the four mutations), and scope honesty.
4. Do NOT edit `tasks/shipped/2026-11-03-v1.48-dependency-install-notice.md` or `tasks/dependency-install-notice-spec.md`: they record what was true at v1.48. The v1.49 shipped file says the v1.48 deviation is now resolved.

**Acceptance Test:**

```bash
grep -n 'without a trailing slash' shell/worktree/README.md   # no match
./scripts/gate_fast.sh                                        # PASS (taxonomy and markdown checks included)
```

---

## What NOT to Do

- Do not add `set -e` to `link-deps.sh`; the loop must continue past a failed entry.
- Do not redirect `mkdir`/`ln` stderr away; the tool's own message is the diagnosis.
- Do not change the invocation form. `bash ~/.claude/worktree/link-deps.sh` takes no arguments and no variables (`commands/plan.md:58`, `commands/code.md:53`); nothing here touches that.
- Do not print a `failed` count when it is 0; the existing output shape (`N linked, M missing`) is asserted by tests and may be parsed by consumers.
- Do not make a missing source an error. It stays a warning with exit 0.
- Do not fix the other `link-deps.sh` oddity found while probing: when the destination is already a real directory (probed: `<wt>/a/node_modules` existing as a directory), `ln -sfn` creates the link INSIDE it, prints `linked a/node_modules`, and no link exists at the destination. That is a separate defect with a separate decision (replace, warn, or refuse). Record it in the shipped file and offer it as a follow-on issue; do not change it here.
- Do not run the real install or touch any consumer project's manifest or copy of the script. Whether any consumer manifest currently has a trailing-slash entry was not scanned (issue #154 says so); do not claim it.
- Do not edit `~/.claude/` directly. The deployed script is a symlink to the main checkout (verify with `ls -l ~/.claude/worktree/link-deps.sh` before writing the shipped file's claim that the fix is live at merge).

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `shell/worktree/link-deps.sh` | Modify | Strip trailing slashes; reject slash-only entries; check `mkdir`/`ln`; `failed` counter; exit 1 on failure; usage text |
| `scripts/check-dep-install-needed.sh` | Modify | Strip trailing slashes the same way; rewrite the comment that said it does not |
| `tests/worktree/run.sh` | Modify | Trailing-slash, root, failure-reported, slash-only cases |
| `tests/dep-install-notice/run.sh` | Modify | Check 9 now expects `dispatch/` recognised; parity comments |
| `shell/worktree/README.md` | Modify | Replace the "write entries without a trailing slash" sentence |
| `docs/CONCURRENT-DEV.md` | Modify (only if needed) | See Change 4 |
| `ROADMAP.md` | Modify | v1.49 entry |
| `tasks/shipped/<date>-v1.49-link-deps-trailing-slash.md` | New | Phase record |
| `tasks/link-deps-trailing-slash-spec.md` | New | This spec |

## Implementation Order

1. Change 1 (`link-deps.sh`), then Change 2 (notice script) — the parity test needs both.
2. Change 3 tests; run `bash tests/worktree/run.sh` and `bash tests/dep-install-notice/run.sh` directly, then the four mutations.
3. Change 4 docs, then `./scripts/gate_fast.sh`.

## Verification Checklist

- [ ] `a/node_modules/`, `a/node_modules//` and `node_modules/` link and are reported `linked` (probe script from 2026-11-03, rerun)
- [ ] A failed `mkdir` or `ln` prints `WARN could not link`, is not counted as linked, and the script exits 1 after trying every entry
- [ ] A slash-only entry is rejected with a warning and exit 1
- [ ] Output is unchanged when nothing fails (`N linked, M missing`)
- [ ] `tests/dep-install-notice` parity passes with `dispatch` linked and recognised
- [ ] Four mutations each fail the check meant to catch them; files restored and diffed identical
- [ ] `./scripts/gate_fast.sh` PASS, count reported from live output
- [ ] No consumer project file touched; no claim about consumer manifests
