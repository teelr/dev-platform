# Dev Platform Foundation

## Coding Specification for Implementation

## Design Philosophy

The repo at `/home/rich/dev/` (GitHub: `teelr/dev-platform`) was originally `dev-standards` — a thin policy repo holding the global `CLAUDE.md` rules that auto-load into every project under `dev/projects/`. The repo's gitignore uses an aggressive allow-list strategy so each `projects/X/` stays its own repo, untouched.

That scope is now too narrow. The repo holds the *policy* but none of the artifacts that *enforce* it: slash commands (`/plan`, `/code`, `/test`, `/review`, `/gate`, `/docs`, `/dev`, `/loop`), skills, hooks, settings, keybindings, IDE config, shell helpers, scaffolding templates. Those live scattered in `~/.claude/`, `~/.vscode/`, and ad-hoc shell config — un-versioned, un-tested, and un-reproducible on a fresh machine.

This spec reorganizes the repo to own the full developer-experience surface: rules + tools + workflows + install. The repo becomes the single source of truth; the user environment (`~/.claude/`, `~/.vscode/`, etc.) becomes a *deployment* of the repo via an install script.

After this spec ships:

- A fresh machine can run `git clone teelr/dev-platform && cd dev-platform && ./scripts/install.sh` and reproduce Rich's dev environment.
- `git diff` on any tracked file shows what's drifted between deployed and tracked.
- A bad hook or command tweak can be `git revert`-ed and reinstalled.
- Subsequent specs (monitoring, testing, extensions) build on this foundation.

**No project under `dev/projects/` is touched.** The aggressive gitignore strategy stays — each project remains its own repo.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `commands/` | Markdown | Slash command definitions (existing format under `~/.claude/commands/`) |
| `skills/` | Markdown + YAML frontmatter | Skill definitions (existing format under `~/.claude/skills/`) |
| `settings/` | JSON | `settings.json`, `keybindings.json` (Claude Code config formats) |
| `hooks/` | Shell | Hooks invoked by Claude Code; portable across machines |
| `scripts/` | Shell | Install / uninstall / verify scripts; no language complexity needed |
| Spec, README, CLAUDE.md, ROADMAP.md, planning.md | Markdown | Standard docs |

## Overview

1. **Phase 1:** Repo foundation — gitignore, top-level dirs, expanded CLAUDE.md, ROADMAP.md, planning.md
2. **Phase 2:** Migrate existing artifacts — copy `~/.claude/{commands,skills,settings.json,keybindings.json}` into the repo
3. **Phase 3:** Install / deploy infrastructure — `install.sh`, `uninstall.sh`, `verify.sh`

**Demo:** delete `~/.claude/commands/`, `~/.claude/skills/`, `~/.claude/settings.json`, `~/.claude/keybindings.json` (after backing up). Run `./scripts/install.sh`. Open a new Claude Code session. Every slash command, skill, hook, setting, and keybinding works identically to before.

---

## Phase 1: Repo Foundation

### Change 1: Update `.gitignore` to allow new top-level directories

**Problem:** The current `.gitignore` ignores everything by default and re-includes only `CLAUDE.md`, `BACKUP_INSTRUCTIONS.md`, `backup-to-cosmo.sh`, `dev.code-workspace`, `docs/`, `tasks/`, `scripts/`. Any new top-level directory would be silently ignored.

**File:** `/home/rich/dev/.gitignore`

**Implementation:**

Add re-include lines for the new top-level directories. Each directory follows the same pattern as the existing `docs/`, `tasks/`, `scripts/` entries — recurse in, then explicitly allow only known file extensions to prevent accidental tracking of generated content.

New top-level dirs to allow:

- `commands/` — slash command markdown files
- `skills/` — skill definitions (markdown + YAML)
- `settings/` — `settings.json`, `keybindings.json`, hook config
- `hooks/` — hook scripts (shell)
- `extensions/` — IDE config (`.vscode/`, statusline scripts)
- `scaffolding/` — new-project starter templates
- `monitoring/` — placeholder for future monitoring spec (track schemas + collectors)
- `shell/` — shell helpers, git hook templates
- `ROADMAP.md`, `planning.md` — repo-root pointers (per kermit-harness pattern)

For each directory, the gitignore entry follows the existing pattern: `!dirname/`, then `dirname/**` to ignore everything inside, then `!dirname/*.ext` to re-allow specific extensions.

