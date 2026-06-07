# v1.3: Mandatory Review Gate

## Coding Specification for Implementation

## Design Philosophy

`/review` is being promoted from an **optional** step ("for risky/large changes") to a **mandatory** step in the canonical dev workflow chain, sitting between `/code` and `/gate fast`. The driver: `/code`'s built-in verification is self-verification — it checks that the work builds and matches the spec, but the same mental model that wrote a bug is the one checking for it. An independent fresh-eyes pass on the staged diff (`/review`) breaks that blind spot. The goal stated by the user is world-class code on *every* change, not just risky ones.

This is **option 3** = both halves: (1) make `/review` mandatory in the chain, AND (2) strengthen `/code`'s internal verification with an explicit adversarial self-review pass before it reports done. The two are complementary, not redundant: `/code`'s self-review catches what the author can catch on a second read; `/review` is the independent gate that catches what the author structurally cannot.

The new canonical chain becomes:

```text
/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge
```

This touches the **canonical workflow contract**, which `dev/CLAUDE.md` declares as something no project may diverge from ("Consistency Across All Projects — Non-Negotiable"). Therefore the change must land in lockstep across: the authoritative rule files (`CLAUDE.md`, `settings/claude-global.md`), the command definitions (`commands/code.md`, `commands/review.md`), the published docs (`docs/index.md`, `skills/WORKFLOW_MANUAL.md`), the scaffolding READMEs, AND the migration tooling that encodes the canonical-chain string (`scripts/migrate-workflow-chain.sh`, `scripts/audit-project-drift.sh`, `tests/migration/run.sh`). If the chain string drifts between any two of these, the drift detector and the docs disagree and the contract is no longer enforceable. The post-merge cascade then re-migrates every consumer project's `CLAUDE.md` from the review-less chain to the review-ful chain.

A critical hazard governs the migration-tooling changes: **detection patterns must not self-match documentation about the pattern** (lessons.md, 2026-05-11 — the v0.9 `audit-project-drift.sh` self-flag incident). The review-less chain is detected by the literal substring `/code → /gate` (no `/review` between). Any prose in `dev/CLAUDE.md` that needs to *describe* this detection must avoid writing that bare substring, or it will flag dev-platform's own `CLAUDE.md` as DRIFT when the audit runs against the repo (dev-platform is in `monitoring/projects.json` with path `.`).

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| Workflow rule/doc files | Markdown | Documentation; no runtime. Matches every existing rule/doc file. |
| Migration tooling extensions | Bash | Extends existing `scripts/migrate-workflow-chain.sh` and `scripts/audit-project-drift.sh`, both already Bash; CLI-glue + text rewriting is the established pattern here, not a candidate for Go/Rust/Python. |
| Test fixtures | Bash | Extends `tests/migration/run.sh`, auto-discovered by `gate_fast.sh` per the v0.4 contract. |

No new runtime components are introduced, so the Go/Rust/Python network/compute/AI matrix does not gate any new service. All changes extend existing artifacts in their existing languages.

## Overview

- **Phase 1 — Authoritative contract (rules + commands):**
  - Change 1: Promote `/review` to a mandatory chain step across `CLAUDE.md`.
  - Change 2: Update `settings/claude-global.md` (full chain + Workflow Step Discipline list).
  - Change 3: Strengthen `commands/code.md` with an adversarial self-review step + point to mandatory `/review`.
  - Change 4: Reframe `commands/review.md` from optional pre-commit to mandatory chain gate.
- **Phase 2 — Published docs + scaffolding:**
  - Change 5: Update `docs/index.md` and `skills/WORKFLOW_MANUAL.md`.
  - Change 6: Update the three scaffolding READMEs to the new canonical chain.
- **Phase 3 — Migration tooling lockstep:**
  - Change 7: Update `scripts/migrate-workflow-chain.sh` (NEW_CHAIN + review-less detection + insert rewrite + idempotency guard + help/comments) and the `CLAUDE.md` carve-out paragraph.
  - Change 8: Update `scripts/audit-project-drift.sh` detection to flag the review-less chain.
