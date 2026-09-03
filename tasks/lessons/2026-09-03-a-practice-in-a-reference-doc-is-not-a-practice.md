# A practice documented only in a reference doc will stop happening

Cutting a release tag at phase completion was written down — in `docs/GLOSSARY.md`'s "Cut release" entry. It still stopped after v1.13 and left twelve phases unpinnable, freezing every consumer at `@v1.12` or `@v1.13`: a tag nobody cut is one nobody can pin, and Dependabot cannot bump to it either. Closing the milestone, the action taken at the same moment by the same person, never once drifted: it is a step in `commands/merge.md`, which `/merge` executes.

*(Corrected 2026-09-03 in v1.27. This lesson originally said every consumer sat on `@v0.7` and had therefore never run the version-collision guard. Both halves were wrong — see [`2026-09-03-verify-consumer-state-against-the-consumer.md`](2026-09-03-verify-consumer-state-against-the-consumer.md). The lesson's actual point is unaffected.)*

The difference is not how well either was documented. It is that one lives in a runbook something runs and the other lived in a doc someone reads. When a practice must happen every time, put it in the executable step and give it a detector, the way v1.10 paired the milestone close with `check-phase-milestones.sh`. A glossary entry records what a term means; it cannot make anything happen.
