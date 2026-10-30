# Pre-Commit Secret Blocker

## Coding Specification for Implementation

Roadmap Phase: `v1.41: Pre-Commit Secret Blocker` (milestone claimed by `/plan`).
Branch: `worktree-v1.41+phase-1-pre-commit-secret-blocker`. One branch, one PR. The hook,
its tests and the `--no-verify` deny rules are one protection and cannot ship separately.

## Design Philosophy

A scan of the local projects on 2026-10-30 found real-looking credentials committed to
private repos: an OpenAI key in `kermit-harness` (`_archive/root/.env.dev`) and a Google
Maps key in `SQRL` (`rps_bid/.env.backup`), plus several tracked `.env` files. Nothing
stopped them being committed. Secret scanning is off on the private repos, so the earliest
place to stop it is before the commit exists. This phase adds a secret check to the shared
`pre-commit` hook in `shell/git-hooks/`. It looks only at what a commit adds, prints the
file and the kind of pattern, and never prints the matched text.

Four constraints shaped the design, each verified on this machine (see "Verified state").
First, the existing hook does nothing unless a repo has `scripts/gate_fast.sh`, and only 9
of 18 local projects have one, so the secret check must run on its own. Second, opting in
via `core.hooksPath` would replace the whole hooks directory, silently disabling the
`pre-push` hooks that `kermit` and `kermit-pa` have in their own `.git/hooks`; the
documented enable step is therefore a symlink at `.git/hooks/pre-commit`, which touches
only that one hook. Third, the existing hook also runs the gate on every commit for repos
that have one, which would surprise a repo that opts in only for the secret check, so the
gate part gets an off switch that defaults to today's behaviour. Fourth, the hook is
useless if a session can skip it with `--no-verify`, and the v1.39 deny rule only covers one
spelling of that flag.

Honest limits, stated in the README by this spec: it catches provider-shaped tokens and
tracked `.env` and key files, not arbitrary passwords or custom key formats; it does not
scan history; it only protects a repo where the hook is enabled; and `git commit
--no-verify` bypasses it for anyone running git directly.

## Verified state

| Claim | Verified by |
| ----- | ----------- |
| The hook is deployed: `~/.claude/git-hooks/pre-commit` is a symlink to `/home/rich/dev/shell/git-hooks/pre-commit` | `ls -la ~/.claude/git-hooks` |
| No local project sets `core.hooksPath` to `~/.claude/git-hooks`; `kermit`, `keystone` and `SQRL` set it to their own `.git/hooks`; the global value is empty | `bash` script run over `/home/rich/dev/projects/*/` reading `git config --get core.hooksPath` |
| 9 of 18 local projects have an executable `scripts/gate_fast.sh` (`kanban`, `kermit-v3`, `keystone`, `keystone_prototype`, `neurx-dashboard`, `OPIE`, `RICH_NVR`, `richteel-portal`, `SQRL`); the other 9 (including `kermit` and `kermit-pa`) do not | same script (the `gate_fast.sh=yes` column); recount at `/code` time |
| `kermit` and `kermit-pa` each have a `pre-push` hook in `.git/hooks` | `ls .git/hooks \| grep -v '\.sample$'` in each |
| The existing hook's bypass variable is `SKIP_GATE_FAST=1`, and it is a no-op without `scripts/gate_fast.sh` | `cat shell/git-hooks/pre-commit` |
| The existing suite is `tests/git-hooks/run.sh` with 5 tests and fixtures `passing-gate.sh` / `failing-gate.sh` | `sed -n 1,140p tests/git-hooks/run.sh`; `ls tests/git-hooks` |
| `install.sh git-hooks` symlinks every file in `shell/git-hooks/` except `README.md`; `verify.sh` checks each | `grep -n git-hooks scripts/install.sh scripts/verify.sh` (install.sh:377-390, verify.sh:188-193) |
| The only `--no-verify` deny rule is `Bash(git commit --no-verify*)` (`settings/settings.json:134`); there is no `-n` rule | `grep -n "no-verify\|commit -n" settings/settings.json settings/permissions-retract.json tests/settings-baseline/run.sh` |
| A key-shaped OpenAI value of length 164 was committed | length measured by the scan script; the value was never printed |

