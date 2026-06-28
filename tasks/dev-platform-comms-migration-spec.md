# v1.5: Cross-Repo Comms Migration

## Coding Specification for Implementation

> Finishes the cross-repo comms migration tracked in `teelr/dev-platform#34`.
> The **inbound** half (consumer→dependency asks go upstream as GitHub issues)
> shipped in #33 (`1734e8b`). This spec ships the parts that live in
> **dev-platform**: the outbound standard, the consumer-adoption artifacts, the
> delivery-enforcement checker, and the rule/doc close-out.

## Design Philosophy

Issue #34 lists four work items. Two of them — the harness actually cutting
GitHub Releases instead of fanning broadcast docs into each consumer's
`HARNESS_REPLIES_INBOX.md`, and each consumer enabling Dependabot — are
behavioral changes in **other repos**. Per the "NEVER write code in another
project's directory" rule in `CLAUDE.md`, dev-platform cannot make those
changes; they run from the harness's and each consumer's own session as
post-merge coordination. What dev-platform **can** ship, and what this spec
covers, is everything that lives in this repo: the written standard, the
copy-paste template consumers adopt, a registry, a label-setup tool, the
delivery checker, and the rule update.

The split mirrors how v0.7 and v0.8 already work. dev-platform shipped the
`dev-platform-gate.yml` consumer template and `fleet-install-template.sh`; the
actual adoption ran per-project. Here dev-platform ships a Dependabot consumer
template + the comms standard + a checker; the actual cutover runs per-repo.
Nothing in this spec writes a file under `projects/` — the label-setup and
delivery-check tools only **read** consumer files and call the GitHub API
(`gh label create`, `gh issue view`), which is the same sanctioned cross-repo
channel as the `gh issue create` the inbound half already uses.

One registry, `monitoring/comms-consumers.json`, serves three consumers at
once: it tells the label-setup script which `consumer:*` labels to create on
which upstream repo (items 1 + 3), and it tells the delivery checker which
consumer directories to scan and which upstream repo to verify issue
references against (item 4). This follows the `monitoring/remotes.json` (v1.1)
precedent — a small JSON registry that a Bash/Python tool reads.

The delivery checker is a standalone fleet-style tool (like `fleet-pins.sh`),
**not** wired into `gate_fast.sh`: it makes network calls (`gh`) and scans
`projects/` paths that may not all be cloned. Its **test suite** is wired into
the gate via auto-discovery, running fully offline against a mock `gh` binary
and a `mktemp` communique tree — the same mock-binary pattern v0.6 used for
`code`.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `monitoring/comms-consumers.json` | JSON | Machine-readable registry; consistent with `monitoring/{projects,remotes}.json` |
| `monitoring/comms_delivery.py` | Python | Markdown parsing + regex issue-ref extraction + `gh` orchestration + JSON. Glue/tooling → Python first per the matrix; matches `monitoring/{fleet_dashboard,fleet_pins}.py` precedent. Not network- or compute-intensive (a handful of `gh` calls). |
| `scripts/check-comms-delivery.sh` | Bash | Thin wrapper that `exec`s the Python module — mirrors `fleet-status.sh` → `fleet_dashboard.py` |
| `scripts/setup-consumer-labels.sh` | Bash | Process flow + `gh label create` CLI calls + Python3 inline for registry parse — same shape as `verify-remotes.sh` |
| `tests/comms-delivery/run.sh`, `tests/comms-labels/run.sh` | Bash | All test runners are Bash per the v0.4 auto-discovery contract; use `tests/helpers/assert.sh` |
| `docs/CROSS-REPO-COMMS.md`, `extensions/github-actions/dependabot-consumer-template.yml` | Markdown / YAML | Documentation + copy-paste consumer template |

## Overview

**Phase 1 — Outbound standard + consumer-adoption artifacts**

1. Change 1 — Rewrite the "Outbound" section of `docs/CROSS-REPO-COMMS.md` into the actual standard (GitHub Releases + Dependabot/Renovate; deprecate the broadcast-doc relay)
2. Change 2 — Add `extensions/github-actions/dependabot-consumer-template.yml` (copy-paste Dependabot config consumers adopt) + adoption note in the doc
3. Change 3 — Create `monitoring/comms-consumers.json` (consumer → upstream repo, dep-slug, label)
4. Change 4 — Create `scripts/setup-consumer-labels.sh` (idempotent `gh label create` from the registry, dry-run default) + `tests/comms-labels/run.sh`

