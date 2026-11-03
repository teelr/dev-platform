# Link Deps Existing Destination

## Coding Specification for Implementation

Fixes issue #156. Roadmap Phase v1.50: Link Deps Existing Destination. One Spec Phase, one branch, one PR: a single check in one script, its tests, and the docs that describe it.

## Design Philosophy

`shell/worktree/link-deps.sh` runs `ln -sfn "${src}" "${dst}"` without looking at what already exists at `dst`. Probed on 2026-11-03 (scratch fixtures, script run with explicit main and worktree paths, `/home/rich/dev/shell/worktree/link-deps.sh` at v1.49):

| Destination already in the worktree | What happens today |
| ----------------------------------- | ------------------ |
| Real directory, empty or not | The link is created INSIDE it (`<dst>/node_modules`), the script prints `linked`, exit 0, and nothing is linked at `<dst>`. The directory's own files stay. |
| Real regular file (a worktree-local `.env` holding `WORKTREE-LOCAL=1`) | Silently replaced by the symlink; the content is gone. Prints `linked`, exit 0. |
| Symlink to a directory (a second run of the script) | Replaced in place, no nesting. Idempotent. |
| Broken symlink | Replaced. |

The directory case is the same symptom as issue #154, a false `linked`, by a path that v1.49's check of the `ln` result cannot see because `ln` succeeds. The file case is a silent data loss.

