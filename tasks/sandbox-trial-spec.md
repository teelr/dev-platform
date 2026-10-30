# Sandbox Trial

## Coding Specification for Implementation

Roadmap Phase: `v1.40: Sandbox Trial` (milestone claimed by `/plan`).
Branch: `worktree-v1.40+phase-1-sandbox-trial`. One branch, one PR. The Changes are one
trial and cannot ship separately.

## Design Philosophy

`PR #128` (v1.39) tightened the permission rules but left `python`, `node`, `npm`, `go`,
`cargo` and `./scripts/*` allowed. Each can run arbitrary code, so a prompt-injected session
can still read credentials and send them out. Claude Code's sandbox is the OS-level boundary
for that. This phase does NOT turn it on for everyone. It runs a **trial**: enable the
sandbox in a throwaway session, run the same probe script with and without it, and record
what breaks on this machine and workflow. The output is a measured findings document and a
recommendation, not a settings change. Enabling it permanently is a separate phase, decided
after the findings are in.

Two constraints shape the design. First, the sandbox only wraps commands run by the Claude
session that was started with it enabled, so the session that runs `/code` for this spec
cannot sandbox itself; the sandboxed run is done by the user in a second terminal. Second,
this server's kernel setting currently blocks the sandbox tool from starting at all (see
"Verified state"), and fixing that is a root-level system change on a shared server. That
change is a separate, explicitly approved Change, not something `/code` does on its own.

Every claim below about this machine names the command that verified it. Claims about the
sandbox's behaviour come from the Claude Code docs, read through a summarizing fetch that
was truncated (about 100k of 107k characters on the sandboxing page); they are marked
**docs:** and must be re-checked against the live page and against the trial results.

## Verified state

| Claim | Verified by |
| ----- | ----------- |
| `bubblewrap 0.9.0` and `socat 1.8.0` are installed | `which bwrap socat`, `bwrap --version`, `socat -V` |
| Ubuntu 24.04.4 LTS, kernel 7.0.0-28-generic | `lsb_release -ds`, `uname -r` |
| `kernel.apparmor_restrict_unprivileged_userns = 1` | `sysctl kernel.apparmor_restrict_unprivileged_userns` |
| No AppArmor profile for `bwrap` exists | `ls /etc/apparmor.d \| grep -i -E "bwrap\|bubblewrap"` printed nothing |
| `bwrap` cannot start today | `bwrap --ro-bind / / --dev /dev true` → `setting up uid map: Permission denied`, exit 1; with `--unshare-net` → `loopback: Failed RTM_NEWADDR: Operation not permitted` |
| Claude Code is 2.1.314 and the live settings have no `sandbox` key | `claude --version`; `python3` read of `~/.claude/settings.json` |
| The git remote is SSH (`git@github.com:teelr/dev-platform.git`) | `git remote -v` |
| `gh` is logged in as `teelr`, git protocol `https` | `gh auth status` |

