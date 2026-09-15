# v1.35: Client-Side VSCode Coverage

## Coding Specification for Implementation

## Design Philosophy

v0.6 (2026-05-11) tracked the VSCode **server-side** state on neurX (43 Remote-SSH extensions) and explicitly deferred client-side coverage — the laptop's `settings.json`, `keybindings.json`, snippets, and theme — to a future spec, "because (a) those files don't exist on this server, (b) the client/server split for Remote-SSH is a real design conversation with OS-specific install paths." This spec is that follow-on, scoped down from v0.6's speculative "Mac/Linux/Windows, settings+keybindings+snippets+theme" list to what the user actually confirmed: **the client machine is Windows only**, dev-platform is **already cloned there**, and the tracked scope is **`settings.json` + `keybindings.json` only** (no snippets, no client-side extension list, no theme-only tracking).

**The central asymmetry from v0.6, and why it drives every design decision below:** v0.6's `/code` session ran ON neurX, the target server — so Change 3 ("capture the current state") could just run `code --list-extensions` directly and populate the tracked file as a Change in that spec. This spec's `/code` session also runs on neurX (Linux), but the target for THIS spec is a separate Windows machine this session has no access to. **`/code` cannot read the real `settings.json`/`keybindings.json` content, cannot run any script on the Windows box, and cannot verify Windows-path detection against a real Windows environment.** Every Change below is scoped to what's buildable and testable from neurX using mocked Windows tooling (`cmd.exe`, `wslpath`, `cygpath` — see Change 2); the actual first capture of real content is a **manual post-merge step the user runs on the Windows machine itself** (see "Post-Merge" section), not a Change in this spec. Writing "captures the user's real VSCode settings" as an accomplished fact here would violate the Honesty About What Ships rule and the spec-writing rule to verify every external-state claim — neither can be true until a human runs the tool on the actual machine.

**Windows path detection is inherently unverified from this session and is flagged as such throughout, not asserted as working.** Two realistic ways dev-platform's Bash tooling could be running on a Windows client — WSL (where `$APPDATA` isn't inherited, but `cmd.exe`/`wslpath` are reachable) and Git-Bash/MSYS/Cygwin (where `$APPDATA` IS inherited directly, and `cygpath` may or may not be installed) — are both supported via a single detection function, each branch unit-tested against a **mocked** `cmd.exe`/`wslpath`/`cygpath` (Change 4), because there is no real Windows machine in this environment to test against. The user must run `./scripts/sync-vscode-client.sh resolve` on the real machine after merge to confirm detection actually works there (see "Post-Merge").

**`settings.json`/`keybindings.json` are treated as opaque text, never parsed as JSON.** VSCode's own config files are JSONC (comments and, in some editor-written cases, trailing commas allowed) and hand-edited by the user — unlike `extensions/vscode/server-extensions.json`, which is a JSON array dev-platform fully owns and controls the shape of. Piping the user's real file through `jq` risks a parse error on a file this spec has never seen. `capture`/`deploy` use plain `cp`; `diff` uses plain `diff -u`. No JSON validation of these two files, anywhere.

**Deploy is a straight copy, not a merge**, unlike `settings.json`'s v1.6 Local Settings Isolation merge-deploy model. That model solved a different problem: Claude Code writes runtime "always allow" grants INTO the live `settings.json` continuously, so overwriting it on every install would destroy state the tracked repo never asked for. VSCode's `settings.json`/`keybindings.json` have no equivalent runtime auto-write from an unrelated process — they're user/UI-edited only, and this spec targets exactly one dedicated Windows client machine, not a fleet needing per-machine overlays. A straight `capture` (live → tracked) / `deploy` (tracked → live) round-trip, mirroring v0.6's own extension `capture`/`deploy`/`diff` shape, is the correct level of complexity — see "What NOT to Do".

**`install_vscode_client()` deliberately duplicates its Windows-detection logic inline in `scripts/install.sh` rather than sourcing a shared helper or shelling out to `scripts/sync-vscode-client.sh`.** This looks like a Derivation Sweep violation at first glance, but it matches TWO existing, deliberate precedents already in this exact file: (1) `install.sh`'s own header explains it keeps its `REPO`-resolution logic inline rather than sourcing `scripts/lib/main_checkout.sh` because `tests/worktree-default/` copies `install.sh`/`verify.sh`/`uninstall.sh` alone into a fixture directory with no `scripts/lib/` alongside — sourcing would break that test; the identical constraint applies to any new helper `install.sh` would source. (2) `install_vscode()` (the v0.6 server-side function, `scripts/install.sh:194-270`) already duplicates `sync-vscode.sh`'s install loop inline rather than shelling out to `sync-vscode.sh deploy`, with its own extra hardening (`timeout`, IPC-reachability probe, attempted/failed counters) that the standalone script doesn't need. `install_vscode_client()` follows the same shape: its own inline resolution copy, its own permissive graceful-skip philosophy (this runs on every machine via `install.sh all`, including neurX itself, where "not a Windows client" is the expected, common, silent case).

**Consumer Audit, run before writing any code:** two new file types land in glob-managed directories — `scripts/sync-vscode-client.sh` and `tests/vscode-client/*.sh` + `tests/vscode-client/fixtures/**`. Probed directly (not assumed):

```bash
touch scripts/probe-audit.sh tests/vscode-client-probe/run.sh tests/vscode-client-probe/fixtures.json
git status --porcelain scripts/ tests/
# → ?? scripts/probe-audit.sh
# → ?? tests/vscode-client-probe/
rm -f scripts/probe-audit.sh; rm -rf tests/vscode-client-probe
```

