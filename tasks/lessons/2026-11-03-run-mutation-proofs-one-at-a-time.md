# Run mutation proofs one at a time, and diff the file back to the original

A mutation proof edits the real file in place, runs the suite, then restores it from a copy.
Two mutation runs sent in the same tool batch share that one file, so each can restore or
mutate underneath the other and the results mean nothing even when they look right. Run each
mutation in its own call, and finish with `diff` of the file against the saved original so a
leftover mutation cannot ship. For a check that depends on the clock (an empty `date -d ""`
reads as midnight today, "recent" only between 00:00 and 02:00), put a `date` shim first in
`PATH` for the test so it fails or passes the same at any hour.