**Phase 2 — Delivery enforcement (item 4)**

5. Change 5 — Create `monitoring/comms_delivery.py` + `scripts/check-comms-delivery.sh` (scan post-cutover ask-communiques, verify each links an existing upstream issue)
6. Change 6 — Create `tests/comms-delivery/run.sh` (offline fixture suite, mock `gh`)

**Phase 3 — Rule + close-out**

7. Change 7 — Update `CLAUDE.md` comms rule + `README.md` + `planning.md` + `ROADMAP.md`; mark the migration complete

---

## Phase 1: Outbound standard + consumer-adoption artifacts

### Change 1: Define the outbound standard in `docs/CROSS-REPO-COMMS.md`

**Problem:** The doc's "Outbound from the dependency" section (lines ~78-84)
is a stub — it says outbound migration is "a separate, larger change" and
"this document governs the inbound ask direction." Item 2 of #34 is to define
that outbound direction: dependency announces versions via GitHub Releases +
release notes; consumers watch the repo / run Dependabot or Renovate — instead
of the harness hand-writing broadcast docs into each consumer's
`HARNESS_REPLIES_INBOX.md`.

**File:** `docs/CROSS-REPO-COMMS.md` (existing, replace the section at ~line 78)

**Implementation:**

Replace the existing stub section with a full standard. Keep the plain-language
rule (`CLAUDE.md` "Plain Language") — no coined names, no marketing adjectives.
The replacement section MUST cover:

- **Transport:** the dependency cuts a **GitHub Release** per version with
  release notes (what changed, new primitives, breaking changes, the pin to
  bump to). The Release is the source of truth for "a new version exists" —
  the mirror of "filing an issue is delivery" on the inbound side.
- **Consumer pull, not dependency push:** consumers learn about versions by
  (a) watching the upstream repo's Releases, and/or (b) running Dependabot or
  Renovate against their pin. No hand-written broadcast doc is relayed into a
  consumer inbox.
- **Deprecation:** the `HARNESS_REPLIES_INBOX.md` broadcast-doc relay is
  deprecated as a transport for the same reason the inbound file-relay was —
  it is lossy and requires a manual copy step. Existing
  `HARNESS_REPLIES_INBOX.md` files remain as a historical receipt trail; they
  are no longer how a consumer learns a version shipped.
- **What stays local:** a consumer's per-version adoption notes (which pin it
  moved to, what it had to change) stay in that consumer's own repo as
  receipts — they are not the transport.
- **Adoption pointer:** reference the Dependabot template added in Change 2
  (`extensions/github-actions/dependabot-consumer-template.yml`) and note it is
  opt-in per consumer.

Add a short "what dev-platform ships vs. what each repo does" note so a reader
does not mistake the doc for a claim that the cutover already happened: the
standard + template live here; the harness cutting Releases and each consumer
enabling Dependabot are per-repo steps.

Update the "Migration status" section: mark the outbound standard as
**defined (this Roadmap Phase)** and list the per-repo cutover as the
remaining coordination work, with a pointer to `tasks/` post-merge steps.

**Acceptance Test:**

```bash
grep -q "GitHub Release" docs/CROSS-REPO-COMMS.md
grep -qi "dependabot\|renovate" docs/CROSS-REPO-COMMS.md
grep -qi "deprecated" docs/CROSS-REPO-COMMS.md
grep -q "dependabot-consumer-template.yml" docs/CROSS-REPO-COMMS.md
# Honesty: the doc must NOT claim the harness already stopped broadcasting.
! grep -qiE "harness (now|already) (cuts|publishes) releases" docs/CROSS-REPO-COMMS.md
```

Markdownlint: blank line after every heading; fenced blocks specify a language.

---

### Change 2: Dependabot consumer template

**Problem:** Consumers need a copy-paste config to watch the upstream repo for
version bumps — the outbound equivalent of the existing
`extensions/github-actions/dev-platform-gate.yml` consumer template. Without a
template, "use Dependabot" is advice with no artifact.

**File:** `extensions/github-actions/dependabot-consumer-template.yml` (new file)

**Implementation:**

A minimal, commented Dependabot v2 config a consumer drops into its repo at
`.github/dependabot.yml`. It must:

- Be valid Dependabot v2 (`version: 2`, `updates:` list).
- Include a leading comment block stating: this is a copy-paste template from
  `teelr/dev-platform`; copy it to `.github/dependabot.yml` in the consumer
  repo; it is opt-in; adjust the `package-ecosystem` / `directory` to match the
  consumer's stack (e.g. `pip` for kermit-pa/keystone-python, `npm` for OPIE).