**docs:** (unverified until the trial) plain `ssh` does not go through the sandbox's HTTP
proxy and fails; `docker` is incompatible and must be excluded; a worktree's git writes go to
the main repo's `.git`, outside the working directory; reads are NOT blocked by default,
including `~/.ssh`; if a dependency is missing the sandbox silently runs unsandboxed unless
`failIfUnavailable` is set. The SSH remote makes the first of those a likely blocker for
`git push` and `git fetch`.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/sandbox-probe.sh` | Bash | Matches the other `scripts/*.sh`; it only runs small commands and prints a table. No new language is warranted. |
| `tests/sandbox-probe/run.sh` | Bash | Matches the existing offline suites. |
| `deploy/sandbox/trial-settings.json`, AppArmor profile | JSON, AppArmor | Configuration, not code. |

## Overview

Phase 1: Run the trial

1. Change 1: Probe script and its offline test
2. Change 2: Trial settings file and the AppArmor profile source
3. Change 3: Enable the sandbox prerequisite (user-approved, root)
4. Change 4: Run the probes without and with the sandbox, record results
5. Change 5: Findings document and recommendation

---

## Phase 1: Run the trial

### Change 1: Probe script and its offline test

**Problem:** The trial needs the same set of checks run twice, once normally and once inside
the sandbox, so the difference between the two runs is the finding.

**File:** `scripts/sandbox-probe.sh` (new), `tests/sandbox-probe/run.sh` (new)

**Implementation:** A Bash script, `set -u`, no `set -e` (a failing probe must not stop the
run). Each probe prints one line `PROBE <name>: OK|FAIL|SKIP <detail>` and the script ends
with a count. Every probe is read-only or cleans up after itself; a `trap` removes anything
the script created. `--list` prints the probe names without running anything. Probes:

1. `write-cwd`: create and delete a file in the current directory.
2. `write-tmp`: create and delete a file under `${TMPDIR:-/tmp}`.
3. `write-home-claude`: try to create a file under `~/.claude/` (expected to be blocked by
   the sandbox; this is a "should FAIL under sandbox" probe, labelled so).
4. `git-status`: `git status --porcelain` (in a worktree this refreshes the index, which
   lives under the main repo's `.git/worktrees/`).
5. `git-commit-worktree`: on a throwaway branch `sandbox-probe-<pid>`, `git commit
   --allow-empty -m probe`, then switch back and delete the branch. Skip with a message if
   the working tree is dirty, so the probe never touches real work.
6. `git-fetch-ssh`: `git ls-remote origin HEAD` (uses the SSH remote; the likely blocker).
7. `gh-api`: `gh api rate_limit --jq .resources.core.limit` (uses HTTPS and `gh`'s token
   file under `~/.config/gh`).
8. `net-allowed`: `curl -sI -m 10 https://api.github.com` (a host the trial settings allow).
9. `net-blocked`: `curl -sI -m 10 https://example.org` (a host the trial settings do NOT
   allow; expected to FAIL under the sandbox).
10. `read-canary`: read a canary file `~/.sandbox-trial-canary`. The script creates it with
    a harmless string if absent and removes it on exit. The trial settings deny reads of it,
    so this is expected to FAIL under the sandbox. It stands in for `~/.ssh`: the probe must
    never read, list, or print anything under `~/.ssh` or `~/.aws`.
11. `exfil-canary`: only if `read-canary` succeeded, try to send the canary string to the
    non-allowlisted host from probe 9 with `curl`. It FAILS under the sandbox. Without the
    sandbox it would succeed, so the script MUST NOT run this probe unless an environment
    variable `SANDBOX_PROBE_ALLOW_EXFIL=1` is set, and SKIPs otherwise. The point is a
    controlled test; the default run never sends data anywhere.
12. `localhost`: `curl -sI -m 3 http://127.0.0.1:1` (expected connection refused either way;
    records whether the sandbox changes the error).
13. `tmux`: `tmux display-message -p ok` if `$TMUX` is set, else SKIP.
14. `docker`: `docker version --format '{{.Client.Version}}'`.
15. `link-deps`: `bash ~/.claude/worktree/link-deps.sh` (exit 0 or the "same directory" exit
    are both OK; record the exit code).

`tests/sandbox-probe/run.sh` (auto-discovered by `scripts/gate_fast.sh`, using
`tests/helpers/assert.sh`): `bash -n` passes; `--list` prints all 15 names and exits 0;
running with an unset `SANDBOX_PROBE_ALLOW_EXFIL` reports `exfil-canary` as SKIP; the script
leaves no stray file or branch behind (`git branch --list 'sandbox-probe-*'` is empty and
the canary is gone). The test must NOT run the network, git-commit, or docker probes (the
gate is offline); it exercises `--list` and a `--only <name>` flag that runs a single named
probe, which the test uses only on `write-tmp`.

**Acceptance Test:** `bash tests/sandbox-probe/run.sh` all PASS;
`bash scripts/sandbox-probe.sh --list | wc -l` prints 15.

---

### Change 2: Trial settings file and the AppArmor profile source

**Problem:** The sandbox settings and the system profile need to be reviewable files, not
text pasted into a terminal.

**File:** `deploy/sandbox/trial-settings.json` (new), `deploy/apparmor/bwrap` (new),
`deploy/sandbox/README.md` (new)

**Implementation:**

- `trial-settings.json` holds only a `sandbox` object, for use with `claude --settings`:
  `enabled: true`, `failIfUnavailable: true`, `allowUnsandboxedCommands: false`,
  `filesystem.denyRead: ["~/.sandbox-trial-canary", "~/.ssh", "~/.aws"]`,
  `filesystem.allowWrite` containing the main repo's git directory (`/home/rich/dev/.git`),
  `network.allowedDomains: ["api.github.com", "github.com"]`, and
  `excludedCommands: ["docker *"]`. This is the starting point from the docs agent's report,
  not a verified-good config; the trial exists to find what is wrong with it. Do not widen
  it to make a probe pass; record the failure instead (Change 4).
- `deploy/apparmor/bwrap` is the AppArmor profile that lets `/usr/bin/bwrap` create user
  namespaces. **Copy it verbatim from the Claude Code sandboxing docs page** (fetch the page;
  it contains the full profile text). Do not write one from memory. Record the page URL and
  the fetch date in a comment at the top of the file.
- `deploy/sandbox/README.md`: how to apply the profile, how to launch the trial session, how
  to undo each (remove the profile and reload AppArmor; just exit the trial session).
- Consumer audit for new file types in glob-managed directories: confirm `deploy/` is
  allowed by `.gitignore` (`touch deploy/sandbox/probe.md && git status --porcelain
  deploy/sandbox/`, then delete the probe) and add the `.json` / extensionless-file rules if
  `git status` does not list the new files. `deploy/systemd/` already exists as the
  precedent.

**Acceptance Test:** both JSON files parse (`python3 -c "import json; json.load(open(...))"`);
`git status --porcelain` lists all three new files; the profile file's header comment names
the docs URL.

---

### Change 3: Enable the sandbox prerequisite (user-approved, root)

**Problem:** `bwrap` cannot start on this server until an AppArmor profile permits it.

**File:** `/etc/apparmor.d/bwrap` (system file, outside the repo), source `deploy/apparmor/bwrap`

**Implementation:** This Change is a **heads-up and pause**. It writes a system file as root
on a shared server (another session, `neurx-sysops`, manages this machine's setup), so `/code`
MUST stop and ask the user before running it, showing the exact commands:

```bash
sudo cp deploy/apparmor/bwrap /etc/apparmor.d/bwrap
sudo systemctl reload apparmor
```

If the user declines, stop the whole phase here and report that the trial cannot run; do not
look for another route to the sandbox.

**Acceptance Test:** `bwrap --ro-bind / / --dev /dev true; echo $?` prints `0`, and
`bwrap --ro-bind / / --unshare-net true; echo $?` prints `0` (the two commands that failed
before). To undo: `sudo rm /etc/apparmor.d/bwrap && sudo systemctl reload apparmor`.

---

### Change 4: Run the probes without and with the sandbox, record results

**Problem:** There is no measured evidence of what the sandbox breaks here.

**File:** `docs/SANDBOX-TRIAL.md` (new; results table)

**Implementation:**

1. **Baseline (no sandbox).** In a normal worktree session run `bash scripts/sandbox-probe.sh`
   and save the output. Every probe should be OK except those labelled "should FAIL under
   sandbox", which will also pass here. Any other failure is a pre-existing problem; record
   it and do not blame the sandbox.
2. **Sandboxed run.** `/code` cannot do this itself. Ask the user to open a second terminal,
   `cd` into the worktree, and start Claude with the trial settings (assumption: unverified —
   `--settings` accepts a JSON string per the docs; the file may need to be passed as
   `--settings "$(cat deploy/sandbox/trial-settings.json)"`). In that session, check `/sandbox`
   shows it enabled, then ask the session to run `bash scripts/sandbox-probe.sh` and paste
   the output back. Also run `SANDBOX_PROBE_ALLOW_EXFIL=1 bash scripts/sandbox-probe.sh
   --only exfil-canary` once in each session.
3. **Workflow smoke.** In the sandboxed session, run `./scripts/gate_fast.sh` and report
   the result and anything that is blocked; then try `git push` of a throwaway branch with
   no changes (`git push origin HEAD:refs/heads/sandbox-trial-probe`, then delete it with
   `git push origin --delete sandbox-trial-probe`) because the SSH remote is the likely
   failure. Do not run `/merge`, `install.sh`, or anything that writes `~/.claude` under the
   sandbox; record those as "not tried".
4. Fill the results table in `docs/SANDBOX-TRIAL.md`: probe, baseline result, sandboxed
   result, expected, matches expected (yes/no).

**Acceptance Test:** the table has a row for each of the 15 probes plus `gate_fast.sh` and
`git push`, each with both results filled in or marked "not tried" with a reason. No row is
left blank. No `~/.ssh` or `~/.aws` content appears anywhere in the document.

---

### Change 5: Findings document and recommendation

**Problem:** The results need to become a decision.

**File:** `docs/SANDBOX-TRIAL.md` (same file), `tasks/shipped/<date>-v1.40-sandbox-trial.md`
and `ROADMAP.md` (written by `/code`'s doc step)

**Implementation:** Add a "Findings" section stating, per category (writes, git, `gh`,
network allowlist, exfiltration, docker, tmux, localhost), what the trial showed. Add a
"Recommendation" section with exactly one of: **adopt** (list the settings block to add in a
follow-on phase), **adopt with exclusions** (list the commands to exclude and what each
costs), or **do not adopt** (list the blockers). If `git push`/`git fetch` fail over SSH,
state the options measured or proposed (exclude those commands, or switch the remote to
HTTPS with `gh` as the credential helper) without choosing one: switching the remote changes
the repo's git configuration and is the user's decision. State the security gain honestly:
what the sandboxed run blocked, and what it did not (the `Read` tool and unsandboxed
commands are outside it, per the docs).

**Acceptance Test:** the document has a Recommendation with one of the three outcomes and
every sentence about this machine traces to a row in the results table.

---

## What NOT to Do

- Do not edit `settings/settings.json`, `settings/permissions-retract.json`, or
  `~/.claude/settings.json`. This phase changes no live permission or sandbox setting.
- Do not run Change 3 without asking the user first, and do not look for another way to get
  `bwrap` working if the user says no.
- Do not read, list, print or copy anything under `~/.ssh`, `~/.aws` or `~/.config/gh`
  while writing or running probes. Use the canary file as the stand-in.
- Do not widen `trial-settings.json` to make a failing probe pass; record the failure.
- Do not run the exfil probe against the real credentials, and never without
  `SANDBOX_PROBE_ALLOW_EXFIL=1` set deliberately.
- Do not claim the sandbox protects against something the trial did not exercise.
- Do not switch the git remote from SSH to HTTPS in this phase.
- Do not touch anything under `projects/`.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/sandbox-probe.sh` | New | 15 probes, `--list`, `--only <name>`, no default exfil |
| `tests/sandbox-probe/run.sh` | New | Offline suite: syntax, `--list`, exfil SKIP, no leftovers |
| `deploy/sandbox/trial-settings.json` | New | `sandbox` block for `claude --settings` |
| `deploy/sandbox/README.md` | New | Apply, launch and undo instructions |
| `deploy/apparmor/bwrap` | New | AppArmor profile copied verbatim from the docs |
| `docs/SANDBOX-TRIAL.md` | New | Results table, findings, recommendation |
| `tasks/shipped/<date>-v1.40-sandbox-trial.md` | New | Written by `/code`'s doc step |
| `ROADMAP.md` | Modify | v1.40 entry |
| `.gitignore` | Modify (conditional) | Only if the new `deploy/` files are not tracked |

## Implementation Order

1. Change 1 and Change 2 (no dependencies; both land before anything runs).
2. Change 3 (pause for the user's approval; blocks everything after it).
3. Change 4 (needs Change 3, and the user's second terminal).
4. Change 5 last.

## Verification Checklist

- [ ] `bash tests/sandbox-probe/run.sh` PASS and `./scripts/gate_fast.sh` PASS
- [ ] `bwrap --ro-bind / / --dev /dev true` exits 0 after Change 3
- [ ] `docs/SANDBOX-TRIAL.md` has both result columns filled, and a one-outcome recommendation
- [ ] The exfil probe never ran without `SANDBOX_PROBE_ALLOW_EXFIL=1`
- [ ] Nothing under `~/.ssh`, `~/.aws` or `~/.config/gh` was read or printed
- [ ] No live settings file was edited
- [ ] No file under `projects/` modified
- [ ] `bash scripts/check_spec_taxonomy.sh` passes
- [ ] `/security-review` run before `/gate fast` (this phase touches credential-adjacent
      paths and a system security profile)
