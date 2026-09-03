# Lessons Learned

Patterns from corrections. Reviewed at session start. Consolidated into CLAUDE.md rules when 2-3 similar entries emerge.

## One file per lesson

Each lesson is its own file, named `<YYYY-MM-DD>-<slug>.md`:

```text
2026-09-03-redirection-scope-bit-twice-in-one-change-both.md
```

That is the whole point. This used to be a single append-only table, which meant every session appended at the same place — so two sessions either conflicted or, worse, merged cleanly at different line offsets and left a silent duplicate. Separate files cannot collide.

The filename leads with the date, so **filename order is date order**. Read newest-first with `ls -1 tasks/lessons/*.md | sort -r`, not `ls -t` — mtime is checkout order, which reshuffles on every clone.

## Writing one

The `#` heading is a short title; the body is the lesson. Say what to do differently, not just what went wrong.

There is no cap on how many files live here — they do not conflict, so there is nothing to prune for. Session start reads the newest handful. What still applies is the consolidation rule: when 2-3 lessons point at the same root cause, promote them into a rule in `CLAUDE.md` and delete the specifics.

Converted from the old `tasks/lessons.md` table by `scripts/migrate-lessons.sh`, which is kept for projects that still need to make the same move.