User decisions (issue #156 pick-up, 2026-11-03): refuse an existing real directory, and refuse an existing real file too. "Refuse" reuses the v1.49 failure path: `WARN could not link: <entry> (destination exists and is not a symlink)` on stderr, the entry counted as failed, the remaining entries still tried, exit 1 at the end with `N linked, M missing, K failed`. Nothing is deleted or moved. One rule covers both: if the destination exists and is not a symlink, refuse; if it is absent, or any symlink (including a broken one), proceed as today.

Risk check, read-only (`bash` loop over `/home/rich/dev/projects/*/.claude/worktree-deps` with `git -C <project> ls-files -- <entry>`, 2026-11-03): none of the 16 live manifest entries in kermit, kermit-pa, kermit-v3, keystone and SQRL has a tracked file, so a fresh worktree from `origin/<default>` has nothing at those paths and the new check does not fire on a first run. It fires only when something created a real file or directory there before `link-deps.sh` ran (for example a dev server started in the worktree first, which creates `frontend/.next`), and then it says so, where today it would link inside it or overwrite it. Whether such a case has happened in practice is unverified.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `shell/worktree/link-deps.sh`, tests | Bash | An added test in an existing Bash script; thin filesystem glue. No new component. |

## Overview

Phase 1: Refuse a destination that exists and is not a symlink

1. `link-deps.sh`: refuse an existing non-symlink destination, using the v1.49 failure path.
2. Tests: new cases in `tests/worktree/run.sh`.
3. Docs: usage text, header comment, `shell/worktree/README.md`, ROADMAP entry, shipped record.

---

## Phase 1: Refuse a destination that exists and is not a symlink

### Change 1: link-deps.sh refuses an existing real file or directory

**Problem:** A real directory at the destination gets the link created inside it while the script prints `linked`; a real file is silently overwritten.

**File:** `shell/worktree/link-deps.sh` (existing; manifest loop at lines 103-134, usage text at lines 32-48, header comment at lines 1-6)

**Implementation:**

1. Insert a check between the source-missing block (lines 120-124) and the `mkdir`/`ln` block (lines 125-133):

   ```bash
   if [[ -e "${dst}" && ! -L "${dst}" ]]; then
       echo "[link-deps] WARN could not link: ${line} (destination exists and is not a symlink)" >&2
       failed=$((failed + 1))
       continue
   fi
   ```

   `-e` follows symlinks, so a symlink to something that exists is `-e` true and `-L` true, and is let through; a broken symlink is `-e` false and is let through; only a real file or directory is `-e` true and `-L` false. Keep `ln -sfn` unchanged for the cases that pass. Reuse the `failed` counter and the end-of-script summary and `exit 1` that v1.49 added; do not add a second counter or a new exit code.
2. Wording must keep the prefix `WARN could not link: <entry>`, because `tests/worktree/run.sh` (v1.49 case 4a-3) greps for it.
3. Update the usage text (lines 41-45) with one sentence: an entry whose destination already exists as a real file or directory is refused, and a symlink there is replaced. Add the same sentence to the file header comment. Leave the self-link guard comment at lines 78-82 as it is; it describes a different case (main checkout and worktree being the same directory).

**Acceptance Test:**

```bash
bash -n shell/worktree/link-deps.sh
# fixtures as in tests/worktree/run.sh (mktemp -d, <main>/.claude/worktree-deps, <wt>):
#   <wt>/a/node_modules is a real non-empty directory, manifest "a/node_modules"
#   -> exit 1, "WARN could not link: a/node_modules (destination exists and is not a symlink)",
#      "0 linked, 0 missing, 1 failed", no "linked a/node_modules", the directory's own files intact,
#      and no <wt>/a/node_modules/node_modules
#   <wt>/.env is a real file containing WORKTREE-LOCAL=1, manifest ".env"
#   -> exit 1, same WARN, content of <wt>/.env unchanged, still a regular file
#   run the script twice on a clean worktree -> second run exit 0, "1 linked, 0 missing"
#   <wt>/a/node_modules is a broken symlink -> replaced, exit 0
```

---

### Change 2: Tests

**Problem:** Nothing exercises an existing destination, which is how both behaviours went unnoticed.

**File:** `tests/worktree/run.sh` (existing; the v1.49 block of cases 4a-1 to 4a-4 is at lines 85-145, with `rm -rf "${tmp4a}"` closing it before the "Tests 4b-4g" comment at line 146)

**Implementation:**

1. Add cases 4a-5 to 4a-8 inside the v1.49 block, before its closing `rm -rf "${tmp4a}"`, reusing `tmp4a` and its pattern (build `m5`/`w5` etc. under it; `record_pass`/`record_fail`):
   - 4a-5, real directories refused: manifest `a/node_modules`, `b/node_modules`, `.env`; main has all three sources; `<wt>/a/node_modules` is a real directory holding `tracked.txt`, `<wt>/b/node_modules` is a real EMPTY directory. Assert: exit 1; output has `WARN could not link: a/node_modules (destination exists and is not a symlink)` and the same for `b/node_modules`; output has `1 linked, 0 missing, 2 failed`; no line `linked a/node_modules` or `linked b/node_modules`; `<wt>/a/node_modules/tracked.txt` still exists; neither directory contains a `node_modules` entry; `<wt>/.env` is a symlink (the loop kept going).
   - 4a-6, real file refused and preserved: `<wt>/.env` is a regular file containing `WORKTREE-LOCAL=1`, manifest `.env`. Assert: exit 1; the WARN line; `<wt>/.env` is not a symlink (`! -L`) and `cat` still prints `WORKTREE-LOCAL=1`.
   - 4a-7, second run is idempotent: clean worktree, manifest `a/node_modules`, run twice. Assert both runs exit 0, the second prints `1 linked, 0 missing`, and `readlink "<wt>/a/node_modules"` equals `<main>/a/node_modules` (no nested link inside the target).
   - 4a-8, a broken symlink is replaced: `ln -s /nonexistent-<name> <wt>/a/node_modules` first; run; assert exit 0, `1 linked, 0 missing`, and `readlink` equals `<main>/a/node_modules`.
2. Mutation proof, one mutation per tool call, restore from a saved copy and `diff` to confirm identical:
   - (a) delete the new `if` block -> 4a-5 and 4a-6 must fail.
   - (b) change the condition to `[[ -d "${dst}" && ! -L "${dst}" ]]` (directories only) -> 4a-6 must fail, 4a-5 must still pass.
   - (c) change the condition to `[[ -e "${dst}" || -L "${dst}" ]]` (refuse symlinks too) -> 4a-7 and 4a-8 must fail.
   - (d) delete the `failed=$((failed + 1))` line inside the new block -> 4a-5 and 4a-6 must fail (summary and exit code).

**Acceptance Test:**

```bash
bash tests/worktree/run.sh      # new cases PASS
./scripts/gate_fast.sh          # 598 PASS before this change; expect 598 + the new cases, 0 FAIL
```

---

### Change 3: Docs

**Problem:** `shell/worktree/README.md:40` describes the v1.49 failure reporting but not this case, and nothing tells a user why a first-run link can now be refused.

**File:** `shell/worktree/README.md` (existing; line 40), `ROADMAP.md`, new `tasks/shipped/<date>-v1.50-link-deps-existing-destination.md`

**Implementation:**

1. `shell/worktree/README.md:40`: after the sentence that ends `A missing source stays a warning with exit 0.` add: an entry whose destination already exists in the worktree as a real file or directory is refused with `WARN could not link: <entry> (destination exists and is not a symlink)` and counted as failed; nothing is deleted. A symlink at the destination (including a broken one) is replaced, so running the script again is safe. To fix a refusal, move or delete the real file or directory yourself and run the script again.
2. `ROADMAP.md`: add the v1.50 entry in the existing list form after v1.49, `(complete — <date>, ...)`, with a scope-honesty sentence. `tasks/shipped/`: new file with the problem (the probe table above), what shipped, verification (gate count, four mutations), and scope honesty.
3. Do NOT edit `tasks/shipped/2026-11-03-v1.49-link-deps-trailing-slash.md` or `tasks/link-deps-trailing-slash-spec.md`: they record what was true at v1.49. The v1.50 shipped file says the "found, not fixed" item in v1.49 is resolved.
4. `docs/CONCURRENT-DEV.md` describes the manifest format only at the level of "symlinks each of these"; grep it for `real file`, `overwrit` and `replac` first (v1.49 found nothing relevant) and leave it alone if that is still true, saying so in the shipped record.

**Acceptance Test:**

```bash
grep -n 'destination exists and is not a symlink' shell/worktree/README.md shell/worktree/link-deps.sh   # both match
./scripts/gate_fast.sh                                                                                    # PASS
```

---

## What NOT to Do

- Do not delete, move or back up anything at the destination. The decision is to refuse and tell the user; removing a directory that may hold tracked or hand-made files is exactly what was rejected.
- Do not refuse a symlink at the destination, including a broken one or one that already points at the right place. Re-running the script must stay safe (case 4a-7), and a stale or broken link is replaced as today.
- Do not add a second failure counter, a new exit code, or a different WARN prefix. Reuse v1.49's `failed`, exit 1 and `WARN could not link:`.
- Do not add `set -e`; the loop must continue past a refused entry (case 4a-5 asserts `.env` still links).
- Do not change the invocation form: `bash ~/.claude/worktree/link-deps.sh` takes no arguments and no variables (`commands/plan.md:58`, `commands/code.md:53`).
- Do not change `scripts/check-dep-install-needed.sh`. It only reads the manifest to name directories; whether the link was made is not its concern, and the parity test compares the set of entries recognised, which this change does not touch.
- Do not touch any consumer project's files or manifests. The read-only `ls-files` check above is the only cross-project access, and no claim beyond its output should be made about consumers.
- Do not edit `~/.claude/` directly. `ls -l ~/.claude/worktree/link-deps.sh` showed a symlink to the main checkout on 2026-11-03; re-verify before writing the shipped file's claim that the fix is live at merge.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `shell/worktree/link-deps.sh` | Modify | Refuse a destination that exists and is not a symlink; usage text and header |
| `tests/worktree/run.sh` | Modify | Cases 4a-5 to 4a-8 |
| `shell/worktree/README.md` | Modify | Describe the refusal and how to resolve it |
| `ROADMAP.md` | Modify | v1.50 entry |
| `tasks/shipped/<date>-v1.50-link-deps-existing-destination.md` | New | Phase record |
| `tasks/link-deps-existing-destination-spec.md` | New | This spec |

## Implementation Order

1. Change 1 (`link-deps.sh`), then run the probe fixtures from its Acceptance Test by hand.
2. Change 2 tests; run `bash tests/worktree/run.sh`, then the four mutations.
3. Change 3 docs, then `./scripts/gate_fast.sh`.

## Verification Checklist

- [ ] A real non-empty directory and a real empty directory at the destination are refused, left untouched, and no link is created inside them
- [ ] A real file at the destination is refused and its content is unchanged
- [ ] A symlink at the destination (valid, to a directory, or broken) is replaced; a second run is idempotent
- [ ] A refused entry does not stop the entries after it; summary reads `N linked, M missing, K failed`; exit 1
- [ ] Output and exit status are unchanged when no destination exists
- [ ] Four mutations each fail the case meant to catch them; file restored and diffed identical
- [ ] `./scripts/gate_fast.sh` PASS, count reported from live output
- [ ] No consumer project file touched; no claim about consumers beyond the `ls-files` result
