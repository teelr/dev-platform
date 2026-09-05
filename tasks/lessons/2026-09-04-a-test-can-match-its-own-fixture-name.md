# A grep assertion can pass by matching the fixture's own name

The check for "a behind row with nothing tracking it is marked `untracked`" ran `grep -q "untracked"` against a table row whose project was named `untracked-1`. It passed against code that rendered no marker at all, because the project name satisfied the grep. Written to fail first, it reported success first — the exact opposite of what a detector-first assertion is for.

Name fixtures so they cannot contain the string under test (`unfiled-1`, not `untracked-1`), and assert on the **rendered form** including its separator (`· untracked`) rather than a bare word that can appear anywhere in the line. Then confirm the assertion actually fails before the feature exists — a "write the test first" step only works if you read the first run's result rather than assuming it.

Related: [[2026-09-04-mutation-tests-need-a-real-result-not-a-proxy]].