**docs:** (unverified) permission patterns match the whole command text, so
`git commit --no-verify*` would not match `git commit -m x --no-verify`. The new deny
rules cover both spellings regardless.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `shell/git-hooks/pre-commit` | Bash | It is a git hook that runs git and a few text filters on every commit; the existing hook and its siblings are Bash, and startup time matters more than any library. |
| `scripts/check-secret-hook.sh` | Bash | A read-only status listing built from `git` and `ls`, like `scripts/audit-project-drift.sh`. |
| tests | Bash | Match `tests/git-hooks/run.sh`. |

## Overview

Phase 1: Add the secret check

1. Change 1: Secret check in the pre-commit hook, with the gate off-switch
2. Change 2: Tests for the secret check
3. Change 3: Read-only status script for which projects have the hook
4. Change 4: Close the `--no-verify` gaps in the Claude permission rules
5. Change 5: Documentation

---

## Phase 1: Add the secret check

### Change 1: Secret check in the pre-commit hook, with the gate off-switch

**Problem:** Credentials were committed to private repos with nothing to stop them.

**File:** `shell/git-hooks/pre-commit` (existing; currently 28 lines)

**Implementation:** Keep the existing gate logic and its `SKIP_GATE_FAST=1` bypass. Add a
secret check that runs **first, and independently of the gate**, so it works in a repo with
no `scripts/gate_fast.sh`:

- **Bypass:** `SKIP_SECRET_SCAN=1` skips the secret check and prints
  `[pre-commit] SKIP_SECRET_SCAN=1 — bypassing secret scan` to stderr. `SKIP_GATE_FAST=1`
  must no longer return early before the secret check runs: restructure so each bypass
  skips only its own part.
- **What it scans:** only what the commit adds. Use `git diff --cached --diff-filter=AM -U0
  --no-color` and look at added lines (starting with `+`, not `+++`), tracking the current
  file from the `+++ b/<path>` line. Binary files produce no added lines and are skipped.
- **Skipped paths:** `venv/`, `*_env/`, `node_modules/`, `site-packages/`, `.git/`, and any
  path matching a glob listed in an optional `.secret-scan-allow` file at the repo root (one
  glob per line, `#` comments and blank lines ignored). An added line containing the marker
  `secret-scan:allow` is also skipped.
- **Content patterns** (extended regex, matched per added line). Each has a name that is
  printed instead of the match:
  - `github-token`: `(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}` and `github_pat_[A-Za-z0-9_]{20,}`
  - `anthropic-key`: `sk-ant-[A-Za-z0-9_-]{20,}`
  - `openai-key`: `sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{40,}` and `sk-[A-Za-z0-9]{40,}`
    (assumption: unverified — current OpenAI project keys are base64url after the prefix;
    the committed key measured 164 characters)
  - `aws-access-key-id`: `AKIA[0-9A-Z]{16}`
  - `google-api-key`: `AIza[0-9A-Za-z_-]{35}`
  - `slack-token`: `xox[baprs]-[0-9A-Za-z-]{10,}`
  - `huggingface-token`: `hf_[A-Za-z0-9]{30,}`
  - `private-key-block`: `-----BEGIN [A-Z ]*PRIVATE KEY-----`
- **Path patterns** (checked on the staged file name, case-insensitive): `.env` and
  `.env.<anything>` (name `path-env-file`), excluding names ending in `.example`, `.sample`,
  `.template` or `.dist`; `*.pem`, `*.p12`, `*.pfx`, `id_rsa*`, `id_ed25519*` (name
  `path-key-file`).
- **Output on a hit:** one line per finding on stderr, `[pre-commit] SECRET? <pattern-name>
  in <path>:<line>` (path only for path patterns), then the refusal and how to proceed:
  `[pre-commit] secret scan: commit refused. Remove the secret, or add the path to
  .secret-scan-allow, or set SKIP_SECRET_SCAN=1 for a one-off.` The matched text must never
  be printed, logged or put in a variable that is echoed. Exit 1.
- **Cap** the output at 20 findings and say how many more were suppressed, so a large paste
  cannot flood the terminal.
- **Gate off-switch:** the gate part runs only if `git config --bool
  devplatform.precommitGate` is not `false`. Unset means true, so the existing behaviour is
  unchanged. When it is false the hook prints nothing for the gate and exits 0 after a clean
  secret scan.
