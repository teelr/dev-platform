# v1.1: Remote Enforcement

## Coding Specification for Implementation

## Design Philosophy

The multi-account problem (`teelr` vs `teelr129` / Osigin-LLC) was fixed manually in Part 1: seven HTTPS remotes converted to SSH, per-repo identity added to `gosqrlgo-dispatch`, spurious keystone override removed. But one-time fixes drift — without a verification step, the same configuration can silently re-enter on a fresh clone, a new machine, or an accidental `git config` command.

Part 2 makes the correct state machine-readable and verifiable. `monitoring/remotes.json` encodes the expected origin URL and identity policy for every owned project. `scripts/verify-remotes.sh` reads that registry and diffs actual vs. expected — exiting 1 on any mismatch. The script is wired into `scripts/verify.sh` so it surfaces in the live deploy check during `gate_fast.sh` and on explicit `./scripts/verify.sh` runs. Going forward, adding a new project means adding one JSON entry; drift becomes visible on the next gate run.

Two projects were discovered post-Part-1 with HTTPS remotes: `keystone_prototype` and `neurx-dashboard`. A pre-flight step (not a numbered Change — no commit) converts them to SSH before the registry is written. All 14 owned projects are then encoded with SSH-only as the expected state, making HTTPS a verifiable anomaly going forward.

**Registry design decision:** `monitoring/remotes.json` is a new file separate from `monitoring/projects.json`. The two files serve different concerns: `projects.json` tracks fleet-gate-capable projects (those with a runnable `gate_cmd`); `remotes.json` tracks the origin URL and identity policy for every owned project. SQRL and `gosqrlgo-dispatch` belong in `remotes.json` (they have remotes to verify) but not in `projects.json` (they have no dev-platform gate integration). The split keeps each file's scope clean.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `monitoring/remotes.json` | JSON | Machine-readable config; consistent with `monitoring/projects.json` pattern already in use |
| `scripts/verify-remotes.sh` | Bash + Python3 inline | Bash for process flow and git CLI invocations; Python3 inline for JSON parsing — same pattern as `scripts/gate_fast.sh` and `scripts/fleet-gate.sh` |
| `tests/remote-verify/run.sh` | Bash | All test runners are Bash per the v0.4 auto-discovery contract; uses `tests/helpers/assert.sh` |

## Overview

**Pre-flight (terminal commands, no commit):**
- Convert `keystone_prototype` and `neurx-dashboard` HTTPS origins to SSH

1. Change 1 — Create `monitoring/remotes.json`: encode expected remote + identity for all 14 owned projects
2. Change 2 — Create `scripts/verify-remotes.sh`: read registry, diff actual vs. expected, exit 1 on any drift
3. Change 3 — Modify `scripts/verify.sh`: wire in `verify-remotes.sh` as a verification section
4. Change 4 — Create `tests/remote-verify/run.sh`: 10-assertion fixture suite

---

## Pre-flight (before any Change)

Run these two commands before starting Change 1. They convert the remaining HTTPS origins to SSH so the registry encodes the correct state from the start. These are local `.git/config` changes — no commit.

```bash
git -C ~/dev/projects/keystone_prototype remote set-url origin git@github.com:teelr/keystone_prototype.git
git -C ~/dev/projects/neurx-dashboard     remote set-url origin git@github.com:teelr/neurx-dashboard.git
```

Verify:

```bash
git -C ~/dev/projects/keystone_prototype remote get-url origin
# expect: git@github.com:teelr/keystone_prototype.git
git -C ~/dev/projects/neurx-dashboard remote get-url origin
# expect: git@github.com:teelr/neurx-dashboard.git
```

---

## Phase 1: Registry + Verification Script

### Change 1: Create `monitoring/remotes.json`

**Problem:** There is no machine-readable record of what each project's origin URL and identity policy should be. Drift cannot be detected automatically.

**File:** `monitoring/remotes.json` (new file)

**Implementation:**

Create the file with one entry per owned project. Schema per entry:

- `name` — project name (matches directory basename)
- `path` — path relative to `~/dev` (`.` for dev-platform itself)
- `remote_url` — exact expected SSH URL for `origin`
- `github_account` — `teelr` or `teelr129`
- `local_email` — `null` means no per-repo `user.email` override expected (inherits global); a string means that exact value must be set per-repo via `git config --local user.email`

Excluded from registry:
- `atlas` — no git remote (not a tracked repo)
- `mcp-servers-archived`, `mcp-servers-official` — third-party forks, not owned
- `olsson-ma-automation` — no git repository