### Change 2: Create top-level directory skeletons

**Problem:** The new directories need to exist before artifacts are migrated. Each needs a `README.md` documenting its contract — what belongs here, what doesn't.

**Files (new):**

- `commands/README.md`
- `skills/README.md`
- `settings/README.md`
- `hooks/README.md`
- `extensions/README.md`
- `scaffolding/README.md`
- `monitoring/README.md`
- `shell/README.md`

**Implementation:**

Each `README.md` is one paragraph (3–5 sentences). State:

1. What goes in this directory (specific file types and naming convention)
2. What does NOT go here (counter-examples to prevent drift)
3. How files here are deployed (symlink / copy / consumed at runtime)
4. Pointer to the install script section that handles this directory

Example for `commands/README.md`:

```markdown
# commands/

Claude Code slash command definitions. Each `*.md` file defines one slash command: filename `foo.md` becomes `/foo`. Markdown body is the prompt template the command uses.

**What goes here:** workflow commands (`plan.md`, `code.md`, `test.md`, `review.md`, `gate.md`, `docs.md`, `dev.md`, `loop.md`), utility commands.

**What does NOT go here:** project-specific commands (those live in the project's own `.claude/commands/`), skills (those go in `skills/`).

**Deployment:** `scripts/install.sh` symlinks each `*.md` here into `~/.claude/commands/`.
```

### Change 3: Expand top-level `CLAUDE.md` to reflect broader scope

**Problem:** The current `/home/rich/dev/CLAUDE.md` is rules-only. With the repo now owning workflow, tooling, and install artifacts, the CLAUDE.md needs sections describing the new structure so Claude (and future contributors) understand what's where.

**File:** `/home/rich/dev/CLAUDE.md` (existing — additive edit, do NOT remove existing content)

**Implementation:**

Add three new sections near the end (before the existing "Patterns" section):

1. **`## Repo Structure`** — table of top-level directories with one-line purpose each. Mirrors the README.md contracts in Change 2.
2. **`## Install / Deploy`** — one paragraph explaining that `scripts/install.sh` deploys repo files into `~/.claude/`, `~/.vscode/`, etc. Make explicit: the repo is the source of truth, the user environment is a deployment.
3. **`## Adding a New Workflow Artifact`** — a checklist for adding a new slash command / skill / hook: (a) write file in correct dir, (b) add to install.sh deploy list, (c) update verify.sh expected paths, (d) add a smoke test (forward-reference to future testing spec — note as TODO).

Keep additions tight — each section ~10 lines. The CLAUDE.md is loaded into every dev-project session; bloat hurts every session.

### Change 4: Add `ROADMAP.md` stub at repo root

**Problem:** The kermit-harness pattern uses a repo-root `ROADMAP.md` as a discoverable pointer to the canonical roadmap (which lives in `tasks/`). Dev-platform should follow the same pattern for `/dev` orientation discoverability.

**File:** `/home/rich/dev/ROADMAP.md` (new)

**Implementation:**

10–15 line stub. Lists the planned spec sequence:

- **R1: Foundation** (this spec) — repo restructure + install/deploy
- **R2: Monitoring** (future) — telemetry on workflow effectiveness
- **R3: Testing** (future) — regression coverage for commands + hooks
- **R4: Extensions** (future) — VSCode + statusline + scaffolding templates
- **R5: Migration tooling** (future) — auto-migrate older project layouts to the standard taxonomy

Pointer at the bottom: "Canonical roadmap detail lives in `tasks/dev-platform-roadmap.md` (created when R2 starts)."

### Change 5: Add `planning.md` stub at repo root

**Problem:** Same rationale as Change 4. The kermit-harness pattern uses repo-root `planning.md` for current-state snapshot.

**File:** `/home/rich/dev/planning.md` (new)

**Implementation:**

15–20 line stub. Sections:

- **Current state** — name (`dev-platform`), GitHub URL, what version of which spec is active
- **Recently shipped** — last 3 commits with one-line summary each
- **In flight** — current spec name + what phase
- **Pointer** — "Canonical state lives in `tasks/` and `CHANGELOG.md` (created when R2 starts)."

Initial population: "Active: `dev-platform-foundation-spec.md`, Phase 1." `/docs` will refresh this file on each spec-completion.

---

## Phase 2: Migrate Existing Artifacts

