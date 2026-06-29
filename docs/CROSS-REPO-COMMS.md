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

### What dev-platform ships vs. what each repo does

dev-platform owns the **standard** (this section), the **Dependabot template**,
and a **delivery check** (`scripts/check-comms-delivery.sh`, which confirms each
post-migration ask-communique links a live upstream issue). The actual cutover is
per-repo coordination, not something dev-platform performs: the dependency stops
relaying broadcast docs and starts cutting Releases **from its own session**, and
each consumer enables Dependabot **from its own session**. The harness completed
that cutover in v4.84.2 (2026-06-29) — relay retired, Releases now the transport;
the section below tracks current state.

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
- The legacy `tasks/communique-to-*` files, `HARNESS_INBOX.md`, and
  `HARNESS_REPLIES_INBOX.md` remain as the historical receipt trail; they are no
  longer the transport.
