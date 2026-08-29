# v1.21: Host Agnostic Repo Detection

## Coding Specification for Implementation

## Design Philosophy

Three dev-platform scripts derive `owner/repo` from `git remote get-url origin`,
and all three assume the host is literally `github.com`. SQRL's remote is
`git@github-teelr129:Osigin-LLC/SQRL.git` — the SSH host-alias multi-account
setup **dev-platform's own docs prescribe** for that separate account — so our
tooling breaks on a convention we told the project to adopt.
[Issue #77](https://github.com/teelr/dev-platform/issues/77).

The three fail differently, and all three are visible — none silently passes:

| Script | Behavior on an alias remote |
| ------ | --------------------------- |
| `scripts/claim_roadmap_version.py:56` | raises `RuntimeError`, `/plan` Step 2 hard-stops. The reported symptom, and the loudest of the three |
| `scripts/check-phase-milestones.sh:94` | `sed` doesn't match, so `REPO` becomes the whole URL. The shape guard at line 96 (`^[^/]+/[^/]+$`) **passes** it, because the URL happens to contain exactly one `/`. `gh api` 404s, gh exits 1, and the script reports `failed to fetch milestones (gh auth/network?)` — visible, but blaming auth for a parsing bug |
| `scripts/check_version_collision.py:90` | returns `None` → prints `SKIP: could not determine owner/repo from origin remote`, sets `degraded`, exits 2. Honest degradation by design (`check_version_collision.py:166,181-186`), but SQRL's CI loses the milestone cross-check entirely |

**Two projects are affected, not one.** A sweep of every remote found SQRL and
`gosqrlgo-dispatch` both on the `github-teelr129` alias; everything else is plain
`github.com`. SQRL is the first to notice, not the only one broken —
`gosqrlgo-dispatch` hits this the moment it runs `/plan`.

**This is the third time one derivation rule, duplicated across scripts, has been
fixed in one place and left broken in the others.** v1.11's roadmap-version regex
matched only kermit-v3's heading form and silently no-op'd against dev-platform's
list form (fixed in v1.12). v1.13's `ROADMAP_PATH` had to be added to a third
script the issue never named, which had the identical bug. Now the repo-slug
derivation is wrong in three. Two near-identical `_repo_slug()` functions already
sit in the two Python scripts, differing only in `$` vs `\s*$` and raise vs.
return-`None` — that duplication is the mechanism. So this spec ships **one**
parse in `scripts/lib/repo_slug.py`, imported by both Python callers and invoked
as a CLI by the shell one, and promotes the recurrence to a rule so the next
derivation doesn't fan out the same way.

Safe for consumer CI: `.github/workflows/taxonomy-check.yml:76-88` does a full
`actions/checkout` of `teelr/dev-platform` before running
`check_version_collision.py`, so a `scripts/lib/` sibling is present. Verified,
because a workflow that copied individual files would have made a shared module
break every consumer.

The parse takes the last two path segments after stripping a trailing `.git`,
which is host-agnostic by construction. Verified against nine URL shapes before
this spec was written; it preserves every shape that works today and additionally
fixes a **second latent bug** — the current `([^/.]+?)` group excludes dots from
repo names, so `git@github.com:owner/my.repo.git` returns `None` today too.

**Branching strategy:** single branch and single PR for the whole spec. The
Phases are not independently shippable — Phase 1 without Phase 2 ships an
untested parser, and Phase 2's regression assertions target Phase 1's code.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/lib/repo_slug.py` | Python | Both existing callers with this bug are Python (`claim_roadmap_version.py`, `check_version_collision.py`), and Python is where the shared logic can be imported rather than copied. The shell caller invokes it as a subprocess — one implementation beats a second one in `sed` that would immediately begin to drift, which is the exact failure this spec exists to stop. |
| test suites | Bash | Matches the existing per-suite runner contract (`record_pass`/`record_fail`, never `exit`). |

The Language Architecture Decision Matrix governs new services and components.
This spec adds neither — it is environment tooling, the same class as every other
file in `scripts/`.

## Overview

**Phase 1: One parse, three callers**

1. Change 1: `scripts/lib/repo_slug.py` — the host-agnostic parse, importable and CLI-invokable
2. Change 2: both Python scripts import it instead of carrying their own regex
3. Change 3: `check-phase-milestones.sh` calls it, and stops blaming auth for a parsing failure

**Phase 2: Coverage**

4. Change 4: `tests/repo-slug/run.sh` plus per-script alias regressions in the two existing suites

**Phase 3: Stop the recurrence**

5. Change 5: promote the three-time pattern to a rule in `CLAUDE.md` + `docs/RULE_RATIONALE.md`

---

## Phase 1: One parse, three callers

### Change 1: `scripts/lib/repo_slug.py`

**Problem:** The same `owner/repo` derivation is written three times, three
different ways, and all three are wrong for a host that isn't literally
`github.com`.

**File:** `scripts/lib/repo_slug.py` (new file, executable — it is both an
importable module and a CLI)

**Implementation:**

Expose one function and a `__main__` entry point:

```python
def parse_repo_slug(url: str) -> str | None:
```

The rule, in order:

1. `url.strip()`, then strip any trailing `/`.
2. If it now ends in `.git`, remove exactly that suffix. Do this **before**
   matching, not inside the regex — that is what lets a repo name contain dots.
3. Match `r"[:/]([^/:]+)/([^/]+)$"`. Return `f"{owner}/{repo}"`, else `None`.
4. Never raise. Callers decide how to handle `None` — they already differ
   deliberately (one raises, one degrades, one errors), and this spec does not
   change that.

Taking the last two segments after a `:` or `/` is host-agnostic by
construction: it never looks at the host, so an alias, an enterprise domain, or
a plain `github.com` all work identically.

Verified behavior — reproduce this table in the module docstring, since it is
the contract:

| URL | Result |
| --- | ------ |
| `git@github.com:owner/repo.git` | `owner/repo` |
| `https://github.com/owner/repo.git` | `owner/repo` |
| `https://github.com/owner/repo` | `owner/repo` |
| `ssh://git@github.com/owner/repo.git` | `owner/repo` |
| `https://user@github.com/owner/repo.git` | `owner/repo` |
| `git@github-teelr129:Osigin-LLC/SQRL.git` | `Osigin-LLC/SQRL` — the alias case, `None` today |
| `git@github.com:owner/my.repo.git` | `owner/my.repo` — dotted repo name, also `None` today |
| `not-a-url` | `None` |
| `""` | `None` |

The docstring must also state the deliberate trade-off: because the parse ignores
the host, a non-GitHub remote (GitLab, Bitbucket) now yields a plausible-looking
slug instead of `None`, and fails later at the `gh api` call rather than at
parse time. That is accepted — every caller requires `gh` anyway, and Change 3's
error-message fix names an unreachable repo as a possible cause.

CLI form, for the shell caller: read the URL from `sys.argv[1]`; print the slug
and exit 0, or print nothing and exit 1 on `None`. No other output on stdout —
the shell caller captures it with `$(...)`.

**Acceptance Test:**

```bash
python3 -c "import sys; sys.path.insert(0,'scripts/lib'); from repo_slug import parse_repo_slug as p; \
print(p('git@github-teelr129:Osigin-LLC/SQRL.git'), p('git@github.com:owner/my.repo.git'), p('nope'))"
# expect: Osigin-LLC/SQRL owner/my.repo None

python3 scripts/lib/repo_slug.py 'git@github-teelr129:Osigin-LLC/SQRL.git'   # Osigin-LLC/SQRL, rc=0
python3 scripts/lib/repo_slug.py 'not-a-url'; echo "rc=$?"                   # no output, rc=1
```

---

### Change 2: both Python scripts import the shared parse

**Problem:** `claim_roadmap_version.py:56` and `check_version_collision.py:90`
carry near-identical regexes that differ only in trailing-anchor detail. Fixing
one and leaving the other is exactly what v1.12 and v1.13 each had to come back
and clean up.

**File:** `scripts/claim_roadmap_version.py` (existing — `_repo_slug()` at lines
44-59), `scripts/check_version_collision.py` (existing — `_repo_slug()` at lines
76-91)

**Implementation:**

Both scripts are invoked by absolute path from arbitrary working directories
(`/plan` Step 2 runs `python3 /home/rich/dev/scripts/claim_roadmap_version.py`),
so resolve the import off `__file__`, never off the cwd. Add near the existing
imports in each:

```python
sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from repo_slug import parse_repo_slug
```

`check_version_collision.py` already imports `Path`; confirm `claim_roadmap_version.py`
does too and add it if not.

Then in each `_repo_slug()`, **keep everything except the regex**:

- The `VERSION_GUARD_REPO_SLUG` override block stays exactly as-is in both,
  warning text included. It is the workaround SQRL is running on today and must
  keep working until they remove it.
- `claim_roadmap_version.py` keeps raising `RuntimeError` with its current
  message when the parse returns `None`.
- `check_version_collision.py` keeps returning `None`, which its caller at line
  145 already handles by degrading to SKIP/exit 2.

Only the regex line is replaced, by `return parse_repo_slug(url)` (with each
script's existing `None` handling around it). Do not unify the two functions'
error behavior — the difference is deliberate.

**Acceptance Test:**

```bash
# A throwaway repo with an alias remote proves the real path, not just the parser.
T=$(mktemp -d /tmp/alias.XXX); git -C "$T" init -q
git -C "$T" remote add origin 'git@github-teelr129:Osigin-LLC/SQRL.git'
cd "$T" && python3 -c "
import sys; sys.path.insert(0,'/home/rich/dev/scripts')
import claim_roadmap_version as c; print(c._repo_slug())"
# expect: Osigin-LLC/SQRL   (RuntimeError before this Change)
```

Also confirm the override still short-circuits:
`VERSION_GUARD_REPO_SLUG=a/b` must return `a/b` and still print its warning.

---

### Change 3: `check-phase-milestones.sh` calls the shared parse, and stops misdiagnosing

**Problem:** Two defects at once. The `sed` at line 94 hardcodes `github.com`, so
an alias URL passes through unchanged; and the shape guard at line 96
(`^[^/]+/[^/]+$`) lets it through because the URL contains exactly one `/`.
The garbage slug reaches `gh api`, which 404s, and the script reports
`failed to fetch milestones for <garbage> (gh auth/network?)` — blaming auth for
a parsing bug. All four behaviors verified live.

**File:** `scripts/check-phase-milestones.sh` (existing — origin block at lines
85-99, fetch-failure message at lines 103-106)

**Implementation:**

1. **Add self-location.** The script has no `BASH_SOURCE` anchor today; it needs
   one to find the helper. Use the idiom every other script in this repo uses,
   placed near the top with the other setup:

   ```bash
   HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   ```

2. **Replace the `sed` at line 94** with a call to the shared parse, keeping the
   surrounding `if [[ -z "${REPO}" ]]` structure and the `--repo` override:

   ```bash
   REPO="$(python3 "${HERE}/lib/repo_slug.py" "${origin_url}" 2>/dev/null)" || REPO=""
   ```

   Update the comment above it (lines 85-86) — it currently claims the block
   "handles git@github.com:owner/repo.git and https://github.com/owner/repo.git",
   which is precisely the assumption being removed.

3. **Make the empty case actionable.** With the parse returning nothing on
   failure, `REPO` is empty and the existing shape guard at line 96 now catches
   it properly instead of waving a URL through. Its message should name the
   real cause:

   ```text
   ERROR: could not parse owner/repo from origin URL '<url>' — pass --repo OWNER/REPO
   ```

   Keep exit 2.

4. **Fix the misdiagnosing fetch error** at lines 103-106. It currently reads
   `(gh auth/network?)`; add an unreachable/nonexistent repo as a possible cause,
   since a host-agnostic parse can now produce a well-formed slug for a repo that
   does not exist on GitHub.

`python3` becomes a dependency of this script alongside `gh` and `jq`. Note it in
the header comment's requirements if one is listed there.

**Acceptance Test:**

```bash
T=$(mktemp -d /tmp/alias.XXX); git -C "$T" init -q
git -C "$T" remote add origin 'git@github-teelr129:Osigin-LLC/SQRL.git'
cd "$T" && bash /home/rich/dev/scripts/check-phase-milestones.sh 2>&1 | head -2
# expect: it queries Osigin-LLC/SQRL — NOT "git@github-teelr129:Osigin-LLC/SQRL"

git -C "$T" remote set-url origin 'garbage'
cd "$T" && bash /home/rich/dev/scripts/check-phase-milestones.sh; echo "rc=$?"
# expect: "could not parse owner/repo from origin URL 'garbage'", rc=2
```

---

## Phase 2: Coverage

### Change 4: `tests/repo-slug/run.sh` plus alias regressions in the two existing suites

**Problem:** The parse has one behavior table and three consumers. Without a
unit suite the table is unenforced, and without per-script assertions nothing
proves each script actually reaches the shared parse rather than keeping a stale
local copy — which is the failure mode this whole spec is about.

**File:** `tests/repo-slug/run.sh` (new), `tests/version-collision/run.sh`
(existing), `tests/phase-milestones/run.sh` (existing)

**Implementation:**

Follow the existing per-suite contract in all three: `set -uo pipefail`, resolve
`REPO` from `BASH_SOURCE`, source `tests/helpers/assert.sh`, use only
`record_pass`/`record_fail`/`record_skip`, **never `exit`**. Suites are
auto-discovered by `scripts/gate_fast.sh:136`, so the new directory needs no
orchestrator change.

**`tests/repo-slug/run.sh`** — one assertion per row of Change 1's table (9
cases), driving the CLI form so both the module and the entry point are covered.
Plus:

- CLI exit code is 0 with output on success, 1 with no stdout on `None`.
- The two rows that are `None` today (`github-teelr129` alias, `owner/my.repo`)
  carry a comment marking them as the v1.21 regressions.

**`tests/version-collision/run.sh`** — add an assertion that
`check_version_collision.py` resolves an alias remote. The suite already builds
a real local git remote, so point a fixture repo's origin at an alias-shaped URL
and assert the run does **not** print
`SKIP: could not determine owner/repo from origin remote`. Assert on that exact
string — it is the observable that distinguishes "parsed" from "gave up".

**`tests/phase-milestones/run.sh`** — the suite already mocks `gh`. Add two:

- With an alias origin, the mock `gh` is called with `repos/Osigin-LLC/SQRL/...`,
  not with the raw URL. Capture the mock's argv, the way the suite already does.
- With a `garbage` origin, the script exits 2 and the message names the URL —
  guarding against the shape guard waving a bad value through, which is how this
  bug reached `gh api` in the first place.

**Acceptance Test:**

```bash
bash tests/repo-slug/run.sh            # all PASS
bash tests/version-collision/run.sh    # all PASS
bash tests/phase-milestones/run.sh     # all PASS
./scripts/gate_fast.sh                 # 293 PASS today; expect ~306
```

---

## Phase 3: Stop the recurrence

### Change 5: promote the three-time pattern to a rule

**Problem:** The same shape has now cost three Roadmap Phases: v1.12 (roadmap
version regex in 2 scripts), v1.13 (`ROADMAP_PATH` in 3 scripts, one of which the
issue never named), and this spec (repo-slug in 3 scripts). Each was found by a
consumer hitting it in production, not by the fix that touched a sibling script.
`/home/rich/.claude/CLAUDE.md`'s feedback-loop rule says 2-3 entries pointing at
one root cause get consolidated into a rule — this is the third.

**File:** `/home/rich/dev/CLAUDE.md` (existing — add to the "Consumer Audit — New
File Types in Glob-Managed Directories" neighborhood, which is the closest
existing sweep-style rule), `docs/RULE_RATIONALE.md` (existing — add a section
with the three-incident lineage)

**Implementation:**

In `CLAUDE.md`, a short rule in the file's existing terse voice — no new
top-level section if it fits as a sibling of the Consumer Audit rule. It must say:
when changing how a value is **derived** from the environment (a git remote, a
config path, a filename convention, an env var), grep for every other script that
derives the same value and fix them together, or extract one shared helper. Name
the tell: two functions with the same name and nearly the same body in different
files. Cite the three incidents by version.

In `docs/RULE_RATIONALE.md`, the full lineage in the style of its existing
sections: what each incident was, how it was found (a consumer hitting it, every
time), and why "fix the one the issue named" keeps being insufficient. Reference
this spec's own sweep — grepping for `remote get-url`/`github.com` across
`scripts/` found all three sites in one command, before any code was written.

Do not add a mechanical checker for this. It is a judgment rule about where to
look, not a pattern a script can detect — and an unenforceable check wired into
the gate would be worse than a documented rule.

**Acceptance Test:**

```bash
grep -n "derive" CLAUDE.md | head                       # rule present
grep -c "v1.12\|v1.13\|v1.21" docs/RULE_RATIONALE.md    # lineage cited
./scripts/gate_fast.sh                                  # PASS
```

---

## What NOT to Do

- **Do not fix only `claim_roadmap_version.py`.** It is the one the issue names
  and the one that blocks `/plan`, but two other scripts share the assumption.
  Shipping one is the v1.13 mistake exactly — that spec had to fix a third script
  the issue never mentioned rather than leave it quietly broken.
- **Do not write a second parse in `sed` for the shell script.** Two
  implementations of one rule is the mechanism this spec exists to remove. Call
  the Python helper.
- **Do not constrain the parse to hosts matching `github`.** It looks safer and
  it breaks GitHub Enterprise on a custom domain. The parse is host-agnostic by
  design; the accepted cost is that a non-GitHub remote fails at `gh api` instead
  of at parse time, which Change 3's error message accounts for.
- **Do not keep `.git`-stripping inside the regex.** Doing it as a separate
  prefix step is what lets a repo name contain dots — the second latent bug, and
  free to fix here.
- **Do not unify the three scripts' failure behavior.** One raises, one degrades
  to SKIP/exit 2, one errors and exits 2. Each is deliberate and its callers
  depend on it; `check_version_collision.py`'s degrade-rather-than-pass is itself
  the fix from an earlier incident.
- **Do not remove or weaken `VERSION_GUARD_REPO_SLUG`.** SQRL is running on it
  right now as an approved workaround. It stays until they remove it, and the
  test-only warning stays with it.
- **Do not change the shape guard in `check-phase-milestones.sh:96` to be
  cleverer.** With the parse returning empty on failure, the existing guard is
  correct; it only ever looked broken because a bad value was reaching it.
- **Do not import the helper via a cwd-relative path.** These scripts run by
  absolute path from other projects' directories. Resolve off `__file__` /
  `BASH_SOURCE`.
- **Do not bump the consumer template's pin** (`dev-platform-gate.yml:44`, on
  `@v1.12`). Consumers pick this up on their own next bump; changing their pin
  from here would be a cross-project write.