- **Order:** secret scan, then the gate. A failed secret scan never reaches the gate.
- The hook source must not contain a literal string that matches its own patterns (the
  regexes above do not), because the repo's own commits are scanned once the hook is
  enabled here.

**Acceptance Test:** in a temp repo, staging a file that contains a synthetic GitHub-token-
shaped string makes `bash shell/git-hooks/pre-commit` exit 1 with `github-token` and the
path in stderr and none of the string; staging a clean file exits 0; staging `.env` exits 1
with `path-env-file`; staging `.env.example` exits 0.

---

### Change 2: Tests for the secret check

**Problem:** A scanner that silently stops matching is worse than none.

**File:** `tests/git-hooks/run.sh` (existing, 5 tests); new fixtures only if needed

**Implementation:** Add tests in the file's existing style (temp repo per test, two-line exit
code capture, assert both exit code and a stderr substring). **Test strings are built at
runtime** by concatenating a prefix and generated filler (for example `printf '%s%s'
'ghp_' "$(printf 'a%.0s' {1..36})"`), never written as literals, so the repo's own commits,
the hook, and GitHub push protection never see a key-shaped string. Cases:

1. A staged file with a synthetic token for each of the nine content patterns exits 1 and
   names the right pattern.
2. The matched text never appears in stdout or stderr.
3. `.env` and `id_rsa` staged exit 1; `.env.example` exits 0.
4. A repo with no `scripts/gate_fast.sh` still runs the secret check (regression for the
   gate-only design).
5. `SKIP_SECRET_SCAN=1` bypasses and prints the bypass message; `SKIP_GATE_FAST=1` alone does
   NOT bypass the secret check.
6. An added line with `secret-scan:allow` passes; a path listed in `.secret-scan-allow`
   passes; a path under `venv/` passes.
7. A secret in a line the commit did not add (already in the file, unchanged) does not
   block.
8. `git config devplatform.precommitGate false` skips a failing gate but still blocks a
   secret.
9. More than 20 findings prints the suppression count.

**Acceptance Test:** `bash tests/git-hooks/run.sh` all PASS, including the original 5.

---

### Change 3: Read-only status script for which projects have the hook

**Problem:** The hook only protects a repo where it is enabled, and nothing reports which
repos those are.

**File:** `scripts/check-secret-hook.sh` (new); `tests/git-hooks/run.sh` (one test)

**Implementation:** For each git repo under `/home/rich/dev/projects/*/` (a `--projects-dir`
argument overrides the default, for the test), print one line: project, whether
`<git-dir>/hooks/pre-commit` is a symlink resolving to the dev-platform hook, whether
`core.hooksPath` is set (and to what), whether the repo has `scripts/gate_fast.sh`, and
whether another `pre-commit` already exists there (which the enable step would not
overwrite). It is **read-only**: it never writes to any project. Exit 0 always (a report, not
a gate). End with the enabling command for a repo that lacks it:
`ln -s ~/.claude/git-hooks/pre-commit <repo>/.git/hooks/pre-commit`, and the warning that
for a repo with `scripts/gate_fast.sh` the hook will also run the gate on every commit unless
`git config devplatform.precommitGate false` is set.

**Acceptance Test:** `bash scripts/check-secret-hook.sh` runs against the real projects and
lists all 18; the test builds a temp projects dir with one enabled, one not, and one with an
existing hook, and asserts the three statuses.

---

### Change 4: Close the `--no-verify` gaps in the Claude permission rules

**Problem:** `settings/settings.json:134` denies only `git commit --no-verify*`. By the
docs' whole-command matching, `git commit -m "x" --no-verify` and `git commit -n` are not
matched, so a session could skip the hook.

**File:** `settings/settings.json` (existing), `tests/settings-baseline/run.sh` (existing)

**Implementation:** Add to `permissions.deny`: `Bash(git commit * --no-verify*)`,
`Bash(git commit -n*)`, `Bash(git commit * -n)`, `Bash(git push * --no-verify*)` and
`Bash(git push --no-verify*)`. Keep the existing entry. Deny entries only add, so the merge
needs no retract entry. Extend the required-deny list in `tests/settings-baseline/run.sh`
(check 3) with the new entries. After merge the user runs `./scripts/install.sh settings`.

