# Mandatory SHA pinning also covers the actions an action calls, so a grep of your workflows is not a pre-check

Before turning on the repo setting `sha_pinning_required`, the v1.42 check was "no workflow
still uses a tag" (a `grep` of `.github/workflows`, all ten `uses:` lines pinned). It passed, the
setting went on, and the next Pages deploy failed: the pinned `actions/upload-pages-artifact`
v3.0.1 is a composite action that calls `actions/upload-artifact@v4` by tag inside itself, and
the enforcement rejects that too ("all actions must be pinned to a full-length commit SHA").

Do differently: the workflow files are not the whole set of references. Before enabling
enforcement, read the `action.yml` of each composite action you use (`uses:` entries inside it
are in scope), or enable it and immediately re-run every workflow that uses an action
(`workflow_dispatch` or a re-run) while it is still easy to switch off. Have a way to turn it back off before you turn it on (here a single `PUT` with
`sha_pinning_required=false`). And a deploy that passed earlier proves nothing about the state
after a setting changed: re-run it after the change, not before.
