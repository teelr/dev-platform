#!/usr/bin/env bash
# scripts/migrate-lessons.sh — convert a single-table tasks/lessons.md into one
# file per lesson under tasks/lessons/.
#
# Why: a single append-only table is a standing merge conflict once more than one
# session works a project. Every session appends at the same place, so git either
# conflicts or merges cleanly at different line offsets and leaves a silent
# duplicate. One file per lesson removes the conflict class structurally.
#
# Committed rather than run-and-discarded (same precedent as v0.9's
# migrate-workflow-chain.sh) so consumer projects can port their own lessons —
# theirs additionally carry hand-incremented "## L<N>" numbers, the variant that
# collides on the number as well as the line.
#
# PARSING — the load-bearing part. Rows are NOT split on "|": lesson bodies
# legitimately contain literal pipes inside backticks (`|| true`, `cmd | head`).
# 7 of dev-platform's own 46 rows do. The pattern below anchors both ends and
# lets the lesson field be greedy, because only the outer columns are pipe-free.
#
# An unparseable row ABORTS the run. A silently skipped lesson is undetectable
# once the source table is deleted.
#
# The derived title is cosmetic; the full original lesson text is always written
# to the body verbatim, so a poor title split can never lose content.
#
# Usage:
#   ./scripts/migrate-lessons.sh            # dry-run: report, write nothing
#   ./scripts/migrate-lessons.sh --apply    # write the files
#   ./scripts/migrate-lessons.sh --help
#
# Env overrides (used by tests/lessons-dir/):
#   LESSONS_FILE   source table   (default: tasks/lessons.md)
#   LESSONS_DIR    output dir     (default: tasks/lessons)
#
# Exit codes:
#   0 — dry-run completed, or --apply wrote successfully
#   1 — a row failed to parse (nothing written), or the source file is missing
#   2 — setup error (bad argument)

set -uo pipefail

LESSONS_FILE="${LESSONS_FILE:-tasks/lessons.md}"
LESSONS_DIR="${LESSONS_DIR:-tasks/lessons}"
APPLY=0

usage() {
    cat <<'USAGE'
migrate-lessons.sh — split a lessons.md table into one file per lesson

  ./scripts/migrate-lessons.sh            dry-run (default): report, write nothing
  ./scripts/migrate-lessons.sh --apply    write tasks/lessons/<date>-<slug>.md
  ./scripts/migrate-lessons.sh --help     this text

Env: LESSONS_FILE (default tasks/lessons.md), LESSONS_DIR (default tasks/lessons)
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply) APPLY=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "migrate-lessons: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ ! -f "${LESSONS_FILE}" ]]; then
    echo "migrate-lessons: no ${LESSONS_FILE} — nothing to migrate" >&2
    exit 1
fi

# python3 does the parsing: bash regex cannot express the both-ends-anchored,
# greedy-middle pattern this needs without mangling the pipe-bearing rows.
LESSONS_FILE="${LESSONS_FILE}" LESSONS_DIR="${LESSONS_DIR}" APPLY="${APPLY}" \
python3 - <<'PY'
import os, re, sys, unicodedata

src   = os.environ["LESSONS_FILE"]
out   = os.environ["LESSONS_DIR"]
apply_= os.environ["APPLY"] == "1"

# Only the outer columns are pipe-free; the lesson body is greedy so embedded
# pipes inside backticks survive intact.
ROW = re.compile(
    r'^\|\s*(?P<date>[^|]+?)\s*\|\s*(?P<lesson>.*?)\s*'
    r'\|\s*(?P<project>[^|]+?)\s*\|\s*(?P<status>[^|]+?)\s*\|\s*$'
)
DATE = re.compile(r'^\d{4}-\d{2}-\d{2}$')

def slugify(text, words=8):
    text = re.sub(r'`[^`]*`', ' ', text)          # code spans make poor slugs
    text = unicodedata.normalize('NFKD', text)
    text = text.encode('ascii', 'ignore').decode()
    parts = re.findall(r'[A-Za-z0-9]+', text)[:words]
    slug = '-'.join(p.lower() for p in parts)[:50].strip('-')
    return slug or 'lesson'

def titleize(text, words=12):
    """Cosmetic only. The full lesson always goes in the body regardless."""
    plain = re.sub(r'\s+', ' ', text).strip()
    toks = plain.split(' ')
    if len(toks) <= words:
        return plain.rstrip('.')
    return ' '.join(toks[:words]).rstrip(',;:').rstrip('.') + '…'

rows, errors = [], []
with open(src, encoding='utf-8') as fh:
    for lineno, line in enumerate(fh, 1):
        line = line.rstrip('\n')
        if not line.startswith('| '):
            continue
        if re.match(r'^\|\s*(Date|-+)\s*\|', line):      # header / separator
            continue
        m = ROW.match(line)
        if not m or not DATE.match(m['date']):
            errors.append((lineno, line))
            continue
        rows.append((m['date'], m['lesson']))

if errors:
    for lineno, line in errors:
        print(f"migrate-lessons: UNPARSEABLE row at line {lineno}:", file=sys.stderr)
        print(f"  {line[:160]}", file=sys.stderr)
    print(f"migrate-lessons: aborting, {len(errors)} row(s) unparseable — "
          "nothing written", file=sys.stderr)
    sys.exit(1)

# Assign filenames, resolving collisions rather than overwriting.
taken, planned, collisions = set(), [], 0
for date, lesson in rows:
    base = f"{date}-{slugify(lesson)}"
    name, n = f"{base}.md", 1
    while name in taken:
        n += 1
        name = f"{base}-{n}.md"
        collisions += 1
    taken.add(name)
    planned.append((name, lesson))

if not apply_:
    print(f"migrate-lessons: DRY RUN — {len(planned)} row(s) would become "
          f"{len(planned)} file(s) in {out}/")
    print("migrate-lessons: re-run with --apply to write them")
    sys.exit(0)

os.makedirs(out, exist_ok=True)
for name, lesson in planned:
    with open(os.path.join(out, name), 'w', encoding='utf-8') as fh:
        fh.write(f"# {titleize(lesson)}\n\n{lesson}\n")

print(f"migrate-lessons: wrote {len(planned)} file(s) to {out}/")
if collisions:
    print(f"migrate-lessons: {collisions} filename collision(s) resolved with a numeric suffix")
PY
