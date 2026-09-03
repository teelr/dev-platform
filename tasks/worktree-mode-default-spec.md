# v1.25: Worktree Mode Default

## Coding Specification for Implementation

## Design Philosophy

Worktree mode (v1.4) gives each concurrent session its own copy of the repo, so
two sessions can never share a working tree or switch each other's branch. Five
of eighteen projects have opted in. dev-platform itself has NOT — which is why
two sessions here still share one checkout and one branch, and why v1.19
deferred opting in with a hazard flagged: `scripts/install.sh` symlinks
`~/.claude/*` at repo paths, so installing from a worktree would leave the live
deployment pointing into a directory `/merge` later deletes.

That hazard is real and it is larger than the deferral said. Verified
empirically before this spec: `scripts/verify.sh` run from a worktree exits 1
with **21 failures**, and every one is the same class — `orphan symlink:
~/.claude/commands/code.md -> /home/rich/dev/commands/code.md`. The deployment
is *correct*; only the checker's expectation is wrong, because both scripts
derive `REPO` from `BASH_SOURCE` (`install.sh:25`, `verify.sh:14`) and a
worktree-invoked run therefore expects its own path. `gate_fast.sh:119` runs
that verify on every gate, so **the gate would fail on every worktree run
today** — the actual blocker, and one that reframes the fix.

The fix is one idea applied in two places: **the live `~/.claude` deployment
always tracks the main checkout, never a branch.** Both scripts resolve `REPO`
to the main checkout via `git-common-dir` (the derivation v1.20's session
detector already uses), so `install.sh` can never create a dangling symlink and
`verify.sh` can never false-fail — from a worktree, a hand-run, or the gate.
This also fixes a second symptom the probe surfaced: `verify.sh` uses `REPO` for
14 things including `verify-remotes.sh`'s `${REPO}/projects/<name>` lookups,
which SKIPped every project from the worktree.

**One honest reinterpretation of "default", stated because the title
overpromises.** The marker stays the mechanism — a true inversion would flip the
13 un-migrated projects into worktree mode with no deps manifest, producing
broken worktrees, and v1.19's core finding was exactly that a manifest cannot be
invented from outside a project (cross-project writes are forbidden regardless).
What changes is the default *experience*: dev-platform opts itself in, and all
three scaffolding templates ship the marker, so **every new project starts in
worktree mode**. Existing projects migrate from their own sessions by adding one
file. This is a scope decision, not a shortfall — record it as such.

**One behavior change to document rather than hide:** with the deployment always
tracking main, a worktree session's edits to `commands/` or `skills/` are not
live in `~/.claude` until merged. That is the safe direction — deployed means
shipped — but it ends mid-phase live dogfooding of command edits, which this
repo has relied on. `docs/CONCURRENT-DEV.md` must say so plainly.

**Branching strategy:** single branch and single PR. The Phases are not
independently shippable — opting dev-platform in before the scripts resolve to
main would red the gate on this very branch's next run.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/install.sh`, `scripts/verify.sh` | Bash | Existing scripts; the change is a four-line `REPO` derivation each, reusing the `git-common-dir` pattern already in `scripts/check-concurrent-sessions.sh` and `shell/worktree/gate-lock.sh`. |
| `tests/worktree-default/run.sh` | Bash | Existing per-suite runner contract. |
| `.claude/worktree-deps`, template markers | Manifest text | One path per line; blank lines and `#` comments ignored (`shell/worktree/README.md`). |

No new services or components — the Language Architecture Decision Matrix is not
in play.

## Overview

**Phase 1: Make the deployment track main**

1. Change 1: `scripts/verify.sh` — resolve `REPO` to the main checkout
2. Change 2: `scripts/install.sh` — same, plus a notice when invoked from a worktree
3. Change 3: `tests/worktree-default/run.sh` — prove both from a real worktree

**Phase 2: Opt in, and make it the default for new projects**

