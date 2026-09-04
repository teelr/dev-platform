#!/usr/bin/env bash
# scripts/migrate-shipped.sh — split planning.md's "Recently shipped" section
# into one file per entry under tasks/shipped/.
#
# Why: every /code turn prepended a bullet to the same section AND rewrote the
# "Active" lines above it, so concurrent sessions collided on planning.md the
# same way they collided on tasks/lessons.md before v1.23. One file per shipped
# phase removes the collision structurally; phase filenames cannot collide
# because version numbers are claimed atomically (v1.11).
#
# Committed rather than run-and-discarded (v0.9 / v1.23 precedent) so consumer
# projects can port their own planning.md from their own sessions.
#
# Two bullet shapes, two filename shapes:
#   - v<X.Y> <Title>, ... (date, ...)   → <date>-v<X.Y>-<slug>.md   (phase)
#   - <description> (<date>, ...)       → <date>-<slug>.md          (chore)
#
# The date is the FIRST YYYY-MM-DD found in the bullet. A bullet with no date,
# or any non-bullet line beyond the single known preamble, ABORTS the run
# naming the line — a silently dropped entry is undetectable once the section
# is deleted (the v1.23 contract). The derived title is cosmetic; the full
# original bullet text is always written to the body verbatim.
#
# This script only READS planning.md. Rewriting planning.md itself is a
# separate, by-hand step — the target is bespoke prose, not a transform.
#
# Usage:
#   ./scripts/migrate-shipped.sh            # dry-run: report, write nothing
#   ./scripts/migrate-shipped.sh --apply    # write the files
#   ./scripts/migrate-shipped.sh --help
#
# Env overrides (used by tests/shipped-dir/):
#   PLANNING_FILE   source file  (default: planning.md)
#   SHIPPED_DIR     output dir   (default: tasks/shipped)
#
# Exit codes:
#   0 — dry-run completed, or --apply wrote successfully
#   1 — unparseable content (nothing written), or source file/section missing
#   2 — setup error (bad argument)

set -uo pipefail

PLANNING_FILE="${PLANNING_FILE:-planning.md}"
SHIPPED_DIR="${SHIPPED_DIR:-tasks/shipped}"
APPLY=0
FORMAT=""

usage() {
    cat <<'USAGE'
migrate-shipped.sh — split planning.md's Recently-shipped section into files

  ./scripts/migrate-shipped.sh            dry-run (default): report, write nothing
  ./scripts/migrate-shipped.sh --apply    write tasks/shipped/<date>-[v<X.Y>-]<slug>.md
  ./scripts/migrate-shipped.sh --help     this text

Env: PLANNING_FILE (default planning.md), SHIPPED_DIR (default tasks/shipped)
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply) APPLY=1; shift ;;
        --format)
            shift
            [[ $# -eq 0 ]] && { echo "migrate-shipped: --format requires bullets|table|sections" >&2; exit 2; }
            case "$1" in
                bullets|table|sections) FORMAT="$1" ;;
                *) echo "migrate-shipped: --format must be bullets|table|sections, got '$1'" >&2; exit 2 ;;
            esac
            shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "migrate-shipped: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ ! -f "${PLANNING_FILE}" ]]; then
    echo "migrate-shipped: no ${PLANNING_FILE} — nothing to migrate" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PLANNING_FILE="${PLANNING_FILE}" SHIPPED_DIR="${SHIPPED_DIR}" APPLY="${APPLY}" \
REPO_ROOT="${REPO_ROOT}" FORMAT="${FORMAT}" \
python3 - <<'PY'
import os, re, sys

# The format-independent half lives in scripts/lib/entry_split.py (v1.28), one
# definition shared with migrate-lessons.sh. This block runs from stdin, so
# there is no __file__ to resolve from — bash exports REPO_ROOT for it.
sys.path.insert(0, os.path.join(os.environ["REPO_ROOT"], "scripts", "lib"))
from entry_split import Entry, assign_filenames, report_and_abort, emit  # noqa: E402

