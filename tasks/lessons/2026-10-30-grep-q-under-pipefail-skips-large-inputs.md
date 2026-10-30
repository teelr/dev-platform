# grep -q at the end of a pipe, under pipefail, silently turns a match into "no match" on large input

The v1.41 secret scan used `... | grep -E '^\+' | grep -qE "${combined}" || return 0` as a
fast path. `grep -q` exits at the first match, the upstream `grep` then gets SIGPIPE, and
with `set -o pipefail` the pipeline status is 141, not 0, so `|| return 0` skipped the scan.
It only happened when the diff was big enough that the upstream had not finished, so every
test (tiny diffs) passed and a secret in a 10,001-line commit was missed.

Do differently: at the end of a pipe under `pipefail`, count with `grep -c` and test the
number, not `grep -q` and the exit status. And for any scanner, include one test with an
input big enough to be buffered, with the needle in the middle, asserting the exact location.
Tiny fixtures cannot reveal this class of bug; a throwaway sanity script with a large input
found it.