4. Change 4: `.gitignore` + `.claude/worktree-deps` — dev-platform opts itself in
5. Change 5: the three scaffolding templates ship the marker
6. Change 6: docs + rule text — the coupling, the limit, and the scope decision

---

## Phase 1: Make the deployment track main

### Change 1: `scripts/verify.sh` — resolve `REPO` to the main checkout

**Problem:** `verify.sh:14` derives `REPO` from `BASH_SOURCE`, so a
worktree-invoked run expects `~/.claude/*` to point into the worktree. Verified:
21 `orphan symlink` failures, exit 1, where the deployment is actually correct.
`gate_fast.sh:119` runs this on every gate.

**File:** `scripts/verify.sh` (existing — line 14)

**Implementation:**

Replace the `BASH_SOURCE`-only derivation with one that resolves the main
checkout, keeping `BASH_SOURCE` as the fallback for a non-git invocation. Use
the pattern already in `scripts/check-concurrent-sessions.sh`'s
`common_dir_of()` — `git rev-parse --git-common-dir`, resolved to absolute
(it may be relative), then its parent:

```bash
# The live ~/.claude deployment always tracks the MAIN checkout, never a
# branch — install.sh symlinks repo paths, and a worktree path would dangle
# the moment /merge removes it. So verify what main deployed, no matter where
# this is invoked from: a worktree-derived REPO reports 21 false "orphan
# symlink" failures against a deployment that is actually correct.
```

Derivation, guarded so a non-git or bare invocation still works: if
`git rev-parse --git-common-dir` succeeds, `REPO` is the absolute parent of that
directory; otherwise keep the existing `BASH_SOURCE` value.

**Print one line when the resolved `REPO` differs from the script's own
location**, so a hand-run from a worktree is never silently confusing — say that
it verified the main checkout's deployment and name the path. Do NOT suppress
this; the surprise is the point of the line.

All 14 existing `${REPO}` uses inherit the fix, including
`verify-remotes.sh`'s `${REPO}/projects/<name>` lookups (which SKIPped every
project from a worktree).

**Acceptance Test:**

```bash
git worktree add -q /tmp/wt-v125 -b wt-v125-tmp
bash /tmp/wt-v125/scripts/verify.sh >/dev/null 2>&1; echo "worktree rc=$?"   # 0
bash /tmp/wt-v125/scripts/verify.sh 2>&1 | grep -c "orphan symlink"          # 0
bash /tmp/wt-v125/scripts/verify.sh 2>&1 | grep -c "main checkout"           # >=1 (the notice)
bash scripts/verify.sh >/dev/null 2>&1; echo "main rc=$?"                    # 0, notice absent
git worktree remove --force /tmp/wt-v125 && git branch -D wt-v125-tmp && git worktree prune
```

---

### Change 2: `scripts/install.sh` — same derivation, plus a worktree notice

**Problem:** `install.sh:25` has the identical derivation and 18 `${REPO}` uses.
Invoked from a worktree it would point every `~/.claude` symlink into
`.claude/worktrees/<branch>/`, which `/merge` deletes — the exact hazard v1.19
flagged when it deferred this.

**File:** `scripts/install.sh` (existing — line 25)

**Implementation:**

Apply the same `git-common-dir` derivation and the same fallback. This is the
**Derivation Sweep** rule (`CLAUDE.md`, promoted v1.21) in action: the same value
derived the same wrong way in two scripts, fixed together rather than one at a
time. Reference the rule in the comment so the pairing is not lost.

When the resolved `REPO` differs from the script's own location, print a notice
before deploying — it must say that files come from the main checkout and that
**edits in this worktree go live only after merge**. This is the documented
behavior change; the notice is where a user actually meets it.

Do NOT refuse the invocation. Refusing was considered and rejected: resolving to
main is safe (symlinks cannot dangle) and keeps `tests/install/run.sh` working
unchanged from either location, because install and verify then agree on the
same source. A refusal would need a test-only override env var — machinery for
no gain.

