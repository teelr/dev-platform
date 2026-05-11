# v0.6: VSCode Coverage (Server-Side)

## Coding Specification for Implementation

## Design Philosophy

v0.6 brings VSCode-server-side configuration under dev-platform management. Today the 43 VSCode extensions installed on this Remote-SSH server (`~/.vscode-server/`) are entirely unmanaged — if this machine is rebuilt or VSCode reinstalled server-side, those 43 extensions vanish and must be reinstalled by hand. v0.6 tracks the list in `extensions/vscode/server-extensions.json`, adds a bidirectional sync helper, and extends `scripts/install.sh` to reinstall them all on demand. The same symlink-and-deploy pattern from v0.1 doesn't apply here — VSCode extensions aren't files, they're installed-package state — so the deploy mechanism is "run `code --install-extension` for each entry" rather than symlinking.

Scope discipline per the decision recorded 2026-05-11: v0.6 is **server-side only** (Option C from the inventory discussion). Client-side coverage (laptop's `settings.json`, `keybindings.json`, snippets, theme) is explicitly deferred to a future spec (v0.6b or rolled into v0.7) because (a) those files don't exist on this server, (b) the client/server split for Remote-SSH is a real design conversation with OS-specific install paths, and (c) the value gap between "44 extensions to reinstall" and "client settings to recreate" justifies shipping the smaller win now and learning before designing the bigger one.

The Consumer Audit rule promoted to `dev/CLAUDE.md` 2026-05-11 (commit `24e062f`) applies here — v0.6 introduces a new file (`server-extensions.json`) and a new directory (`extensions/vscode/`) under `extensions/`. The audit confirms: (1) gitignore allow-list `!extensions/**/*.json` already covers it, (2) install.sh extension is part of this spec, (3) verify.sh doesn't apply (the file isn't symlinked; it's read in-place), (4) directory README ships as part of this spec, (5) `tests/vscode/` test orchestrator ships as part of this spec. The spec is self-checking the rule it just landed.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `extensions/vscode/server-extensions.json` | JSON | Standard data format; existing `!extensions/**/*.json` gitignore allow-list covers it without modification. Parseable with `jq` (already a dev dep). |
| `scripts/sync-vscode.sh` | Bash | Matches the existing entry-point pattern (`install.sh`, `verify.sh`, `gate_fast.sh`, `new-project.sh`, `report.sh`). Zero new deps. |
| `scripts/install.sh` extension | Bash | Modify existing Bash script — add a new `install_vscode()` function alongside `install_commands()`, `install_skills()`, etc. |
| `tests/vscode/run.sh` | Bash | Matches v0.4 test-suite pattern; auto-discovered by `gate_fast.sh`. |
| Markdown docs | Markdown | Standard. |

## Overview

1. **Phase 1:** Tracking — directory contract, capture current state, sync helper (Changes 1–3)
2. **Phase 2:** Deploy — `install.sh` extension + auto-discovered test suite (Changes 4–5)
3. **Phase 3:** Wire-up — `dev/CLAUDE.md` Repo Structure table updated (Change 6)

**Demo:** Running `./scripts/sync-vscode.sh capture` from this server reads the 43 currently-installed extensions and writes them as a JSON array to `extensions/vscode/server-extensions.json`. Running `./scripts/install.sh vscode` (or `./scripts/install.sh all`) reads that file and runs `code --install-extension <id>` for each — idempotent (already-installed extensions are no-ops with `--force`). Running `./scripts/sync-vscode.sh diff` compares tracked vs currently-installed and shows any drift. The `tests/vscode/run.sh` suite asserts the tracked file is well-formed and the install path works against a synthetic fixture. After v0.6 ships, a fresh server with the same `code` CLI available can run `install.sh all` once and recover the full 43-extension state.

---

## Phase 1: Tracking

### Change 1: `extensions/vscode/` directory + initial extension list + README

**Problem:** The `extensions/` directory exists (with a placeholder README from v0.1) but `extensions/vscode/` doesn't. The 43 currently-installed extensions live in `~/.vscode-server/` and are completely unmanaged — no inventory exists in this repo. Before any deploy mechanism can read a tracked list, the list itself must be captured.

**File:** `extensions/vscode/server-extensions.json` (new), `extensions/vscode/README.md` (new)

**Implementation:**

Capture the current extension list mechanically:

```bash
mkdir -p extensions/vscode
code --list-extensions 2>&1 \
    | grep -v "^Extensions installed on SSH:" \
    | jq -R . | jq -s . > extensions/vscode/server-extensions.json
```

The `grep -v` strips VSCode's informational header line (e.g., `Extensions installed on SSH: neurx:`) that's not actually an extension ID. The `jq -R . | jq -s .` chain converts the line-per-extension stream into a JSON array of strings.

Result shape (43 entries):

```json
[
  "anthropic.claude-code",
  "bierner.markdown-mermaid",
  "bradlc.vscode-tailwindcss",
  ...
  "yzhang.markdown-all-in-one"
]
```

Then write `extensions/vscode/README.md` — directory contract (~30 lines):

- **What goes here:** `server-extensions.json` (the tracked extension list), and in the future `client-extensions.json` plus per-OS settings files when v0.6b ships
- **What does NOT go here:** per-project `.vscode/` extension recommendations (those belong in each project's repo); client-side `settings.json` / `keybindings.json` (deferred to v0.6b)
- **Deployment:** `scripts/install.sh vscode` reads the JSON array and runs `code --install-extension <id> --force` for each. Idempotent.
- **Sync:** `scripts/sync-vscode.sh capture` rewrites the file from current VSCode state; `... deploy` does the reverse; `... diff` shows drift.
- **Format choice:** JSON array of extension IDs (matches VSCode's `--list-extensions` output shape after de-streaming). Avoided `.txt` so the existing gitignore allow-list `!extensions/**/*.json` covers it.

**Acceptance Test:**

```bash
test -f extensions/vscode/server-extensions.json
test -f extensions/vscode/README.md
jq length extensions/vscode/server-extensions.json    # expect 43
jq '.[0]' extensions/vscode/server-extensions.json    # expect "anthropic.claude-code"
git check-ignore -v extensions/vscode/server-extensions.json && echo "FAIL ignored" || echo "OK tracked"
```

### Change 2: `scripts/sync-vscode.sh` — bidirectional sync helper

**Problem:** Without a sync helper, the user has to remember the exact `code --list-extensions | jq` invocation to capture state, or the `xargs ... code --install-extension` invocation to redeploy. A small CLI wrapper standardizes the round-trip and is the canonical surface for v0.6 operations.

**File:** `scripts/sync-vscode.sh` (new, executable)

**Implementation:**

```bash
#!/usr/bin/env bash
# scripts/sync-vscode.sh — bidirectional sync between the tracked extension
# list and the live VSCode server-side state.
#
# Modes:
#   capture   Read current `code --list-extensions` into the tracked file.
#             Overwrites server-extensions.json. Run this after installing
#             a new extension via VSCode UI.
#   deploy    Read the tracked file and install every extension via
#             `code --install-extension --force`. Idempotent — already-
#             installed extensions are no-ops.
#   diff      Show drift: lines in tracked-not-installed prefixed `<`,
#             installed-not-tracked prefixed `>`.
#
# Usage:
#   ./scripts/sync-vscode.sh [capture|deploy|diff]    # default: diff

set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="${REPO}/extensions/vscode/server-extensions.json"

if ! command -v code >/dev/null 2>&1; then
    echo "ERROR: 'code' CLI not on PATH. Run from a VSCode server-side environment." >&2
    exit 1
fi

current() {
    code --list-extensions 2>&1 | grep -v "^Extensions installed"
}

MODE="${1:-diff}"
case "${MODE}" in
    capture)
        mkdir -p "$(dirname "${FILE}")"
        current | jq -R . | jq -s . > "${FILE}"
        n="$(jq length "${FILE}")"
        echo "captured ${n} extensions to ${FILE}"
        ;;
    deploy)
        [[ -f "${FILE}" ]] || { echo "ERROR: no tracked list at ${FILE}" >&2; exit 1; }
        n="$(jq length "${FILE}")"
        echo "installing ${n} extensions from ${FILE}..."
        jq -r '.[]' "${FILE}" | while read -r ext; do
            code --install-extension "${ext}" --force >/dev/null 2>&1 || \
                echo "  WARN failed to install ${ext}"
        done
        echo "deploy complete"
        ;;
    diff)
        [[ -f "${FILE}" ]] || { echo "ERROR: no tracked list at ${FILE}" >&2; exit 1; }
        diff <(jq -r '.[]' "${FILE}" | sort) <(current | sort)
        rc=$?
        [[ ${rc} -eq 0 ]] && echo "no drift — tracked matches installed"
        exit ${rc}
        ;;
    --help|-h)
        sed -n '2,18p' "${BASH_SOURCE[0]}"
        ;;
    *)
        echo "Unknown mode: ${MODE}" >&2
        echo "Usage: $0 [capture|deploy|diff]" >&2
        exit 1
        ;;
esac
```

**Acceptance Test:**

```bash
chmod +x scripts/sync-vscode.sh
bash -n scripts/sync-vscode.sh   # syntax check

# Diff against the just-captured file should report no drift
./scripts/sync-vscode.sh diff    # expect: "no drift"

# Help renders
./scripts/sync-vscode.sh --help | head -5
```

### Change 3: Capture the current state into the tracked file

**Problem:** Change 1 specified the FORMAT of the file, but the actual capture step needs to happen as a discrete Change so /code does it explicitly (rather than relying on the user to remember). This Change is the "first write" of `extensions/vscode/server-extensions.json`.

**File:** `extensions/vscode/server-extensions.json` (populated)

**Implementation:**

```bash
./scripts/sync-vscode.sh capture
```

Verify the result:

```bash
jq length extensions/vscode/server-extensions.json   # expect 43 (or current count if it has drifted)
jq '.[0]' extensions/vscode/server-extensions.json   # expect first extension by alphabetical order
```

**Acceptance Test:**

```bash
# File contains a JSON array of strings, each matching the publisher.name pattern
jq -e 'all(. == ascii_downcase) and all(test("^[a-z0-9][a-z0-9_-]*\\.[a-z0-9_-]+$"))' \
    extensions/vscode/server-extensions.json
```

The regex `^[a-z0-9][a-z0-9_-]*\.[a-z0-9_-]+$` matches VSCode's extension-ID convention (publisher.name, lowercase, hyphens allowed). All 43 currently-installed extensions match.

---

## Phase 2: Deploy + Test

### Change 4: `scripts/install.sh` extension — `install_vscode()` function

**Problem:** Without an `install.sh` extension, the v0.1 deploy workflow (`./scripts/install.sh`) doesn't restore VSCode extensions on a fresh server. The user would have to remember to run `sync-vscode.sh deploy` separately.

**File:** `scripts/install.sh` (existing — add new function + wire into case statement)

**Implementation:**

Add a new function after `install_hooks()` (around line 119):

```bash
install_vscode() {
    local file="${REPO}/extensions/vscode/server-extensions.json"
    if [[ ! -f "${file}" ]]; then
        echo "  vscode: no tracked list at ${file} — skipping"
        return 0
    fi
    if ! command -v code >/dev/null 2>&1; then
        echo "  vscode: 'code' CLI not on PATH — skipping (not a VSCode server-side env)"
        return 0
    fi
    local count
    count="$(jq length "${file}")"
    echo "  vscode: installing/verifying ${count} extensions..."
    jq -r '.[]' "${file}" | while read -r ext; do
        code --install-extension "${ext}" --force >/dev/null 2>&1 || \
            echo "    WARN failed to install ${ext}"
    done
    echo "  vscode: ${count} extensions installed/verified"
}
```

Extend the case statement at the bottom:

```bash
case "${CATEGORY}" in
    commands)  install_commands ;;
    skills)    install_skills ;;
    settings)  install_settings ;;
    hooks)     install_hooks ;;
    vscode)    install_vscode ;;
    all)       install_commands; install_skills; install_settings; install_hooks; install_vscode ;;
    *)         echo "Unknown category: ${CATEGORY}" >&2
               echo "Usage: $0 [commands|skills|settings|hooks|vscode|all]" >&2
               exit 1 ;;
esac
```

Note the graceful-skip pattern: if the file is missing OR the `code` CLI isn't available, the function returns 0 with a one-line "skipping" notice. This keeps `install.sh all` from failing on machines where VSCode server-side isn't installed (e.g., a CI runner). Same shape as the existing optional checks in `install_settings()` for `keybindings.json` / `settings.local.json`.

**Acceptance Test:**

```bash
# Round-trip on a throwaway $HOME — should NOT actually install extensions on the real system
# (because the throwaway $HOME doesn't have ~/.vscode-server)
FAKE=$(mktemp -d /tmp/v06.XXX)
HOME="${FAKE}" bash scripts/install.sh vscode
# Expect: "vscode: 'code' CLI not on PATH" OR "installed/verified N extensions" depending on env
rm -rf "${FAKE}"

# Real invocation — should be idempotent
bash scripts/install.sh vscode
# Expect: "vscode: installing/verifying 43 extensions..." then "vscode: 43 extensions installed/verified"
```

### Change 5: `tests/vscode/` fixture suite

**Problem:** Without a regression test, edits to `server-extensions.json` or `sync-vscode.sh` could break the format silently. The v0.4 R3 auto-discovery contract picks up `tests/vscode/run.sh` automatically — adding the suite is enough.

**File:** `tests/vscode/run.sh` (new, executable), `tests/vscode/fixtures/valid-list.json` (new), `tests/vscode/fixtures/empty-list.json` (new)

**Implementation:**

Fixtures:

```json
// tests/vscode/fixtures/valid-list.json
["anthropic.claude-code", "ms-python.python", "esbenp.prettier-vscode"]
```

```json
// tests/vscode/fixtures/empty-list.json
[]
```

Runner:

```bash
#!/usr/bin/env bash
# tests/vscode/run.sh — fixture suite for v0.6 VSCode coverage.
# Validates the tracked extensions list format and confirms install.sh
# gracefully skips when the `code` CLI is unavailable.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

# Check 1: live tracked file is valid JSON array of strings
if jq -e 'type == "array" and all(type == "string")' \
        "${REPO}/extensions/vscode/server-extensions.json" >/dev/null 2>&1; then
    n="$(jq length "${REPO}/extensions/vscode/server-extensions.json")"
    record_pass "vscode: server-extensions.json is JSON array of strings (${n} entries)"
else
    record_fail "vscode: server-extensions.json is not a JSON array of strings"
fi

# Check 2: every entry matches the publisher.name extension-ID convention
if jq -e 'all(test("^[a-z0-9][a-z0-9_-]*\\.[a-z0-9_-]+$"))' \
        "${REPO}/extensions/vscode/server-extensions.json" >/dev/null 2>&1; then
    record_pass "vscode: every entry matches publisher.name convention"
else
    record_fail "vscode: some entry violates publisher.name convention"
fi

# Check 3: fixture valid-list.json passes the same shape check
if jq -e 'type == "array" and all(type == "string") and length == 3' \
        "${HERE}/fixtures/valid-list.json" >/dev/null 2>&1; then
    record_pass "vscode: valid-list fixture parses as 3-entry array"
else
    record_fail "vscode: valid-list fixture shape wrong"
fi

# Check 4: empty-list fixture is valid empty array
if jq -e 'type == "array" and length == 0' \
        "${HERE}/fixtures/empty-list.json" >/dev/null 2>&1; then
    record_pass "vscode: empty-list fixture is empty array"
else
    record_fail "vscode: empty-list fixture shape wrong"
fi

# Check 5: install.sh skips gracefully when `code` is unavailable
FAKE_PATH=$(mktemp -d /tmp/v06-test.XXX)
out="$(PATH="${FAKE_PATH}" bash "${REPO}/scripts/install.sh" vscode 2>&1)"
rm -rf "${FAKE_PATH}"
if echo "${out}" | grep -q "code.*CLI not on PATH"; then
    record_pass "vscode: install.sh skips gracefully when code CLI missing"
else
    record_fail "vscode: install.sh did not skip gracefully (output: ${out:0:200})"
fi

# Check 6: sync-vscode.sh syntax + --help renders
if bash -n "${REPO}/scripts/sync-vscode.sh"; then
    record_pass "vscode: sync-vscode.sh bash syntax clean"
else
    record_fail "vscode: sync-vscode.sh bash syntax error"
fi
```

**Acceptance Test:**

```bash
bash tests/vscode/run.sh
# Expect: 6 PASS, 0 FAIL

# Auto-discovery — running gate_fast.sh should pick up tests/vscode/ automatically
bash scripts/gate_fast.sh
# Expect: total PASS count grew by 6 (was 52, now 58)
```

---

## Phase 3: Wire-up

### Change 6: `dev/CLAUDE.md` Repo Structure + workflow notes

**Problem:** The Repo Structure table in `dev/CLAUDE.md` lists `extensions/` with a placeholder description. After v0.6, it should reflect the actual content. The `scripts/install.sh` arg list also gained a `vscode` category that should be mentioned in the Install / Deploy section.

**File:** `dev/CLAUDE.md` (existing — two edits)

**Implementation:**

Edit 1 — Repo Structure table row for `extensions/`:

```markdown
| `extensions/` | IDE config tracked + deployed. `vscode/server-extensions.json` is the tracked extension list; `scripts/install.sh vscode` reinstalls them all; `scripts/sync-vscode.sh` is the capture/deploy/diff helper. |
```

Edit 2 — Install / Deploy section's `install.sh` argument list:

Change "categories: `commands`, `skills`, `settings`, `hooks`, or `all`" to include `vscode`:

```markdown
`scripts/install.sh [category]` symlinks tracked files into the user environment (categories: `commands`, `skills`, `settings`, `hooks`, `vscode`, or `all`).
```

**Acceptance Test:** Both edits land; the Repo Structure table mentions `vscode/server-extensions.json` explicitly; the install.sh arg list includes `vscode`.

---

## Acceptance Criteria

- [ ] `extensions/vscode/server-extensions.json` exists, is a valid JSON array of strings, contains the currently-installed extension IDs (Change 1, 3)
- [ ] `extensions/vscode/README.md` exists with directory contract (Change 1)
- [ ] `scripts/sync-vscode.sh` exists, executable; `capture` / `deploy` / `diff` modes work; `--help` renders (Change 2)
- [ ] `./scripts/sync-vscode.sh capture` produces an array matching what `code --list-extensions` reports right now (Change 3)
- [ ] `scripts/install.sh vscode` deploys the tracked list; idempotent on re-run; gracefully skips when `code` CLI is absent (Change 4)
- [ ] `tests/vscode/run.sh` exists, records ≥6 PASS, auto-discovered by `gate_fast.sh` (Change 5)
- [ ] `dev/CLAUDE.md` Repo Structure table + Install / Deploy section updated (Change 6)
- [ ] `bash scripts/gate_fast.sh` still PASS after all changes
- [ ] No file under `projects/` modified
- [ ] Spec deviations (if any) explicitly flagged at /code time

## Out of Scope (Future Specs)

- **Client-side coverage (laptop-side `settings.json`, `keybindings.json`, snippets, theme)** — deferred to v0.6b or rolled into v0.7. The client/server split for Remote-SSH is its own design conversation (OS-specific install paths, where the repo clones on the laptop, etc.).
- **Statusline scripts** — no custom statusline files exist on the server today; aspirational v0.6b territory.
- **VSCode workspace `.vscode/` settings per project** — those belong in each project's own repo; explicitly out of dev-platform scope per the Scope rule.
- **Automatic capture on every commit** — a git hook that auto-runs `sync-vscode.sh capture` if drift detected. Useful but premature; defer until manual sync becomes friction.
- **VSCode profile management** (multiple distinct profile sets) — single global profile only in v0.6.

## What NOT to Do

- **Do not symlink `server-extensions.json` anywhere.** Unlike `settings.json` or hook scripts, this file isn't read by VSCode at startup. It's read in-place by `install.sh` and `sync-vscode.sh` to drive `code --install-extension`. Symlinking would add no value and complicate the model.
- **Do not commit a populated `server-extensions.json` with extensions specific to a single machine's quirks.** The list captured by Change 3 is THIS machine's current state at the moment of v0.6 implementation. Future curation (removing extensions you didn't actually want) is a follow-on.
- **Do not extend `verify.sh` to drift-check installed extensions.** The diff is one-off via `sync-vscode.sh diff`; baking it into `verify.sh` would slow the verify step + couple it to the `code` CLI availability. The dedicated `diff` mode is the right surface.
- **Do not bundle laptop-side VSCode config in v0.6.** Option C from the design discussion was explicitly server-side only. Resist scope creep.
- **Do not use `.txt` for the extension list.** The existing gitignore allow-list covers `**/*.json` under `extensions/`; `.txt` would require a gitignore extension AND a less standard parse path.
- **Do not fail `install.sh` when the `code` CLI is absent.** A graceful skip with a one-line notice is the correct pattern — matches how `install_settings()` handles optional `keybindings.json` / `settings.local.json`.
- **Do not bundle the v0.6 commit with the post-v0.5 Consumer Audit chore commit.** The Consumer Audit rule landed in PR #5 (`24e062f`). v0.6 commits go on a `v0.6/<spec-phase>` branch from main, separately.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `extensions/vscode/server-extensions.json` | New | JSON array of ~43 currently-installed extension IDs |
| `extensions/vscode/README.md` | New | Directory contract |
| `scripts/sync-vscode.sh` | New | Bidirectional sync helper (capture / deploy / diff) |
| `scripts/install.sh` | Modify | Add `install_vscode()` function + extend case statement |
| `tests/vscode/run.sh` | New | Fixture suite (auto-discovered by `gate_fast.sh`) |
| `tests/vscode/fixtures/valid-list.json` | New | 3-entry valid fixture |
| `tests/vscode/fixtures/empty-list.json` | New | Empty-array fixture |
| `dev/CLAUDE.md` | Modify (by /docs) | Repo Structure row for `extensions/` + Install / Deploy section |
| `tasks/dev-platform-vscode-coverage-spec.md` | (this file) | Spec |

## Implementation Order

1. **Phase 1 (Change 1)** — Create `extensions/vscode/` directory + skeleton README + initial empty file (or stub). Foundation.
2. **Phase 1 (Change 2)** — Write `scripts/sync-vscode.sh` with all three modes. Needed before Change 3 because Change 3 invokes the script.
3. **Phase 1 (Change 3)** — Run `./scripts/sync-vscode.sh capture` to populate `server-extensions.json` with real current state. This is the moment the tracked file becomes useful.
4. **Phase 2 (Change 4)** — Extend `install.sh` with `install_vscode()` function. Verify idempotent re-run + graceful skip.
5. **Phase 2 (Change 5)** — Write `tests/vscode/` suite. Auto-discovery picks it up via `gate_fast.sh` without orchestrator edit (per the v0.4 R3 contract).
6. **Phase 3 (Change 6)** — `dev/CLAUDE.md` updates. Handled by `/docs` per the established pattern (matches Phases 1–4 of v0.5).

All 6 Changes can be batched in a single `/code` session — small phase. Single feature branch `v0.6/server-side-extensions` → single PR (no Per-Spec-Phase strategy needed since the whole phase fits in <200 lines of diff).

## Verification Checklist

- [ ] All 6 Changes implemented per the spec
- [ ] `bash -n` passes on `scripts/sync-vscode.sh` and the modified `scripts/install.sh`
- [ ] `jq` parses `extensions/vscode/server-extensions.json` cleanly
- [ ] `./scripts/sync-vscode.sh diff` reports no drift immediately after `capture`
- [ ] `./scripts/install.sh vscode` is idempotent (re-running doesn't change state)
- [ ] `./scripts/install.sh vscode` gracefully skips when `code` CLI is absent (test with `PATH=$(mktemp -d)`)
- [ ] `tests/vscode/run.sh` records ≥6 PASS, auto-discovered by `gate_fast.sh`
- [ ] Total gate count grew from 52 → 58 (added 6 vscode checks)
- [ ] `dev/CLAUDE.md` Repo Structure row for `extensions/` reflects actual content
- [ ] Spec taxonomy check (`scripts/check_spec_taxonomy.sh`) passes
- [ ] No file under `projects/` modified

## Notes for Implementation

- **`jq` is a dependency.** It's already used by `monitoring/aggregator.py`'s adjacent tooling and is universally installed on dev-platform machines. The Language Decisions table doesn't formally list it because it's not a "component" — but `install_vscode()`, `sync-vscode.sh`, and `tests/vscode/run.sh` all rely on it. If `jq` is somehow not on PATH, the scripts fail with a clear error rather than silently degrading.
- **The 43-extension number is THIS machine, RIGHT NOW.** When /code captures, the count may differ — that's fine, capture what's there. The acceptance tests check shape (JSON array of valid IDs), not a specific count.
- **`code --install-extension --force` is idempotent.** Re-running it for an already-installed extension is a no-op. This makes `install.sh vscode` safe to run repeatedly without state corruption.
- **The "Extensions installed on SSH: neurx:" header** that `code --list-extensions` emits is part of the Remote-SSH wrapper's output, not an actual extension. `grep -v "^Extensions installed"` strips it. Other Remote-SSH targets (different hostnames) emit a similar header — the grep handles all variants.
- **`tests/vscode/` follows the auto-discovery contract from v0.4 R3.** No edit to `scripts/gate_fast.sh` is needed — it walks `tests/*/` and runs any `*.sh` file it finds.
- **Consumer Audit rule (just promoted to dev/CLAUDE.md 2026-05-11) self-checked:** gitignore covers `.json` under `extensions/` ✓; install.sh extension is Change 4 ✓; verify.sh doesn't apply (no symlinking) ✓; directory README is Change 1 ✓; test orchestrator (`tests/vscode/`) is Change 5 ✓. All five audit points addressed.
- **Future v0.6b / client-side spec** will likely add: `extensions/vscode/client-extensions.json` (separate from server), per-OS install path handling in `install.sh` (Mac: `~/Library/Application Support/Code/User/`, Linux: `~/.config/Code/User/`, Windows: `%APPDATA%/Code/User/`), `settings.json` + `keybindings.json` + `snippets/` tracking. Don't pre-build for it; just don't paint into a corner here.
