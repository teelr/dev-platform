#!/usr/bin/env python3
"""entry_split.py — the format-independent half of the migration scripts.

`migrate-lessons.sh` and `migrate-shipped.sh` both split one markdown file into
one file per entry. Only the *parser* differs between them — what counts as an
entry. Everything downstream (slug, title, collision-safe filenames, abort
reporting, dry-run/apply emit) was near-duplicate across both, and would have
been triplicated the moment a third format arrived. v1.28 added four formats, so
it was extracted here first.

Near-duplicate, not identical, and the differences are deliberate: `slugify`'s
empty-slug fallback was `'lesson'` in one caller and `'entry'` in the other, so
it is a parameter rather than a constant. Merging it to one value would silently
rename files for one caller.

TWO CONTRACTS THIS FILE ENFORCES, both load-bearing when pointed at hundreds of
irreplaceable entries:

1. An unparseable entry ABORTS the whole run and names the line. A silently
   skipped entry is undetectable once the source file is deleted.
2. The derived title is COSMETIC. The original entry text is always written to
   the body verbatim, so a poor title split can never lose content.

    from entry_split import Entry, slugify, titleize, assign_filenames, \
        report_and_abort, emit
"""

from __future__ import annotations

import os
import re
import sys
import unicodedata
from dataclasses import dataclass
from typing import Optional


@dataclass
class Entry:
    """One parsed entry, on its way to one file.

    date          YYYY-MM-DD. Parsers that cannot source a date leave this None
                  and the caller fills it (see migrate-lessons.sh --date-from).
    title_source  Text the cosmetic title is derived from.
    body          The entry VERBATIM, written to the file unchanged.
    version       v<X.Y> for a shipped phase; None for lessons and chores. Set,
                  it selects the <date>-v<X.Y>-<slug>.md filename shape.
    slug_source   Text the slug is derived from, when it differs from
                  title_source. It does for shipped phases: the pre-extraction
                  script titled them "v<X.Y> <Title>" but slugged <Title> alone,
                  so collapsing the two would rename every phase file. Defaults
                  to title_source.
    """

    date: Optional[str]
    title_source: str
    body: str
    version: Optional[str] = None
    slug_source: Optional[str] = None

    def slug_from(self) -> str:
        return self.slug_source if self.slug_source is not None else self.title_source


def slugify(text: str, words: int = 8, fallback: str = "entry") -> str:
    """Filename-safe slug from arbitrary entry text.

    `fallback` differs by caller — 'lesson' for migrate-lessons.sh, 'entry' for
    migrate-shipped.sh. Kept as a parameter so the extraction cannot silently
    rename either caller's output.
    """
    text = re.sub(r'`[^`]*`', ' ', text)          # code spans make poor slugs
    text = unicodedata.normalize('NFKD', text)
    text = text.encode('ascii', 'ignore').decode()
    parts = re.findall(r'[A-Za-z0-9]+', text)[:words]
    slug = '-'.join(p.lower() for p in parts)[:50].strip('-')
    return slug or fallback


def titleize(text: str, words: int = 12) -> str:
    """Cosmetic only. The full entry always goes in the body regardless."""
    plain = re.sub(r'\s+', ' ', text).strip()
    toks = plain.split(' ')
    if len(toks) <= words:
        return plain.rstrip('.')
    return ' '.join(toks[:words]).rstrip(',;:').rstrip('.') + '…'


def assign_filenames(entries: list[Entry], fallback: str = "entry") -> tuple[list[tuple[str, Entry]], int]:
    """Map entries to unique filenames, resolving collisions with -2, -3, ….

    Returns (planned, collision_count). Never overwrites: a repeated base name
    gets a numeric suffix. Repeats are legitimate — a project can ship two
    phases of one version on one day, and two lessons can slugify alike.
    """
    taken: set[str] = set()
    planned: list[tuple[str, Entry]] = []
    collisions = 0
    for e in entries:
        slug = slugify(e.slug_from(), fallback=fallback)
        base = f"{e.date}-{e.version}-{slug}" if e.version else f"{e.date}-{slug}"
        name, n = f"{base}.md", 1
        while name in taken:
            n += 1
            name = f"{base}-{n}.md"
            collisions += 1
        taken.add(name)
        planned.append((name, e))
    return planned, collisions


def report_and_abort(errors: list[tuple], tool: str,
                     line_label: str = "UNPARSEABLE at",
                     summary_noun: str = "problem(s)") -> None:
    """Print every unparseable line and exit 1. Never partially writes.

    `errors` entries are (lineno, line) or (lineno, why, line).

    The two labels are parameters because the pre-extraction scripts worded
    these differently — migrate-lessons said "UNPARSEABLE row at" and
    "N row(s) unparseable", migrate-shipped said "UNPARSEABLE at" and
    "N problem(s)". Their test suites assert on that wording, and the
    extraction is required to be behaviour-identical.
    """
    if not errors:
        return
    for err in errors:
        if len(err) == 3:
            lineno, why, line = err
            print(f"{tool}: {line_label} line {lineno} ({why}):", file=sys.stderr)
        else:
            lineno, line = err
            print(f"{tool}: {line_label} line {lineno}:", file=sys.stderr)
        print(f"  {line[:160]}", file=sys.stderr)
    print(f"{tool}: aborting, {len(errors)} {summary_noun} — nothing written",
          file=sys.stderr)
    sys.exit(1)


def emit(planned: list[tuple[str, Entry]], out: str, apply_: bool, tool: str,
         summary: str, collisions: int = 0, notes: Optional[list[str]] = None,
         apply_summary: Optional[str] = None) -> None:
    """Dry-run report, or write one file per entry. Exits the process.

    `summary` is the caller's dry-run count phrasing. `apply_summary` is the
    parenthetical on the apply line, and is omitted when None — migrate-lessons
    printed no parenthetical there and migrate-shipped printed one, a difference
    the extraction must preserve. `notes` are informational lines (ignored
    headings, duplicate numbers) shown in BOTH modes, because they are what an
    operator needs before deciding to --apply.
    """
    for note in (notes or []):
        print(f"{tool}: {note}")

    if not apply_:
        print(f"{tool}: DRY RUN — {summary} would become {len(planned)} file(s) in {out}/")
        print(f"{tool}: re-run with --apply to write them")
        sys.exit(0)

    os.makedirs(out, exist_ok=True)
    for name, e in planned:
        with open(os.path.join(out, name), 'w', encoding='utf-8') as fh:
            fh.write(f"# {titleize(e.title_source)}\n\n{e.body}\n")

    tail = f" ({apply_summary})" if apply_summary else ""
    print(f"{tool}: wrote {len(planned)} file(s) to {out}/{tail}")
    if collisions:
        print(f"{tool}: {collisions} filename collision(s) resolved with a numeric suffix")