**Acceptance Test:** `bash tests/settings-baseline/run.sh` PASS with the new entries; a
dry-run merge (`python3 scripts/merge_settings.py settings/settings.json
~/.claude/settings.json --retract settings/permissions-retract.json --dry-run`) shows them in
`deny`. Whether a pattern matches a given command is not testable offline; note it as
verified-by-docs only.

---

### Change 5: Documentation

**Problem:** The enable step, the bypasses and the limits must be written down.

**File:** `shell/git-hooks/README.md`, `tests/README.md`, `tasks/shipped/<date>-v1.41-pre-commit-secret-blocker.md`, `ROADMAP.md` (the last two by `/code`'s doc step)

**Implementation:** In `shell/git-hooks/README.md`: replace the `core.hooksPath` activation
text with the per-repo symlink command and explain why (it leaves other hooks such as
`pre-push` alone); document `SKIP_SECRET_SCAN`, `SKIP_GATE_FAST`, `devplatform.precommitGate`,
`.secret-scan-allow` and `secret-scan:allow`; list the pattern names; state the limits from
Design Philosophy; say that an agent session must not set the bypass variables or use
`--no-verify` without the user's say-so. Note that enabling the hook in a project is a
one-line action the **user** runs in that project, because dev-platform sessions do not write
into `projects/`. Add the new script and tests to `tests/README.md`.

**Acceptance Test:** `grep -n "core.hooksPath" shell/git-hooks/README.md` shows only the
explanation of why it is NOT the enable step; the README names every variable and pattern the
hook implements (`grep -c` each name against `shell/git-hooks/pre-commit`).

---

## What NOT to Do

- Do not print, log, echo or store the matched text anywhere. Names and paths only.
- Do not put key-shaped literals in tests or fixtures; build them at runtime.
- Do not make the secret check depend on `scripts/gate_fast.sh` existing.
- Do not tell anyone to use `core.hooksPath ~/.claude/git-hooks`; it disables each repo's
  other hooks.
- Do not write into any project under `projects/` (no `ln`, no `git config` there). The
  status script is read-only; enabling is the user's action.
- Do not scan whole files or history; added lines only.
- Do not add a generic "password=" or entropy rule in this phase; they need tuning against
  false positives and are a follow-on.
- Do not weaken or remove any existing deny rule.
- Do not claim the hook stops a determined user: `--no-verify` run directly bypasses it.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `shell/git-hooks/pre-commit` | Modify | Secret check, `SKIP_SECRET_SCAN`, allowlist, gate off-switch |
| `tests/git-hooks/run.sh` | Modify | Nine secret-check cases plus the status-script test |
| `scripts/check-secret-hook.sh` | New | Read-only report of which projects have the hook |
| `settings/settings.json` | Modify | New `--no-verify` / `-n` deny entries |
| `tests/settings-baseline/run.sh` | Modify | Require the new deny entries |
| `shell/git-hooks/README.md` | Modify | Enable step, bypasses, limits |
| `tests/README.md` | Modify | Mention the new test and script |
| `tasks/shipped/<date>-v1.41-pre-commit-secret-blocker.md` | New | Written by `/code`'s doc step |
| `ROADMAP.md` | Modify | v1.41 entry |

## Implementation Order

1. Change 1, then Change 2 (tests drive the hook's behaviour).
2. Change 3 (independent of the hook's internals).
3. Change 4 (independent; touches settings).
4. Change 5 last.

## Verification Checklist

- [ ] `bash tests/git-hooks/run.sh` and `bash tests/settings-baseline/run.sh` PASS
- [ ] The hook refuses a staged synthetic secret and prints no part of it
- [ ] The hook works in a repo with no `scripts/gate_fast.sh`
- [ ] `SKIP_GATE_FAST=1` alone does not bypass the secret check
- [ ] `./scripts/gate_fast.sh` PASS
- [ ] `bash scripts/check_spec_taxonomy.sh` passes
- [ ] No file under `projects/` modified, and no key-shaped literal in any new file
- [ ] After merge: the user runs `./scripts/install.sh settings` and enables the hook per repo
- [ ] `/security-review` run before `/gate fast` (this phase handles credential patterns)