- **Phase 4 — Tests:**
  - Change 9: Extend `tests/migration/run.sh` with a review-less fixture + assertions, and update the `NEW_CHAIN` constant.

Post-merge (bespoke, not a Change): re-run the migration script against every consumer project to upgrade their `CLAUDE.md` chain line; update ROADMAP/milestone bookkeeping.

---

## Phase 1: Authoritative Contract

### Change 1: Promote `/review` to a mandatory chain step in `CLAUDE.md`

**Problem:** `dev/CLAUDE.md` lists `/review` under "Optional steps" and prints the review-less chain in four places. As the single source of truth for every project, it must define the review-ful chain and place `/review` in the standard sequence.

**File:** `/home/rich/dev/CLAUDE.md` (existing — edits at lines ~23, ~31, ~94, ~107–112, ~116, ~342)

**Implementation:**

1. **Line ~31** (What dev-platform owns → Dev workflow bullet). Current:
   > - **Dev workflow** — `/plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge`. `/review` optional for risky changes. `/code` handles verification, auto-fix, and doc updates internally.

   Rewrite to:
   > - **Dev workflow** — `/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`. `/review` is a mandatory independent review gate on every change. `/code` handles verification, auto-fix, and doc updates internally; `/review` is the independent fresh-eyes pass `/code` cannot be.

2. **Line ~94** (standard chain code block). Change the chain to:
   ```text
   /plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge
   ```

3. **Lines ~97–112** (step bullets + Optional steps). Insert a `/review` bullet into the standard step list, immediately after the `/code` bullet and before `/gate fast`:
   > - **`/review`** — Independent fresh-eyes pass on the staged diff. Catches logic errors that still compile, edge cases, and security issues a green build won't surface. Auto-fixes SECURITY / BUG / COMPLIANCE / QUALITY; surfaces ARCHITECTURE for user decision. **Mandatory on every change.**

   Then change the **"Optional steps:"** block so `/review` is no longer listed there. The block keeps `/security-review`, `/test`, `/docs`:
   > **Optional steps:**
   >
   > - **`/security-review`** — For changes touching auth, credentials, external input, or new endpoints: between `/review` and `/gate fast`.
   > - **`/test`** — Standalone spec validation. Not required when `/code` verifies as it goes.
   > - **`/docs`** — Standalone doc update. Recovery only — `/code` handles it normally.

4. **Line ~116** (Quick fixes). Current:
   > **Quick fixes:** fix → `/gate fast` → commit → push → `/pr` → CI → `/merge`.

   Rewrite to insert `/review` (world-class code on every change, including quick fixes):
   > **Quick fixes:** fix → `/review` → `/gate fast` → commit → push → `/pr` → CI → `/merge`.

5. **Line ~342** (Patterns → Dev workflow bullet). Update both the standard and quick-fix chains there to the review-ful forms:
   > - **Dev workflow** — `/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge` for features. Quick fixes: `/review → /gate fast` → commit → push → `/pr` → CI → `/merge`. `/review` is mandatory on every change.

6. **Line ~23** (migration-tooling carve-out paragraph). This paragraph documents what `migrate-workflow-chain.sh` detects and the canonical string it rewrites to. Update the canonical-chain string to the review-ful form, AND update the detection description **without writing the bare substring `/code → /gate`** (self-match hazard). Current paragraph ends:
   > Detects lines matching the old chain pattern (`/plan → /code → /test`) and rewrites them to the canonical chain (`/plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge`). …

   Rewrite to:
   > Detects lines matching a superseded chain pattern — either the legacy `/test`-bearing chain (`/plan → /code → /test`) or any chain that omits the mandatory `/review` gate — and rewrites them to the canonical chain (`/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`). …

   **Do NOT** write a review-less chain example (`…/code → /gate fast…`) anywhere in `CLAUDE.md`. Describe the review-less case only in prose ("omits the mandatory `/review` gate"), never as a literal chain string. After this Change, `grep -nE "/code → /gate" /home/rich/dev/CLAUDE.md` MUST return nothing.