src    = os.environ["PLANNING_FILE"]
out    = os.environ["SHIPPED_DIR"]
apply_ = os.environ["APPLY"] == "1"

fmt_arg = os.environ.get("FORMAT", "")

DATE    = re.compile(r'\d{4}-\d{2}-\d{2}')
PHASE   = re.compile(r'^- (v\d+\.\d+)\s+(.*)$')
BULLET  = re.compile(r'^- (.*)$')

# kermit's `## Recently shipped` holds a table, not bullets:
#   | v4.120.0 | 2026-08-25 | MINOR: VectorBackend.flush — … |
SHIPPED_ROW = re.compile(
    r'^\|\s*(?P<version>v[\d.]+)\s*\|\s*(?P<date>\d{4}-\d{2}-\d{2})\s*\|\s*'
    r'(?P<summary>.*?)\s*\|?\s*$'
)
# kermit-v3's planning.md is 182 of these instead of any Recently-shipped section:
#   ## Ground Truth (2026-09-03, v0.197 Duplicate Upload Badge — ✅ COMPLETE, milestone #198)
GROUND_TRUTH = re.compile(
    r'^## Ground Truth \((?P<date>\d{4}-\d{2}-\d{2}),\s*(?P<rest>.+)\)\s*$'
)
GT_VERSION = re.compile(r'^(?P<version>v\d+\.\d+)\s*(?P<title>.*)$')

lines = open(src, encoding='utf-8').read().split('\n')


def detect():
    """bullets | table (both inside `## Recently shipped`) | sections."""
    if fmt_arg:
        return fmt_arg
    if any(GROUND_TRUTH.match(l) for l in lines):
        return 'sections'
    try:
        s = next(i for i, l in enumerate(lines) if l.strip() == '## Recently shipped')
    except StopIteration:
        print(f"migrate-shipped: no '## Recently shipped' section in {src} — nothing to migrate",
              file=sys.stderr)
        sys.exit(1)
    e = next((i for i in range(s + 1, len(lines)) if lines[i].startswith('## ')), len(lines))
    body = lines[s + 1:e]
    if any(SHIPPED_ROW.match(l) for l in body):
        return 'table'
    return 'bullets'


fmt = detect()

if fmt in ('bullets', 'table'):
    # Isolate the Recently-shipped section.
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == '## Recently shipped')
    except StopIteration:
        print(f"migrate-shipped: no '## Recently shipped' section in {src} — nothing to migrate",
              file=sys.stderr)
        sys.exit(1)
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith('## ')), len(lines))
    section = lines[start + 1:end]
else:
    start, section = 0, []

phases, chores, preamble, errors, skipped = [], [], [], [], []

for offset, line in enumerate(section if fmt == 'bullets' else []):
    lineno = start + 2 + offset          # 1-based line number in the file
    if not line.strip():
        continue
    m = PHASE.match(line)
    if m:
        version, rest = m.group(1), m.group(2)
        dm = DATE.search(line)
        if not dm:
            errors.append((lineno, "phase bullet has no YYYY-MM-DD date", line))
            continue
        # Title: text between the version and the first comma.
        title_src = rest.split(',', 1)[0]
        phases.append((dm.group(0), version, title_src, line[2:]))
        continue
    m = BULLET.match(line)
    if m:
        dm = DATE.search(line)
        if not dm:
            errors.append((lineno, "chore bullet has no YYYY-MM-DD date", line))
            continue
        # (date, title_source, body). For a bullet the two are the same text,
        # which keeps this path byte-identical to the pre-v1.28 script; a
        # section's differ (see the sections parser).
        chores.append((dm.group(0), m.group(1), m.group(1)))
        continue
    # Non-bullet, non-blank: exactly one preamble line is expected.
    preamble.append(line)
    if len(preamble) > 1:
        errors.append((lineno, "second non-bullet line — not the known preamble", line))

