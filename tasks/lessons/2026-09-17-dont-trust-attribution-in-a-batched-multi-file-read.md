# Don't trust which file a line of output belongs to in a batched, multi-file shell read

While researching `v1.38`'s spec, a single Bash call chained `find` + `cat <file> | grep -A3
-B3` against `kermit-v3/pyproject.toml`. The returned block's content (a long pin-history
comment) got mentally attributed to the wrong file, momentarily reading as if it belonged
to Keystone's — most likely because the same call was one of two run in parallel that
turn, and the two results' content got cross-attributed while skimming them side by side.
Had that wrong attribution shipped, the spec would have asserted the wrong consumer's pin
style (Keystone exact-pins vs. range-pins) as verified fact — exactly the class of error
`CLAUDE.md`'s "Verify Against Source of Truth" rule exists to prevent, except the failure
mode here wasn't skipping verification, it was misreading which command's output was being
read.

Do differently: when several parallel tool calls each touch a different file, and the
result is dense or unusually shaped, re-issue a narrower, single-purpose command per file
before writing the claim down — one file, one pattern, one call, so there's no cross-call
attribution to get wrong. This cost nothing here (a few extra `grep` calls) and is what
actually caught the mistake before it reached the spec.