**Acceptance Test:**

```bash
# Review-ful chain present in all four canonical locations:
grep -c "/plan → /code → /review → /gate fast" /home/rich/dev/CLAUDE.md   # expect >= 3
# No bare review-less substring anywhere (would self-flag the audit):
grep -nE "/code → /gate" /home/rich/dev/CLAUDE.md && echo "FAIL: review-less substring present" || echo "OK"
# /review no longer under Optional steps:
awk '/\*\*Optional steps:\*\*/,/Plan mode default/' /home/rich/dev/CLAUDE.md | grep -q "\`/review\`" && echo "FAIL: /review still listed optional" || echo "OK"
```

---

### Change 2: Update `settings/claude-global.md`

**Problem:** `settings/claude-global.md` line 33 prints the review-less chain and states "`/review` is optional." It also defines the Workflow Step Discipline "STOP and wait" list, which enumerates the steps after which Claude must stop — `/review` must be in that list.

**File:** `/home/rich/dev/settings/claude-global.md` (existing — edit at line ~33 and the Workflow Step Discipline list above it)

**Implementation:**

1. **Line ~33.** Current:
   > The full chain: `/plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge`. `/review` is optional for risky/large changes. `/security-review` is optional for changes touching auth, credentials, external input, or new endpoints. `/test` and `/docs` are standalone — `/code` handles verification, auto-fix, and doc updates internally.

   Rewrite to:
   > The full chain: `/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`. `/review` is a mandatory independent review gate on every change. `/security-review` is optional for changes touching auth, credentials, external input, or new endpoints. `/test` and `/docs` are standalone — `/code` handles verification, auto-fix, and doc updates internally.

2. **Workflow Step Discipline list.** Find the sentence enumerating the steps after which to STOP and wait (currently: "After `/plan`, `/code`, `/gate`, `commit`, `push`, `/pr`, `/merge`, or `post-merge`: report results, …"). Add `/review` to that list in chain order, after `/code`:
   > After `/plan`, `/code`, `/review`, `/gate`, `commit`, `push`, `/pr`, `/merge`, or `post-merge`: …

3. If the same file restates the chain or the "/review optional" framing anywhere else, update those occurrences for consistency. Run `grep -n "/review" /home/rich/dev/settings/claude-global.md` first and reconcile each hit with the mandatory framing.

**Acceptance Test:**

```bash
grep -q "/plan → /code → /review → /gate fast" /home/rich/dev/settings/claude-global.md && echo OK || echo FAIL
grep -q "/review is optional" /home/rich/dev/settings/claude-global.md && echo "FAIL: still says optional" || echo OK
grep -q "After \`/plan\`, \`/code\`, \`/review\`" /home/rich/dev/settings/claude-global.md && echo OK || echo FAIL
```

---

### Change 3: Strengthen `commands/code.md` with an adversarial self-review pass

**Problem:** `commands/code.md` Step 5 (Final Verification) runs build + spec-checklist — mechanical self-verification only. It needs an explicit adversarial diff re-read before reporting done, and it must point the user to `/review` as the now-mandatory next step (not optional).

**File:** `/home/rich/dev/commands/code.md` (existing — new step after Step 5 at line ~83; end-of-step framing)

**Implementation:**

