# Declaring `trap ... EXIT` twice replaces the first trap, it doesn't stack

`gate_release.sh`'s spec (written during `/plan`) declared `trap "rm -f '${_GATE_COUNTS_FILE}'" EXIT`
near the top, then later declared a second `trap "rm -rf '${CLONE_DIR}' '${FAKE_HOME}'; rm -f
'${_GATE_COUNTS_FILE}'" EXIT` once those two paths existed. Bash traps for a given signal don't
accumulate — the second `trap ... EXIT` call fully replaces the first. This one happened to still
work, because the second string was written to also repeat the first's cleanup — but that's a
coincidence of careful copying, not something the shell enforces, and it reads as if both traps fire.
Caught during `/code`'s adversarial self-review (re-reading the diff, not from any test failing —
the redundant cleanup meant nothing was actually left dirty).

Do differently: when a script accumulates scratch paths to clean up across its own execution,
declare ONE cleanup function up front (`_cleanup() { rm -f "${A:-}"; rm -rf "${B:-}" "${C:-}"; }`,
referencing variables that get set later in the script) and register it once with `trap _cleanup
EXIT` — the function only runs at actual exit, by which point every variable it references is set,
so declaration order doesn't matter. Never re-declare `trap ... EXIT` a second time to "add" a
cleanup target; a later declaration silently drops whatever the earlier one covered unless it's
manually repeated.
