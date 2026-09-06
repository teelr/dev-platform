# Fixing a defect can obsolete the fixture that encoded it

`tests/migration-coverage` used kermit's real `## L19+` and `## L51+L60` as its lossy-path fixture, because those headings were unparseable. Widening the parser to accept them — the whole point of the next change — made the fixture stop exercising the branch it was written for, and two assertions went red in the gate rather than in the suite I was editing.

That failure was correct and worth having: the fixture, not the code, was out of date. When a fix removes a real-world example, check whether any test used that example *as* the failure case, and replace it with a form that still is one — here, a malformed label and a heading with no title separator. Copying a real defect into a fixture is good practice; it just carries an expiry date once the defect is fixed.