1. After Step 5 (Final Verification, ends ~line 83) and before Step 6 (Update Project Docs), insert a new step. Renumber the subsequent steps (current Step 6 → 7, Step 7 → 8) and update any internal cross-references to those step numbers:

   ```markdown
   ## Step 6: Adversarial Self-Review

   Before reporting done, re-read your own staged diff as a hostile reviewer who assumes it is broken. This is distinct from Step 5's build/spec verification — it is a fresh-eyes pass over the *diff*, not the spec.

   ```bash
   git diff --stat
   git diff                     # read the full diff, hunk by hunk
   ```

   For every hunk, ask:

   - **Logic that still compiles but is wrong** — off-by-one, inverted boolean, wrong variable, missing `await`, swapped args.
   - **Edge cases** — empty input, null/undefined, zero-length, first/last element, concurrent access.
   - **Boundary sweep** — if a signature, return type, or call path changed, did EVERY caller in `src/` AND `tests/` get updated? (`grep -rn` the symbol.)
   - **Did I change something the spec didn't ask for?** Revert it.
   - **Did I leave something the spec asked for unimplemented?** Finish it.
   - **Secrets / debug output** — no credentials, no `console.log`, no leftover `print`/`dbg!`.

   Fix everything you find here before proceeding — do NOT defer it to `/review`. The self-review is your obligation; `/review` is the independent backstop, not a substitute for reading your own work.
   ```

2. Update Step 7 (Security Reminder, currently Step 7) and the end-of-step report so the reported next step is **mandatory `/review`**, not optional. In the security-reminder block and/or the command's closing guidance, ensure the agent's end-of-step report states:
   > Ready for `/review` (mandatory) → then `/gate fast`.

   If the command file already prints a "Ready for X" line, set X to `/review`. Do not describe `/review` as optional anywhere in this file.

**Acceptance Test:**

```bash
grep -q "Adversarial Self-Review" /home/rich/dev/commands/code.md && echo OK || echo FAIL
grep -q "Ready for \`/review\`" /home/rich/dev/commands/code.md && echo OK || echo FAIL
# Step numbering stayed contiguous (no duplicate "## Step 6"):
test "$(grep -c '^## Step 6:' /home/rich/dev/commands/code.md)" -eq 1 && echo OK || echo "FAIL: Step 6 count"
```

---

### Change 4: Reframe `commands/review.md` as a mandatory chain gate

**Problem:** `commands/review.md` describes itself as an optional pre-commit nicety ("Use before committing to catch issues early"). It is now a mandatory chain step between `/code` and `/gate fast`. The framing in the description frontmatter and the agent's self-description should reflect that.

**File:** `/home/rich/dev/commands/review.md` (existing — frontmatter `description` line 2; intro paragraph line ~8)

**Implementation:**

1. **Line 2** (`description:`). Current:
   > description: Pre-commit code review on staged git changes. Use before committing to catch issues early.

   Rewrite to:
   > description: Mandatory independent review gate on staged git changes — runs between /code and /gate fast on every change. The fresh-eyes pass /code cannot be.

2. **Intro paragraph (~line 8).** Add a sentence establishing the gate's place in the chain: that it is mandatory, runs after `/code`'s self-review and before `/gate fast`, and that its independence (a separate pass, not the author grading their own homework) is the entire point. Keep the existing review mechanics (Steps 1–5) unchanged — they already auto-fix SECURITY/BUG/COMPLIANCE/QUALITY and surface ARCHITECTURE, which is exactly the contract.

**Acceptance Test:**

```bash
grep -qi "mandatory" /home/rich/dev/commands/review.md && echo OK || echo FAIL
grep -q "between /code and /gate fast" /home/rich/dev/commands/review.md && echo OK || echo FAIL
```

---

## Phase 2: Published Docs + Scaffolding

### Change 5: Update `docs/index.md` and `skills/WORKFLOW_MANUAL.md`

**Problem:** The published Pages site (`docs/index.md:21`) prints the review-less chain. `skills/WORKFLOW_MANUAL.md` already treats `/review` as a step but its "Full Feature Development" sequence is stale (shows `/test` as a mandatory Step 3, lacks the PR→CI→merge→post-merge tail, and does not name `/review` as mandatory).

**File:** `/home/rich/dev/docs/index.md` (line ~21) and `/home/rich/dev/skills/WORKFLOW_MANUAL.md` (workflow section ~lines 132–183, tips ~242)

**Implementation:**

