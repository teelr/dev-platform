# v1.38: Pinned Harness Install Standard

## Coding Specification for Implementation

## Design Philosophy

Issue #122 (filed from `teelr/kermit-v3#722`) asked dev-platform to decide the install
strategy for the shared `kermit` conda env: pinned wheel vs. editable vs. per-project
envs. Rich chose pinned wheel/sdist in this session's conversation on 2026-09-17. This
spec ships the piece of that decision dev-platform can actually write — a documented
standard — and files the one concrete unblocking ask as a post-merge step. It does not
touch any file under `projects/` (the no-cross-project-writes rule): the harness itself
and each consumer act on their own follow-on from their own sessions.

**Verified state of the problem, 2026-09-17:**

- The shared `kermit` conda env installs `kermit-harness` **editable**, against the live
  sibling checkout at `/home/rich/dev/projects/kermit`, via `pip install -e
  /home/rich/dev/projects/kermit` — run by hand as part of each consumer's own pin-bump
  survey, never by an automated script (verified: `kermit-v3/docs/roadmap.md:372`
  documents this exact command as "editable install — not on PyPI").
- Every active consumer declares its own pin in `pyproject.toml`, but the three pin
  styles differ and none of them constrain what's actually *installed* — only what's
  *declared*:
  - `kermit-v3` exact-pins: `kermit-harness==4.167.0` (verified:
    `projects/kermit-v3/pyproject.toml:11`).
  - `keystone` range-pins: `kermit-harness>=4.105.2,<5.0.0` (verified:
    `projects/keystone/pyproject.toml:11`).
  - `kermit-pa` (frozen, superseded by `kermit-v3`) range-pins with extras:
    `kermit-harness[audio,bm25,reranker,documents]>=4.91.0,<5.0.0` (verified:
    `projects/kermit-pa/pyproject.toml:52`).
- `teelr/kermit-harness` already cuts a Release on nearly every commit — 10 releases,
  `v4.158.0` through `v4.167.0`, over roughly two days (verified: `gh release list
  --repo teelr/kermit-harness --limit 10`), automated by its own `make release
  VERSION=X.Y.Z` target (verified: `projects/kermit/Makefile:452-487`, which runs `gh
  release create` / `gh release edit` with changelog-derived notes) — but **attaches no
  build artifact to any of them** (verified: `gh release view --repo teelr/kermit-harness
  --json assets` on `v4.167.0` returns `"assets": []`). There is currently nothing
  installable *except* the live tree.
- Measured cost, from issue #122 and a live cross-session report received the same day
  this spec was written: three harness releases in about a day each turned every live
  `kermit-v3` session's gate red simultaneously, with no change from that session; two
  sessions independently started the same fix before noticing the duplication; the
  identical drift then hard-blocked a real `kermit-v3` prod-deploy build the same day
  (the shared checkout had already moved to `4.167.0` while `pyproject.toml` still
  pinned `4.165.0`; fixed by a pin bump `4.165.0` → `4.167.0`).
- `kermit-v3` and `keystone` have each already built their *own* mitigation, but only for
  the deploy path: both `scripts/prod-deploy.sh` independently run `pip wheel
  "${KERMIT_SRC}" --no-deps` against the same sibling checkout at deploy time (verified:
  `projects/kermit-v3/scripts/prod-deploy.sh:65-69`,
  `projects/keystone/scripts/prod-deploy.sh:10-17`). That duplicated logic protects only
  the prod image build; the shared **dev** env — where the gate actually goes red — stays
  unpinned regardless.

**Why per-project envs alone don't work:** an editable install against the SAME sibling
checkout stays live no matter how many conda envs point at it — decoupling requires a
pinned artifact, not more envs. That's why the decision landed on pinned wheel/sdist
rather than the third option issue #122 listed.

