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
        --help|-h) usage; exit 0 ;;
        *) echo "migrate-shipped: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ ! -f "${PLANNING_FILE}" ]]; then
    echo "migrate-shipped: no ${PLANNING_FILE} — nothing to migrate" >&2
    exit 1
fi

PLANNING_FILE="${PLANNING_FILE}" SHIPPED_DIR="${SHIPPED_DIR}" APPLY="${APPLY}" \
python3 - <<'PY'
import os, re, sys, unicodedata

src    = os.environ["PLANNING_FILE"]
out    = os.environ["SHIPPED_DIR"]
apply_ = os.environ["APPLY"] == "1"

DATE    = re.compile(r'\d{4}-\d{2}-\d{2}')
PHASE   = re.compile(r'^- (v\d+\.\d+)\s+(.*)$')
BULLET  = re.compile(r'^- (.*)$')

def slugify(text, words=8):
    text = re.sub(r'`[^`]*`', ' ', text)
    text = unicodedata.normalize('NFKD', text)
    text = text.encode('ascii', 'ignore').decode()
    parts = re.findall(r'[A-Za-z0-9]+', text)[:words]
    slug = '-'.join(p.lower() for p in parts)[:50].strip('-')
    return slug or 'entry'

def titleize(text, words=12):
    plain = re.sub(r'\s+', ' ', text).strip()
    toks = plain.split(' ')
    if len(toks) <= words:
        return plain.rstrip('.')
    return ' '.join(toks[:words]).rstrip(',;:').rstrip('.') + '…'

# Isolate the Recently-shipped section.
lines = open(src, encoding='utf-8').read().split('\n')
try:
    start = next(i for i, l in enumerate(lines) if l.strip() == '## Recently shipped')
except StopIteration:
    print(f"migrate-shipped: no '## Recently shipped' section in {src} — nothing to migrate",
          file=sys.stderr)
    sys.exit(1)
end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith('## ')), len(lines))
section = lines[start + 1:end]

phases, chores, preamble, errors = [], [], [], []
for offset, line in enumerate(section):
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
        chores.append((dm.group(0), m.group(1)))
        continue
    # Non-bullet, non-blank: exactly one preamble line is expected.
    preamble.append(line)
    if len(preamble) > 1:
        errors.append((lineno, "second non-bullet line — not the known preamble", line))

if errors:
    for lineno, why, line in errors:
        print(f"migrate-shipped: UNPARSEABLE at line {lineno} ({why}):", file=sys.stderr)
        print(f"  {line[:160]}", file=sys.stderr)
    print(f"migrate-shipped: aborting, {len(errors)} problem(s) — nothing written",
          file=sys.stderr)
    sys.exit(1)

# Plan filenames, resolving collisions rather than overwriting.
taken, planned = set(), []
for date, version, title_src, body in phases:
    base = f"{date}-{version}-{slugify(title_src)}"
    name, n = f"{base}.md", 1
    while name in taken:
        n += 1
        name = f"{base}-{n}.md"
    taken.add(name)
    planned.append((name, titleize(f"{version} {title_src}"), body))
for date, body in chores:
    base = f"{date}-{slugify(body)}"
    name, n = f"{base}.md", 1
    while name in taken:
        n += 1
        name = f"{base}-{n}.md"
    taken.add(name)
    planned.append((name, titleize(body), body))

if not apply_:
    print(f"migrate-shipped: DRY RUN — {len(phases)} phase + {len(chores)} chore "
          f"entr{'y' if len(phases)+len(chores)==1 else 'ies'} would become "
          f"{len(planned)} file(s) in {out}/")
    print("migrate-shipped: re-run with --apply to write them")
    sys.exit(0)

os.makedirs(out, exist_ok=True)
for name, title, body in planned:
    with open(os.path.join(out, name), 'w', encoding='utf-8') as fh:
        fh.write(f"# {title}\n\n{body}\n")

print(f"migrate-shipped: wrote {len(planned)} file(s) to {out}/ "
      f"({len(phases)} phase, {len(chores)} chore)")
PY