1. **`docs/index.md:21`** — change the chain string to:
   ```text
   /plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge
   ```

2. **`skills/WORKFLOW_MANUAL.md`** — in "Workflow: Full Feature Development", make the canonical chain explicit and correct. At minimum:
   - Add the canonical chain string once at the top of that section:
     `/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`.
   - Mark `/review` (currently "Step 4: Review") as **mandatory**, positioned after `/code` and before `/gate fast`.
   - Demote `/test` to optional/standalone (it is not in the canonical chain) — keep its description but note it is standalone validation, not a required gate.
   - The Quick Fix section already runs `/review`; update it to `/review → /gate fast → commit` to match the canonical quick-fix chain.
   - Keep edits minimal and factual; do not rewrite the whole manual.

**Acceptance Test:**

```bash
grep -q "/plan → /code → /review → /gate fast" /home/rich/dev/docs/index.md && echo OK || echo FAIL
grep -q "/plan → /code → /review → /gate fast" /home/rich/dev/skills/WORKFLOW_MANUAL.md && echo OK || echo FAIL
```

---

### Change 6: Update the three scaffolding READMEs

**Problem:** `scaffolding/{go-service,python-agent,next-frontend}/README.md` each print an even-older chain (`/plan → /code → /test → /review → /gate fast → /docs → commit → push`) — stale since the v0.8 redesign and never migrated. New projects scaffolded from these inherit a wrong chain.

**File:** `/home/rich/dev/scaffolding/go-service/README.md` (~line 36), `/home/rich/dev/scaffolding/python-agent/README.md` (~line 35), `/home/rich/dev/scaffolding/next-frontend/README.md` (~line 34)

**Implementation:**

In each of the three READMEs, replace the `Workflow:` line's chain with the new canonical chain:

> Workflow: `/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge` (see `/home/rich/dev/CLAUDE.md`).

**Acceptance Test:**

```bash
for f in go-service python-agent next-frontend; do
  grep -q "/plan → /code → /review → /gate fast" "/home/rich/dev/scaffolding/$f/README.md" \
    && echo "$f OK" || echo "$f FAIL"
done
# No stale /test chain left in scaffolding:
grep -rn "/code → /test" /home/rich/dev/scaffolding/ && echo "FAIL: stale /test chain" || echo OK
```

---

## Phase 3: Migration Tooling Lockstep

### Change 7: Update `scripts/migrate-workflow-chain.sh` to migrate review-less → review-ful

**Problem:** The migration script's `NEW_CHAIN` is the review-less chain, and its detection (`/code → /test →|/test → /review`) only catches the legacy `/test` chain. Consumer projects currently sit on the review-less canonical chain (`/plan → /code → /gate fast → …`) after the v0.9 cascade. To upgrade them, the script must (a) emit the review-ful `NEW_CHAIN`, (b) detect the review-less chain, (c) rewrite it by inserting `/review`, and (d) keep the idempotency guard honest.

**File:** `/home/rich/dev/scripts/migrate-workflow-chain.sh` (existing — lines 25, 59, 106–107, 114–131, 153)

**Implementation:**

1. **Line 25 — `NEW_CHAIN`.** Change to:
   ```bash
   NEW_CHAIN="/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge"
   ```

2. **Detection (line ~107 and the dry/apply guard at ~153).** Extend the grep to also catch the review-less chain. Use a marker that matches the review-less chain but NOT the review-ful one. The review-less chain contains `/code → /gate`; the review-ful chain contains `/code → /review → /gate` (no `/code → /gate` substring). New detection:
   ```bash
   grep -qE "/code → /test →|/test → /review|/code → /gate" "${claude_md}"
   ```
   Apply the same pattern at **both** the early-exit detection (line ~107) and the post-apply idempotency guard (line ~153).

