# A "the pattern never happens" heuristic needs to be checked against the existing fixtures, not just the one real file that motivated it

`migrate-lessons.sh`'s `detect()` fix (v1.37) was first written as "only count `| ` table rows found
*before* the first `## ` heading" — reasoned from kermit's real file, where the residual reference
table sits after a `## Renumbering note` heading, and the stated assumption that "a genuine
table-format file is a flat table under one H1, never mixed with `## ` subsections." That assumption
was never checked against this repo's own existing fixtures before shipping the fix — `bash -n`
passed, the fix worked against kermit's real file, and `tests/migration-formats/run.sh` was run only
*after* the position-based version was already written. Running the *existing* suite immediately
surfaced `tests/lessons-dir/run.sh`'s `good.md` fixture: dev-platform's own canonical table format,
with a real `## Active Lessons` heading directly *before* its table — the exact shape the new
assumption said couldn't exist, misdetected as "nothing to migrate" and breaking 6 previously-passing
checks.

Do differently: before trusting a new heuristic's stated assumption ("X never happens", "the real
case is always shaped like Y"), run the full existing test suite against the change *before* writing
new fixtures for the new case — an old fixture is exactly the kind of counterexample a motivating
example can't surface, because it wasn't written with the new case in mind. The eventual fix used a
schema check instead (does the row match the table's actual 4-column-plus-date shape) — a property of
the row's *content*, not its *position* relative to other structure — which needed no assumption
about heading placement at all.