```json
[
  {
    "name": "dev-platform",
    "path": ".",
    "remote_url": "git@github.com:teelr/dev-platform.git",
    "github_account": "teelr",
    "local_email": null
  },
  {
    "name": "kermit",
    "path": "projects/kermit",
    "remote_url": "git@github.com:teelr/kermit-harness.git",
    "github_account": "teelr",
    "local_email": null
  },
  {
    "name": "kermit-pa",
    "path": "projects/kermit-pa",
    "remote_url": "git@github.com:teelr/kermit-pa.git",
    "github_account": "teelr",
    "local_email": null
  },
  {
    "name": "keystone",
    "path": "projects/keystone",
    "remote_url": "git@github.com:teelr/keystone.git",
    "github_account": "teelr",
    "local_email": null
  },
  {
    "name": "OPIE",
    "path": "projects/OPIE",
    "remote_url": "git@github.com:teelr/OPIE.git",
    "github_account": "teelr",
    "local_email": null
  },
  {
    "name": "RICH_NVR",
    "path": "projects/RICH_NVR",
    "remote_url": "git@github.com:teelr/nvr-dashboard.git",
    "github_account": "teelr",
    "local_email": null
  },
  {
    "name": "richteel-portal",
    "path": "projects/richteel-portal",
    "remote_url": "git@github.com:teelr/richteel-portal.git",
    "github_account": "teelr",
    "local_email": null
  },
  {
    "name": "SQRL",
    "path": "projects/SQRL",
    "remote_url": "git@github-teelr129:Osigin-LLC/SQRL.git",
    "github_account": "teelr129",
    "local_email": "teelr129@users.noreply.github.com"
  },
  {
    "name": "gosqrlgo-dispatch",
    "path": "projects/gosqrlgo-dispatch",
    "remote_url": "git@github-teelr129:Osigin-LLC/gosqrlgo-dispatch.git",
    "github_account": "teelr129",
    "local_email": "teelr129@users.noreply.github.com"
  },
  {
    "name": "aRKa",
    "path": "projects/aRKa",
    "remote_url": "git@github.com:teelr/aRKa.git",
    "github_account": "teelr",
    "local_email": null
  },
  {
    "name": "aws_controller",
    "path": "projects/aws_controller",
    "remote_url": "git@github.com:teelr/aws_controller.git",
    "github_account": "teelr",
    "local_email": null
  },
  {
    "name": "meeting_analyzer",
    "path": "projects/meeting_analyzer",
    "remote_url": "git@github.com:teelr/meeting_analyzer.git",
    "github_account": "teelr",
    "local_email": null
  },
  {
    "name": "keystone_prototype",
    "path": "projects/keystone_prototype",
    "remote_url": "git@github.com:teelr/keystone_prototype.git",
    "github_account": "teelr",
    "local_email": null
  },
  {
    "name": "neurx-dashboard",
    "path": "projects/neurx-dashboard",
    "remote_url": "git@github.com:teelr/neurx-dashboard.git",
    "github_account": "teelr",
    "local_email": null
  }
]
```

**Consumer Audit:** `monitoring/remotes.json` is a new `.json` file under `monitoring/`. Verify it is not gitignored before committing:

```bash
git check-ignore -v monitoring/remotes.json
# expect: no output (not ignored)
```

The `monitoring/**/*.json` pattern was added to `.gitignore` allow-list in v0.5 Phase 1. Confirm it covers this file. If `git check-ignore` shows it IS ignored, add `!monitoring/remotes.json` to `.gitignore`.

**Acceptance Test:**

```bash
python3 -c "import json; data=json.load(open('monitoring/remotes.json')); print(len(data), 'entries')"
# expect: 14 entries
python3 -c "import json; data=json.load(open('monitoring/remotes.json')); print([p['name'] for p in data if p['github_account']=='teelr129'])"
# expect: ['SQRL', 'gosqrlgo-dispatch']
python3 -c "import json; data=json.load(open('monitoring/remotes.json')); assert all('git@' in p['remote_url'] for p in data), 'HTTPS found'"
echo "PASS — all SSH"
```

---

### Change 2: Create `scripts/verify-remotes.sh`

**Problem:** With the registry in place, there is no script to check actual vs. expected state. Drift is invisible.

**File:** `scripts/verify-remotes.sh` (new file)

**Implementation:**

The script follows the same exit-code-and-output contract as `scripts/verify.sh`:
- Prints one line per project: `OK`, `SKIP`, or `X FAIL` + reason
- Accumulates errors; exits 1 if any errors; exits 0 if all OK/SKIP

