# A heuristic built from one consumer's data fits only that consumer

`check-migration-coverage.sh` reported `NEEDS --ignore-heading` for any unparseable `## ` heading, because the case it was written from — SQRL, whose 8 unparseable rows are all category labels like `## Frontend` — made that true. On kermit, 2 of 3 are real lessons carrying that repo's own consolidation numbering (`## L19+ —`, `## L51+L60 —`). Following the advice would have silently dropped both, which is precisely the loss the parser's abort exists to prevent.

When a check emits *advice* rather than a fact, test it against a second consumer before shipping — the discriminator here (`## L<digit>` means content, not a category) was obvious once two datasets sat side by side and invisible with one. Prefer a verdict that names what it saw (`UNPARSEABLE (2 entries, 1 headings)`) over one that prescribes a fix, and when the prescription is destructive, say so in the summary rather than trusting the reader to know.