- Include a worked example for the common case (a Python consumer pinned to a
  PyPI/Git dependency) plus a commented `github-actions` ecosystem block (so
  the consumer also gets bumped when the `dev-platform-gate.yml` pin moves).
- NOT reference Rich-only absolute paths or a specific machine.

Because this is a **template** (not active config in dev-platform itself),
place it under `extensions/github-actions/` alongside the existing consumer
template — do NOT put it at `.github/dependabot.yml` in dev-platform (that
would make dev-platform itself run it, which is out of scope for this spec).

**Consumer Audit** (new `.yml` under `extensions/github-actions/`):

```bash
git check-ignore -v extensions/github-actions/dependabot-consumer-template.yml
# expect: NO output (not ignored). dev-platform-gate.yml already lives here,
# so the .gitignore allow-list already covers extensions/**/*.yml — confirm.
```

If `git check-ignore` shows it IS ignored, add the matching `!extensions/**/*.yml`
re-include (mirror whatever rule already admits `dev-platform-gate.yml`).

**Acceptance Test:**

```bash
python3 -c "import yaml,sys; d=yaml.safe_load(open('extensions/github-actions/dependabot-consumer-template.yml')); assert d['version']==2; assert isinstance(d['updates'],list) and d['updates']; print('valid dependabot v2')"
# If pyyaml is unavailable in the env, fall back to a structural grep:
grep -q "version: 2" extensions/github-actions/dependabot-consumer-template.yml
grep -q "package-ecosystem" extensions/github-actions/dependabot-consumer-template.yml
git check-ignore -q extensions/github-actions/dependabot-consumer-template.yml && echo "IGNORED — fix .gitignore" || echo "tracked OK"
```

---

### Change 3: Consumer registry `monitoring/comms-consumers.json`

**Problem:** Both the label-setup script (Change 4) and the delivery checker
(Change 5) need the same facts: which projects file asks against which upstream
repo, what their `consumer:*` label is, and which directory to scan. Encode it
once.

**File:** `monitoring/comms-consumers.json` (new file)

**Implementation:**

Schema per entry:

- `consumer` — project name (matches the `projects/<name>` basename)
- `path` — path relative to `~/dev`
- `dep_slug` — the slug used in the `communique-to-<slug>-…` filename for asks
  to this dependency (today: `harness`)
- `upstream_repo` — `<owner>/<repo>` the asks are filed against
- `label` — the `consumer:*` label to create on `upstream_repo`
- `active` — `true` for projects that currently file asks; `false` for
  deprecated ones (atlas). The checker SKIPs inactive; the label script still
  creates the label (labels are cheap; historical atlas asks exist).

```json
[
  {
    "consumer": "kermit-pa",
    "path": "projects/kermit-pa",
    "dep_slug": "harness",
    "upstream_repo": "teelr/kermit-harness",
    "label": "consumer:pa",
    "active": true
  },
  {
    "consumer": "keystone",
    "path": "projects/keystone",
    "dep_slug": "harness",
    "upstream_repo": "teelr/kermit-harness",
    "label": "consumer:keystone",
    "active": true
  },
  {
    "consumer": "atlas",
    "path": "projects/atlas",
    "dep_slug": "harness",
    "upstream_repo": "teelr/kermit-harness",
    "label": "consumer:atlas",
    "active": false
  }
]
```

**Consumer Audit:**

```bash
git check-ignore -v monitoring/comms-consumers.json
# expect: NO output. monitoring/**/*.json allow-listed since v0.5 Phase 1.
```

**Acceptance Test:**

```bash
python3 -c "import json; d=json.load(open('monitoring/comms-consumers.json')); assert len(d)==3; assert {p['label'] for p in d}=={'consumer:pa','consumer:keystone','consumer:atlas'}; assert [p for p in d if p['consumer']=='atlas'][0]['active'] is False; print('registry OK')"
```

---

### Change 4: `scripts/setup-consumer-labels.sh` + test

**Problem:** Item 1 (and the label half of item 3) — the upstream repo needs
`consumer:pa` / `consumer:keystone` / `consumer:atlas` labels so asks are
sortable by consumer. The pilot issue #200 currently has only `bug`. This
should be a repeatable, idempotent tool, not a one-off `gh` command, and it
must be safe to dry-run.

