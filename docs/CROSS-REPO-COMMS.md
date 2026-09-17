# Cross-Repo Communication Protocol

How a **consumer** project (Kermit PA, Keystone, ATLAS) raises a change request
against a **dependency** it does not own (today: the Kermit Harness, `teelr/kermit-harness`).

This is the detail behind the one-line rule in [`CLAUDE.md`](../CLAUDE.md)
("Dependency asks go upstream as GitHub issues"). It applies to every
consumer↔dependency pair, not just PA↔Harness.

## The rule in one sentence

**File the ask as a GitHub issue on the upstream repo. That issue is the source
of truth. The local communique file + handoff-queue row are receipts, not the
transport.**

## Why — the failure mode this replaces

The legacy channel was file-relay: a consumer wrote
`tasks/communique-to-harness-<date>-<slug>.md` in its own repo, then a human or
agent had to **manually copy it** into the dependency's in-repo inbox
(`kermit/tasks/HARNESS_INBOX.md` + `communiques-from-<consumer>/`) in a separate
session. That relay step is lossy:

- **2026-06-28 incident:** Kermit PA filed an OllamaAdapter empty-reply ask
  PA-side (communique + handoff-queue row, merged) but it was never relayed into
  the harness inbox. When the harness team checked, they reported **"no open PA
  asks"** — the ask existed but had not been delivered. (PA's
  `tasks/communique-to-harness-2026-06-28-ollama-adapter-empty-reply.md`; the ask
  was then re-filed correctly as `teelr/kermit-harness#200`.)

A GitHub issue removes the relay: **filing is delivery.** It also gives
notifications, assignees, search, open/closed state, and one place to ask "what's
still open" — none of which a pile of markdown files across two repos provides.

## What goes where

| Concern | Home | Why |
| --- | --- | --- |
| The ask itself (open/closed status) | **GitHub issue on the upstream repo** | Single source of truth; filing = delivery; notifications |
| Local receipt / full diagnosis / repro | `tasks/communique-to-<dep>-<date>-<slug>.md` in the consumer repo | Agent-readable in-context, git-tracked audit trail |
| Consumer-side tracking of carried debt | `tasks/HARNESS_HANDOFF_QUEUE.md` (or equivalent) row, **linking the issue URL** | The consumer's local lens on what it's carrying / what's migrated |
| The fix | A normal PR cycle **in the dependency's own repo / session** | The dependency lands it under its own gate + review |

## Procedure (when a consumer finds a dependency bug/gap)

1. **STOP.** Do not edit the dependency repo from the consumer session (see the
   "NEVER write code in another project's directory" rule in `CLAUDE.md`).
2. **File a GitHub issue on the upstream repo:**
   ```bash
   gh issue create --repo <owner>/<repo> \
     --title "[<Consumer>] <concise symptom>" \
     --label bug \
     --body "<symptom · why-not-the-model · hypotheses · repro · ask · consumer status>"
   ```
   Use a `consumer:<name>` label if the upstream repo defines one (recommended —
   makes issues sortable by consumer).
3. **Write the local receipt:** `tasks/communique-to-<dep>-<date>-<slug>.md` with
   the full diagnosis + repro, and add/refresh the consumer's handoff-queue row
   **with the issue URL**.
4. **Revert any dependency edits** already made in the consumer session.
5. **Ship the consumer side fail-closed** (gated off, no workaround) and note the
   blocker; the fix lands later in the dependency's own session.
6. **On resolution:** the dependency closes the issue + ships a release; the
   consumer bumps its pin, re-verifies, and moves the handoff-queue row to
   Migrated (with the issue number + the dependency version).

## Issue body checklist

- **Symptom** — exact observed behavior (and that no error was raised, if so).
- **Why it's not the obvious cause** — e.g. "the model returns valid content on a
  direct call" — rules out the easy misdiagnosis.
- **Hypotheses** — where in the dependency the bug likely is.
- **Repro** — minimal steps the dependency team can run.
- **Ask** — the specific behavior change wanted, and how to verify it.
- **Consumer status** — what the consumer shipped (usually: gated off, no
  workaround), so the team knows nothing is blocked on their side.

## Outbound from the dependency (the dependency telling consumers about versions)

This is the mirror of the inbound rule. Where inbound is "the consumer files an
issue and filing is delivery," outbound is "the dependency cuts a release and the
release is the announcement." The consumer pulls; the dependency does not push a
hand-written doc into each consumer's repo.

### The outbound rule in one sentence

**The dependency announces every version as a GitHub Release with release notes.
The Release is the source of truth that a new version exists. Consumers learn
about it by watching the repo's Releases and/or running Dependabot/Renovate
against their pin — not by a broadcast doc relayed into an inbox.**

### What goes where (outbound)