**Scope boundary:** dev-platform ships the standard (this spec's one Change). The
concrete unblocking step — the harness attaching a build artifact to `make release` — is
filed as the sanctioned upstream ask (`docs/CROSS-REPO-COMMS.md`'s existing Procedure) on
`teelr/kermit-harness`, from this session, **post-merge**, not as a spec Change (it is a
`gh issue create` call against another repo, not a file edit, and per the "Executing
actions with care" rule it gets a heads-up and a pause before it runs, same as any other
bespoke post-merge action). Each consumer's own switch-over — new dev-env install
command, retiring its own ad hoc deploy-time wheel build — is deliberately NOT filed yet:
there is nothing to switch to until the harness ships an asset, and filing that ask now
would repeat the exact "asked before it was real" mistake `v1.26`'s own record already
corrected.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `docs/CROSS-REPO-COMMS.md` addition | Markdown (documentation) | Matches every existing standard doc in this repo. This phase ships zero executable code and no new component — the Language Architecture Matrix has nothing to evaluate here, the same shape as v1.15/v1.16/v1.29/v1.33 (instruction/doc-only phases). |

## Overview

1. **Phase 1: Ship the standard** — extend `docs/CROSS-REPO-COMMS.md` with the pinned-wheel
   install decision, the verified problem, and the split between what dev-platform ships
   and what each other repo's own session does (Change 1).

**Demo:** `grep -n "Runtime install: pinned wheel" docs/CROSS-REPO-COMMS.md` finds the new
section; before this spec, `docs/CROSS-REPO-COMMS.md` has no mention of the shared conda
env's install mechanism at all.

---

## Phase 1: Ship the Standard

### Change 1: `docs/CROSS-REPO-COMMS.md` — document the pinned-wheel install standard

**Problem:** `docs/CROSS-REPO-COMMS.md` already documents two halves of cross-repo
communication for `teelr/kermit-harness` — consumers filing asks inbound, and the
harness announcing versions outbound via Releases. Neither covers a third thing: how the
package the Release announces actually reaches a consumer's Python environment. Today
the answer is "it doesn't — the shared env stays on the live tree" — undocumented,
and the reason issue #122 had to ask.

**File:** `docs/CROSS-REPO-COMMS.md` (existing, 178 lines)

**Implementation:**

Insert a new top-level section immediately after line 157 (the sentence ending "...the
section below tracks current state.") and before line 159's `## Migration status`
heading — i.e., in the blank-line gap at line 158. Insert this whole block (blank lines
included, matching the file's existing spacing convention of one blank line before and
after every heading):

```markdown
## Runtime install: pinned wheel, not the live tree

A third case, distinct from both halves above. Inbound is "a consumer files an issue."
Outbound is "the dependency cuts a Release and consumers watch/Dependabot for it."
Neither covers **how the package actually reaches a consumer's Python environment** —
and for the one dependency this applies to today (`teelr/kermit-harness`), the current
answer defeats every pin any consumer declares.

### The problem (verified 2026-09-17)

Every active consumer of `teelr/kermit-harness` shares one conda env (`kermit`) on the
dev box, and that env installs the harness **editable**, against the live sibling
checkout at `/home/rich/dev/projects/kermit`:

```bash
pip install -e /home/rich/dev/projects/kermit
```

— run by hand as part of each consumer's own pin-bump survey (e.g.
`kermit-v3/docs/roadmap.md:372`, "editable install — not on PyPI"), never by an
automated script. Because it is editable, `import kermit_harness` resolves to whatever
that one checkout currently has on disk, **regardless of what version any consumer
declared** in its own `pyproject.toml`:

- `kermit-v3` exact-pins (`pyproject.toml:11`: `kermit-harness==4.167.0`)
- `keystone` range-pins (`pyproject.toml:11`: `kermit-harness>=4.105.2,<5.0.0`)
- `kermit-pa` (frozen) range-pins with extras (`pyproject.toml:52`:
  `kermit-harness[audio,bm25,reranker,documents]>=4.91.0,<5.0.0`)

None of the three pins constrain what's actually *installed* — only what's *declared*.
The harness cuts a Release on nearly every commit already (10 releases,
`v4.158.0`–`v4.167.0`, over roughly two days — `gh release list --repo
teelr/kermit-harness`), automated by its own `make release VERSION=X.Y.Z`
(`Makefile:452-487`, which runs `gh release create` / `gh release edit`) — but
**attaches no build artifact to any of them** (`gh release view --repo
teelr/kermit-harness --json assets` on `v4.167.0` returns `"assets": []`). There is
nothing to install *except* the live tree.

Measured cost (issue #122, and a live cross-session report the same day this spec was
written): three harness releases in about a day each turned every live `kermit-v3`
session's gate red simultaneously; two sessions independently started the same fix
before noticing the duplicate work; the identical drift then hard-blocked a real
`kermit-v3` prod-deploy build (the shared checkout had already moved to `4.167.0` while
`pyproject.toml` still pinned `4.165.0`). `kermit-v3` and `keystone` have each
independently built their *own* mitigation for the deploy path only — both
`scripts/prod-deploy.sh` run `pip wheel "${KERMIT_SRC}" --no-deps` against the same
sibling checkout at deploy time — duplicated logic that still leaves the shared **dev**
env unpinned, which is where the gate actually goes red.

### The decision

Pinned wheel/sdist, over an editable tree or per-project conda envs. Per-project envs
alone would not decouple anything — an editable install against the SAME sibling
checkout is live regardless of how many envs point at it. A pinned artifact is the only
option where each consumer's env, not just its deploy build, installs one version and
stays there until it deliberately reinstalls.

**Target shape:** `teelr/kermit-harness` attaches a wheel (and sdist) to every Release
it already cuts — it already declares a `hatchling` build backend
(`pyproject.toml:329-331`), so `python -m build` needs no new packaging config, only a
step that runs it and uploads the result (`gh release upload`). Each consumer's shared
dev env then installs its own pinned version directly from that Release asset instead
of the live tree — e.g. `pip install
https://github.com/teelr/kermit-harness/releases/download/vX.Y.Z/kermit_harness-X.Y.Z-py3-none-any.whl`
(pip installs directly from a URL to a wheel; no package index required) — and each
consumer's deploy script can install the same published artifact instead of rebuilding
its own wheel from source at deploy time.

**Open question for the harness's own session, not resolved here:** the Makefile also
builds a Rust component (`cargo build --release`, line 438, `services/wiki-processor`) —
whether that ships inside the same installable wheel or as a separate artifact
determines the wheel's platform tag, and is not something a read-only pass from outside
that repo can determine.

### What dev-platform ships vs. what each repo does

Same split as the outbound standard above: dev-platform ships this decision and standard
(this section). It does not build the wheel, does not edit `teelr/kermit-harness`'s
`Makefile`, and does not touch any consumer's `prod-deploy.sh` or env-setup script — per
the no-cross-project-writes rule. The concrete unblocking step (attach the build
artifact to `make release`) is filed as the sanctioned upstream ask on
`teelr/kermit-harness`, from this session, post-merge. Each consumer switching its own
dev-env install command — and retiring its own ad hoc deploy-time wheel build once an
asset exists to install instead — is that consumer's own follow-on decision, filed only
once there is something to switch to.
```

Then, in the existing `## Migration status` list, add one new bullet immediately after
the line `- **Only open item:** Keystone applies its \`consumer:keystone\` label on its
next actual harness ask (the label exists; it is just unused so far).` and before the
`- The legacy \`tasks/communique-to-*\` files...` bullet:

```markdown
- **Pinned wheel install — DECIDED** (v1.38, issue #122): the harness cuts Releases but
  attaches no build assets, so the shared dev conda env still installs editable off the
  live sibling checkout. The upstream ask (attach a wheel/sdist to `make release`) is
  filed post-merge against `teelr/kermit-harness`; each consumer's own switch-over is
  deferred until that asset exists.
```

**Acceptance Test:**

```bash
grep -n "^## Runtime install: pinned wheel, not the live tree" docs/CROSS-REPO-COMMS.md
grep -n "issue #122" docs/CROSS-REPO-COMMS.md
grep -n "Pinned wheel install — DECIDED" docs/CROSS-REPO-COMMS.md

# Markdown Rules: blank line after every heading — spot-check the new section
grep -A1 "^## Runtime install: pinned wheel, not the live tree" docs/CROSS-REPO-COMMS.md | tail -1
# expect: blank line

bash scripts/gate_fast.sh
# docs-only diff vs. main — skips the test-suite loop, taxonomy/structural checks still run
bash scripts/check_spec_taxonomy.sh
```

---

## What NOT to Do

- **Do not file per-consumer switch-over issues in this spec.** There is nothing for
  `kermit-v3`, `keystone`, or `kermit-pa` to switch to until `teelr/kermit-harness`
  actually ships a build asset — filing that ask now repeats the exact "asked before it
  was real" mistake `v1.26`'s own corrected record already made once.
- **Do not assume a uniform pin style across consumers.** `kermit-v3` exact-pins;
  `keystone` and `kermit-pa` range-pin. The standard must describe "each consumer
  installs the version its own pin resolves to," not "the exact version," or it
  silently misdescribes two of the three consumers.
- **Do not name an exact wheel filename/platform tag as settled fact.** The harness's
  Makefile also builds a Rust component; whether it ships inside the Python wheel or as
  a separate artifact is an open question for the harness's own session, not something
  to assert here.
- **Do not edit anything under `projects/`.** This spec verifies against the real
  `kermit`, `kermit-v3`, `keystone`, and `kermit-pa` checkouts read-only (the Scope rule
  permits read-only cross-project operations); it ships entirely in
  `docs/CROSS-REPO-COMMS.md`.
- **Do not build or upload anything from this session.** No wheel, no `gh release
  upload` — that is the harness's own follow-on work once the ask is filed and it plans
  its own spec.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `docs/CROSS-REPO-COMMS.md` | Modify | New "Runtime install: pinned wheel, not the live tree" section + one `Migration status` bullet |
| `tasks/pinned-harness-install-standard-spec.md` | (this file) | Spec |

## Implementation Order

1. **Change 1** — the only Change. Single doc edit, single commit, single branch/PR.

**Post-merge (bespoke — needs a heads-up and a pause before running, not auto-run):**

- File the upstream ask: `gh issue create --repo teelr/kermit-harness --title
  "[dev-platform] Attach a wheel+sdist build to every Release" --label enhancement
  --body <symptom (verified assets: [] on v4.167.0) · why (shared dev env has nothing
  pinned to install) · ask (add a python -m build + gh release upload step to \`make
  release\`, Makefile:452-487) · consumer status (dev-platform standard merged, see
  docs/CROSS-REPO-COMMS.md) · link back to teelr/dev-platform#122>`, using a
  `consumer:*`-style label if one fits, per `docs/CROSS-REPO-COMMS.md`'s existing
  Procedure.
- Comment on/close issue #122 pointing at the merged doc section and the new upstream
  issue.
- Do NOT file anything against `kermit-v3`, `keystone`, or `kermit-pa` yet.

## Verification Checklist

- [ ] `docs/CROSS-REPO-COMMS.md` contains the new "Runtime install: pinned wheel, not the
      live tree" section, inserted between the outbound section and `## Migration
      status`
- [ ] New section cross-references issue #122
- [ ] `Migration status` gains the new "Pinned wheel install — DECIDED" bullet
- [ ] Blank line after every new heading (Markdown Rules)
- [ ] `bash scripts/gate_fast.sh` passes
- [ ] `bash scripts/check_spec_taxonomy.sh` passes
- [ ] No file under `projects/` modified
- [ ] Spec deviations (if any) explicitly flagged at `/code` time

## Out of Scope (Future Specs)

- **Actually adding the wheel-build-and-upload step to `teelr/kermit-harness`'s `make
  release`** — the harness's own `/plan` + `/code`, once the upstream issue is filed and
  accepted.
- **Each consumer switching its dev-env install command and retiring its own ad hoc
  deploy-time wheel build** (`kermit-v3`'s and `keystone`'s `prod-deploy.sh` `pip wheel
  "${KERMIT_SRC}"` steps) — each consumer's own follow-on decision, filed only once an
  asset exists to install.
- **`kermit-pa`** — frozen, superseded by `kermit-v3`; not a target for switch-over asks
  regardless of asset availability.