3. **Rewrite rule (inside `apply_rewrite`, lines ~117–132).** Keep all existing `/test`-chain sed rules (they replace the whole legacy chain with the now-review-ful `NEW_CHAIN`). ADD one new rule that converts the review-less chain to review-ful by inserting `/review` in place:
   ```bash
   -e "s|/code → /gate fast|/code → /review → /gate fast|g" \
   ```
   This single rule is idempotent-safe: after it runs, the text is `/code → /review → /gate fast`, which no longer contains `/code → /gate fast`. Place it as the LAST `-e` in the `sed` invocation so it runs after the legacy full-chain replacements (which already eliminate `/code → /gate` from `/test` chains, so the insert rule only touches genuinely review-less chains).

4. **Help text (line ~59) and the detection comment (line ~106).** Update to mention the review-less case. NOTE: this is the script file, which the audit does NOT scan — writing `/code → /gate` here is safe. Update the help "Detection:" line to:
   > Detection: any line containing "/code → /test", "/test → /review", or a review-less chain ("/code → /gate" with no "/review" between) is treated as a superseded chain and rewritten.

5. Verify the dry-run diff and `--apply` both work end-to-end against a scratch `CLAUDE.md` containing the review-less chain (manual smoke before relying on the test suite):
   ```bash
   tmp=$(mktemp -d); mkdir -p "$tmp/proj"
   printf '# x\n\nFollow: /plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge\n' > "$tmp/proj/CLAUDE.md"
   printf '[{"name":"proj","path":"%s/proj","enabled":true}]\n' "$tmp" > "$tmp/reg.json"
   ./scripts/migrate-workflow-chain.sh --project proj --registry "$tmp/reg.json"            # dry-run shows insert
   ./scripts/migrate-workflow-chain.sh --project proj --registry "$tmp/reg.json" --apply    # inserts /review
   grep -q "/code → /review → /gate fast" "$tmp/proj/CLAUDE.md" && echo OK || echo FAIL
   ./scripts/migrate-workflow-chain.sh --project proj --registry "$tmp/reg.json" --apply | grep -q "already up-to-date" && echo "idempotent OK" || echo "idempotent FAIL"
   rm -rf "$tmp"
   ```

**Acceptance Test:** the smoke block above prints `OK` then `idempotent OK`; `bash -n scripts/migrate-workflow-chain.sh` is clean.

---

### Change 8: Update `scripts/audit-project-drift.sh` detection

**Problem:** `audit-project-drift.sh:114` uses the same `/test`-only detection and will report a review-less consumer `CLAUDE.md` as `CLEAN`. After this spec, the review-less chain IS drift.

**File:** `/home/rich/dev/scripts/audit-project-drift.sh` (existing — line ~114)

**Implementation:**

Change the chain-drift grep to match the migration script's new detection:
```bash
elif grep -qE "/code → /test →|/test → /review|/code → /gate" "${claude_md}" 2>/dev/null; then
    chain_status="DRIFT"
```

**Verification that this does not self-flag dev-platform:** after Change 1, `/home/rich/dev/CLAUDE.md` contains no bare `/code → /gate` substring (only `/code → /review → /gate`). Confirm:
```bash
./scripts/audit-project-drift.sh --project dev-platform   # dev-platform row must show Chain=CLEAN
```

**Acceptance Test:**

```bash
bash -n /home/rich/dev/scripts/audit-project-drift.sh && echo OK || echo FAIL
./scripts/audit-project-drift.sh --project dev-platform | grep -q "CLEAN" && echo "self-clean OK" || echo "FAIL: dev-platform self-flagged"
```

---

## Phase 4: Tests

### Change 9: Extend `tests/migration/run.sh`

**Problem:** The migration test suite's `NEW_CHAIN` constant is review-less, and there is no fixture exercising the review-less → review-ful upgrade path (the actual migration consumers will undergo). Without it, Change 7/8 ship untested.

**File:** `/home/rich/dev/tests/migration/run.sh` (existing — line 26 + new fixture + new checks)

**Implementation:**