**Acceptance Test:**

```bash
git worktree add -q /tmp/wt-v125 -b wt-v125-tmp
FAKE=$(mktemp -d)
HOME="${FAKE}" bash /tmp/wt-v125/scripts/install.sh >/dev/null 2>&1; echo "rc=$?"   # 0
readlink "${FAKE}/.claude/commands/code.md"    # must be /home/rich/dev/commands/code.md
HOME="${FAKE}" bash /tmp/wt-v125/scripts/verify.sh >/dev/null 2>&1; echo "rc=$?"   # 0
HOME="${FAKE}" bash /tmp/wt-v125/scripts/install.sh 2>&1 | grep -c "after merge"   # >=1
rm -rf "${FAKE}"; git worktree remove --force /tmp/wt-v125 && git branch -D wt-v125-tmp && git worktree prune
```

---

### Change 3: `tests/worktree-default/run.sh`

**Problem:** The blocker is invisible from the main checkout — the gate passes
today and would only fail once someone worked in a worktree. Nothing currently
exercises either script from one.

**File:** `tests/worktree-default/run.sh` (new file, executable)

**Implementation:**

Standard suite contract: `set -uo pipefail`, `REPO` from `BASH_SOURCE`, source
`tests/helpers/assert.sh`, `record_pass`/`record_fail`/`record_skip` only, never
`exit`. Auto-discovered by `gate_fast.sh:136`.

Create a real throwaway worktree of THIS repo (`git worktree add` to a `mktemp
-d` path on a temp branch), run against it, and tear it down in a `trap` —
including `git branch -D` and `git worktree prune`, so a failed run leaves no
worktree behind. Guard the whole suite with `record_skip` if `git worktree add`
fails (shallow clone, permissions).

Every install runs against a throwaway `HOME`, never the real `~/.claude` — this
suite must not touch the live deployment. `tests/install/run.sh` is the model.

Assertions (~8):

- Both scripts' `bash -n` clean.
- `verify.sh` from the worktree exits 0 and reports **zero** `orphan symlink`
  lines — the regression this phase exists for.
- Its notice line naming the main checkout is present from the worktree and
  ABSENT from a main-checkout run (the conditional must actually be conditional).
- `install.sh` from the worktree into a fake `HOME` deploys symlinks whose
  targets are under the MAIN checkout, not the worktree path. Assert on the
  resolved target prefix, not just exit 0.
- Its "after merge" notice appears from the worktree, absent from main.
- Install-then-verify from the worktree round-trips to exit 0 (the two agree).
- With `.claude/worktree-deps` present in the worktree,
  `shell/worktree/link-deps.sh` reports no-op cleanly (dev-platform's manifest
  is comment-only — no `.env`, no `node_modules`).
- A non-git invocation still works: run `verify.sh` copied outside any repo, or
  with `GIT_CEILING_DIRECTORIES` set, and assert it falls back to `BASH_SOURCE`
  rather than erroring. This guards the fallback branch, which nothing else hits.

**Acceptance Test:**

```bash
bash tests/worktree-default/run.sh    # all PASS
git worktree list                     # exactly 1 — no leaked probe worktree
./scripts/gate_fast.sh                # 341 PASS today; expect ~349
```

---

## Phase 2: Opt in, and make it the default for new projects

### Change 4: `.gitignore` + `.claude/worktree-deps` — dev-platform opts in

**Problem:** `.gitignore:184` is a blanket `.claude/` directory ignore, so the
marker file would be silently untracked — the FIFTH occurrence of this trap
(v1.18, v1.21, v1.23, v1.24, now). A blanket directory ignore also means a
single `!` re-include would start tracking `.claude/worktrees/` itself.

**File:** `.gitignore` (existing — the `.claude/` block at lines 184-188),
`.claude/worktree-deps` (new)