Both are already covered by the existing gitignore allow-list (`!scripts/*.sh` at `.gitignore:74`; `!tests/**/`, `!tests/**/*.sh`, `!tests/**/*.json` at `.gitignore:158-164`) — **no gitignore edit needed.** `scripts/install.sh`'s glob (audit point 2) is this spec's own Change 3. `scripts/verify.sh` (audit point 3) needs no change — confirmed by `grep -n "sync-vscode" scripts/verify.sh` returning no match; neither `sync-vscode.sh` nor the new `sync-vscode-client.sh` are symlinked categories `verify.sh` tracks. Directory README (audit point 4) is Change 1. Test orchestrator (audit point 5) needs no edit — `scripts/gate_fast.sh:221` already walks `"${REPO}/tests"/*/` and auto-discovers any `run.sh` it finds (the same v0.4 R3 contract `tests/vscode/` already relies on).

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/sync-vscode-client.sh` | Bash | Matches the existing entry-point pattern (`install.sh`, `sync-vscode.sh`, `gate_fast.sh`). Zero new deps — deliberately avoids `jq` (see Design Philosophy: these two files are opaque text, not JSON dev-platform parses). |
| `scripts/install.sh` extension | Bash | Modify existing Bash script — add `install_vscode_client()` alongside `install_vscode()`. |
| `tests/vscode-client/run.sh` + mock binaries | Bash | Matches the `tests/vscode/` pattern (mock `code` CLI) — extends it with mock `cmd.exe`/`wslpath`/`cygpath`. |
| `extensions/vscode/README.md`, root `README.md` | Markdown | Standard. |

## Overview

1. **Phase 1: Tracking & Sync Helper** — directory contract update, `scripts/sync-vscode-client.sh` with `resolve`/`capture`/`deploy`/`diff` modes (Changes 1–2)
2. **Phase 2: Deploy Integration & Tests** — `install.sh` extension (`vscode-client` category), auto-discovered fixture suite with mocked Windows tooling (Changes 3–4)
3. **Phase 3: Wire-up** — root `README.md` corrected (Change 5)

**Demo (from neurX, everything `/code` can actually run):** `./scripts/sync-vscode-client.sh resolve` on this Linux machine prints a clear "not a Windows client" error and exits 1 — the correct, expected behavior here. `bash tests/vscode-client/run.sh` exercises the WSL and Git-Bash/MSYS detection branches against mocked `cmd.exe`/`wslpath`/`cygpath`, and exercises `capture`/`deploy`/`diff` against a fake directory via `--dir`, all without touching a real Windows machine. `./scripts/install.sh vscode-client` on neurX prints the same graceful one-line skip and exits 0, exactly like `install_vscode()` does when the `code` CLI is absent. **What this demo does NOT show, and cannot show from here:** the tool actually working against the real Windows client's real `settings.json`. That's the Post-Merge step below.

---

## Phase 1: Tracking & Sync Helper

### Change 1: `extensions/vscode/README.md` — extend the directory contract

**Problem:** The current README explicitly lists client-side config under "What does NOT go here" with a note that it's "deferred to a future spec (v0.6b or rolled into v0.7)." That future spec is this one — the contract needs to flip from "explicitly excluded" to "tracked, Windows-only."

**File:** `extensions/vscode/README.md` (existing)

**Implementation:**

Edit "## What goes here" — add:

```markdown
- `client-settings.json`, `client-keybindings.json` — the Windows VSCode client's `settings.json` / `keybindings.json` (v1.35). **Windows-only** — no Mac/Linux client support exists. Populated by `scripts/sync-vscode-client.sh capture`, run FROM the Windows client machine (not by `/code` — see that script's header for why). Read by `scripts/install.sh vscode-client` to deploy.
```

Edit "## What does NOT go here" — remove the bullet stating client-side config is deferred; replace with:

```markdown
- **Mac/Linux client config** — v1.35 shipped Windows-only, per an explicit scope decision (the confirmed client machine is Windows). A Mac (`~/Library/Application Support/Code/User/`) or Linux (`~/.config/Code/User/`) client would need its own detection branch in `scripts/sync-vscode-client.sh` — not built here.
- **Snippets, theme-only tracking, client-side extension list** — out of scope for v1.35; see the spec's "Out of Scope" section if revisiting.
```

Add a new section, after the existing "## Sync helper" section:

```markdown
## Client-side sync (v1.35, Windows only)

`./scripts/sync-vscode-client.sh [resolve|capture|deploy|diff]`, run from the Windows client machine:

- `resolve` — print the detected Windows VSCode `User/` directory and exit. Sanity-check detection before trusting `capture`/`deploy`.
- `capture` — copy the live `settings.json`/`keybindings.json` into `client-settings.json`/`client-keybindings.json`. Run after changing VSCode client settings.
- `deploy` — copy the tracked files onto the live path. Creates the `User/` directory if absent.
- `diff` — unified diff between tracked and live, per file.

Unlike `server-extensions.json`, these two files are treated as **opaque text** (plain `cp`/`diff -u`), never parsed as JSON — VSCode's config format is JSONC (comments allowed) and hand-edited.

**Detection is unverified against a real Windows machine as of v1.35** — built and unit-tested here against mocked `cmd.exe`/`wslpath`/`cygpath` on Linux, because no Windows machine exists in the dev-platform build environment. Run `resolve` on the real machine first; if it fails, the detection logic in `scripts/sync-vscode-client.sh` needs a follow-on fix, not a workaround.
```

**Acceptance Test:**

```bash
test -f extensions/vscode/README.md
grep -q "client-settings.json" extensions/vscode/README.md
grep -q "client-keybindings.json" extensions/vscode/README.md
grep -q "sync-vscode-client.sh" extensions/vscode/README.md
! grep -q "deferred to a future spec" extensions/vscode/README.md
```

### Change 2: `scripts/sync-vscode-client.sh` — client config sync helper

**Problem:** Without this, there's no tool to move `settings.json`/`keybindings.json` between the Windows client's live path and the tracked repo files in either direction, and no way to detect the live path in the first place across the two realistic Windows-Bash environments (WSL, Git-Bash/MSYS/Cygwin).

**File:** `scripts/sync-vscode-client.sh` (new, executable)

**Implementation:**

```bash
#!/usr/bin/env bash
# scripts/sync-vscode-client.sh — sync helper for client-side VSCode config
# (settings.json, keybindings.json) on the Windows VSCode client machine.
#
# Unlike scripts/sync-vscode.sh (server-side extensions — a JSON array
# dev-platform fully controls), these two files are VSCode's own JSONC
# format (comments allowed) and hand-edited by the user — treated here as
# OPAQUE TEXT (cp / diff -u), never parsed or validated as JSON.
#
# Modes:
#   resolve   Print the detected Windows VSCode User directory and exit.
#             Sanity-check detection before trusting capture/deploy.
#   capture   Copy the live settings.json/keybindings.json into the tracked
#             files. Run after changing VSCode client settings.
#   deploy    Copy the tracked files onto the live path. Creates the User/
#             directory if absent.
#   diff      Unified diff between tracked and live, per file.
#             Exit 0 if no drift, 1 if drift in either file.
#
# Windows detection, in order (see resolve_vscode_user_dir below):
#   1. WSL        — $WSL_DISTRO_NAME set, or /proc/version mentions
#                    "microsoft". Bridges via `cmd.exe /c "echo %APPDATA%"`
#                    + `wslpath -u`.
#   2. Git-Bash /  — $APPDATA set directly (Windows env vars are inherited).
#      MSYS/Cygwin   Uses `cygpath -u` if present, else a naive backslash
#                    substitution fallback (Git-Bash's own coreutils
#                    generally accept a forward-slash drive-letter path
#                    like "C:/Users/..." directly, even without cygpath).
#   3. Neither     — not a Windows client. Exit 1 with a clear message.
#
# UNVERIFIED AGAINST A REAL WINDOWS MACHINE: unit-tested here (tests/vscode-client/)
# against mocked cmd.exe/wslpath/cygpath on Linux, because no Windows machine
# exists in this build environment. Run `resolve` on the real client machine
# after merge before trusting `capture`.
#
# Usage:
#   ./scripts/sync-vscode-client.sh [resolve|capture|deploy|diff] [--dir <path>]
#   ./scripts/sync-vscode-client.sh --help

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS_TRACKED="${REPO}/extensions/vscode/client-settings.json"
KEYBINDINGS_TRACKED="${REPO}/extensions/vscode/client-keybindings.json"