- **Do not file or close issue #77 from this session.** Post-merge closes it.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scripts/lib/repo_slug.py` | New | Host-agnostic `parse_repo_slug()` + CLI entry point; never raises |
| `scripts/claim_roadmap_version.py` | Modify | `_repo_slug()` imports the shared parse; override and `RuntimeError` behavior unchanged |
| `scripts/check_version_collision.py` | Modify | Same; override and `None`/degrade behavior unchanged |
| `scripts/check-phase-milestones.sh` | Modify | `HERE` anchor, calls the helper instead of `sed`, error messages name parsing and unreachable-repo causes |
| `tests/repo-slug/run.sh` | New | ~11 assertions over the URL-shape table + CLI exit codes |
| `tests/version-collision/run.sh` | Modify | Alias-remote regression: must not print the "could not determine owner/repo" SKIP |
| `tests/phase-milestones/run.sh` | Modify | Alias remote reaches `gh` as a real slug; garbage origin exits 2 naming the URL |
| `CLAUDE.md` | Modify | Rule: sweep every script sharing a derivation, or extract one helper |
| `docs/RULE_RATIONALE.md` | Modify | v1.12 → v1.13 → v1.21 lineage |
| `ROADMAP.md`, `planning.md` | Modify | v1.21 entry (handled by `/code`'s doc step) |

No `.gitignore`, `install.sh`, or `verify.sh` changes are needed — verified during
planning: `.gitignore:63` (`!scripts/*.sh`) and the existing `scripts/lib/`
precedent (`docs_only_diff.sh`) cover the new file, `install.sh` has no `scripts`
deploy category, and `gate_fast.sh` auto-discovers the new test suite. Confirm
`git check-ignore -v scripts/lib/repo_slug.py` at implementation time, since the
allow-rule is `!scripts/*.sh` and this is a `.py` file in a subdirectory —
**this is the one consumer-audit item that could genuinely bite.**

## Implementation Order

1. **Change 1** — the shared parse. Everything depends on it.
2. **Change 2** — the two Python callers. Verify the alias case against a real
   throwaway repo, not just the parser.
3. **Change 3** — the shell caller, including both error messages.
4. **Change 4** — tests. Run `./scripts/gate_fast.sh` here and confirm the count
   moved from 293.
5. **Change 5** — the rule and its rationale. Last, so it describes shipped work.

## Verification Checklist

- [ ] `git check-ignore -v scripts/lib/repo_slug.py` shows the file is NOT ignored
- [ ] All nine URL shapes from Change 1's table return the documented result
- [ ] `claim_roadmap_version.py` resolves an alias remote instead of raising
- [ ] `check_version_collision.py` on an alias remote does NOT print `SKIP: could not determine owner/repo from origin remote`
- [ ] `check-phase-milestones.sh` on an alias remote queries `Osigin-LLC/SQRL`, not the raw URL
- [ ] `check-phase-milestones.sh` on a garbage remote exits 2 with a message naming the URL and `--repo`
- [ ] `VERSION_GUARD_REPO_SLUG` still overrides in both Python scripts, warning intact
- [ ] Every previously-working URL shape still resolves identically (no regression on plain `github.com`)
- [ ] A dotted repo name (`owner/my.repo.git`) resolves — it does not today
- [ ] Both Python scripts still run correctly when invoked by absolute path from another project's cwd
- [ ] `./scripts/check-phase-milestones.sh` and `check_version_collision.py` still behave identically in dev-platform itself (plain `github.com` remote)
- [ ] `bash tests/repo-slug/run.sh`, `tests/version-collision/run.sh`, `tests/phase-milestones/run.sh` — all PASS
- [ ] `./scripts/gate_fast.sh` — PASS, count up from 293
- [ ] `CLAUDE.md` rule and `docs/RULE_RATIONALE.md` lineage present
- [ ] Markdown: blank line after headings, fenced blocks tagged with a language