**Implementation:**

The correct rule shape needs **three** rules, verified by probe before this spec
was written (a one-rule re-include tracks every worktree; `git status` without
`-uall` collapses the directory and hides which files are actually tracked, so
verify with `git check-ignore -q` per file):

```gitignore
# v1.25: dev-platform opts into worktree mode, so .claude/worktree-deps must be
# tracked — but nothing else under .claude/ (worktrees/, settings.local.json,
# projects/) may be. Blanket `.claude/` above is a DIRECTORY ignore, so
# re-include the dir, re-ignore its contents, then allow just the marker.
# Root-anchored: projects/*/.claude/ are other repos' business.
!/.claude/
/.claude/*
!/.claude/worktree-deps
```

Then create `.claude/worktree-deps`. dev-platform has no heavy git-ignored
runtime deps — no `.env`, no `node_modules` — so the manifest is
**comment-only**, explaining that emptiness is deliberate and what would go
here if that changed. `link-deps.sh` treats a manifest with no live paths as a
clean no-op (v1.4 contract).

**Acceptance Test:**

```bash
mkdir -p .claude/worktrees/probe && touch .claude/worktrees/probe/x.md .claude/settings.local.json
git status --porcelain -uall .claude/          # ONLY ?? .claude/worktree-deps
git check-ignore -q .claude/worktrees/probe/x.md && echo "worktrees ignored: OK"
git check-ignore -q .claude/settings.local.json && echo "local settings ignored: OK"
rm -rf .claude/worktrees/probe .claude/settings.local.json
```

Then end-to-end: `/plan` on this repo must now take the worktree branch. Verify
by hand that `test -f .claude/worktree-deps` succeeds and that
`bash ~/.claude/worktree/link-deps.sh "$(pwd)" /tmp/x` no-ops cleanly.

---

### Change 5: the three scaffolding templates ship the marker

**Problem:** This is what actually makes worktree mode the default —
new projects are born with it. The templates' own `.gitignore`s have **no
`.claude` rules at all** (verified), so a scaffolded project would commit its
runtime worktrees.

**File:** `scaffolding/{go-service,python-agent,next-frontend}/.claude/worktree-deps`
(new ×3), `scaffolding/*/.gitignore` (existing ×3),
`scaffolding/*/CLAUDE.md` (existing ×3 — the `tasks/` tree comment area),
`.gitignore` (the `!scaffolding/**/.claude/` allow-list at line 187)

**Implementation:**

1. **Per-template manifest** with the paths that template's stack actually needs
   — not a copied placeholder: `go-service` → `.env`; `python-agent` → `.env`
   plus its virtualenv dir if the template has one; `next-frontend` → `.env`,
   `.env.local`, `node_modules`, `.next`. Read each template's existing
   `.gitignore` to name the real paths rather than guessing; a listed path that
   does not exist yet is a warning, not an error (v1.4 contract), so listing
   `node_modules` before first install is correct.
2. **Each template's `.gitignore`** gains the `.claude/*` + `!.claude/worktree-deps`
   pair so scaffolded projects ignore runtime worktrees and local settings but
   track the marker. These files have no `.claude` rules today, so this is an
   addition, not an edit — and the template `.gitignore`s are not
   `**`-ignoring `.claude` the way dev-platform's is, so two rules suffice
   here, not three. Verify per template with the same probe.
3. **dev-platform's own `.gitignore:187`** currently allows
   `!scaffolding/**/.claude/` and `!scaffolding/**/.claude/*.json` — the marker
   is not a `.json`, so add a rule for it or the template markers are untracked.
   This is the consumer-audit half of the trap and is easy to miss because the
   directory is already allowed.
4. **Each template's `CLAUDE.md`** notes that the project is worktree-mode by
   default, one line, near the existing structure comment.

**Acceptance Test:**