DIR_OVERRIDE=""
MODE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)
            shift
            DIR_OVERRIDE="$1"
            ;;
        --help|-h)
            MODE="--help"
            ;;
        resolve|capture|deploy|diff)
            MODE="$1"
            ;;
        *)
            echo "Unknown arg: $1" >&2
            echo "Usage: $0 [resolve|capture|deploy|diff] [--dir <path>]" >&2
            exit 1
            ;;
    esac
    shift
done
MODE="${MODE:-resolve}"

# Detect the Windows VSCode User config directory. Prints the resolved path
# to stdout and returns 0, or prints nothing and returns 1 if this isn't a
# Windows client environment. --dir short-circuits detection entirely (tests).
resolve_vscode_user_dir() {
    if [[ -n "${DIR_OVERRIDE}" ]]; then
        echo "${DIR_OVERRIDE}"
        return 0
    fi

    # 1. WSL
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
        if command -v cmd.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
            local appdata_win
            appdata_win="$(cmd.exe /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r\n')"
            if [[ -n "${appdata_win}" && "${appdata_win}" != "%APPDATA%" ]]; then
                echo "$(wslpath -u "${appdata_win}")/Code/User"
                return 0
            fi
        fi
        return 1
    fi

    # 2. Git-Bash / MSYS / Cygwin
    if [[ -n "${APPDATA:-}" ]]; then
        if command -v cygpath >/dev/null 2>&1; then
            echo "$(cygpath -u "${APPDATA}")/Code/User"
        else
            echo "${APPDATA//\\//}/Code/User"
        fi
        return 0
    fi

    return 1
}

not_windows_error() {
    echo "ERROR: could not detect a Windows VSCode client environment (no WSL, no APPDATA)." >&2
    echo "       This script targets the Windows VSCode client machine only." >&2
}

case "${MODE}" in
    resolve)
        if dir="$(resolve_vscode_user_dir)"; then
            echo "${dir}"
        else
            not_windows_error
            exit 1
        fi
        ;;
    capture)
        dir="$(resolve_vscode_user_dir)" || { not_windows_error; exit 1; }
        mkdir -p "$(dirname "${SETTINGS_TRACKED}")"
        captured=0
        if [[ -f "${dir}/settings.json" ]]; then
            cp "${dir}/settings.json" "${SETTINGS_TRACKED}"
            captured=$((captured + 1))
        else
            echo "  WARN ${dir}/settings.json not found — skipping" >&2
        fi
        if [[ -f "${dir}/keybindings.json" ]]; then
            cp "${dir}/keybindings.json" "${KEYBINDINGS_TRACKED}"
            captured=$((captured + 1))
        else
            echo "  WARN ${dir}/keybindings.json not found — skipping" >&2
        fi
        echo "captured ${captured}/2 files from ${dir}"
        ;;
    deploy)
        dir="$(resolve_vscode_user_dir)" || { not_windows_error; exit 1; }
        if [[ ! -f "${SETTINGS_TRACKED}" && ! -f "${KEYBINDINGS_TRACKED}" ]]; then
            echo "ERROR: no tracked client config at ${SETTINGS_TRACKED#${REPO}/} or ${KEYBINDINGS_TRACKED#${REPO}/}" >&2
            echo "       Run '$0 capture' on the client machine first." >&2
            exit 1
        fi
        mkdir -p "${dir}"
        deployed=0
        if [[ -f "${SETTINGS_TRACKED}" ]]; then
            cp "${SETTINGS_TRACKED}" "${dir}/settings.json"
            deployed=$((deployed + 1))
        fi
        if [[ -f "${KEYBINDINGS_TRACKED}" ]]; then
            cp "${KEYBINDINGS_TRACKED}" "${dir}/keybindings.json"
            deployed=$((deployed + 1))
        fi
        echo "deployed ${deployed} file(s) to ${dir}"
        ;;
    diff)
        dir="$(resolve_vscode_user_dir)" || { not_windows_error; exit 1; }
        drift=0
        for pair in "settings.json:${SETTINGS_TRACKED}" "keybindings.json:${KEYBINDINGS_TRACKED}"; do
            name="${pair%%:*}"
            tracked="${pair#*:}"
            live="${dir}/${name}"
            if [[ ! -f "${tracked}" ]]; then
                echo "  ${name}: no tracked file — run '$0 capture' first" >&2
                drift=1
                continue
            fi
            if [[ ! -f "${live}" ]]; then
                echo "  ${name}: no live file at ${live}" >&2
                drift=1
                continue
            fi
            if ! diff -u "${live}" "${tracked}"; then
                drift=1
            fi
        done
        [[ ${drift} -eq 0 ]] && echo "no drift — tracked matches live"
        exit ${drift}
        ;;
    --help|-h)
        cat <<'HELP'