Support flags:
- `--project <name>` — check only the named project (for targeted checks)
- `--registry <path>` — override the registry path (used by tests)
- `--help` — print usage and exit 0

The script resolves each entry's `path` relative to `$REPO` (the dev-platform repo root, i.e., `~/dev`). If the path does not exist or is not a git repo, it records `SKIP` — not FAIL. This handles machines where only a subset of projects are cloned.

Checks performed per project (in order):
1. **Origin URL** — `git -C <abs_path> remote get-url origin 2>/dev/null` must equal `remote_url`
2. **Local email** — if `local_email` is non-null: `git -C <abs_path> config --local user.email 2>/dev/null` must equal `local_email`. If `local_email` is null: `git -C <abs_path> config --local user.email 2>/dev/null` must return empty (no per-repo override).

Pattern — follow the structure of `scripts/fleet-gate.sh` for the registry parsing (Python3 inline) and `scripts/verify.sh` for the per-check output format:

```bash
#!/usr/bin/env bash
# scripts/verify-remotes.sh — verify each owned project's git origin and
# per-repo identity against monitoring/remotes.json.
#
# Exit code:
#   0 — all reachable projects match expected config
#   1 — at least one mismatch detected
#
# Usage: ./scripts/verify-remotes.sh [--project <name>] [--registry <path>]

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REPO}/monitoring/remotes.json"
FILTER=""
ERRORS=0

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            echo "Usage: verify-remotes.sh [--project <name>] [--registry <path>]"
            echo "Verifies git origin and identity for every owned project in monitoring/remotes.json."
            exit 0
            ;;
        --project) FILTER="$2"; shift 2 ;;
        --registry) REGISTRY="$2"; shift 2 ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

# Parse registry and iterate. Python3 inline emits TSV: name\tpath\tremote_url\tlocal_email_or_NONE
while IFS=$'\t' read -r name rel_path remote_url local_email; do
    # Filter to single project if requested
    [[ -n "${FILTER}" && "${name}" != "${FILTER}" ]] && continue

    # Resolve absolute path
    if [[ "${rel_path}" == "." ]]; then
        abs_path="${REPO}"
    else
        abs_path="${REPO}/${rel_path}"
    fi

    # SKIP if path does not exist
    if [[ ! -d "${abs_path}" ]]; then
        echo "  SKIP  ${name}: path not found (${abs_path})"
        continue
    fi

    # SKIP if not a git repo
    if ! git -C "${abs_path}" rev-parse --git-dir >/dev/null 2>&1; then
        echo "  SKIP  ${name}: not a git repository"
        continue
    fi

    ok=1

    # Check 1: origin URL
    actual_url="$(git -C "${abs_path}" remote get-url origin 2>/dev/null || echo "")"
    if [[ "${actual_url}" != "${remote_url}" ]]; then
        echo "  X     ${name}: origin mismatch"
        echo "          expected: ${remote_url}"
        echo "          got:      ${actual_url}"
        ERRORS=$((ERRORS + 1))
        ok=0
    fi

    # Check 2: per-repo identity
    actual_email="$(git -C "${abs_path}" config --local user.email 2>/dev/null || echo "")"
    if [[ "${local_email}" == "NONE" ]]; then
        # Expect no per-repo override
        if [[ -n "${actual_email}" ]]; then
            echo "  X     ${name}: unexpected per-repo user.email (${actual_email}); should inherit global"
            ERRORS=$((ERRORS + 1))
            ok=0
        fi
    else
        # Expect a specific per-repo override
        if [[ "${actual_email}" != "${local_email}" ]]; then
            echo "  X     ${name}: user.email mismatch"
            echo "          expected: ${local_email}"
            echo "          got:      ${actual_email:-'(not set)'}"
            ERRORS=$((ERRORS + 1))
            ok=0
        fi
    fi

    [[ ${ok} -eq 1 ]] && echo "  OK    ${name}"

done < <(python3 - "${REGISTRY}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for p in data:
    local_email = p.get("local_email") or "NONE"
    print(p["name"], p["path"], p["remote_url"], local_email, sep="\t")
PY
)

echo ""
if [[ ${ERRORS} -gt 0 ]]; then
    echo "Remote verification FAILED: ${ERRORS} issue(s)."
    exit 1
fi
echo "All remotes verified."
```

Make the script executable: `chmod +x scripts/verify-remotes.sh`

**Acceptance Test:**