### Change 6: Copy `~/.claude/commands/` into `commands/`

**Problem:** Slash commands currently live only in `~/.claude/commands/`. They need to be tracked in the repo so they're versioned, reviewable, and reproducible on a fresh machine.

**Files:** copy all `~/.claude/commands/*.md` → `commands/*.md`

**Implementation:**

```bash
cp -a ~/.claude/commands/*.md /home/rich/dev/commands/
```

Verify: `ls /home/rich/dev/commands/` should show every command Rich uses today (`plan.md`, `code.md`, `test.md`, `review.md`, `gate.md`, `docs.md`, `dev.md`, `loop.md`, others).

After commit lands, the source-of-truth is `commands/`. `~/.claude/commands/` will be replaced with symlinks in Change 11. **Until install.sh runs, both copies exist** — that's fine; identical content, no behavioral change.

### Change 7: Copy `~/.claude/skills/` into `skills/`

**Problem:** Same rationale as Change 6 for skill definitions.

**Files:** recursive copy `~/.claude/skills/*` → `skills/*`

**Implementation:**

```bash
cp -a ~/.claude/skills/. /home/rich/dev/skills/
```

Skills may be directories (each skill in its own subdir with `SKILL.md` + supporting files) or flat markdown — copy the structure as-is.

### Change 8: Copy `~/.claude/settings.json` and `keybindings.json` into `settings/`

**Problem:** Claude Code's global config files are user-environment-only. They need to be tracked.

**Files (new):**

- `settings/settings.json` — copy of `~/.claude/settings.json`
- `settings/keybindings.json` — copy of `~/.claude/keybindings.json`

**Implementation:**

```bash
cp ~/.claude/settings.json /home/rich/dev/settings/settings.json
cp ~/.claude/keybindings.json /home/rich/dev/settings/keybindings.json
```

**Caution:** review `settings.json` for any secrets, machine-local paths, or auth tokens before committing. If found, redact them and use a `.local.json` overlay pattern (same as `settings.local.json` Claude Code already supports) to keep machine-specific values out of the repo. Document the overlay pattern in `settings/README.md`.

### Change 9: Document the install-vs-deployed model in `settings/README.md`

**Problem:** Whoever reads `settings/` first needs to understand: edits go to the file in this directory, install.sh deploys to `~/.claude/`. Skipping the deploy step means edits don't take effect.

**File:** `settings/README.md` (already created in Change 2 — expand here)

**Implementation:**

Expand `settings/README.md` to specifically address the settings/keybindings flow:

```markdown
# settings/

Claude Code global configuration. Tracked here, deployed by `scripts/install.sh` to `~/.claude/`.

## Files

- `settings.json` — global Claude Code settings (hooks, permissions, env vars)
- `keybindings.json` — global keybindings
- `*.local.json` — gitignored, machine-specific overlays (auth tokens, machine paths)

## Editing

Edit the file in this directory, then run `./scripts/install.sh` (or `./scripts/install.sh settings` to redeploy just this category). Edits to `~/.claude/settings.json` directly will be overwritten on next install — don't edit there.

## Secrets and machine-local paths

Anything that varies per machine (auth tokens, absolute paths beyond `$HOME`) goes in `settings.local.json` — same overlay format Claude Code already merges.
```

---

## Phase 3: Install / Deploy Infrastructure

### Change 10: Write `scripts/install.sh`

**Problem:** Without an install script, the repo is just a directory of files — there's no way to deploy them into `~/.claude/`, `~/.vscode/`, etc. The repo can't be the source of truth without a deploy step.

**File:** `scripts/install.sh` (new)

**Implementation:**

Bash script. Idempotent — running it twice produces the same result. Symlinks rather than copies (so editor edits the tracked file directly; runtime always reads the source of truth).

Functional outline:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_CLAUDE="${HOME}/.claude"

# Argument: optional category to install (commands, skills, settings, hooks, all)
CATEGORY="${1:-all}"

