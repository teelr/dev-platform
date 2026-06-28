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

## Outbound from the dependency (releases / broadcasts)

The mirror direction — the dependency telling consumers about new versions —
should use **GitHub Releases + release notes**, with consumers watching the repo
or running Dependabot/Renovate, rather than hand-written broadcast docs relayed
into each consumer's inbox. (Migration of the existing broadcast-doc flow is a
separate, larger change; this document governs the inbound *ask* direction.)

## Migration status

- **Adopted 2026-06-28** for PA↔Harness (pilot issue `teelr/kermit-harness#200`).
- **Keystone↔Harness, ATLAS↔Harness:** adopt the same protocol; add
  `consumer:keystone` / `consumer:atlas` labels on the harness repo when those
  consumers file their next ask.
- The legacy `tasks/communique-to-*` files and `HARNESS_INBOX.md` remain as the
  historical receipt trail; they are no longer the transport.