```bash
# Must pass against current live state (all projects were fixed in Part 1)
./scripts/verify-remotes.sh
# expect: all OK or SKIP lines, "All remotes verified.", exit 0

# Single-project flag
./scripts/verify-remotes.sh --project SQRL
# expect: "  OK    SQRL"

# --help
./scripts/verify-remotes.sh --help
# expect: usage text, exit 0

# Syntax check
bash -n scripts/verify-remotes.sh
```

---

### Change 3: Wire `verify-remotes.sh` into `scripts/verify.sh`

**Problem:** `verify-remotes.sh` exists but isn't called from anywhere automatically. `./scripts/verify.sh` is the canonical deploy-integrity check (called by `gate_fast.sh` as the `live ~/.claude/ verify` lift check). Remote verification should surface there.

**File:** `scripts/verify.sh` (existing, line ~80)

**Implementation:**

Add a "Verifying remotes..." section after the existing hooks verification block and before the final summary. Follow the existing pattern: run the subscript, capture its output, indent it, count errors.

At line ~80 (after the hooks `*.py` loop, before the blank line before the summary), insert:

```bash
echo "Verifying remotes..."
_remote_out="$(bash "${REPO}/scripts/verify-remotes.sh" 2>&1)"
_remote_exit=$?
echo "${_remote_out}" | sed 's/^/  /'
if [[ ${_remote_exit} -ne 0 ]]; then
    ERRORS=$((ERRORS + 1))
fi
```

The output from `verify-remotes.sh` is already formatted with `OK`/`SKIP`/`X` prefixes; the `sed` indents it one level to match the section style of `verify.sh`.

**Acceptance Test:**

```bash
./scripts/verify.sh
# expect: "Verifying remotes..." section appears, all OK/SKIP, no drift
# expect: exits 0

# Gate integration — remotes check appears within gate run
./scripts/gate_fast.sh 2>&1 | grep -A2 "live ~/.claude/ verify"
# The gate_fast.sh live verify lift check calls verify.sh, which now calls verify-remotes.sh
```

---

## Phase 2: Tests

### Change 4: Create `tests/remote-verify/run.sh`

**Problem:** Without a fixture suite, regressions in `verify-remotes.sh` (broken TSV parsing, wrong error detection, flag handling) are invisible until someone hits a live failure.

**File:** `tests/remote-verify/run.sh` (new file)

**Implementation:**

10 assertions. Follows the exact pattern of `tests/migration/run.sh`: `mktemp` temp dir, mock git repos initialized inline, mock registry written with absolute paths, `assert.sh` helpers for PASS/FAIL, `trap` cleanup.

Auto-discovered by `gate_fast.sh` per the v0.4 contract (runner at `tests/<suite>/run.sh`, not under `fixtures/`).

Mock repo setup helpers needed:
- `make_repo <dir> <remote_url>` — `git init`, `git remote add origin <url>`
- `make_repo_with_email <dir> <remote_url> <email>` — same + `git config user.email`

Assertions:

| # | Description | Setup | Expected |
|---|-------------|-------|----------|
| 1 | `bash -n` syntax clean | — | exit 0 |
| 2 | `--help` renders | — | output contains "verify-remotes" |
| 3 | All correct → exits 0 | registry: 2 teelr + 1 teelr129 repos, all matching | exit 0, no `FAIL` lines |
| 4 | Wrong origin URL → exits 1 | one repo has wrong SSH URL | exit 1, output contains project name + "origin mismatch" |
| 5 | Unexpected per-repo email → exits 1 | `local_email: null` entry but repo has `user.email` set | exit 1, output contains "unexpected per-repo user.email" |
| 6 | Missing required per-repo email → exits 1 | `local_email: "teelr129@..."` entry but repo has no `user.email` | exit 1, output contains "user.email mismatch" |
| 7 | Wrong per-repo email value → exits 1 | `local_email: "teelr129@..."` but repo has `wrong@example.com` | exit 1, output contains "user.email mismatch" |
| 8 | Path does not exist → SKIP, exits 0 | registry entry with non-existent path | exit 0, output contains "SKIP" |
| 9 | Path exists but not a git repo → SKIP, exits 0 | `mkdir` only, no `git init` | exit 0, output contains "SKIP" |
| 10 | `--project <name>` checks only that project | registry: 2 entries, one wrong; filter to the correct one | exit 0 |