```bash
for t in go-service python-agent next-frontend; do
  git check-ignore -q "scaffolding/$t/.claude/worktree-deps" \
    && echo "$t: MARKER UNTRACKED (bad)" || echo "$t: marker tracked"
done
git status --porcelain -uall scaffolding/ | grep worktree-deps   # all three appear
```

Then scaffold into a temp dir with `scripts/new-project.sh` (dry-run or a
throwaway target) and confirm the generated project has a tracked marker and
ignores `.claude/worktrees/`. If `new-project.sh` has no dry-run, copy the
template tree by hand and run the two probes there — do NOT scaffold into
`projects/`.

---

### Change 6: docs + rule text

**Problem:** Three things are now true and undocumented: the deployment tracks
main (with the mid-phase dogfooding consequence), dev-platform is worktree-mode,
and new projects are worktree-mode by default while the 13 existing ones are
not. The last is a scope decision and must be recorded as one, not left to look
like an oversight.

**File:** `docs/CONCURRENT-DEV.md` (existing — "Turning it on for a project" and
"The honest limit"), `shell/worktree/README.md` (existing),
`/home/rich/dev/CLAUDE.md` (the worktree-mode mention in the workflow section),
`README.md` (the `install.sh` category paragraph, which describes deployment)

**Implementation:**

- **`docs/CONCURRENT-DEV.md`** — a short section stating that the live
  `~/.claude` deployment always tracks the main checkout: `install.sh` and
  `verify.sh` both resolve there, so symlinks never dangle when `/merge` removes
  a worktree, and **a worktree session's `commands/`/`skills/` edits are not
  live until merged.** Say the last part plainly with its consequence — no
  mid-phase live dogfooding of command edits — since this repo has relied on it.
  Also update "Turning it on for a project" to note new projects start with the
  marker, and add the scope decision to "The honest limit": the 13 existing
  projects stay branch-mode until each adds one file from its own session,
  because a deps manifest cannot be written from outside the project.
- **`shell/worktree/README.md`** — the main-checkout-resolution contract in the
  file-level notes, and that dev-platform's own manifest is deliberately
  comment-only.
- **`CLAUDE.md`** — the worktree-mode line stops calling it opt-in-only: new
  projects default to it, existing ones opt in per project, and dev-platform is
  now in. Keep it to a sentence or two; this is a rule file.
- **`README.md`** — one clause in the deployment paragraph: symlinks always
  target the main checkout.

**Acceptance Test:**

```bash
grep -c "main checkout" docs/CONCURRENT-DEV.md shell/worktree/README.md   # >0 each
grep -c "until merged\|after merge" docs/CONCURRENT-DEV.md                # >0
./scripts/gate_fast.sh
```

---

## What NOT to Do

- **Do not opt dev-platform in before Changes 1-2 land.** The gate runs
  `verify.sh` (`gate_fast.sh:119`); a worktree run reds it with 21 false
  failures. Phase order is load-bearing.
- **Do not make `install.sh` refuse a worktree invocation.** Considered and
  rejected: resolving to main is safe and keeps `tests/install/run.sh` working
  from either location. Refusing needs a test-only override for no gain.
- **Do not flip un-migrated projects into worktree mode**, and do not write a
  `worktree-deps` into any project under `projects/`. Cross-project writes are
  forbidden, and v1.19 established that a manifest cannot be invented from
  outside the project.
- **Do not use a single `!` re-include for `.claude/`.** It is a blanket
  directory ignore; one rule tracks every worktree. Three rules, verified per
  file with `git check-ignore -q` — `git status` without `-uall` collapses the
  directory and hides the truth (this probe misled once already while planning).
- **Do not forget `.gitignore:187`'s scaffolding allow-list.** It permits
  `.claude/*.json`; the marker is not JSON, so template markers stay untracked
  without a rule of their own.
- **Do not copy one manifest across all three templates.** Their stacks differ;
  read each `.gitignore` and list what that stack actually has.