install_commands() {
    mkdir -p "${HOME_CLAUDE}/commands"
    for f in "${REPO}/commands"/*.md; do
        ln -sfn "${f}" "${HOME_CLAUDE}/commands/$(basename "${f}")"
    done
    echo "  commands: $(ls "${REPO}/commands"/*.md | wc -l) files linked"
}

install_skills() {
    mkdir -p "${HOME_CLAUDE}/skills"
    # symlink each skill subdir or file
    ...
}

install_settings() {
    ln -sfn "${REPO}/settings/settings.json" "${HOME_CLAUDE}/settings.json"
    ln -sfn "${REPO}/settings/keybindings.json" "${HOME_CLAUDE}/keybindings.json"
    # local overlays NOT touched
}

case "${CATEGORY}" in
    commands)  install_commands ;;
    skills)    install_skills ;;
    settings)  install_settings ;;
    hooks)     install_hooks ;;
    all)       install_commands; install_skills; install_settings; install_hooks ;;
    *)         echo "Unknown category: ${CATEGORY}"; exit 1 ;;
esac

echo "Install complete. Restart Claude Code for changes to take effect."
```

**Symlink strategy:** `ln -sfn` (force, no-deref-symlink) so re-running install.sh updates targets cleanly even if a stale symlink exists.

**Backup strategy:** before first-time install, if `~/.claude/commands/` (or any target) is a real directory (not a symlink), the script MUST refuse and instruct the user to back up + delete the existing directory first. Never silently overwrite real files.

**Error handling:** `set -euo pipefail` at top. Any failure aborts. Print the failing step to stderr.

### Change 11: Write `scripts/uninstall.sh`

**Problem:** If a user wants to revert to a fresh `~/.claude/` (e.g., to debug whether a tracked file is the cause of an issue), they need a way to remove the symlinks without manually finding each one.

**File:** `scripts/uninstall.sh` (new)

**Implementation:**

Removes only symlinks pointing into `${REPO}` — never deletes real files (which would be user data not tracked by the repo). Walks `~/.claude/`, `~/.vscode/`, etc. and `rm` any symlink whose target starts with `${REPO}/`.

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

remove_repo_symlinks() {
    local target_dir="$1"
    [[ -d "${target_dir}" ]] || return 0
    find "${target_dir}" -type l | while read -r link; do
        target=$(readlink -f "${link}")
        if [[ "${target}" == "${REPO}"* ]]; then
            rm "${link}"
            echo "  removed: ${link}"
        fi
    done
}

remove_repo_symlinks "${HOME}/.claude"
echo "Uninstall complete. ~/.claude/ no longer references ${REPO}."
```

The uninstall is non-destructive: leaves the user's auto-generated `~/.claude/projects/` (memory, transcripts) untouched.

### Change 12: Write `scripts/verify.sh`

**Problem:** Once the repo is the source of truth, drift between tracked and deployed becomes a real failure mode (someone edits `~/.claude/settings.json` directly, doesn't realize the next install will overwrite). Need a way to detect drift.

**File:** `scripts/verify.sh` (new)

**Implementation:**

Walks every file in `commands/`, `skills/`, `settings/`, `hooks/` and verifies the corresponding `~/.claude/` path is a symlink pointing back into `${REPO}`. Reports:

- ✓ tracked file is symlinked correctly
- ✗ tracked file is NOT deployed (no symlink at expected path)
- ⚠ deployed path is a real file, not a symlink (drift — user edited directly, would be lost on next install)
- ⚠ deployed path is a symlink to somewhere else (orphan from old install)

Exit code: 0 if all ✓, 1 if any ✗ or ⚠.

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_CLAUDE="${HOME}/.claude"
ERRORS=0

check_symlink() {
    local tracked="$1"
    local deployed="$2"
    if [[ ! -e "${deployed}" ]]; then
        echo "  ✗ NOT deployed: ${deployed}"
        ERRORS=$((ERRORS + 1))
    elif [[ ! -L "${deployed}" ]]; then
        echo "  ⚠ drift (real file): ${deployed} (run install.sh to fix, but BACK UP first)"
        ERRORS=$((ERRORS + 1))
    elif [[ "$(readlink -f "${deployed}")" != "${tracked}" ]]; then
        echo "  ⚠ orphan symlink: ${deployed} → $(readlink "${deployed}")"
        ERRORS=$((ERRORS + 1))
    else
        echo "  ✓ ${deployed}"
    fi
}

# verify commands
for f in "${REPO}/commands"/*.md; do
    check_symlink "${f}" "${HOME_CLAUDE}/commands/$(basename "${f}")"
done
# verify skills, settings, hooks similarly...

if [[ ${ERRORS} -gt 0 ]]; then
    echo ""
    echo "Verification FAILED: ${ERRORS} issue(s)."
    exit 1
fi
echo "All tracked files deployed correctly."
```

### Change 13: Update top-level `README.md` with install instructions

**Problem:** Anyone (including future Rich on a new machine) cloning the repo needs to know what it is and how to deploy it.

**File:** `/home/rich/dev/README.md` (likely doesn't exist yet at root — verify, create if missing)

**Implementation:**

Sections:

1. **What this is** — one paragraph: "dev-platform is the source-of-truth repo for Rich's developer environment: rules, slash commands, skills, hooks, settings, install/uninstall scripts. The `~/.claude/` directory on each machine is a deployment of this repo."
2. **Quick start** — 4 lines:
   ```
   git clone git@github.com:teelr/dev-platform.git ~/dev
   cd ~/dev
   ./scripts/install.sh
   # restart Claude Code
   ```
3. **Repo structure** — bullet list of top-level dirs with one-line purpose each (mirror Change 3 CLAUDE.md table).
4. **Editing artifacts** — the tracked file is the source of truth. Edit there, run `install.sh` (or `install.sh <category>` for partial), Claude Code picks up changes on next session.
5. **Verifying deployment** — `./scripts/verify.sh` reports drift.
6. **Uninstall** — `./scripts/uninstall.sh` removes all repo-owned symlinks; user's auto-generated state in `~/.claude/projects/` untouched.

Keep README under 80 lines. Detailed docs live in per-directory READMEs and CLAUDE.md.

---

## Acceptance Criteria

- [ ] `gh repo view` shows `teelr/dev-platform` (renamed) — already done before this spec.
- [ ] `git status` clean after each Change in this spec.
- [ ] All 8 new top-level directories exist with `README.md` contracts (Change 2).
- [ ] `commands/`, `skills/`, `settings/` populated from `~/.claude/` (Phase 2).
- [ ] `scripts/install.sh` runs without error from a fresh state (post-uninstall).
- [ ] `scripts/verify.sh` reports all ✓ after install.
- [ ] `scripts/uninstall.sh` removes all repo-owned symlinks; subsequent `verify.sh` reports all ✗ (expected — un-installed).
- [ ] Re-running `install.sh` after uninstall restores all ✓ — idempotent.
- [ ] Closing Claude Code, deleting `~/.claude/{commands,skills,settings.json,keybindings.json}`, running `install.sh`, opening Claude Code → every slash command, skill, setting, keybinding behaves identically to pre-spec state.
- [ ] No file under `dev/projects/` modified.

## Out of Scope (Future Specs)

- **Monitoring** (`dev-platform-monitoring-spec.md`) — telemetry collectors, hook event emitters, daily summary report. Scope: track gate pass rate, /code retry counts, /review catch rate, hook execution time per project.
- **Testing** (`dev-platform-testing-spec.md`) — smoke tests for slash commands (run them in a fixture, verify expected artifact produced), regression tests for hooks, `make check` target.
- **Extensions** (`dev-platform-extensions-spec.md`) — VSCode `.vscode/` templates, statusline scripts, scaffolding templates for new projects.
- **Hooks migration** — `~/.claude/settings.json` already declares hooks; once Phase 2 lands, the hook scripts themselves move into `hooks/` and `settings.json` paths get rewritten to point at the deployed location. Deferred — minor and can ride with the testing spec.
- **CHANGELOG.md** + **`tasks/dev-platform-roadmap.md`** — created when R2 (monitoring spec) starts. Foundation spec doesn't need its own CHANGELOG entry; the spec itself + commit history are the record.

## Notes for Implementation

- **Run `install.sh` after Phase 2 completes**, not after Phase 3 lands. The migrated files in Phase 2 can be tracked alongside the still-functioning `~/.claude/` original files — no behavior change until install.sh symlinks the deployed paths to the tracked ones.
- **The first install is the risky moment.** Before symlinking, the script must back up or refuse if `~/.claude/commands/` is a real directory. Test on a throwaway home first if there's any doubt.
- **Symlinks vs copies** — symlinks chosen so editor edits land directly on the tracked file. If symlinks ever cause issues (e.g., a tool refuses to follow them), a copy mode can be added behind a flag without breaking the user-facing contract.
- **No `~/.claude/projects/` content tracked, ever.** That directory holds memory, transcripts, and session state — auto-generated, machine-specific, and may contain auth tokens. The install script must never touch it.
