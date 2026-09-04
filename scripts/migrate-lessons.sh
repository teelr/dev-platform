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
FORMAT=""
DATE_FROM=""
IGNORE_HEADINGS=""

usage() {
    cat <<'USAGE'
migrate-lessons.sh — split a lessons.md into one file per lesson

  ./scripts/migrate-lessons.sh            dry-run (default): report, write nothing
  ./scripts/migrate-lessons.sh --apply    write tasks/lessons/<date>-<slug>.md
  ./scripts/migrate-lessons.sh --help     this text

Formats (auto-detected; ambiguity aborts rather than guessing):
  table       | Date | Lesson | Project | Status |   (dev-platform's own)
  numbered    ## L12 — title                        (kermit-pa, keystone, OPIE,
                                                     SQRL, kermit-v3)
  dated       ## Title (2026-03-30)                 (keystone_prototype)

  --format <table|numbered|dated>   force a parser instead of detecting

The numbered format carries no per-entry date, so one is required:
  --date-from git          date each entry from the commit that introduced it
  --date-from today        stamp every entry with today's date
  --date-from 2026-09-03   stamp every entry with an explicit date

  --ignore-heading <regex>  (repeatable) treat a matching `## ` line as a
                            structural container, not a lesson. Needed where
                            lessons sit under category headings at the same
                            level — SQRL groups its 30 lessons under 8 of them.
                            Every ignored heading is listed in the output.

Env: LESSONS_FILE (default tasks/lessons.md), LESSONS_DIR (default tasks/lessons)

Examples:
  # kermit-v3: 205 numbered lessons, dated from git history
  LESSONS_FILE=tasks/lessons.md ./scripts/migrate-lessons.sh --date-from git

  # SQRL: 30 lessons under 8 category headings
  ./scripts/migrate-lessons.sh --date-from today \
      --ignore-heading '^## (Sails|Schema|Billing|Data|Verification|Frontend|Infrastructure|Retired)'
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply) APPLY=1; shift ;;
        --format)
            shift
            [[ $# -eq 0 ]] && { echo "migrate-lessons: --format requires table|numbered|dated" >&2; exit 2; }
            case "$1" in
                table|numbered|dated) FORMAT="$1" ;;
                *) echo "migrate-lessons: --format must be table|numbered|dated, got '$1'" >&2; exit 2 ;;
            esac
            shift ;;
        --date-from)
            shift
            [[ $# -eq 0 ]] && { echo "migrate-lessons: --date-from requires git|today|<YYYY-MM-DD>" >&2; exit 2; }
            DATE_FROM="$1"; shift ;;
        --ignore-heading)
            shift
            [[ $# -eq 0 ]] && { echo "migrate-lessons: --ignore-heading requires a regex" >&2; exit 2; }
            IGNORE_HEADINGS+="$1"$'\n'; shift ;;
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
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LESSONS_FILE="${LESSONS_FILE}" LESSONS_DIR="${LESSONS_DIR}" APPLY="${APPLY}" \
REPO_ROOT="${REPO_ROOT}" FORMAT="${FORMAT}" DATE_FROM="${DATE_FROM}" \
IGNORE_HEADINGS="${IGNORE_HEADINGS}" \
python3 - <<'PY'
import os, re, sys
from datetime import date as _date

TODAY = _date.today().isoformat()

# The format-independent half lives in scripts/lib/entry_split.py (v1.28), one
# definition shared with migrate-shipped.sh. This block runs from stdin, so
# there is no __file__ to resolve from — bash exports REPO_ROOT for it.
sys.path.insert(0, os.path.join(os.environ["REPO_ROOT"], "scripts", "lib"))
from entry_split import Entry, assign_filenames, report_and_abort, emit  # noqa: E402

src   = os.environ["LESSONS_FILE"]
out   = os.environ["LESSONS_DIR"]
apply_= os.environ["APPLY"] == "1"

fmt_arg    = os.environ.get("FORMAT", "")
date_from  = os.environ.get("DATE_FROM", "")
ignore_res = [re.compile(p) for p in
              os.environ.get("IGNORE_HEADINGS", "").split("\n") if p]

# Only the outer columns are pipe-free; the lesson body is greedy so embedded
# pipes inside backticks survive intact.
ROW = re.compile(
    r'^\|\s*(?P<date>[^|]+?)\s*\|\s*(?P<lesson>.*?)\s*'
    r'\|\s*(?P<project>[^|]+?)\s*\|\s*(?P<status>[^|]+?)\s*\|\s*$'
)
DATE = re.compile(r'^\d{4}-\d{2}-\d{2}$')

# `## L12 — title`. Em dash, en dash and plain hyphen all appear across
# consumers (kermit-v3 and SQRL use —); do not assume one.
NUMBERED = re.compile(r'^## L(?P<num>\d+)\s*[—–-]\s*(?P<title>.+?)\s*$')
# `## Title (2026-03-30)` — keystone_prototype's shape, date already present.
DATED    = re.compile(r'^## (?P<title>.+?)\s*\((?P<date>\d{4}-\d{2}-\d{2})\)\s*$')

lines = open(src, encoding='utf-8').read().split('\n')


def detect():
    """Pick a parser. Heading formats win over the table whenever they appear.

    NOT a raw count comparison. A heading-format file routinely contains
    markdown tables *inside* lesson bodies — SQRL's has a 60-row "Retired Index"
    mapping table, which outnumbers its 30 lesson headings and made an earlier
    count-based version pick 'table' and then abort on all 60 rows. The reverse
    never happens: a table-format file's rows are its entries, and a `## L<N>`
    heading in one would not be a table row. So any entry heading at all means
    the file is heading-format, and the table parser is the fallback.
    """
    numbered = sum(1 for l in lines if NUMBERED.match(l))
    dated    = sum(1 for l in lines if DATED.match(l))
    table    = sum(1 for l in lines
                   if l.startswith('| ')
                   and not re.match(r'^\|\s*(Date|-+)\s*\|', l))

    if numbered or dated:
        # Both heading shapes present in quantity is genuine ambiguity — that is
        # when a human chooses, not a heuristic.
        if numbered and dated and min(numbered, dated) > max(numbered, dated) // 4:
            print(f"migrate-lessons: ambiguous format — numbered={numbered}, "
                  f"dated={dated}. Pass --format numbered|dated.", file=sys.stderr)
            sys.exit(1)
        return 'numbered' if numbered >= dated else 'dated'

    if table:
        return 'table'

    print("migrate-lessons: no lessons found in any known format "
          f"(table/numbered/dated) in {src}", file=sys.stderr)
    sys.exit(1)


fmt = fmt_arg or detect()


def parse_table():
    rows, errors = [], []
    for lineno, line in enumerate(lines, 1):
        if not line.startswith('| '):
            continue
        if re.match(r'^\|\s*(Date|-+)\s*\|', line):      # header / separator
            continue
        m = ROW.match(line)
        if not m or not DATE.match(m['date']):
            errors.append((lineno, line))
            continue
        rows.append(Entry(date=m['date'], title_source=m['lesson'],
                          body=m['lesson']))
    return rows, errors, []


def parse_headings(pattern, dated):
    """Split on a specific `## ` pattern; everything to the next `## ` is body.

    A `## ` line matching neither the pattern nor an --ignore-heading regex
    ABORTS. That is what stops SQRL's 8 category headings from silently
    becoming 8 lessons.
    """
    out_entries, errors, ignored = [], [], []
    cur_head, cur_body = None, []

    def close():
        if cur_head is None:
            return
        m = pattern.match(cur_head)
        body = '\n'.join([cur_head] + cur_body).rstrip()
        out_entries.append(Entry(
            date=m.group('date') if dated else None,
            title_source=m.group('title'),
            body=body,
        ))

    for lineno, line in enumerate(lines, 1):
        if line.startswith('## '):
            close()
            cur_head, cur_body = None, []
            if pattern.match(line):
                cur_head = line
            elif any(r.search(line) for r in ignore_res):
                ignored.append(line.strip())
            else:
                errors.append((lineno, line))
            continue
        if cur_head is not None:
            cur_body.append(line)
    close()
    return out_entries, errors, ignored


if fmt == 'table':
    entries, errors, ignored = parse_table()
elif fmt == 'numbered':
    entries, errors, ignored = parse_headings(NUMBERED, dated=False)
else:
    entries, errors, ignored = parse_headings(DATED, dated=True)

report_and_abort(errors, "migrate-lessons",
                 line_label="UNPARSEABLE row at",
                 summary_noun="row(s) unparseable")

notes = [f"format: {fmt} ({len(entries)} entries)"]
if ignored:
    notes.append(f"{len(ignored)} heading(s) ignored per --ignore-heading:")
    notes += [f"    {h}" for h in ignored]

# The numbered format carries no date. Refuse to guess one.
if any(e.date is None for e in entries):
    if not date_from:
        print("migrate-lessons: this format has no per-entry date — pass "
              "--date-from git|today|<YYYY-MM-DD>", file=sys.stderr)
        sys.exit(1)
    if date_from == 'git':
        import subprocess
        repo_dir = os.path.dirname(os.path.abspath(src)) or '.'
        missed = 0
        for e in entries:
            head = e.body.split('\n', 1)[0]
            r = subprocess.run(
                ['git', 'log', '--diff-filter=A', '-S', head, '--reverse',
                 '--format=%ad', '--date=short', '--', os.path.abspath(src)],
                cwd=repo_dir, capture_output=True, text=True)
            first = r.stdout.strip().split('\n')[0] if r.stdout.strip() else ''
            if DATE.match(first):
                e.date = first
            else:
                e.date = TODAY
                missed += 1
        if missed:
            notes.append(f"WARNING: {missed} entr{'y' if missed == 1 else 'ies'} "
                         f"had no introducing commit — dated {TODAY}")
    elif date_from == 'today':
        for e in entries:
            e.date = TODAY
    elif DATE.match(date_from):
        for e in entries:
            e.date = date_from
    else:
        print(f"migrate-lessons: --date-from must be git|today|<YYYY-MM-DD>, "
              f"got '{date_from}'", file=sys.stderr)
        sys.exit(2)
elif date_from:
    print(f"migrate-lessons: --date-from is meaningless for the '{fmt}' format "
          "— every entry already carries its own date", file=sys.stderr)
    sys.exit(2)

planned, collisions = assign_filenames(entries, fallback="lesson")

# Duplicate L-numbers are real corruption worth surfacing, not an error: two
# sessions each appended what they thought was the next number. kermit-v3 has
# six such pairs. The number is not the filename key, so they migrate fine.
if fmt == 'numbered':
    nums = [NUMBERED.match(e.body.split('\n', 1)[0]).group('num') for e in entries]
    dupes = sorted({n for n in nums if nums.count(n) > 1}, key=int)
    if dupes:
        notes.append(f"{len(dupes)} duplicate L-number(s) found, migrating as "
                     f"distinct files: {', '.join('L' + d for d in dupes)}")

emit(planned, out, apply_, "migrate-lessons",
     summary=f"{len(planned)} row(s)", collisions=collisions, notes=notes)
PY