scripts/sync-vscode-client.sh — sync helper for client-side VSCode config
(settings.json, keybindings.json) on the Windows VSCode client machine.

Modes:
  resolve   Print the detected Windows VSCode User directory and exit.
  capture   Copy live settings.json/keybindings.json into the tracked files.
  deploy    Copy the tracked files onto the live path.
  diff      Show drift (unified diff) between tracked and live.

Tracked files:
  extensions/vscode/client-settings.json
  extensions/vscode/client-keybindings.json

Override the detected directory with --dir <path> (used by tests/vscode-client/).

Usage:
  ./scripts/sync-vscode-client.sh resolve
  ./scripts/sync-vscode-client.sh capture
  ./scripts/sync-vscode-client.sh deploy
  ./scripts/sync-vscode-client.sh diff
  ./scripts/sync-vscode-client.sh capture --dir /tmp/fake/Code/User
HELP
        ;;
esac
```

**Acceptance Test:**

```bash
chmod +x scripts/sync-vscode-client.sh
bash -n scripts/sync-vscode-client.sh

# Real environment on THIS (Linux) gate machine — the expected common case.
env -u WSL_DISTRO_NAME -u APPDATA bash scripts/sync-vscode-client.sh resolve
# expect: exit 1, stderr "could not detect a Windows VSCode client environment"

# --dir short-circuits detection entirely.
bash scripts/sync-vscode-client.sh resolve --dir /tmp/whatever
# expect: prints "/tmp/whatever", exit 0

bash scripts/sync-vscode-client.sh --help | head -5
```

---

## Phase 2: Deploy Integration & Tests

### Change 3: `scripts/install.sh` extension — `install_vscode_client()` + `vscode-client` category

**Problem:** Without an `install.sh` category, deploying the tracked client config to a fresh Windows machine (or re-deploying after a `capture`) requires remembering to run `sync-vscode-client.sh deploy` separately — the same gap v0.6's `install_vscode()` closed for extensions.

**File:** `scripts/install.sh` (existing — three edits)

**Implementation:**

Edit 1 — add to the usage comment block near the top (after the existing `#   ./scripts/install.sh vscode` line, `scripts/install.sh:15`):

```bash
#   ./scripts/install.sh vscode-client
```

Edit 2 — add a new function immediately after `install_vscode()` (after `scripts/install.sh:270`, before `install_managed()`):

```bash
install_vscode_client() {
    # Client-side VSCode config (settings.json, keybindings.json) on the
    # Windows VSCode client machine (v1.35). Deliberately duplicates the
    # Windows-detection logic in scripts/sync-vscode-client.sh's
    # resolve_vscode_user_dir() rather than sourcing it or shelling out to
    # it — same reason install_vscode() above duplicates sync-vscode.sh's
    # install loop instead of calling it, and the same reason this file's
    # own REPO resolution (see file header) stays inline: this function
    # must keep working when install.sh is copied out and run standalone
    # (tests/worktree-default copies install.sh/verify.sh/uninstall.sh
    # alone, with no scripts/lib/ or sibling scripts alongside them).
    #
    # Permissive by design, same philosophy as install_vscode(): this runs
    # as part of `install.sh all` on every machine, including the Linux
    # neurX server, where "not a Windows client" is the expected, common
    # case and must be a silent one-line skip, never an error.
    local dir=""
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
        if command -v cmd.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
            local appdata_win
            appdata_win="$(cmd.exe /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r\n')"
            if [[ -n "${appdata_win}" && "${appdata_win}" != "%APPDATA%" ]]; then
                dir="$(wslpath -u "${appdata_win}")/Code/User"
            fi
        fi
    elif [[ -n "${APPDATA:-}" ]]; then
        if command -v cygpath >/dev/null 2>&1; then
            dir="$(cygpath -u "${APPDATA}")/Code/User"
        else
            dir="${APPDATA//\\//}/Code/User"
        fi
    fi

    if [[ -z "${dir}" ]]; then
        echo "  vscode-client: not a Windows VSCode client environment — skipping"
        return 0
    fi

    local settings="${REPO}/extensions/vscode/client-settings.json"
    local keybindings="${REPO}/extensions/vscode/client-keybindings.json"
    if [[ ! -f "${settings}" && ! -f "${keybindings}" ]]; then
        echo "  vscode-client: no tracked client config — run 'scripts/sync-vscode-client.sh capture' on this machine first — skipping"
        return 0
    fi

    mkdir -p "${dir}"
    local deployed=0
    if [[ -f "${settings}" ]]; then
        cp "${settings}" "${dir}/settings.json" && deployed=$((deployed + 1))
    fi
    if [[ -f "${keybindings}" ]]; then
        cp "${keybindings}" "${dir}/keybindings.json" && deployed=$((deployed + 1))
    fi
    echo "  vscode-client: ${deployed} file(s) deployed to ${dir}"
}
```

Edit 3 — extend the case statement (`scripts/install.sh:371-385`):

```bash
case "${CATEGORY}" in
    commands)       install_commands ;;
    skills)         install_skills ;;
    settings)       install_settings ;;
    hooks)          install_hooks ;;
    vscode)         install_vscode ;;
    vscode-client)  install_vscode_client ;;
    managed)        install_managed ;;
    git-hooks)      install_git_hooks ;;
    worktree)       install_worktree ;;
    shell)          install_shell ;;
    all)            install_commands; install_skills; install_settings; install_hooks; install_vscode; install_vscode_client; install_managed; install_git_hooks; install_worktree; install_shell ;;
    *)              echo "Unknown category: ${CATEGORY}" >&2
                    echo "Usage: $0 [commands|skills|settings|hooks|vscode|vscode-client|managed|git-hooks|worktree|shell|all]" >&2
                    exit 1 ;;
esac
```

**Acceptance Test:**

```bash
bash -n scripts/install.sh

# Real environment on this Linux gate machine — expected common case.
HOME="$(mktemp -d)" bash scripts/install.sh vscode-client
# expect: "vscode-client: not a Windows VSCode client environment — skipping", exit 0

# `all` still runs clean end to end with the new function wired in.
HOME="$(mktemp -d)" bash scripts/install.sh all
# expect: exit 0, includes the vscode-client skip line among the others

grep -q "vscode-client" scripts/install.sh
```

### Change 4: `tests/vscode-client/` fixture suite — mocked Windows detection + capture/deploy/diff round trip

