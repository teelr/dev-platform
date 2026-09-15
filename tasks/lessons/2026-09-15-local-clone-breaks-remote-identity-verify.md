# A local `git clone` breaks any check that verifies the remote's identity

Building `gate_release.sh`'s fresh-clone round trip (`git clone "${REPO}" "${CLONE_DIR}"`, then
`install.sh all` + `verify.sh` against it), the real run failed at `verify.sh`'s remote-verify step
(`verify-remotes.sh`) with "origin mismatch: expected `git@github.com:teelr/dev-platform.git`, got
`/home/rich/dev/.claude/worktrees/...`". `git clone <local-path>` sets the clone's `origin` to that
local path, not to whatever real remote the SOURCE repo itself points at — this is correct, expected
git behavior, not a bug in `verify.sh` or `install.sh`. The spec's own code, written and reasoned
through during `/plan`, didn't anticipate that `verify.sh`'s scope extends beyond symlink-deployment
checks into remote-identity verification, because nothing in `install.sh`/`verify.sh`'s own headers
suggested it — only running the fresh clone for real surfaced it.

Do differently: before trusting a local clone to stand in for a real one in any test, check whether
anything downstream inspects `git remote`/origin identity, not just file contents — a local clone is
byte-identical in tracked-file content but never identical in remote metadata. Fixed here with
`git -C "${CLONE_DIR}" remote set-url origin "<real-url>"` right after cloning (metadata-only, no
network call), reading the expected URL from `monitoring/remotes.json` rather than hardcoding it so
it can't drift from the registry.