if fmt == 'table':
    # kermit's shape: | version | date | summary | rows under the same heading.
    for offset, line in enumerate(section):
        lineno = start + 2 + offset
        if not line.strip() or not line.lstrip().startswith('|'):
            continue
        if re.match(r'^\|\s*(Version|-+)\s*\|', line):        # header / separator
            continue
        m = SHIPPED_ROW.match(line)
        if not m:
            errors.append((lineno, "table row is not | version | date | summary |", line))
            continue
        phases.append((m['date'], m['version'], m['summary'], line.strip()))

if fmt == 'sections':
    # kermit-v3's shape: one `## Ground Truth (...)` block per shipped phase,
    # body running to the next `## `.
    cur, cur_body = None, []

    def close_section():
        if cur is None:
            return
        date, rest, head = cur
        body = '\n'.join([head] + cur_body).rstrip()
        vm = GT_VERSION.match(rest)
        if vm:
            # Keep the qualifier ("Spec Phase 6", "follow-up") in the slug:
            # kermit-v3 ships seven sections for v0.175 alone, and a bare
            # version key would make seven indistinguishable filenames.
            phases.append((date, vm['version'], vm['title'].strip(' —-') or rest, body))
        else:
            # Title/slug from the heading's own descriptive text, NOT the whole
            # body — the body starts with the literal "## Ground Truth (<date>,"
            # line, which slugged to filenames like
            # 2026-09-03-ground-truth-2026-09-03-chores-exact-harness.md.
            chores.append((date, rest, body))

    for lineno, line in enumerate(lines, 1):
        if line.startswith('## '):
            close_section()
            cur, cur_body = None, []
            m = GROUND_TRUTH.match(line)
            if m:
                cur = (m['date'], m['rest'], line)
            else:
                # A non-Ground-Truth `## ` is ordinary planning.md prose, not a
                # shipped entry, so this does NOT abort the way an unrecognised
                # heading does in migrate-lessons — planning.md legitimately
                # carries narrative sections. But it is never dropped SILENTLY:
                # kermit-v3 has four, including two `## Incident (...)` blocks
                # that are substantive records someone must decide about by
                # hand. Listed in the output, both dry-run and apply.
                skipped.append(line.strip())
            continue
        if cur is not None:
            cur_body.append(line)
    close_section()

report_and_abort(errors, "migrate-shipped")

# Phases title as "v<X.Y> <Title>" but slug on <Title> alone — the two sources
# differ, which is why Entry carries slug_source separately.
entries = [Entry(date=date, title_source=f"{version} {title_src}", body=body,
                 version=version, slug_source=title_src)
           for date, version, title_src, body in phases]
entries += [Entry(date=date, title_source=title_src, body=body)
            for date, title_src, body in chores]
planned, collisions = assign_filenames(entries, fallback="entry")

notes = [f"format: {fmt} ({len(phases)} phase, {len(chores)} chore)"]

if skipped:
    notes.append(f"{len(skipped)} `## ` section(s) NOT migrated — not shipped "
                 "entries. Move anything here by hand if it belongs:")
    notes += [f"    {h}" for h in skipped]

# Repeated versions are NORMAL here and must not read as damage: kermit-v3
# ships one section per Spec Phase, seven for v0.175 alone. Say so, so the
# collision count below is not mistaken for corruption.
repeats = {}
for _d, v, _t, _b in phases:
    repeats[v] = repeats.get(v, 0) + 1
many = sorted((v for v, c in repeats.items() if c > 1),
              key=lambda s: [int(x) for x in s[1:].split('.')])
if many:
    notes.append(f"{len(many)} version(s) ship more than one section "
                 f"(normal — one per Spec Phase): "
                 + ", ".join(f"{v}×{repeats[v]}" for v in many[:6])
                 + (" …" if len(many) > 6 else ""))

n = len(phases) + len(chores)
emit(planned, out, apply_, "migrate-shipped",
     summary=f"{len(phases)} phase + {len(chores)} chore "
             f"entr{'y' if n == 1 else 'ies'}",
     collisions=collisions, notes=notes,
     apply_summary=f"{len(phases)} phase, {len(chores)} chore")
PY