**File:** `scripts/setup-consumer-labels.sh` (new file)

**Implementation:**

Reads `monitoring/comms-consumers.json`, derives the unique set of
`(upstream_repo, label)` pairs, and creates each label on its upstream repo via
`gh label create`. Contract:

- **Dry-run by default.** Prints the `gh label create` commands it would run.
  `--apply` actually runs them. (Same dry-run-default posture as
  `fleet-install-template.sh` and `sync-milestones.sh`.)
- **Idempotent.** Use `gh label create <label> --repo <repo> --color <hex>
  --description "<desc>" --force` — `--force` updates the label if it already
  exists instead of erroring, so re-running is safe.
- Flags: `--apply`, `--registry <path>` (test override), `--repo <name>`
  (restrict to one upstream repo), `--help`.
- One fixed color + description for all `consumer:*` labels (e.g. color
  `0e8a16`, description `"Ask filed by the <consumer> consumer"` — derive the
  consumer name from the label suffix).
- Resolve `$REPO` from `BASH_SOURCE[0]` (no hardcoded `/home/rich`).
- **gh availability:** if `command -v gh` fails, print a clear message and exit
  2 (not 0, not 1) under `--apply`; under dry-run, still print the intended
  commands and exit 0 (dry-run needs no gh).

Structure follows `scripts/verify-remotes.sh`: Python3-inline registry parse
emitting TSV (`label\tupstream_repo`), `while IFS=$'\t' read` loop, arg parsing
`case` block.

**This is a coordination tool, not a code change to the harness.** It calls the
GitHub **label API** on the upstream repo; it never clones, checks out, or
edits a file in `projects/kermit/`. Running it (`--apply`) is a post-merge
coordination step (see post-merge). Flag this framing at `/code` intake so the
user can confirm the label-creation-via-API approach before it ships.

**File:** `tests/comms-labels/run.sh` (new file) — mock-`gh` suite.

Use the v0.6 mock-binary pattern: a `tests/comms-labels/fixtures/mock-bin/gh`
script (extension-less) that records its args to `$MOCK_GH_LOG` and exits 0.
The runner sets `PATH="${MOCK_BIN}:${PATH}"`. Assertions (use
`tests/helpers/assert.sh`):

| # | Description | Expected |
|---|-------------|----------|
| 1 | `bash -n` syntax clean | exit 0 |
| 2 | `--help` renders | output contains "setup-consumer-labels" |
| 3 | Dry-run (default) prints intended labels, calls `gh` 0 times | `$MOCK_GH_LOG` empty / absent; output names all 3 labels |
| 4 | `--apply` calls `gh label create` once per unique label | `$MOCK_GH_LOG` has 3 `label create` lines, each with `--force` |
| 5 | `--apply --repo teelr/kermit-harness` only targets that repo | all logged calls `--repo teelr/kermit-harness` |
| 6 | `--registry <mock>` honored | labels from the mock registry, not the real one |

**Consumer Audit for the mock binary** (extension-less file under `tests/`):

