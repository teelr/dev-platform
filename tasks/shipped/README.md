# Shipped record

One file per shipped entry. Hashes are intentionally omitted — `git log` is the authoritative record; these files are the human-readable narrative.

## Naming

```text
2026-09-03-v1.23-lessons-directory.md    a shipped Roadmap Phase
2026-08-20-merge-post-merge-chore.md     a chore (no version number)
```

The date leads, so **filename order is date order**: read newest-first with `ls -1 tasks/shipped/*.md | sort -r`, never `ls -t` (mtime is checkout order and reshuffles on every clone). Phase filenames can never collide because Roadmap Phase versions are claimed atomically (v1.11).

## Why one file per entry

This used to be planning.md's "Recently shipped" section, which every `/code` turn prepended a bullet to — so two concurrent sessions collided on every pair of finishes, or merged cleanly at different offsets and left a silent duplicate. Separate files cannot collide. Same reasoning as `tasks/lessons/` (v1.23).

`/code` writes one file here per shipped phase (problem → what shipped → key findings); `/merge`'s Change Summary reads the file the merge added. Converted from the old section by `scripts/migrate-shipped.sh`, kept for projects making the same move.