Key implementation notes (from lessons.md):
- Use `mktemp` paths, not hardcoded paths — the registry is written inline with `${TMP}` absolute paths (same as `tests/migration/run.sh` line 85).
- Mock repos under `${TMP}/mock-repos/` — NOT under `tests/remote-verify/fixtures/` to avoid the gate orchestrator auto-discovering `.sh` files in fixtures (v0.8 Phase 1 lesson).
- Both assertions for negative tests: exit code AND specific output substring (lessons.md: "Exit-code-only is 'did something break'; substring assertion is 'did THIS break'").

Make the runner executable: `chmod +x tests/remote-verify/run.sh`

**Consumer Audit for `tests/remote-verify/run.sh`:**
1. `git check-ignore -v tests/remote-verify/run.sh` — expect not ignored (`!tests/**/*.sh` added in v0.5)
2. `scripts/gate_fast.sh` auto-discovers `tests/*/run.sh` — no orchestrator edit needed ✓
3. `scripts/verify.sh` does not scan `tests/` — no verify.sh edit needed ✓

**Acceptance Test:**

```bash
# Run standalone
bash tests/remote-verify/run.sh
# expect: 10 PASS, 0 FAIL

# Run via gate (auto-discovered)
./scripts/gate_fast.sh
# expect: gate count increases by 10, still PASS
```

---

## What NOT to Do

- **Do not add SQRL or gosqrlgo-dispatch to `monitoring/projects.json`.** That file is for fleet-gate-capable projects with a runnable `gate_cmd`. These two have no dev-platform gate integration. `remotes.json` is the right file for them.
- **Do not add `remote_url` or `github_account` fields to `monitoring/projects.json`.** The two files have different scopes — keep them clean.
- **Do not FAIL on missing path.** A machine that only has a subset of projects cloned is valid. Missing paths → SKIP.
- **Do not use `git config user.email` (global lookup) to check per-repo identity.** Use `git config --local user.email` — it reads only `.git/config`, not the global or system level. The distinction is the whole point.
- **Do not hardcode `~/dev` or `/home/rich/dev` inside the script.** Use `$REPO` derived from `BASH_SOURCE[0]` — the same pattern used by every other script in `scripts/`.
- **Do not put mock git repos under `tests/remote-verify/fixtures/` if they contain `.sh` files.** The gate orchestrator's find excludes `*/fixtures/*` for exactly this reason (v0.8 Phase 1 lesson). Use a `mktemp` dir outside the repo tree.
- **Do not assert the global `user.email` in the verify script.** The script only checks per-repo overrides. Global identity is outside the scope of this tool.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `monitoring/remotes.json` | New | 14-entry registry of expected origin URLs and identity policies |
| `scripts/verify-remotes.sh` | New | Reads registry, diffs actual vs. expected, exits 1 on drift |
| `scripts/verify.sh` | Modify | Add "Verifying remotes..." section calling verify-remotes.sh (~6 lines after line 80) |
| `tests/remote-verify/run.sh` | New | 10-assertion fixture suite; auto-discovered by gate_fast.sh |

## Implementation Order

1. Pre-flight: convert `keystone_prototype` + `neurx-dashboard` to SSH (terminal, no commit)
2. Change 1: `monitoring/remotes.json` — run Consumer Audit `git check-ignore` immediately after writing
3. Change 2: `scripts/verify-remotes.sh` — run `./scripts/verify-remotes.sh` live before proceeding
4. Change 3: `scripts/verify.sh` wiring — verify `./scripts/verify.sh` shows the remotes section
5. Change 4: `tests/remote-verify/run.sh` — run standalone, then run full gate to confirm count increase

Changes 1→2→3 are strictly sequential (script needs the registry; verify.sh needs the script). Change 4 can be written after Change 2 but should be run last.

## Verification Checklist

- [ ] Pre-flight: `keystone_prototype` and `neurx-dashboard` report SSH origin
- [ ] `monitoring/remotes.json`: 14 entries; `git check-ignore` returns no output (not gitignored); all `remote_url` values start with `git@`
- [ ] `./scripts/verify-remotes.sh` exits 0 against live projects (all OK or SKIP)
- [ ] `./scripts/verify-remotes.sh --project SQRL` exits 0 and shows OK
- [ ] `./scripts/verify.sh` shows "Verifying remotes..." section and exits 0
- [ ] `./scripts/gate_fast.sh` passes with gate count increased by 10
- [ ] `bash tests/remote-verify/run.sh` → 10 PASS, 0 FAIL
- [ ] Language architecture matrix followed for all new components ✓
- [ ] No hardcoded `/home/rich` paths in any new script
