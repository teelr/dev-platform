# Read line numbers and counts from command output; never write them from memory

`issue #131` quoted `taxonomy-check.yml` lines "~57-59 and ~94-96" for the `job_workflow_ref`
interpolation; the real lines were 74 and 103 (`grep -n`). The v1.42 spec then said the repo
had "nine `uses:` lines" when `grep -rn "uses:"` shows ten. Both were typed from an earlier read
instead of copied from a fresh one, and the first reached a public issue.

Do differently: when a spec, issue or record names a line number or a count, run the `grep -n`
or `grep -c` in the same turn and paste what it prints. A `~` in front of a number is a tell that
it was not measured; run the command or leave the number out.