**Problem:** Without a regression suite, the two detection branches (WSL, Git-Bash/MSYS) and the capture/deploy/diff logic have no coverage beyond manual inspection — and per the Design Philosophy, they can NEVER be tested against a real Windows machine from this environment, so mocked coverage here is the only coverage this feature will ever get in CI.

**File:** `tests/vscode-client/run.sh` (new, executable), `tests/vscode-client/fixtures/mock-bin/cmd.exe`, `tests/vscode-client/fixtures/mock-bin/wslpath`, `tests/vscode-client/fixtures/mock-bin/cygpath` (new, executable)

**Implementation:**

Mock `cmd.exe` (only invocation used: `cmd.exe /c "echo %APPDATA%"`):

```bash
#!/usr/bin/env bash
# tests/vscode-client/fixtures/mock-bin/cmd.exe
# Echoes $MOCK_APPDATA_WIN with a trailing \r\n, matching real cmd.exe's
# CRLF output — exercises the `tr -d '\r\n'` strip in resolve_vscode_user_dir.
: "${MOCK_APPDATA_WIN:?MOCK_APPDATA_WIN must be set in env}"
if [[ "${1:-}" == "/c" ]]; then
    printf '%s\r\n' "${MOCK_APPDATA_WIN}"
else
    echo "mock-cmd.exe: unsupported invocation: $*" >&2
    exit 1
fi
```

Mock `wslpath` (only invocation used: `wslpath -u <windows-path>`):

```bash
#!/usr/bin/env bash
# tests/vscode-client/fixtures/mock-bin/wslpath
# Translates a "C:\..." style path into $MOCK_WSL_ROOT + the remainder,
# standing in for the real WSL mount of the Windows C: drive.
: "${MOCK_WSL_ROOT:?MOCK_WSL_ROOT must be set in env}"
if [[ "${1:-}" == "-u" ]]; then
    win_path="${2:-}"
    rel="${win_path#*:}"
    rel="${rel//\\//}"
    echo "${MOCK_WSL_ROOT}${rel}"
else
    echo "mock-wslpath: unsupported invocation: $*" >&2
    exit 1
fi
```

Mock `cygpath` (only invocation used: `cygpath -u <windows-path>`):

```bash
#!/usr/bin/env bash
# tests/vscode-client/fixtures/mock-bin/cygpath
: "${MOCK_CYGPATH_ROOT:?MOCK_CYGPATH_ROOT must be set in env}"
if [[ "${1:-}" == "-u" ]]; then
    win_path="${2:-}"
    rel="${win_path#*:}"
    rel="${rel//\\//}"
    echo "${MOCK_CYGPATH_ROOT}${rel}"
else
    echo "mock-cygpath: unsupported invocation: $*" >&2
    exit 1
fi
```

Runner (`tests/vscode-client/run.sh`):

