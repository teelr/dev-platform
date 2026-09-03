# A practice documented only in a reference doc will stop happening

Cutting a release tag at phase completion was written down — in `docs/GLOSSARY.md`'s "Cut release" entry. It still stopped after v1.13 and left twelve phases unpinnable while every consumer sat on `@v0.7` and consequently never ran the version-collision guard at all. Closing the milestone, the action taken at the same moment by the same person, never once drifted: it is a step in `commands/merge.md`, which `/merge` executes.

The difference is not how well either was documented. It is that one lives in a runbook something runs and the other lived in a doc someone reads. When a practice must happen every time, put it in the executable step and give it a detector, the way v1.10 paired the milestone close with `check-phase-milestones.sh`. A glossary entry records what a term means; it cannot make anything happen.
