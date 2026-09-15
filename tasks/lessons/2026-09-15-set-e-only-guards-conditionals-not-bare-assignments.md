# A bare command-substitution assignment isn't `set -e`-safe just because a sibling call site is

`scripts/sync-vscode-client.sh`'s `resolve_vscode_user_dir()` calls a failing `cmd.exe`/`wslpath`
inside a bare assignment (`appdata_win="$(cmd.exe ... | tr ...)"`), then string-concatenates the
next command's output onto a literal suffix (`"$(wslpath -u ...)/Code/User"`) without checking it
succeeded. Manual testing against a mocked failing `cmd.exe`/`wslpath` showed the function itself
degraded gracefully — but only because every call site happened to invoke it as the condition of
an `if` or the left side of `||`, both of which bash exempts from `errexit`. `install.sh`'s
deliberately-duplicated inline copy of the same logic (mirroring `install_vscode()`'s own
precedent of not sharing code with the standalone script) has no such wrapper — a bare assignment
inside a plain `if` *body* — so the identical failing `cmd.exe` silently killed the whole
`install.sh` run under `set -e`, skipping every category queued after it with zero error message.
A second, independent bug rode along: an empty failed command substitution concatenated with
`/Code/User` produces the literal string `/Code/User` — a plausible-looking absolute path at the
filesystem root — reported as a *successful* resolution instead of a failure.

Do differently: when wrapping an external command whose failure mode hasn't been tested, always
(1) check success explicitly (`if result="$(cmd)" ...` or append `|| true` plus a non-emptiness
check) before trusting the output, never rely on "empty string" as the only failure signal once
that output gets string-concatenated with anything, and (2) test every duplicated copy of a
function independently against the same failure injection — a fix verified only through the
original's call sites doesn't prove the duplicate is safe, especially when the duplication was a
deliberate, spec-documented decision (matching an established precedent) rather than an oversight.
