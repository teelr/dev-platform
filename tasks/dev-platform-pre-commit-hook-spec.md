# v1.2 Pre-commit Git Hook

## Coding Specification for Implementation

## Design Philosophy

[CLAUDE.md:114](CLAUDE.md#L114) declares: "NEVER commit before `/gate fast` passes. NEVER merge before CI green." Today this is enforced by reading the rule and remembering. Memory degrades under cognitive load. A mechanical git-hook guard converts the rule into refusal that fires on every `git commit` — same shape as branch protection on `main`: take the human-discipline rule and make it impossible to bypass without explicit intent.

v0.4's testing-spec at [tasks/dev-platform-testing-spec.md:545-547](tasks/dev-platform-testing-spec.md#L545-L547) deferred the pre-commit hook to "a future small spec." v1.2 IS that future small spec. Two other v0.4 deferred items (`gate_full.sh` per-template builds, performance benchmarks) stay deferred — neither has accumulated evidence of need since v0.4 closed.

The hook is **universally installable** across `teelr/dev-*` repos: looks for `scripts/gate_fast.sh` at the repo root, no-ops if absent, refuses on failure otherwise. **Opt-in stays opt-in** — install symlinks the hook into `~/.claude/git-hooks/`; the user runs `git config core.hooksPath ~/.claude/git-hooks/` per-repo to activate. Auto-writing repo-level git config is the kind of "magic" that surprises users and breaks workflows; we leave the activation step explicit.

Per the small-Phase precedent at v0.6 ([tasks/lessons.md:27](tasks/lessons.md) — "small Roadmap Phases fitting in <200 LOC can ship as a single branch/PR"), v1.2 is **one Phase, one branch, one PR**. The branch is `v1.2/pre-commit-hook`.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `shell/git-hooks/pre-commit` | Bash | Git hooks are POSIX shell scripts by convention. Pure bash matches existing tooling. Zero new dependencies. |
| `scripts/install.sh` extension | Bash | Inline extension to existing bash installer. Same pattern as `install_vscode()` / `install_hooks()`. |
| `tests/git-hooks/run.sh` | Bash | Per-suite runner. Same pattern as other `tests/<suite>/run.sh` runners. |

No new languages introduced. v1.2 tightens existing infrastructure.

## Overview

One Phase, four Changes:

1. **Change 1:** `shell/git-hooks/pre-commit` template + `shell/git-hooks/README.md` directory contract.
2. **Change 2:** Extend `scripts/install.sh` with a `git-hooks` category. Extend `scripts/uninstall.sh` + `scripts/verify.sh` symmetrically.
3. **Change 3:** `tests/git-hooks/run.sh` fixture suite covering no-gate / passing-gate / failing-gate / bypass / install-integration behaviors.
4. **Change 4:** End-to-end acceptance + doc closeout (`/code` handles doc updates atomically with the feature commit per the standard chain).

**Demo:** After v1.2 ships, running `./scripts/install.sh git-hooks` symlinks the hook into `~/.claude/git-hooks/pre-commit`. Activating per-repo via `git config core.hooksPath ~/.claude/git-hooks/` makes every subsequent `git commit` run `./scripts/gate_fast.sh` first; commits refuse on gate failure unless `SKIP_GATE_FAST=1` is set in env.

---

## Phase 1: Pre-commit Git Hook

### Change 1: `shell/git-hooks/pre-commit` template

**Problem:** No mechanical guard exists for the /gate-fast-before-commit rule. The dev-platform's `shell/` directory is currently README-only ([shell/README.md](shell/README.md) explicitly anticipates `git-hooks/pre-commit` as a future addition). This Change populates it.

**File:** `shell/git-hooks/pre-commit` (new, executable, **no extension** — git's convention) + `shell/git-hooks/README.md` (new, directory contract)

**Implementation:**

`shell/git-hooks/pre-commit`:

```bash
#!/usr/bin/env bash
# shell/git-hooks/pre-commit — refuses commits when scripts/gate_fast.sh
# fails. Universal across all teelr/dev-* repos: looks for gate_fast.sh
# at the repo root; if absent, exits 0 (no-op). Bypass with SKIP_GATE_FAST=1
# for WIP commits on private branches.
#
# Install: scripts/install.sh git-hooks
# Activate per-repo: git config core.hooksPath ~/.claude/git-hooks

set -uo pipefail

if [[ "${SKIP_GATE_FAST:-0}" == "1" ]]; then
    echo "[pre-commit] SKIP_GATE_FAST=1 — bypassing gate" >&2
    exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[[ -z "${REPO_ROOT}" ]] && exit 0

GATE="${REPO_ROOT}/scripts/gate_fast.sh"
[[ ! -x "${GATE}" ]] && exit 0

echo "[pre-commit] Running ${GATE#${REPO_ROOT}/}..." >&2
if bash "${GATE}" >/dev/null 2>&1; then
    exit 0
fi

echo "[pre-commit] GATE FAST: FAIL — commit refused." >&2
echo "[pre-commit] Re-run ./scripts/gate_fast.sh for details, or set SKIP_GATE_FAST=1 to override." >&2
exit 1
```

`shell/git-hooks/README.md` (~15 lines): directory contract — what goes here (git-hook scripts, no extension, executable), what does NOT go here (Claude Code hooks → `hooks/`; bash helpers → `shell/*.sh`), deploy mechanism (`scripts/install.sh git-hooks` symlinks files into `~/.claude/git-hooks/`; users activate per-repo via `git config core.hooksPath`).

`chmod +x shell/git-hooks/pre-commit` so the executable bit is preserved through the symlink.

**Consumer Audit per [CLAUDE.md:75-83](CLAUDE.md#L75-L83)** — `shell/git-hooks/pre-commit` is the **first extension-less file under `shell/`** and the first non-README file in `shell/`. Required:

1. `.gitignore` allow-list: needs `!shell/git-hooks/` subdir re-include + `!shell/git-hooks/pre-commit` explicit entry (extension-less, won't match any `*.sh`-style pattern). Verify with `git check-ignore -v shell/git-hooks/pre-commit` — must return a re-include line.
2. `scripts/install.sh` glob update: handled by Change 2.
3. `scripts/verify.sh` symlink check: handled by Change 2.
4. Directory README: covered above.
5. Test orchestrator: `tests/git-hooks/run.sh` (Change 3); auto-discovered by `gate_fast.sh`.

**Acceptance Test:** `bash -n shell/git-hooks/pre-commit` exits 0. `git check-ignore -v shell/git-hooks/pre-commit` returns a re-include rule (file IS tracked, not gitignored). `ls -la shell/git-hooks/pre-commit` shows the executable bit. Running the script in a directory with no `scripts/gate_fast.sh` exits 0 (no-op). Running it in a directory with a failing `scripts/gate_fast.sh` exits 1 and emits the refusal message. Running with `SKIP_GATE_FAST=1` exits 0 with the bypass message.

### Change 2: Extend `scripts/install.sh`, `uninstall.sh`, `verify.sh` with `git-hooks` category

**Problem:** Each owned repo opts in to the pre-commit hook by setting `core.hooksPath` to a directory the dev-platform symlinks the hook into. The clean target is `~/.claude/git-hooks/` (parallel to `~/.claude/hooks/` for Claude Code hooks). The existing installer at [scripts/install.sh](scripts/install.sh) needs a new `git-hooks` category alongside the existing `commands|skills|settings|hooks|vscode|all`.

**File:** `scripts/install.sh` (existing — extend), `scripts/uninstall.sh` (existing — extend symmetrically), `scripts/verify.sh` (existing — extend symmetrically)

**Implementation:**

`scripts/install.sh` — add `install_git_hooks()` function after `install_vscode()` at [scripts/install.sh:185](scripts/install.sh#L185):

```bash
install_git_hooks() {
    mkdir -p "${HOME_CLAUDE}/git-hooks"
    local count=0
    for f in "${REPO}/shell/git-hooks"/*; do
        [[ -f "${f}" ]] || continue
        local name; name="$(basename "${f}")"
        [[ "${name}" == "README.md" ]] && continue
        link_file "${f}" "${HOME_CLAUDE}/git-hooks/${name}"
        count=$((count + 1))
    done
    echo "  git-hooks: ${count} files linked to ${HOME_CLAUDE}/git-hooks/"
    echo "             Activate per-repo with:"
    echo "             git config core.hooksPath ${HOME_CLAUDE}/git-hooks"
}
```

Wire into the `case` block at the bottom of `install.sh`:

```bash
case "${CATEGORY}" in
    commands)   install_commands ;;
    skills)     install_skills ;;
    settings)   install_settings ;;
    hooks)      install_hooks ;;
    vscode)     install_vscode ;;
    git-hooks)  install_git_hooks ;;
    all)        install_commands; install_skills; install_settings; install_hooks; install_vscode; install_git_hooks ;;
    *)          echo "Unknown category: ${CATEGORY}" >&2
                echo "Usage: $0 [commands|skills|settings|hooks|vscode|git-hooks|all]" >&2
                exit 1 ;;
esac
```

Update the usage comment at the top of `install.sh` (currently lines 9-14) to mention the new category.

`scripts/uninstall.sh` — extend symmetrically. Add removal of `${HOME_CLAUDE}/git-hooks/*` symlinks. Read the existing uninstall structure during /code and match its pattern (likely a parallel `uninstall_git_hooks()` function + case branch).

`scripts/verify.sh` — extend symmetrically. For each tracked file in `shell/git-hooks/` (excluding README.md), assert the symlink at `~/.claude/git-hooks/<name>` exists and points back to the tracked source. Match existing per-category verification pattern.

Update [README.md](README.md) install-categories table/list if one exists, adding `git-hooks` as a sixth category.

**Acceptance Test:** `./scripts/install.sh git-hooks` creates `~/.claude/git-hooks/pre-commit` as a symlink to `<repo>/shell/git-hooks/pre-commit`; activation instructions printed. `./scripts/verify.sh` reports the symlink as healthy. `./scripts/install.sh all` includes the git-hooks step. `./scripts/uninstall.sh` removes the symlink. `./scripts/install.sh nonexistent` exits 1 with the updated usage message listing `git-hooks`.

### Change 3: `tests/git-hooks/` fixture suite

**Problem:** The pre-commit hook needs fixture-based regression coverage so future edits can't silently break its behavior. Five behaviors to cover: no-op when no `gate_fast.sh`; PASS when gate passes; refuse when gate fails; bypass via `SKIP_GATE_FAST=1`; install integration symlinks correctly.

**File:** `tests/git-hooks/run.sh` (new, executable) + fixtures under `tests/git-hooks/fixtures/`

**Implementation:**

Per the testing contract at [tests/README.md](tests/README.md), suite runners live at `tests/<suite>/run.sh` and runnable mock fixtures under `tests/<suite>/fixtures/`. The orchestrator's `! -path "*/fixtures/*"` filter at [scripts/gate_fast.sh:118](scripts/gate_fast.sh#L118) already excludes fixtures from auto-discovery — no orchestrator edit needed.

Fixtures:
- `tests/git-hooks/fixtures/passing-gate.sh` — `#!/usr/bin/env bash\nexit 0`
- `tests/git-hooks/fixtures/failing-gate.sh` — `#!/usr/bin/env bash\nexit 1`

Runner (`tests/git-hooks/run.sh`) — sources `tests/helpers/assert.sh`. Five tests:

1. **No-gate no-op:** mktemp tmpdir (no `scripts/gate_fast.sh`); run the hook. Assert exit 0.
2. **Passing-gate:** mktemp tmpdir, place `passing-gate.sh` as `scripts/gate_fast.sh`, `chmod +x`, run the hook from inside the tmpdir. Assert exit 0.
3. **Failing-gate refuses:** same as Test 2 with `failing-gate.sh`. Assert exit 1. **Substring assertion on stderr** per [tasks/lessons.md:28](tasks/lessons.md) — the FAIL message text ("GATE FAST: FAIL — commit refused.") must appear, not just exit 1.
4. **Bypass via env var:** same as Test 3 with `SKIP_GATE_FAST=1`. Assert exit 0 and the bypass message in stderr.
5. **Install integration:** invoke `./scripts/install.sh git-hooks` with `HOME=<tmpdir>` (passed via env, not by changing the real HOME). Assert `<tmpdir>/.claude/git-hooks/pre-commit` is a symlink resolving back to the tracked source.

Exit-code capture pattern per [tasks/lessons.md:39](tasks/lessons.md) — never `cmd || true; check $?` (always yields 0); use the two-line `out="$(cmd 2>&1)"; rc=$?` pattern.

Cleanup pattern per [tasks/lessons.md:32](tasks/lessons.md): `trap 'rm -rf "${tmp}"' EXIT` on each tmpdir so failed assertions still clean up. Each test creates its own tmpdir (don't reuse — leaked state between tests is its own bug class).

**Acceptance Test:** `bash tests/git-hooks/run.sh` records 5 PASS, 0 FAIL. `./scripts/gate_fast.sh` auto-discovers the new suite (no orchestrator edit needed). Total PASS count climbs from 153 (v1.1) to 158 after Change 3. `git check-ignore -v tests/git-hooks/fixtures/passing-gate.sh` returns a re-include rule (`!tests/**/*.sh`). No `/tmp/git-hooks-*` residue after the suite runs.

### Change 4: End-to-end acceptance + doc closeout

**Problem:** v1.2 needs an end-to-end run proving the pieces work together against the real repo state, plus the standard doc updates and post-merge release closeout.

**File:** none for the procedural verification (handled in the /code session before commit); doc updates handled by /code's final step atomically with the feature commit.

**Implementation:**

End-to-end acceptance run (in /code, before commit):

```bash
# 1. Clean working state
cd /home/rich/dev
git status --short    # expected: only the v1.2 changes

# 2. gate_fast passes with new suite included
./scripts/gate_fast.sh
# Expected: ~158 PASS (up from 153 in v1.1), exit 0

# 3. Install integration works against real ~/.claude/
./scripts/install.sh git-hooks
ls -la "${HOME}/.claude/git-hooks/pre-commit"
# Expected: symlink → /home/rich/dev/shell/git-hooks/pre-commit

# 4. verify.sh confirms the new symlink
./scripts/verify.sh
# Expected: exit 0

# 5. Hook fires when activated in dev-platform itself
git config core.hooksPath "${HOME}/.claude/git-hooks"
git commit --allow-empty -m "test: gate fires"
# Expected: pre-commit runs ./scripts/gate_fast.sh, commits on PASS

# 6. Hook refuses on contrived failure
echo "junk" >> tests/git-hooks/fixtures/passing-gate.sh   # intentionally break a fixture
git commit --allow-empty -m "test: gate refuses"
# Expected: pre-commit refuses; exit 1; "GATE FAST: FAIL" message
git checkout tests/git-hooks/fixtures/passing-gate.sh     # restore

# 7. Bypass works
SKIP_GATE_FAST=1 git commit --allow-empty -m "test: bypass"
# Expected: bypass message; commit succeeds even with broken fixture
git reset --hard HEAD~3   # drop the 3 test commits (1-3 actual commits depending on which succeeded)

# 8. Cleanup
git config --unset core.hooksPath   # restore default behavior on dev-platform repo
```

Doc updates (`/code` handles as its final step atomically with the feature commit):
- [ROADMAP.md](ROADMAP.md) — add `**v1.2: Pre-commit Git Hook**` entry with shipped date and summary.
- [planning.md](planning.md) — update "Current state" + "In flight" + "Recently shipped" to reflect v1.2 ship.
- [README.md](README.md) — update install-categories list to mention `git-hooks` as a sixth category.
- [tasks/lessons.md](tasks/lessons.md) — capture any new lessons surfaced during /code.

**CLAUDE.md does not need updating for v1.2.** The Gate Tiers section already names "/gate fast" and the workflow chain already says "NEVER commit before /gate fast passes" — the hook enforces existing documented behavior, no new rules to add.

Post-merge (handled outside /code, after the PR squash-merges):
1. `./scripts/sync-milestones.sh --apply` — verify v1.2 milestone state.
2. `gh release create v1.2 --target <squash-merge SHA> --title "v1.2: Pre-commit Git Hook"`.
3. Close v1.2 GitHub Milestone (sync-milestones may handle this; verify).
4. Consumer-template default-pin bump as a follow-up chore PR: `@v1.1` → `@v1.2` in [extensions/github-actions/dev-platform-gate.yml](extensions/github-actions/dev-platform-gate.yml).

**Acceptance Test:** All 8 procedural sub-steps complete with expected outputs. PR merges with gate-fast green on CI. Post-merge: v1.2 tag exists at <https://github.com/teelr/dev-platform/releases/tag/v1.2>, v1.2 GitHub Milestone closed.

---

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `shell/git-hooks/pre-commit` | New | Pre-commit hook script, no extension, executable |
| `shell/git-hooks/README.md` | New | Directory contract (~15 lines) |
| `.gitignore` | Modify | Allow-list re-include for `!shell/git-hooks/` + `!shell/git-hooks/pre-commit` |
| `scripts/install.sh` | Modify | Add `install_git_hooks()` + `git-hooks` category in case block + usage comment |
| `scripts/uninstall.sh` | Modify | Symmetric removal of git-hooks symlinks |
| `scripts/verify.sh` | Modify | Symmetric symlink-health check for git-hooks |
| `tests/git-hooks/run.sh` | New | 5-assertion suite runner (~120 lines) |
| `tests/git-hooks/fixtures/passing-gate.sh` | New | Mock gate fixture, exit 0 |
| `tests/git-hooks/fixtures/failing-gate.sh` | New | Mock gate fixture, exit 1 |
| `ROADMAP.md` | Modify | Add v1.2 shipped entry |
| `planning.md` | Modify | Update current state + recently shipped |
| `README.md` | Modify | Add git-hooks to install-categories |
| `tasks/lessons.md` | Modify | Any new lessons from /code |
| `tasks/dev-platform-pre-commit-hook-spec.md` | (this file) | Spec |

## Implementation Order

One branch (`v1.2/pre-commit-hook` — already created), one PR, four Changes in sequence:

1. **Change 1** — `shell/git-hooks/pre-commit` + README + .gitignore re-include. Verify with `git check-ignore -v` before treating the file as tracked.
2. **Change 2** — `scripts/install.sh`/`uninstall.sh`/`verify.sh` extensions. Smoke-test against a tmpdir-HOME.
3. **Change 3** — `tests/git-hooks/run.sh` + fixtures. Run the suite locally; confirm 5 PASS.
4. **Change 4** — End-to-end acceptance + doc updates. Doc updates land in the same /code session atomically.

Single /code session implements all four Changes. Branch is already `v1.2/pre-commit-hook`.

## Verification Checklist

- [ ] All 4 Changes implemented in one bundled commit.
- [ ] `bash -n` passes on every new/modified `.sh` file.
- [ ] `git check-ignore -v shell/git-hooks/pre-commit` returns a re-include rule.
- [ ] `tests/git-hooks/run.sh` records 5 PASS, 0 FAIL.
- [ ] `./scripts/gate_fast.sh` auto-discovers the new suite; total PASS climbs from 153 → 158.
- [ ] `./scripts/install.sh git-hooks` symlinks the hook into `~/.claude/git-hooks/pre-commit`; activation message printed.
- [ ] `./scripts/verify.sh` reports the new symlink healthy.
- [ ] `./scripts/uninstall.sh` removes the symlink.
- [ ] End-to-end acceptance against the real dev-platform repo passes all 8 sub-steps.
- [ ] Doc updates land atomically with the feature commit (ROADMAP, planning, README; lessons if new).
- [ ] No `console.log` / debug code in production paths.
- [ ] No file under `projects/` modified.
- [ ] `/security-review` NOT required — no auth, credentials, external input, or new endpoints touched.

## What NOT to Do

- **Do not auto-write `core.hooksPath` in install.sh.** Opt-in stays opt-in. Print the activation command; let the user run it per-repo where they want enforcement.
- **Do not silently overwrite an existing `~/.claude/git-hooks/pre-commit` real file.** Rely on `link_file`'s existing refusal-to-clobber behavior at [scripts/install.sh:42-51](scripts/install.sh#L42-L51) — it errors when the target is a real file (not a symlink), forcing the user to back up first.
- **Do not make the hook FAIL when `scripts/gate_fast.sh` is absent.** Many repos won't have it. Universal-installability requires the no-op behavior. The hook is dormant where there's no gate to enforce.
- **Do not put the hook script under `hooks/`.** That directory is for Claude Code hooks (PostToolUse, SessionStart, etc.) — different domain, different deployment target. Git hooks live under `shell/git-hooks/`.
- **Do not give the hook a `.sh` extension.** Git's convention is extension-less hook names (`pre-commit`, `commit-msg`, `pre-push`). The `git check-ignore -v` audit must explicitly cover this case — `!shell/git-hooks/pre-commit` as an explicit entry, not a glob.
- **Do not skip the [tasks/lessons.md:39](tasks/lessons.md) rule on exit-code capture in the test suite.** `out="$(cmd)" || true; check $?` always reports `$? = 0`. Use the two-line `out="$(cmd 2>&1)"; rc=$?` pattern.
- **Do not skip substring assertions on the refusal message** per [tasks/lessons.md:28](tasks/lessons.md). Test 3 asserts BOTH exit 1 AND that stderr contains the specific "GATE FAST: FAIL" text — exit-code-only assertions can pass for the wrong reason (e.g., the hook crashing on a typo before reaching the gate invocation).
- **Do not commit `gate_full.sh` or perf-guard infra to v1.2.** Those stay deferred — the v0.4 ruling was "defer until evidence" and the evidence still hasn't shown up. Resist scope creep.

## Notes for Implementation

- **`shell/git-hooks/` is the first non-README content under `shell/`.** Apply the full Consumer Audit per [CLAUDE.md:75-83](CLAUDE.md#L75-L83). The extension-less filename is the trickiest part — `git check-ignore -v` after creating the file is non-negotiable.
- **The hook is universally installable across teelr/dev-* repos.** Once symlinked from `~/.claude/git-hooks/pre-commit`, any repo that runs `git config core.hooksPath ~/.claude/git-hooks/` gets the hook. v1.2 doesn't auto-enable it anywhere — including dev-platform itself; the user activates after install.
- **`uninstall.sh` and `verify.sh` extensions are symmetric infrastructure**, not afterthoughts. Skipping either creates the "install doesn't match uninstall" drift class that bit the foundation spec at [tasks/lessons.md:10](tasks/lessons.md).
- **The 5-test cross-product** for the hook covers all behaviorally-distinct states: (no gate / passing / failing) × (env=default / SKIP=1). Per [tasks/lessons.md:35](tasks/lessons.md), single-axis coverage gives false confidence — enumerate the cross product. Tests 1-5 do.
- **Post-merge consumer-pin bump is a separate chore PR**, not part of v1.2 itself. The pin file at [extensions/github-actions/dev-platform-gate.yml](extensions/github-actions/dev-platform-gate.yml) can't reference `@v1.2` until the `v1.2` tag exists — chicken-and-egg avoided by deferring the bump to post-merge per v1.0/v1.1 precedent.
