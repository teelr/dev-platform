# Lessons Learned

Patterns from corrections in {{PROJECT_NAME}}. Reviewed at session start. Consolidated into `/home/rich/dev/CLAUDE.md` rules when 2-3 similar entries emerge across projects.

## One file per lesson

Each lesson is its own file here, named `<YYYY-MM-DD>-<slug>.md`, with a `#` title and a few sentences saying what to do differently.

One file per lesson so two sessions never append to the same place. A single shared table conflicts on every concurrent `/code` turn — or worse, merges cleanly at different line offsets and leaves a silent duplicate.

Read the newest few with `ls -1 tasks/lessons/*.md | sort -r | head -5`. Sort by NAME, not `ls -t`: the filename leads with the date, whereas mtime is checkout order.

No entries yet.