| Concern | Home | Why |
| --- | --- | --- |
| A new version exists (what changed, new primitives, breaking changes, pin to bump to) | **GitHub Release + release notes on the dependency repo** | Single source of truth; one place per version; notifications via repo watch |
| A consumer learning a version shipped | **Repo watch + Dependabot/Renovate** in the consumer repo | Pull, not push; the consumer's tooling opens a bump PR — no manual relay |
| A consumer's own adoption notes (which pin it moved to, what it had to change) | A receipt file in the **consumer** repo | Local audit trail, not the transport |

### Deprecated: the broadcast-doc relay

Hand-writing a release-broadcast doc and relaying it into each consumer's
`HARNESS_REPLIES_INBOX.md` is **deprecated as a transport**, for the same reason
the inbound file-relay was: it is lossy and needs a manual copy step. Existing
`HARNESS_REPLIES_INBOX.md` files stay as a historical receipt trail — they are no
longer how a consumer learns a version shipped.

### Adopting on the consumer side

dev-platform ships a copy-paste Dependabot config at
[`extensions/github-actions/dependabot-consumer-template.yml`](../extensions/github-actions/dependabot-consumer-template.yml).
Copy it to `.github/dependabot.yml` in the consumer repo and keep the
`package-ecosystem` blocks that match the stack. It is **opt-in per consumer**.

### A repo `gh` cannot reach is unverifiable, not compliant

`Osigin-LLC/SQRL` is on a different GitHub account, reached through the
`github-teelr129` SSH host alias. `gh api repos/Osigin-LLC/SQRL` returns 404 under
the account this machine authenticates as, so from here its pin cannot be read and
any ask filed against it cannot be confirmed delivered.

Note which failure that is. `scripts/lib/repo_slug.py` parses the alias remote
correctly — the slug is right; the **access** is missing. Two consequences, both
mandatory:

- Any tool querying it must report `unverifiable` and must **never** fall back to
  the local checkout and present that as the answer. `monitoring/fleet_pins.py`
  probes the repo before the file for exactly this reason (v1.27): `gh` returns
  the same 404 for "no such file" and "no access to this repo", and treating the
  second as the first turns an unknown into a fact.
- An unverifiable repo is not a compliant one. Verify from a session
  authenticated to that account, or ask in that repo's own session — do not record
  it as done.

### Pin-bump asks specifically

A dev-platform release does not need an issue per consumer. For a consumer running
the Dependabot `github-actions` block, the **release tag is the notification** —
that is the outbound half this document already prescribes, and it works: three
consumers have had Dependabot bump PRs opened for them this way.

File a pin-bump issue only for consumers without it, and put that consumer's
**verified** current pin in the title. v1.26 filed seven issues titled
`@v0.7 → @v1.26` when no consumer was on `@v0.7`; the number came from a stale doc
example rather than from any repo. Read the pin first —
`./scripts/fleet-pins.sh`, or `gh api repos/<slug>/contents/.github/workflows/dev-platform-gate.yml`.

### What dev-platform ships vs. what each repo does

dev-platform owns the **standard** (this section), the **Dependabot template**,
and a **delivery check** (`scripts/check-comms-delivery.sh`, which confirms each
post-migration ask-communique links a live upstream issue). The actual cutover is
per-repo coordination, not something dev-platform performs: the dependency stops
relaying broadcast docs and starts cutting Releases **from its own session**, and
each consumer enables Dependabot **from its own session**. The harness completed
that cutover in v4.84.2 (2026-06-29) — relay retired, Releases now the transport;
the section below tracks current state.

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

## Migration status

- **Inbound** adopted 2026-06-28 (PA↔Harness, pilot issue `teelr/kermit-harness#200`).
- **Outbound standard** defined in Roadmap Phase v1.5: Releases +
  Dependabot/Renovate, with the consumer template and delivery check shipped in
  dev-platform.
- **Outbound cutover — DONE** (harness v4.84.2, 2026-06-29): the broadcast-doc
  relay was retired (`check_outbound_reply_sync` / CT92 deregistered + deleted;
  `check_release_broadcast_exists` / CT93 repurposed to an offline CHANGELOG
  release-notes check), and versions are now announced via GitHub Releases.
- **`consumer:*` labels — DONE** on the harness repo (`consumer:pa` /
  `consumer:keystone` / `consumer:atlas`; pilot `#200` labeled `consumer:pa`).
- **Consumer Dependabot adoption — DONE** for PA (kermit-pa `#127`) and Keystone
  (keystone `#355`); ATLAS deprecated, so complete for active consumers.
- **Only open item:** Keystone applies its `consumer:keystone` label on its next
  actual harness ask (the label exists; it is just unused so far).
- **Pinned wheel install — DECIDED** (v1.38, issue #122): the harness cuts Releases but
  attaches no build assets, so the shared dev conda env still installs editable off the
  live sibling checkout. The upstream ask (attach a wheel/sdist to `make release`) is
  filed post-merge against `teelr/kermit-harness`; each consumer's own switch-over is
  deferred until that asset exists.
- The legacy `tasks/communique-to-*` files, `HARNESS_INBOX.md`, and
  `HARNESS_REPLIES_INBOX.md` remain as the historical receipt trail; they are no
  longer the transport.