```bash
#!/usr/bin/env bash
# tests/vscode-client/run.sh — fixture suite for v1.35 client-side VSCode
# coverage. Mocks cmd.exe/wslpath/cygpath since no real Windows machine
# exists in this build environment — see the spec's Design Philosophy.
#
# Auto-discovered by scripts/gate_fast.sh per the v0.4 (R3) auto-discovery
# contract.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
MOCK_BIN="${HERE}/fixtures/mock-bin"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

SYNC="${REPO}/scripts/sync-vscode-client.sh"
INSTALL="${REPO}/scripts/install.sh"

# Check 1: syntax
if bash -n "${SYNC}"; then
    record_pass "vscode-client: sync-vscode-client.sh bash syntax clean"
else
    record_fail "vscode-client: sync-vscode-client.sh bash syntax error"
fi

# Check 2: real environment on this (Linux) gate machine — resolve fails cleanly
out="$(env -u WSL_DISTRO_NAME -u APPDATA bash "${SYNC}" resolve 2>&1)"; rc=$?
if [[ ${rc} -eq 1 ]] && echo "${out}" | grep -q "could not detect a Windows VSCode client environment"; then
    record_pass "vscode-client: resolve fails cleanly on a non-Windows machine"
else
    record_fail "vscode-client: resolve did not fail cleanly — rc=${rc}, out=${out:0:200}"
fi

# Check 3: --dir short-circuits detection
out="$(bash "${SYNC}" resolve --dir /tmp/whatever 2>&1)"
if [[ "${out}" == "/tmp/whatever" ]]; then
    record_pass "vscode-client: --dir override short-circuits detection"
else
    record_fail "vscode-client: --dir override did not short-circuit — got '${out}'"
fi

# Check 4: WSL branch resolves via mocked cmd.exe + wslpath
WSL_ROOT="$(mktemp -d /tmp/vc-wsl.XXXXXX)"
out="$(WSL_DISTRO_NAME=test-distro MOCK_APPDATA_WIN='C:\Users\test\AppData\Roaming' \
        MOCK_WSL_ROOT="${WSL_ROOT}" PATH="${MOCK_BIN}:${PATH}" \
        bash "${SYNC}" resolve 2>&1)"
if [[ "${out}" == "${WSL_ROOT}/Users/test/AppData/Roaming/Code/User" ]]; then
    record_pass "vscode-client: WSL branch resolves via mocked cmd.exe/wslpath"
else
    record_fail "vscode-client: WSL branch resolution wrong — got '${out}'"
fi
rm -rf "${WSL_ROOT}"

# Check 5: Git-Bash/MSYS branch resolves via mocked cygpath
CYG_ROOT="$(mktemp -d /tmp/vc-cyg.XXXXXX)"
out="$(env -u WSL_DISTRO_NAME APPDATA='C:\Users\test\AppData\Roaming' \
        MOCK_CYGPATH_ROOT="${CYG_ROOT}" PATH="${MOCK_BIN}:${PATH}" \
        bash "${SYNC}" resolve 2>&1)"
if [[ "${out}" == "${CYG_ROOT}/Users/test/AppData/Roaming/Code/User" ]]; then
    record_pass "vscode-client: Git-Bash/MSYS branch resolves via mocked cygpath"
else
    record_fail "vscode-client: Git-Bash/MSYS branch resolution wrong — got '${out}'"
fi
rm -rf "${CYG_ROOT}"

# Check 6: Git-Bash/MSYS branch falls back to naive substitution when cygpath is absent
SANDBOX_BIN="$(mktemp -d /tmp/vc-sandbox.XXXXXX)"
for cmd in bash dirname pwd grep cat mkdir test rm sed tr; do
    if path="$(command -v "${cmd}" 2>/dev/null)"; then
        ln -s "${path}" "${SANDBOX_BIN}/${cmd}" 2>/dev/null || true
    fi
done
out="$(env -u WSL_DISTRO_NAME APPDATA='C:\Users\test\AppData\Roaming' \
        PATH="${SANDBOX_BIN}" bash "${SYNC}" resolve 2>&1)"
if [[ "${out}" == "C:/Users/test/AppData/Roaming/Code/User" ]]; then
    record_pass "vscode-client: Git-Bash/MSYS fallback (no cygpath) does naive substitution"
else
    record_fail "vscode-client: fallback wrong — got '${out}'"
fi
rm -rf "${SANDBOX_BIN}"

# --- capture/deploy/diff round trip via --dir (content logic, detection already covered above) ---

RT="$(mktemp -d /tmp/vc-rt.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${RT}'" EXIT

# Check 7: capture copies both files when both exist
LIVE1="${RT}/live1"; mkdir -p "${LIVE1}"
echo '{"a": 1}' > "${LIVE1}/settings.json"
echo '{"b": 2}' > "${LIVE1}/keybindings.json"
TRACKED_DIR1="${RT}/tracked1"; mkdir -p "${TRACKED_DIR1}"
out="$(bash "${SYNC}" capture --dir "${LIVE1}" 2>&1)"
if echo "${out}" | grep -q "captured 2/2" \
        && diff -q "${LIVE1}/settings.json" "${REPO}/extensions/vscode/client-settings.json" >/dev/null 2>&1 \
        && diff -q "${LIVE1}/keybindings.json" "${REPO}/extensions/vscode/client-keybindings.json" >/dev/null 2>&1; then
    record_pass "vscode-client: capture copies both files (2/2)"
else
    record_fail "vscode-client: capture did not copy both files — out=${out:0:200}"
fi

# Check 8: capture skips a missing file with a WARN, still captures the other
LIVE2="${RT}/live2"; mkdir -p "${LIVE2}"
echo '{"c": 3}' > "${LIVE2}/settings.json"
# no keybindings.json in LIVE2
out="$(bash "${SYNC}" capture --dir "${LIVE2}" 2>&1)"
if echo "${out}" | grep -q "captured 1/2" && echo "${out}" | grep -q "keybindings.json not found"; then
    record_pass "vscode-client: capture skips a missing file with a WARN (1/2)"
else
    record_fail "vscode-client: capture did not degrade gracefully — out=${out:0:200}"
fi

# Check 9: deploy copies tracked files onto a fresh --dir, creating it if absent
DEPLOY_DIR1="${RT}/deploy1/nested/User"   # deliberately absent, multiple levels
out="$(bash "${SYNC}" deploy --dir "${DEPLOY_DIR1}" 2>&1)"
if [[ -f "${DEPLOY_DIR1}/settings.json" ]] && echo "${out}" | grep -q "deployed"; then
    record_pass "vscode-client: deploy creates the target dir and copies tracked files"
else
    record_fail "vscode-client: deploy did not create/populate target — out=${out:0:200}"
fi

# Check 10: diff reports no drift immediately after a deploy
out="$(bash "${SYNC}" diff --dir "${DEPLOY_DIR1}" 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "no drift"; then
    record_pass "vscode-client: diff reports no drift right after deploy"
else
    record_fail "vscode-client: diff false drift — rc=${rc}, out=${out:0:200}"
fi

# Check 11: diff reports drift when live disagrees with tracked
echo '{"changed": true}' > "${DEPLOY_DIR1}/settings.json"
out="$(bash "${SYNC}" diff --dir "${DEPLOY_DIR1}" 2>&1)"; rc=$?
if [[ ${rc} -eq 1 ]] && echo "${out}" | grep -q "changed"; then
    record_pass "vscode-client: diff detects drift (exit 1) and shows the change"
else
    record_fail "vscode-client: diff missed drift — rc=${rc}, out=${out:0:200}"
fi

# Check 12: deploy refuses cleanly when no tracked file exists at all
EMPTY_REPO_SETTINGS="${REPO}/extensions/vscode/client-settings.json"
EMPTY_REPO_KEYBINDINGS="${REPO}/extensions/vscode/client-keybindings.json"
mv "${EMPTY_REPO_SETTINGS}" "${RT}/settings.bak" 2>/dev/null || true
mv "${EMPTY_REPO_KEYBINDINGS}" "${RT}/keybindings.bak" 2>/dev/null || true
out="$(bash "${SYNC}" deploy --dir "${RT}/deploy-empty" 2>&1)"; rc=$?
[[ -f "${RT}/settings.bak" ]] && mv "${RT}/settings.bak" "${EMPTY_REPO_SETTINGS}"
[[ -f "${RT}/keybindings.bak" ]] && mv "${RT}/keybindings.bak" "${EMPTY_REPO_KEYBINDINGS}"
if [[ ${rc} -eq 1 ]] && echo "${out}" | grep -q "no tracked client config"; then
    record_pass "vscode-client: deploy refuses cleanly with no tracked files"
else
    record_fail "vscode-client: deploy did not refuse cleanly — rc=${rc}, out=${out:0:200}"
fi

# --- install.sh vscode-client integration ---

# Check 13: real environment on this gate machine — graceful skip, exit 0
out="$(HOME="$(mktemp -d)" bash "${INSTALL}" vscode-client 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "not a Windows VSCode client environment"; then
    record_pass "vscode-client: install.sh skips gracefully on a non-Windows machine"
else
    record_fail "vscode-client: install.sh did not skip gracefully — rc=${rc}, out=${out:0:200}"
fi

# Check 14: mocked WSL env, but no tracked files — graceful skip naming the capture step
mv "${EMPTY_REPO_SETTINGS}" "${RT}/settings.bak2" 2>/dev/null || true
mv "${EMPTY_REPO_KEYBINDINGS}" "${RT}/keybindings.bak2" 2>/dev/null || true
WSL_ROOT2="$(mktemp -d /tmp/vc-wsl2.XXXXXX)"
out="$(HOME="$(mktemp -d)" WSL_DISTRO_NAME=test-distro MOCK_APPDATA_WIN='C:\Users\test\AppData\Roaming' \
        MOCK_WSL_ROOT="${WSL_ROOT2}" PATH="${MOCK_BIN}:${PATH}" \
        bash "${INSTALL}" vscode-client 2>&1)"; rc=$?
[[ -f "${RT}/settings.bak2" ]] && mv "${RT}/settings.bak2" "${EMPTY_REPO_SETTINGS}"
[[ -f "${RT}/keybindings.bak2" ]] && mv "${RT}/keybindings.bak2" "${EMPTY_REPO_KEYBINDINGS}"
rm -rf "${WSL_ROOT2}"
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "no tracked client config"; then
    record_pass "vscode-client: install.sh skips gracefully when Windows detected but nothing captured yet"
else
    record_fail "vscode-client: install.sh did not skip correctly — rc=${rc}, out=${out:0:200}"
fi

# Check 15: mocked WSL env + tracked files present — install.sh deploys end to end
WSL_ROOT3="$(mktemp -d /tmp/vc-wsl3.XXXXXX)"
out="$(HOME="$(mktemp -d)" WSL_DISTRO_NAME=test-distro MOCK_APPDATA_WIN='C:\Users\test\AppData\Roaming' \
        MOCK_WSL_ROOT="${WSL_ROOT3}" PATH="${MOCK_BIN}:${PATH}" \
        bash "${INSTALL}" vscode-client 2>&1)"; rc=$?
target="${WSL_ROOT3}/Users/test/AppData/Roaming/Code/User"
if [[ ${rc} -eq 0 ]] && [[ -f "${target}/settings.json" || -f "${target}/keybindings.json" ]]; then
    record_pass "vscode-client: install.sh deploys end to end via its own duplicated detection"
else
    record_fail "vscode-client: install.sh did not deploy — rc=${rc}, out=${out:0:200}, target=${target}"
fi
rm -rf "${WSL_ROOT3}"
```