1. **Line 26 — `NEW_CHAIN` constant.** Update to the review-ful chain so the `clean-1` and `taxonomy-drift-1` fixtures (which embed `${NEW_CHAIN}`) represent genuinely-clean projects under the new contract:
   ```bash
   NEW_CHAIN="/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge"
   ```
   Existing Checks 10/12 assert the substring `gate fast → commit → push → /pr`, which is still present in the review-ful chain — they keep passing.

2. **Add a new mock project `review-less-1`** (a project on the old review-less canonical chain), alongside the existing fixtures:
   ```bash
   mkdir -p "${MOCK_ROOT}/review-less-1/tasks"
   cat > "${MOCK_ROOT}/review-less-1/CLAUDE.md" <<'EOF'
   # Review-less Project

   ## Dev Workflow

   Follow: /plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge
   EOF
   ```
   Add its registry entry to `MOCK_REGISTRY`.

3. **Add assertions** (append after Check 12; bump the header comment count and the file's assertion total):
   - **Check 13:** `audit --project review-less-1` reports `DRIFT` (review-less is now drift).
   - **Check 14:** `migrate --project review-less-1` dry-run shows a `+`-line containing `/review` and writes nothing (hash unchanged).
   - **Check 15:** `migrate --project review-less-1 --apply` produces a `CLAUDE.md` containing `/code → /review → /gate fast` and no longer matching the review-less detection.
   - **Check 16:** a second `--apply` on `review-less-1` reports `already up-to-date` (idempotent).
   - **Check 17 (regression / self-clean):** `clean-1` (now embedding the review-ful `NEW_CHAIN`) audits as `CLEAN`, proving the review-ful chain is not falsely flagged.

4. Update the suite header comment (line 3) from "12 assertions" to the new total.

**Acceptance Test:**

```bash
bash /home/rich/dev/tests/migration/run.sh    # all checks PASS, including 13–17
./scripts/gate_fast.sh                          # full gate green; assertion count rises by the number of new checks
```

---

## What NOT to Do

- **Do NOT write a bare review-less chain string (`…/code → /gate fast…`) anywhere in `/home/rich/dev/CLAUDE.md`.** The audit detector greps `CLAUDE.md` for `/code → /gate`; a literal example would self-flag dev-platform as DRIFT (exact repeat of the v0.9 `audit-project-drift.sh` self-match incident — lessons.md 2026-05-11). Describe the review-less case in prose only.
- **Do NOT place the new `s|/code → /gate fast|…|` sed rule before the legacy `/test` full-chain rules** in a way that mangles a `/test` chain. (It won't — `/test` chains contain `/code → /test`, not `/code → /gate fast` — but keep it last to make the ordering intent explicit.)
- **Do NOT change the review mechanics in `commands/review.md` Steps 1–5.** They already auto-fix SECURITY/BUG/COMPLIANCE/QUALITY and surface ARCHITECTURE. Only the framing (mandatory vs optional) changes.
- **Do NOT delete `/test` or `/docs` from the docs.** They remain standalone/optional steps — they are simply not in the canonical chain. Only `/review` is being promoted.
- **Do NOT migrate consumer projects' `CLAUDE.md` from this session.** Cross-project writes are forbidden except via the explicit `migrate-workflow-chain.sh` carve-out, which the user runs as a post-merge step from each project (or via the script's per-project opt-in). The spec ships the *tooling*; the cascade runs post-merge.
- **Do NOT hardcode a new gate assertion count into ROADMAP/planning before observing it.** `/code`'s doc step records the actual count `gate_fast.sh` reports after Change 9.
- **Do NOT auto-advance.** This spec touches the canonical contract; each workflow step waits for explicit invocation.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `CLAUDE.md` | Modify | Promote `/review` to mandatory chain step (4 chain locations + step list + Optional block + quick-fix + carve-out paragraph); no bare review-less substring. |
| `settings/claude-global.md` | Modify | Review-ful full chain; drop "/review optional"; add `/review` to Workflow Step Discipline STOP list. |
| `commands/code.md` | Modify | New "Adversarial Self-Review" step; renumber subsequent steps; report mandatory `/review` as next step. |
| `commands/review.md` | Modify | Reframe description + intro from optional pre-commit to mandatory chain gate; mechanics unchanged. |
| `docs/index.md` | Modify | Review-ful chain string. |
| `skills/WORKFLOW_MANUAL.md` | Modify | Canonical chain string; `/review` mandatory; `/test` demoted to standalone; quick-fix updated. |
| `scaffolding/go-service/README.md` | Modify | Workflow line → new canonical chain. |
| `scaffolding/python-agent/README.md` | Modify | Workflow line → new canonical chain. |
| `scaffolding/next-frontend/README.md` | Modify | Workflow line → new canonical chain. |
| `scripts/migrate-workflow-chain.sh` | Modify | `NEW_CHAIN` review-ful; detect `/code → /gate`; insert-`/review` sed rule; idempotency guard; help/comments. |
| `scripts/audit-project-drift.sh` | Modify | Detection grep adds `/code → /gate`. |
| `tests/migration/run.sh` | Modify | `NEW_CHAIN` review-ful; `review-less-1` fixture; Checks 13–17; header count. |

## Implementation Order

1. **Change 1** (`CLAUDE.md`) — the source of truth; everything else aligns to it. Verify no bare `/code → /gate` substring before proceeding.
2. **Change 2** (`settings/claude-global.md`) — paired authoritative rule file.
3. **Change 3** (`commands/code.md`) and **Change 4** (`commands/review.md`) — command behavior matches the new contract.
4. **Change 5** (`docs/index.md`, `WORKFLOW_MANUAL.md`) and **Change 6** (scaffolding READMEs) — published surfaces.
5. **Change 7** (`migrate-workflow-chain.sh`) — depends on the canonical string from Change 1; smoke-test the review-less upgrade path manually.
6. **Change 8** (`audit-project-drift.sh`) — detection parity with Change 7; verify dev-platform self-audits CLEAN (depends on Change 1 having removed the bare substring).
7. **Change 9** (`tests/migration/run.sh`) — locks Changes 7–8 under the gate. Run `gate_fast.sh` last.

## Verification Checklist

- [ ] `CLAUDE.md` shows the review-ful chain in all four canonical locations; `grep -nE "/code → /gate" CLAUDE.md` returns nothing.
- [ ] `/review` removed from the "Optional steps" block and present as a standard step between `/code` and `/gate fast`.
- [ ] Quick-fix chain includes `/review` in both `CLAUDE.md` locations.
- [ ] `settings/claude-global.md`: review-ful chain, no "optional" framing, `/review` in the STOP list.
- [ ] `commands/code.md`: "Adversarial Self-Review" step present; steps renumbered contiguously; end-of-step points to mandatory `/review`.
- [ ] `commands/review.md`: framed as mandatory chain gate; Steps 1–5 mechanics unchanged.
- [ ] `docs/index.md`, `skills/WORKFLOW_MANUAL.md`, and all three scaffolding READMEs show the new canonical chain; no stale `/code → /test` chain in scaffolding.
- [ ] `migrate-workflow-chain.sh`: `NEW_CHAIN` review-ful; review-less detection + insert rule; manual smoke (review-less → review-ful, then idempotent) passes; `bash -n` clean.
- [ ] `audit-project-drift.sh`: detection includes `/code → /gate`; `--project dev-platform` reports Chain=CLEAN (no self-flag).
- [ ] `tests/migration/run.sh`: Checks 13–17 added and PASS; `NEW_CHAIN` updated; header count updated.
- [ ] `./scripts/gate_fast.sh` green; assertion count rises by the number of new checks (record the actual number in planning.md/ROADMAP).
- [ ] No new components, so the Language Architecture matrix is satisfied trivially (docs + existing-Bash tooling).
- [ ] This spec touches no auth/credentials/external input/new endpoints — `/security-review` not required. `/review` IS required (it's mandatory now, and dogfooding it on this very change is the point).
