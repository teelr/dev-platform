# Docker And Fuser Grants

## Coding Specification for Implementation

Roadmap Phase: `v1.44: Docker And Fuser Grants` (milestone claimed by `/plan`).
Branch: `worktree-v1.44+phase-1-docker-fuser-grants`. One branch, one PR. Follow-up to v1.43:
the tracked baseline still allows `Bash(docker *)`, `Bash(docker-compose *)` and
`Bash(fuser *)`, which no prune of the live file can fix, because the next
`scripts/install.sh settings` union-merges them straight back in.

## Design Philosophy

`Bash(docker *)` allows every docker subcommand with no prompt. `docker run` can mount the
host's root filesystem or run privileged, which is root on this box; `docker cp`, `docker
save` and `docker commit` move data in and out of containers. `Bash(fuser *)` allows `fuser -k`,
which kills whatever owns a port. Both entries sit in the tracked baseline, so they are
re-added on every install (the live file is a union of baseline and local grants). The fix
is in the baseline, plus retract entries so machines that already hold the old grants lose them
(the v1.39 mechanism, `settings/permissions-retract.json`).

The change is sized by what is actually used. The decision was made with the user at planning
time: `docker exec` stays allowed (629 uses in past sessions, about half against the project's
own dev and prod containers), `docker run` moves to prompting (39 uses, none with a host-escape
flag). For docker the baseline uses a list of specific read and lifecycle verbs instead of
`docker *`, so a verb nobody listed prompts (fail closed). Compose is different: its verb comes
after optional flags (`docker compose -f <file> up`), so listing verbs would need a pattern per
flag shape. Compose therefore stays `docker compose *`, with `ask` entries for `run`. Per the
v1.39 lesson, an `ask` entry beats any allow, so every `ask` pattern added here must be one with
no workflow exception. `fuser` is dropped from the allow list entirely: no past session ran
it directly, and the project scripts that call `fuser -k` are not checked against these
patterns.

This does not make a session safe. `docker exec` is arbitrary code inside a container, and a
prefix pattern can be sidestepped by chaining or quoting (`settings/README.md`, "Permission rule
behaviour"). The goal is to stop the unprompted routes to root-on-host and to port-kills.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `settings/settings.json`, `permissions-retract.json`, scaffold settings | JSON | Configuration, not code. |
| `tests/settings-baseline/run.sh` | Bash | Matches the existing suite it extends. |

## Verified state

| Claim | Verified by |
| ----- | ----------- |
| The baseline allows `Bash(docker *)` (line 27), `Bash(docker-compose *)` (28) and `Bash(fuser *)` (35); the `ask` list is lines 109-121 and already holds `docker rm *`, `docker rmi *`, `docker system prune*`, `docker volume rm *`, `docker compose down -v*`, `docker-compose down -v*` | `Read settings/settings.json` at planning time |
| Both scaffold templates also allow `Bash(docker *)` and `Bash(docker-compose *)` | `grep -rn 'docker \*' scaffolding` |
| Nothing else in `settings docs tests scaffolding shell hooks extensions` names these patterns | `grep -rn 'docker \*\|fuser \*\|Bash(docker\|Bash(fuser' ...` (only `settings/settings.json` and the two scaffold files matched) |
| 74,415 past Bash commands were extracted from `~/.claude/projects/*/*.jsonl`. Verb counts for commands starting `docker`: exec 629, ps 233, logs 155, tag 92, inspect 51, image 45, run 39, network 34, compose up 21, start 19, rm 19, compose config 18, volume 16, images 14, compose ps 10, info 8, stop 7, manifest 6, build 6, rmi 5, system 2, pull 2, compose restart 2, compose down 2, compose build 2, port 1 | `grep -E '^(docker\|docker-compose\|fuser)( \|$)'` over the extracted file, then `awk` on the verb; the count was taken across all session transcripts including closed worktrees, so it over-counts relative to one repo |
| 0 of 39 `docker run` commands had `--privileged`, `-v /:`, `docker.sock`, `--pid=host` or `--net=host` | `grep -E '^docker run' ... \| grep -cE ...` |
| 0 past commands start with `fuser`. Project scripts call `fuser -k -n tcp <port>` (kermit-v3 `scripts/start_keystone.sh:62,117`, keystone `scripts/start_keystone.sh:45,135`, and the gate scripts) | `grep -E '^fuser'` over the extracted file; `grep -rn fuser projects/*/scripts` |
| `commands/code.md:105` runs `docker compose build <service> && docker compose up -d <service>`; no other tracked command, skill, script or hook runs docker | `grep -rn 'docker ' commands skills scripts shell hooks` |
| The permission order is deny, then ask, then allow, first match decides, so an `ask` entry defeats any narrower allow | `settings/README.md` "Permission rule behaviour" (v1.39, from the Claude Code docs) |
| `permissions-retract.json` removes exact strings from the live allow list on install, and an entry in both the baseline allow list and the retract list is an error | `scripts/merge_settings.py` docstring; `tests/settings-baseline/run.sh` Check 4 |
| Assumption: a pattern with a `*` in the middle, such as `Bash(docker compose * run *)`, matches `docker compose -f x.yml run svc`. The baseline already uses mid-pattern wildcards in deny (`Bash(git push * --force*)`) but they were not probed for `ask`. Probed in the post-merge step. | unverified |
| Assumption: the live file has `defaultMode: auto`, which drops broad allow rules (`settings/README.md`). Whether `docker *` is one of the rules auto mode already drops is unknown, so the current prompting behaviour on this machine may differ from what the baseline implies. | unverified |

## Overview

Phase 1: Baseline

1. Change 1: Replace the docker and fuser allow entries in `settings/settings.json`
2. Change 2: Retract the old entries
3. Change 3: Extend `tests/settings-baseline/run.sh`
4. Change 4: Scaffold templates
5. Change 5: `settings/README.md`

Phase 2: Close out

6. Change 6: Shipped record and ROADMAP entry

---

## Phase 1: Baseline

### Change 1: Replace the docker and fuser allow entries

**Problem:** `docker *`, `docker-compose *` and `fuser *` allow root-on-host and port-kills with
no prompt.

**File:** `settings/settings.json` (allow list lines 27, 28, 35; ask list lines 109-121)

**Implementation:**

- Remove from `allow`: `Bash(docker *)`, `Bash(docker-compose *)`, `Bash(fuser *)`.
- Add to `allow`, in the place the removed docker lines were:
  `Bash(docker ps*)`, `Bash(docker logs *)`, `Bash(docker inspect *)`, `Bash(docker images*)`,
  `Bash(docker image ls*)`, `Bash(docker image inspect *)`, `Bash(docker network ls*)`,
  `Bash(docker network inspect *)`, `Bash(docker volume ls*)`, `Bash(docker volume inspect *)`,
  `Bash(docker info*)`, `Bash(docker version*)`, `Bash(docker port *)`, `Bash(docker exec *)`,
  `Bash(docker start *)`, `Bash(docker stop *)`, `Bash(docker restart *)`, `Bash(docker tag *)`,
  `Bash(docker build *)`, `Bash(docker manifest inspect *)`, `Bash(docker compose *)`.
  Every verb here appears in the past-command counts above; `docker pull` (2 uses),
  `docker image` write verbs, and `docker-compose` (0 uses) are left out on purpose.
- Add to `ask`: `Bash(docker run *)`, `Bash(docker cp *)`, `Bash(docker compose run *)`,
  `Bash(docker compose * run *)`. Do not add `docker exec`: it is allowed on purpose.
  Added after the by-hand security review of the staged diff (not in the first draft of this
  spec): `Bash(docker build -o*)`, `Bash(docker build --output*)`, `Bash(docker build * -o*)`,
  `Bash(docker build * --output*)`, because `docker build -o` makes BuildKit write into a host
  directory. `docker build *` itself stays allowed.
- Do not add anything for `fuser`. With the allow entry gone it falls to the default prompt.
- Keep the existing `ask` entries as they are.

**Acceptance Test:**

```bash
python3 -c "import json; d=json.load(open('settings/settings.json'))['permissions']; print('Bash(docker *)' in d['allow'], 'Bash(fuser *)' in d['allow'], 'Bash(docker run *)' in d['ask'])"
```

Expect `False False True`. `python3 scripts/merge_settings.py settings/settings.json /dev/null --dry-run`
prints valid JSON (a missing live file seeds from the baseline).

---

### Change 2: Retract the old entries

**Problem:** A union merge cannot remove a grant, so every machine that has `Bash(docker *)`,
`Bash(docker-compose *)` or `Bash(fuser *)` in its live file keeps them.

**File:** `settings/permissions-retract.json`

**Implementation:** Add the three exact strings to `allow`, in the existing alphabetical-ish
order. They are baseline patterns, not one-offs, so the public file is the right place (unlike
the v1.43 one-off grants).

**Acceptance Test:** `bash tests/settings-baseline/run.sh` passes, including Check 4 (no entry
both allowed and retracted).

---

### Change 3: Extend `tests/settings-baseline/run.sh`

**Problem:** A later edit could quietly re-add `docker *` or drop the `docker run` prompt.

**File:** `tests/settings-baseline/run.sh` (Check 2 banned list at line ~31; new checks after Check 5)

**Implementation:**

- Add `Bash(docker *)`, `Bash(docker-compose *)` and `Bash(fuser *)` to Check 2's `banned` list.
- New check: these `ask` entries exist: `Bash(docker run *)`, `Bash(docker cp *)`,
  `Bash(docker compose run *)`.
- New check (guards the v1.39 lesson): no `ask` entry is also matched by a workflow-needed allow.
  Concretely, `Bash(docker exec *)`, `Bash(docker compose *)` and `Bash(docker build *)` must
  remain in `allow`, and none of `docker exec`, `docker build` may appear in `ask`.
- Show each new check able to fail, by running it once against a temp copy of the baseline with
  the entry re-added or removed, the same way the existing checks are exercised.

**Acceptance Test:** `bash tests/settings-baseline/run.sh` prints only PASS lines, and the temp
copy runs print the matching FAIL.

---

### Change 4: Scaffold templates

**Problem:** New projects get `Bash(docker *)` and `Bash(docker-compose *)` copied into their own
`.claude/settings.json`, repeating the baseline's hole. The global `ask` entries win over a
project allow, but `docker cp`, `docker save` and every other unlisted verb would still be
allowed.

**Files:** `scaffolding/go-service/.claude/settings.json:7-8`,
`scaffolding/python-agent/.claude/settings.json:12-13`

**Implementation:** Replace the two lines in each file with `Bash(docker compose *)`,
`Bash(docker ps*)` and `Bash(docker logs *)`. Leave `Bash(curl *)` alone (out of scope; see
below).

**Acceptance Test:** `grep -rn 'docker \*' scaffolding` prints nothing; `bash tests/scaffold/run.sh`
(if present, else `ls tests | grep scaffold`) passes.

---

### Change 5: `settings/README.md`

**Problem:** The README's list of what the baseline stops names `kill` and `systemctl` but not
docker or fuser.

**File:** `settings/README.md` ("What the permission baseline does and does not protect")

**Implementation:** One short paragraph: docker is an explicit verb list; `docker run` and
`docker cp` prompt; `docker exec` is allowed on purpose and is arbitrary code in a container;
`fuser` is not allowed (scripts that call `fuser -k` are unaffected because only the command
Claude issues is checked). Add the mid-pattern wildcard result (or "UNTESTED") to "Permission
rule behaviour" after the post-merge probe.

**Acceptance Test:** `bash tests/commands/frontmatter.sh` and `./scripts/gate_fast.sh` pass.

---

## Phase 2: Close out

### Change 6: Shipped record and ROADMAP entry

**Files:** `tasks/shipped/<date>-v1.44-docker-fuser-grants.md` (new), `ROADMAP.md`, a
`tasks/lessons/` file only if something went wrong during `/code`.

**Implementation:** Follow `tasks/shipped/2026-11-01-v1.43-security-review-leftovers.md`. State the
usage counts with the command that produced them, that `docker exec` is allowed on purpose, and
that the mid-pattern wildcard behaviour was or was not probed.

**Acceptance Test:** `scripts/check-phase-milestones.sh` reports nothing for v1.44 after merge.

---

## Post-merge step

Needs the user's go-ahead first: it changes permissions on the live machine.

1. `./scripts/install.sh settings`, then `./scripts/verify.sh`. Verify reports any retracted entry
   still present in the live file.
2. `python3 -c` count of the live allow list; expect `Bash(docker *)`, `Bash(docker-compose *)`
   and `Bash(fuser *)` gone, and the new docker verbs present. The install also re-adds
   `Bash(docker exec *)` that the 2026-11-01 manual prune removed from the live file.
3. After a Claude Code restart, probe in a scratch session: `docker ps` runs without a prompt;
   `docker run --help` prompts; `docker compose -f /nonexistent.yml run x` prompts (this is the
   mid-pattern wildcard check); `fuser -n tcp 59999` prompts. Record the results in
   `settings/README.md` "Permission rule behaviour".

## What NOT to Do

- Do not put `Bash(docker exec *)` in `ask`. It is the most-used docker verb and ask beats allow.
- Do not add `docker pull`, `docker image rm` or `docker-compose` back to make a prompt go away.
- Do not edit `~/.claude/settings.json` from `/code`; the install does it, after the user agrees.
- Do not touch `curl *` in the scaffolds, or any project's own settings, from this session.
- Do not add one-off grants to `permissions-retract.json`.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `settings/settings.json` | Modify | Replace three broad allows with a docker verb list; add four `ask` entries |
| `settings/permissions-retract.json` | Modify | Retract the three old entries |
| `tests/settings-baseline/run.sh` | Modify | Banned entries, required asks, exec stays allowed |
| `scaffolding/go-service/.claude/settings.json` | Modify | Narrow docker allows |
| `scaffolding/python-agent/.claude/settings.json` | Modify | Narrow docker allows |
| `settings/README.md` | Modify | Document the docker and fuser stance |
| `tasks/shipped/<date>-v1.44-docker-fuser-grants.md` | New | Shipped record |
| `ROADMAP.md` | Modify | v1.44 entry |

## Implementation Order

1. Change 1, then Change 2 (the retract list must not overlap the allow list).
2. Change 3 (tests assert 1 and 2).
3. Change 4, Change 5 (independent).
4. Change 6 last.

## Verification Checklist

- [ ] `bash tests/settings-baseline/run.sh` all PASS, new checks shown able to fail
- [ ] `bash tests/merge-settings/run.sh` still passes
- [ ] `grep -rn 'docker \*' scaffolding settings/settings.json` prints nothing
- [ ] `./scripts/gate_fast.sh` passes
- [ ] No new top-level category, so `scripts/install.sh` and `scripts/verify.sh` need no change; confirm
- [ ] Post-merge probes recorded, or marked UNTESTED
- [ ] Language architecture matrix followed
- [ ] `/security-review` run before `/gate fast` (touches the permission baseline)