**Note on Checks 12/14/15:** the real tracked files (`extensions/vscode/client-settings.json`/`client-keybindings.json`, if present from an earlier real `capture` on this machine — they won't be present right after `/code` implements this spec, per the Design Philosophy) are moved aside and restored around these checks so the suite never depends on, or corrupts, whatever state happens to be tracked. This mirrors the general fixture-isolation posture of `tests/vscode/run.sh`'s round-trip checks (temp dirs, trap cleanup) applied to files instead of a single JSON list.

**Acceptance Test:**

```bash
bash tests/vscode-client/run.sh
# expect: 15 PASS, 0 FAIL

bash scripts/gate_fast.sh
# expect: total PASS count grew by 15 (auto-discovered, no orchestrator edit)
```

---

## Phase 3: Wire-up

### Change 5: root `README.md` — correct the stale "deferred to v0.6b" claim

**Problem:** `README.md`'s Repo Structure table (line 24) still says client-side VSCode coverage is "deferred to v0.6b" and its `install.sh` category list (line 40) doesn't mention `vscode-client`. Both are now false. Per Honesty About What Ships, a stale "not yet built" claim left in place after the feature ships is as wrong as an overstated one.

**File:** `README.md` (existing — two edits)

**Implementation:**

Edit 1 — Repo Structure table, `extensions/` row (`README.md:24`):

```markdown
| `extensions/` | IDE config. `vscode/server-extensions.json` is the tracked server-side extension list (`scripts/install.sh vscode` / `scripts/sync-vscode.sh`); `vscode/client-settings.json` + `client-keybindings.json` are the Windows client's tracked config (`scripts/install.sh vscode-client` / `scripts/sync-vscode-client.sh`, v1.35). |
```

Edit 2 — install.sh category list (`README.md:40`):

```markdown
`./scripts/install.sh` accepts: `commands`, `skills`, `settings`, `hooks`, `vscode`, `vscode-client` (v1.35 — Windows client `settings.json`/`keybindings.json`), `managed` (v1.11 — machine-wide auth pin, needs sudo), `git-hooks` (v1.2 — opt-in pre-commit hook), `worktree` (v1.4 — concurrent-dev isolation tooling), `shell` (v1.18 — sourced shell functions, `cc`), or `all` (default).
```

The long historical "Roadmap" paragraph (`README.md:60`) is left to `/code`'s standard final-step doc update (per `dev/CLAUDE.md`'s "Docs Ship With The Code" rule) — this Change only hand-specifies the two edits a generic doc pass would likely miss (a stale negative claim, an omitted category in an enumerated list), matching v0.6's Change 6 precedent.

**Acceptance Test:**

```bash
grep -q "client-settings.json" README.md
grep -q "vscode-client" README.md
! grep -q "deferred to v0.6b" README.md
```

---

## Post-Merge (Manual — Not a Coded Change)

**These steps happen on the real Windows client machine, run by the user, not by `/code` or this session** — the whole reason this section exists separately, per the Design Philosophy's central asymmetry:

1. Pull `main` on the Windows machine (dev-platform is already cloned there per the user's confirmation).
2. Run `./scripts/sync-vscode-client.sh resolve`. **If this fails or prints a wrong path, the detection logic in `scripts/sync-vscode-client.sh` needs a follow-on fix** — file it the normal way (a bug against this repo), don't hand-patch around it.
3. Run `./scripts/sync-vscode-client.sh capture` to populate `extensions/vscode/client-settings.json` and `client-keybindings.json` with the real config.
4. Review the diff (`git diff extensions/vscode/`) before committing — confirm nothing machine-specific-and-unwanted (an absolute path only valid on that one machine, a secret pasted into a setting) is being captured.
5. Commit and push that capture as its own small commit (`chore: capture Windows client VSCode settings`) — this is real state only that machine can produce, not something this spec's `/code` session commits.
6. Optionally run `./scripts/sync-vscode-client.sh diff` afterward to confirm it reports no drift, and `./scripts/install.sh vscode-client` (or `all`) to confirm the deploy path round-trips cleanly.

## What NOT to Do

- **Do not parse `client-settings.json`/`client-keybindings.json` with `jq` or any JSON parser.** They're JSONC, hand-edited, and dev-platform doesn't own their shape. Treat as opaque text (`cp`/`diff -u`) — see Design Philosophy.
- **Do not build merge semantics for client config**, mirroring `settings.json`'s v1.6 model. That model exists because Claude Code writes runtime grants into its `settings.json` continuously; nothing writes into VSCode's `settings.json`/`keybindings.json` outside the user's own edits, and this is a single dedicated Windows machine, not a fleet. A straight capture/deploy copy is correct and simpler.
- **Do not attempt Mac or Linux client support.** The user confirmed the client machine is Windows only. Building per-OS branches for OSes with no confirmed target is speculative scope creep — see "Out of Scope."
- **Do not have `/code` (or this session) attempt to populate `client-settings.json`/`client-keybindings.json` with real content, or claim it did.** There is no Windows machine here. The first real `capture` is a manual Post-Merge step. Writing placeholder or invented content into these files would be worse than leaving them absent — a fabricated "capture" that looks real.
- **Do not make `install_vscode_client()` source a shared helper or shell out to `sync-vscode-client.sh`.** Deliberate inline duplication, matching `install_vscode()`'s own precedent — see Design Philosophy.
- **Do not treat the WSL/Git-Bash detection logic as verified.** It is unit-tested against mocks only. State it as unverified in any doc or commit message that mentions it, per the spec-writing rule on external-state claims.
- **Do not symlink `client-settings.json`/`client-keybindings.json` anywhere in this repo.** Same reasoning as `server-extensions.json` (v0.6): they're read in-place by `install.sh`/`sync-vscode-client.sh` to drive `cp`, never read directly by any tool at startup.

## Out of Scope (Future Specs)

- **Mac (`~/Library/Application Support/Code/User/`) or Linux (`~/.config/Code/User/`) client support** — no confirmed target machine on either OS; add a detection branch to `resolve_vscode_user_dir()` in a future spec if one appears.
- **Snippets (`User/snippets/`)** — explicitly excluded from this spec's scope per the user's confirmed answer (settings + keybindings only).
- **Client-side extension list** — the user confirmed this is out of scope; server-side extensions (v0.6) remain the only tracked extension list.
- **Theme-only tracking as a separate concern** — `workbench.colorTheme` and `colorCustomizations` already live inside `settings.json` and are captured as part of it; no separate mechanism is needed or being built.
- **Automatic capture on every commit / a git hook watching for drift** — useful but premature, same reasoning v0.6 gave for the equivalent server-side idea.
- **VSCode profile management (multiple distinct profile sets)** — single global client config only.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `extensions/vscode/README.md` | Modify | Extend contract: client-side files, Windows-only scope note, new sync-helper section |
| `scripts/sync-vscode-client.sh` | New | `resolve`/`capture`/`deploy`/`diff` sync helper, `--dir` override |
| `scripts/install.sh` | Modify | Add `install_vscode_client()` + `vscode-client` case + usage lines |
| `tests/vscode-client/run.sh` | New | 15-assertion fixture suite (auto-discovered by `gate_fast.sh`) |
| `tests/vscode-client/fixtures/mock-bin/cmd.exe` | New | Mocks the WSL→Windows bridge |
| `tests/vscode-client/fixtures/mock-bin/wslpath` | New | Mocks WSL path translation |
| `tests/vscode-client/fixtures/mock-bin/cygpath` | New | Mocks Git-Bash/MSYS path translation |
| `README.md` | Modify | Correct stale "deferred to v0.6b" claim, add `vscode-client` category |
| `extensions/vscode/client-settings.json` | **Not created by this spec** | Populated by the user running `sync-vscode-client.sh capture` on the Windows client — see Post-Merge |
| `extensions/vscode/client-keybindings.json` | **Not created by this spec** | Same as above |
| `tasks/client-side-vscode-coverage-spec.md` | (this file) | Spec |

## Implementation Order

1. **Phase 1 (Change 1)** — `extensions/vscode/README.md` contract update. No dependencies.
2. **Phase 1 (Change 2)** — `scripts/sync-vscode-client.sh`. Needed before Change 4's tests can run against it.
3. **Phase 2 (Change 3)** — `scripts/install.sh` extension. Independent of Change 2 (deliberately duplicated, not shared), but do after Change 2 so the two implementations can be eyeballed side by side for the review pass.
4. **Phase 2 (Change 4)** — `tests/vscode-client/` suite. Depends on Changes 2 and 3 both existing.
5. **Phase 3 (Change 5)** — `README.md` wire-up. Do last, once the real category name and script name are final.

All 5 Changes fit comfortably in one `/code` session (single Phase-1-sized spec, well under 200 lines of net diff excluding the verbatim script bodies). Single feature branch/worktree → single PR, matching the Per-Spec-Phase branching default for a small, non-independently-shippable spec (the test suite in Change 4 is meaningless without Changes 2 and 3).

## Verification Checklist

- [ ] All 5 Changes implemented per the spec
- [ ] `bash -n` passes on `scripts/sync-vscode-client.sh` and the modified `scripts/install.sh`
- [ ] `./scripts/sync-vscode-client.sh resolve` on this (Linux) gate machine fails cleanly with the documented message
- [ ] `./scripts/sync-vscode-client.sh resolve --dir <path>` short-circuits detection
- [ ] WSL branch resolves correctly against mocked `cmd.exe`/`wslpath`
- [ ] Git-Bash/MSYS branch resolves correctly against mocked `cygpath`, and falls back to naive substitution when `cygpath` is absent
- [ ] `capture`/`deploy`/`diff` round-trip correctly against a fake `--dir`, including the missing-file WARN path
- [ ] `./scripts/install.sh vscode-client` skips gracefully on this gate machine, and deploys end to end against a mocked WSL environment
- [ ] `tests/vscode-client/run.sh` records 15 PASS, 0 FAIL, auto-discovered by `gate_fast.sh`
- [ ] Gate grows from 470 → 485 PASS
- [ ] `extensions/vscode/README.md` and root `README.md` no longer claim client-side coverage is deferred
- [ ] `extensions/vscode/client-settings.json` / `client-keybindings.json` do NOT exist after `/code` — confirmed absent, not fabricated (Post-Merge populates them)
- [ ] Consumer Audit gitignore probe re-run and passes (`touch` + `git status --porcelain` on both new paths)
- [ ] Spec taxonomy check (`scripts/check_spec_taxonomy.sh`) passes
- [ ] No file under `projects/` modified
- [ ] Spec deviations (if any) explicitly flagged at `/code` time