- **Do not let the test suite touch the real `~/.claude`.** Fake `HOME` for every
  install, and tear the probe worktree down in a `trap` including
  `git branch -D` + `git worktree prune`.
- **Do not claim this "inverts the default" for existing projects.** It changes
  the default for NEW ones and opts dev-platform in. Say that.
- **Do not silence the two new notice lines.** They are where a user meets the
  behavior change; a silent resolution to main is the confusing version.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/verify.sh` | Modify | `REPO` resolves to the main checkout via `git-common-dir`; notice when it differs from the script's location |
| `scripts/install.sh` | Modify | Same derivation; notice naming the main checkout and the after-merge consequence |
| `tests/worktree-default/run.sh` | New | ~8 assertions from a real throwaway worktree, fake `HOME`, trap teardown |
| `.gitignore` | Modify | Three-rule `.claude/` shape for the marker; scaffolding marker allow-rule |
| `.claude/worktree-deps` | New | Comment-only manifest — dev-platform has no heavy ignored deps |
| `scaffolding/*/.claude/worktree-deps` ×3 | New | Per-stack manifests |
| `scaffolding/*/.gitignore` ×3 | Modify | Ignore `.claude/*`, track the marker |
| `scaffolding/*/CLAUDE.md` ×3 | Modify | One line: worktree-mode by default |
| `docs/CONCURRENT-DEV.md` | Modify | Main-checkout contract, the dogfooding consequence, the scope decision |
| `shell/worktree/README.md`, `CLAUDE.md`, `README.md` | Modify | Contract + rule wording |
| `ROADMAP.md`, `tasks/shipped/`, `tasks/lessons/` | Modify/New | v1.24 conventions — `/code` writes a shipped file, not `planning.md` |

No `gate_fast.sh` change: it invokes `verify.sh`, which now self-resolves. Test
suites auto-discover.

## Implementation Order

1. **Change 1** — `verify.sh`. The blocker.
2. **Change 2** — `install.sh`. Same derivation, swept together per the rule.
3. **Change 3** — the worktree suite, proving both before dev-platform depends
   on them.
4. **Change 4** — `.gitignore` + marker. dev-platform opts in only once the gate
   survives it.
5. **Change 5** — the templates.
6. **Change 6** — docs. Gate; confirm the count moved from 341.

## Verification Checklist

- [ ] `verify.sh` from a real worktree exits 0 with zero `orphan symlink` lines (21 before)
- [ ] `install.sh` from a worktree deploys symlinks resolving under the MAIN checkout
- [ ] Install-then-verify from a worktree round-trips to exit 0
- [ ] Both notice lines present from a worktree, absent from a main-checkout run
- [ ] Non-git / ceiling-dir invocation still works via the `BASH_SOURCE` fallback
- [ ] `verify-remotes.sh`'s project lookups no longer SKIP from a worktree
- [ ] `.claude/worktree-deps` tracked; `.claude/worktrees/*` and `settings.local.json` ignored (per-file `check-ignore`, not collapsed `git status`)
- [ ] All three template markers tracked (`.gitignore:187` allow-list extended)
- [ ] Each template manifest lists that stack's real paths, read from its `.gitignore`
- [ ] A scaffolded copy tracks its marker and ignores `.claude/worktrees/`
- [ ] `tests/worktree-default/run.sh` all PASS; `git worktree list` shows exactly 1 afterwards
- [ ] Live `~/.claude` untouched by the suite (`scripts/verify.sh` still exits 0 after it runs)
- [ ] `./scripts/gate_fast.sh` — PASS, count up from 341
- [ ] The scope decision (new projects default; 13 existing opt in per project) recorded in `docs/CONCURRENT-DEV.md`
- [ ] The mid-phase dogfooding consequence documented plainly
- [ ] No file under `projects/` modified
- [ ] Markdown: blank line after headings, fenced blocks tagged with a language