```bash
git check-ignore -q tests/comms-labels/fixtures/mock-bin/gh && echo "IGNORED — add re-include" || echo "tracked OK"
# v0.6 added `!tests/**/mock-bin/*` for exactly this (the mock `code` binary).
# Confirm it covers mock-bin/gh; if not, extend the allow-list.
```

**Acceptance Test:**

```bash
bash tests/comms-labels/run.sh         # expect: all PASS
./scripts/setup-consumer-labels.sh     # dry-run: prints 3 labels, runs no gh
./scripts/setup-consumer-labels.sh --help
bash -n scripts/setup-consumer-labels.sh
```

---

## Phase 2: Delivery enforcement (item 4)

### Change 5: `monitoring/comms_delivery.py` + `scripts/check-comms-delivery.sh`

**Problem:** Item 4 — the inbound rule ("file the ask as a GitHub issue") is
advisory. The 2026-06-28 failure mode (PA's OllamaAdapter ask filed locally but
never delivered, while the harness reported "no open PA asks") is exactly what
a checker prevents: confirm that every ask-communique written after the
migration adoption actually links to a real upstream issue.

**File:** `monitoring/comms_delivery.py` (new file)

**Implementation:**

A stdlib-only Python module (mirror `monitoring/fleet_pins.py` structure:
argparse CLI, functions, `if __name__ == "__main__"`). Logic:

1. **Load registry** (`--registry`, default `monitoring/comms-consumers.json`).
2. For each **active** consumer (skip `active: false`), resolve `<path>` against
   the repo root. If the path or its `tasks/` dir is missing → record `SKIP`
   (consumer not cloned on this machine) — never FAIL.
3. **Find ask-communiques:** glob `<path>/tasks/communique-to-<dep_slug>-*.md`.
   Parse a `YYYY-MM-DD` date out of the filename. Classify:
   - date **<** `--since` (default `2026-06-28`, the adoption date) → `SKIP (legacy)`
   - no parseable date in the filename → `SKIP (legacy, undated)`
   - date **>=** `--since` → an in-scope ask that MUST link a live issue
4. **Extract issue refs** from each in-scope file's text. Match, for the entry's
   `upstream_repo` = `<owner>/<repo>`:
   - full URL: `https://github.com/<owner>/<repo>/issues/(\d+)`
   - org shorthand: `<owner>/<repo>#(\d+)`
   - repo-name shorthand: `<repo>#(\d+)` (e.g. `kermit-harness#200`)
   - bare `#(\d+)` (fallback)
   Collect the set of issue numbers.
5. **Classify each in-scope file:**
   - no issue ref found → **FAIL** (`undelivered: no upstream issue linked`)
   - ref found, and `verify_issue` confirms it exists → **OK**
   - ref found, `verify_issue` says it does NOT exist → **FAIL**
     (`linked issue <n> not found on <repo>`)
   - ref found, but `gh` unreachable/unauth or `--offline` → **UNVERIFIED**
     (not FAIL — don't block on network; matches "mark UNTESTED, never PASS")
6. **`verify_issue(repo, number)`** runs:
   `gh issue view <number> --repo <repo> --json number,state`
   - exit 0 → exists
   - exit non-zero with "not found"/"Could not resolve" → missing
   - `gh` absent / not authenticated / other error → unverified
   **MUST use `--json number,state`.** The bare `gh issue view <n>` form fetches
   classic-Projects fields and dies with a GraphQL "Projects (classic) is being
   deprecated" error (hit live in this repo 2026-06-28). `--json` avoids it.
7. **CLI flags:** `--registry`, `--since YYYY-MM-DD` (default `2026-06-28`),
   `--consumer <name>` (restrict to one), `--offline` (skip all `gh` calls; only
   the no-ref FAIL check runs), `--json` (machine output), `--help`.
8. **Exit code:** `1` if any **FAIL**; `0` otherwise (UNVERIFIED and SKIP do not
   fail). Print a one-line-per-file report with `OK` / `FAIL` / `UNVERIFIED` /
   `SKIP` prefixes + a summary tally.

**File:** `scripts/check-comms-delivery.sh` (new file) — thin wrapper:

```bash
#!/usr/bin/env bash
# scripts/check-comms-delivery.sh — verify every post-migration ask-communique
# links a live upstream GitHub issue. Wrapper around monitoring/comms_delivery.py.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "${REPO}/monitoring/comms_delivery.py" "$@"
```

(Exact mirror of `scripts/fleet-status.sh` → `monitoring/fleet_dashboard.py`.)

Make both executable. **Do NOT wire this into `gate_fast.sh`** — it makes `gh`
network calls and scans `projects/` paths that may not be cloned. It is a
standalone fleet-style tool like `fleet-pins.sh`. The gate gets coverage via
the offline test suite in Change 6.

**Acceptance Test:**

```bash
bash -n scripts/check-comms-delivery.sh
python3 -c "import ast; ast.parse(open('monitoring/comms_delivery.py').read()); print('parses')"
# Offline run against live tree — the no-ref check only (no gh):
./scripts/check-comms-delivery.sh --offline
# expect: exit 0 OR exit 1 with named undelivered files; SKIP for legacy + uncloned
# Single consumer:
./scripts/check-comms-delivery.sh --consumer kermit-pa --offline
# Live verify (gh reachable) — confirms the pilot links #200:
./scripts/check-comms-delivery.sh --consumer kermit-pa --since 2026-06-28
```

---

### Change 6: `tests/comms-delivery/run.sh`

**Problem:** Without a deterministic offline suite, regressions in the
extractor (regex misses `kermit-harness#200` shorthand), the date cutoff, the
direction filter, or the `gh --json` call are invisible until a live failure.

**File:** `tests/comms-delivery/run.sh` (new file)

**Implementation:**

Auto-discovered by `gate_fast.sh` (`tests/<suite>/run.sh`, not under
`fixtures/`). Builds a `mktemp` tree of mock consumer dirs + a mock registry
written inline with `${TMP}` absolute paths (the `tests/migration/run.sh`
pattern). Mock `gh` binary at `tests/comms-delivery/fixtures/mock-bin/gh`
(extension-less, v0.6 pattern) that, for `issue view <n> --repo <r> --json …`,
exits 0 with `{"number":<n>,"state":"OPEN"}` for a configured set of
"existing" issue numbers and non-zero with a "not found" message otherwise —
driven by a `$MOCK_GH_EXISTING` env var. Runner sets
`PATH="${MOCK_BIN}:${PATH}"`.

Mock communique fixtures to create under `${TMP}/projects/<consumer>/tasks/`:

- `communique-to-harness-2026-06-30-good.md` — post-cutover, links
  `teelr/kermit-harness#200` (existing) → OK
- `communique-to-harness-2026-06-30-shorthand.md` — links `kermit-harness#200`
  shorthand → OK (proves the repo-name regex)
- `communique-to-harness-2026-06-30-undelivered.md` — post-cutover, NO issue
  ref → FAIL
- `communique-to-harness-2026-06-30-deadlink.md` — links
  `kermit-harness#9999` (NOT in `$MOCK_GH_EXISTING`) → FAIL
- `communique-to-harness-2026-05-01-legacy.md` — pre-cutover → SKIP (legacy)
- `communique-to-harness-behavioral-gap.md` — undated → SKIP (legacy, undated)
- `communique-to-pa-2026-06-30-reply.md` — wrong direction (a reply TO pa, not
  an ask to `harness`) → ignored entirely (not even SKIP-counted as an ask)

Assertions (each negative test asserts exit code **and** a specific output
substring, per the lessons.md rule):

| # | Description | Expected |
|---|-------------|----------|
| 1 | `bash -n` wrapper + `ast.parse` module | both clean |
| 2 | `--help` renders | contains "comms-delivery" or "comms_delivery" |
| 3 | All-good tree → exit 0 | no `FAIL` lines |
| 4 | Undelivered (no ref) → exit 1 | output contains the filename + "no upstream issue" |
| 5 | Dead link (issue missing) → exit 1 | output contains "9999" + "not found" |
| 6 | Shorthand ref resolves | the shorthand file shows `OK`, not FAIL |
| 7 | Pre-cutover file → SKIP, not FAIL | output `SKIP` for the legacy file; exit unaffected by it |
| 8 | Undated file → SKIP | output `SKIP` for the undated file |
| 9 | Reply-direction file ignored | the `communique-to-pa-*` file appears in no OK/FAIL/SKIP ask line |
| 10 | `--offline` → dead-link becomes UNVERIFIED, no-ref still FAILs | exit 1 (the no-ref file), dead-link line shows `UNVERIFIED` not `FAIL` |
| 11 | `--consumer <name>` filters | only the named consumer's files appear |
| 12 | `active:false` consumer skipped | a deprecated entry in the mock registry yields no ask lines |

**Consumer Audit** for `tests/comms-delivery/fixtures/mock-bin/gh`: same as
Change 4 — confirm `!tests/**/mock-bin/*` admits it (`git check-ignore -q`).

**Acceptance Test:**

```bash
bash tests/comms-delivery/run.sh       # expect: 12 PASS, 0 FAIL
./scripts/gate_fast.sh                  # expect: PASS, gate count +~12 +~6 (Change 4)
```

---

## Phase 3: Rule + close-out

### Change 7: Rule + docs close-out

**Problem:** The `CLAUDE.md` comms rule (line ~166) describes only the inbound
direction and calls the outbound relay merely "deprecated as a transport" for
inbound. It should point at the now-defined outbound standard and the checker.
`README.md`, `planning.md`, and `ROADMAP.md` need the v1.5 entry.

**Files:** `CLAUDE.md` (~line 166), `README.md` (Roadmap paragraph ~line 58),
`planning.md` (In-flight / Recently-shipped), `ROADMAP.md` (new v1.5 entry)

**Implementation:**

- **`CLAUDE.md`** — extend the "Dependency asks go upstream as GitHub issues"
  bullet with one sentence: the **outbound** direction (dependency → consumers)
  uses GitHub Releases + Dependabot/Renovate, defined in
  `docs/CROSS-REPO-COMMS.md`; and note `scripts/check-comms-delivery.sh` checks
  that post-migration ask-communiques link a live issue. Keep it tight — do not
  duplicate the doc. **Do not introduce a bare review-less chain string or any
  self-matching detector text** (v1.3 hazard — not relevant here, but keep the
  edit minimal).
- **`README.md`** — add `./scripts/check-comms-delivery.sh` and
  `./scripts/setup-consumer-labels.sh` to the tools paragraph; mention the
  Dependabot consumer template alongside `dev-platform-gate.yml`.
- **`ROADMAP.md`** — add the `v1.5: Cross-Repo Comms Migration` entry following
  the existing format, with an **honest** scope line: dev-platform ships the
  outbound standard + Dependabot template + delivery checker + label tool; the
  harness cutting Releases and consumers enabling Dependabot are post-merge
  per-repo coordination, not shipped here.
- **`planning.md`** — move the in-flight block; add a hash-free "Recently
  shipped" entry (per the no-self-hash rule).

**Acceptance Test:**

```bash
grep -q "check-comms-delivery" README.md
grep -qi "release" CLAUDE.md && grep -qi "dependabot\|renovate" CLAUDE.md
grep -q "v1.5: Cross-Repo Comms Migration" ROADMAP.md
./scripts/check_spec_taxonomy.sh        # ROADMAP/planning headers still conform
./scripts/gate_fast.sh                   # full gate green
# Honesty check — ROADMAP must not claim the harness already cut over:
! grep -qiE "harness (now|already) (cuts|publishes|stopped)" ROADMAP.md
```

---

## What NOT to Do

- **Do not write any file under `projects/`.** The label tool and the checker
  only **read** consumer files and call the GitHub API. No clone, no checkout,
  no edit of the harness or any consumer repo. The harness cutting Releases and
  consumers enabling Dependabot run from those repos' own sessions (post-merge).
- **Do not claim the outbound cutover happened.** dev-platform ships the
  standard + template + tools. The harness still fans broadcast docs until its
  own session stops. Honesty rule: "designed for / defines the standard," not
  "migrated the outbound flow."
- **Do not wire `check-comms-delivery.sh` into `gate_fast.sh`.** It makes `gh`
  network calls and scans maybe-uncloned `projects/` paths. The offline test
  suite is the gate's coverage — same split as `fleet-pins.sh`.
- **Do not use the bare `gh issue view <n>` form.** It pulls classic-Projects
  fields and dies on the "Projects (classic) deprecated" GraphQL error (hit live
  2026-06-28). Always `gh issue view <n> --repo <r> --json number,state`.
- **Do not FAIL on a missing consumer path or on `gh` being unreachable.**
  Missing path → SKIP. `gh` unreachable / unauth / `--offline` → UNVERIFIED.
  Only "no issue ref at all" and "linked issue confirmed absent" are FAIL.
- **Do not enforce on pre-cutover communiques.** ~80 communique files predate
  the migration (file-relay era). Only files dated on/after `--since`
  (`2026-06-28`) are in scope; older and undated ones → SKIP (legacy).
- **Do not check the reply direction.** `communique-to-pa-*` / `…-keystone-*`
  in the harness are harness→consumer replies, not asks needing an upstream
  issue. Only `communique-to-<dep_slug>-*` (asks to the dependency) are checked.
- **Do not put `.sh` test runners or mock binaries under `fixtures/` where the
  gate would auto-run them.** Mock `gh` lives at
  `tests/<suite>/fixtures/mock-bin/gh` (extension-less, excluded by the gate's
  `*/fixtures/*` find guard); mock trees live under `mktemp`.
- **Do not add `consumer`/`upstream_repo` fields to `monitoring/projects.json`
  or `remotes.json`.** Different scopes — `comms-consumers.json` is its own
  registry (the v1.1 `remotes.json`-vs-`projects.json` split precedent).
- **Do not place the Dependabot template at dev-platform's own
  `.github/dependabot.yml`.** It is a consumer template under
  `extensions/github-actions/`, not active config for this repo.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `docs/CROSS-REPO-COMMS.md` | Modify | Replace the "Outbound" stub with the Releases + Dependabot/Renovate standard; deprecate the broadcast-doc relay; update Migration status |
| `extensions/github-actions/dependabot-consumer-template.yml` | New | Copy-paste Dependabot v2 config consumers adopt |
| `monitoring/comms-consumers.json` | New | 3-entry registry (consumer → upstream repo, dep-slug, label, active) |
| `scripts/setup-consumer-labels.sh` | New | Idempotent `gh label create` from the registry; dry-run default, `--apply` |
| `tests/comms-labels/run.sh` | New | 6-assertion mock-`gh` suite for the label tool |
| `monitoring/comms_delivery.py` | New | Scan post-cutover ask-communiques, verify each links a live upstream issue |
| `scripts/check-comms-delivery.sh` | New | Thin wrapper around `comms_delivery.py` |
| `tests/comms-delivery/run.sh` | New | 12-assertion offline fixture suite, mock `gh` |
| `CLAUDE.md` | Modify | Extend the comms rule with the outbound direction + checker pointer |
| `README.md` | Modify | Add the two new scripts + Dependabot template to the tools paragraph |
| `ROADMAP.md` | Modify | New `v1.5: Cross-Repo Comms Migration` entry |
| `planning.md` | Modify | In-flight + Recently-shipped update (hash-free) |

## Implementation Order

1. Change 3 (registry) — both tools read it; build it first.
2. Change 4 (label script + test) — depends on the registry.
3. Change 1 (doc outbound section) — independent; can run anytime in Phase 1.
4. Change 2 (Dependabot template) — referenced by Change 1's doc; build before or with Change 1.
5. Change 5 (checker + wrapper) — depends on the registry.
6. Change 6 (checker tests) — after Change 5.
7. Change 7 (rule + close-out) — last; references everything above.

Recommended branch strategy: **one branch** `v1.5/comms-migration`, not
per-Spec-Phase. The phases are tightly coupled (one registry feeds the label
tool and the checker; the doc references the template and the checker) and each
phase is well under ~150 LOC. This is the v0.6 / v1.4 "tightly coupled OR each
phase >150 LOC → single branch" carve-out. Flag the deviation at `/code` intake.

## Post-merge (coordination — NOT dev-platform code)

These finish #34's behavioral items and run from the named repo's own session:

1. **Labels (items 1, 3):** `./scripts/setup-consumer-labels.sh --apply` →
   creates `consumer:pa` / `consumer:keystone` / `consumer:atlas` on
   `teelr/kermit-harness`. Then relabel pilot issue #200 with `consumer:pa`.
2. **Outbound cutover (item 2) — from the harness's own session:** stop fanning
   broadcast docs into consumers' `HARNESS_REPLIES_INBOX.md`; cut a GitHub
   Release with notes per version going forward.
3. **Consumer adoption (items 2, 3) — from each consumer's own session:** copy
   `dependabot-consumer-template.yml` to `.github/dependabot.yml`; watch the
   harness repo; keystone/atlas add their `consumer:*` label on their next ask.
4. **Release/milestone:** `./scripts/sync-milestones.sh --apply`;
   `gh release create v1.5`; close the `v1.5` milestone; close issue #34;
   bump the consumer-template default pin if the cycle calls for it.

## Verification Checklist

- [ ] `monitoring/comms-consumers.json`: 3 entries, correct labels, atlas `active:false`, not gitignored
- [ ] `./scripts/setup-consumer-labels.sh` dry-run lists 3 labels and runs no `gh`; `--apply` (mock) calls `gh label create --force` once per label
- [ ] `bash tests/comms-labels/run.sh` → all PASS
- [ ] `extensions/github-actions/dependabot-consumer-template.yml` is valid Dependabot v2, tracked (not gitignored)
- [ ] `docs/CROSS-REPO-COMMS.md` outbound section names Releases + Dependabot/Renovate + deprecation; does not claim the cutover happened
- [ ] `monitoring/comms_delivery.py` parses; `./scripts/check-comms-delivery.sh --offline` runs; live run confirms the pilot links #200
- [ ] checker uses `gh issue view --json number,state` (not the bare form)
- [ ] `bash tests/comms-delivery/run.sh` → 12 PASS, 0 FAIL
- [ ] `./scripts/gate_fast.sh` green with gate count increased
- [ ] `./scripts/check_spec_taxonomy.sh` clean (ROADMAP/planning headers conform)
- [ ] `CLAUDE.md` + `README.md` + `ROADMAP.md` + `planning.md` updated; no false "harness already cut over" claim
- [ ] Language architecture matrix followed (Python checker, Bash wrappers, JSON registry)
- [ ] No file written under `projects/`; no hardcoded `/home/rich` paths in new scripts
- [ ] `/security-review` — N/A (no auth/credentials/endpoints; `gh` uses the user's existing auth). Skip unless `/code` surfaces external-input handling.
</content>
</invoke>
