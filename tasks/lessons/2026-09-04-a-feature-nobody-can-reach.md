# A knob the caller cannot turn is not a feature

`ROADMAP_PATH` shipped in v1.13, four scripts read it, and `docs/CI-INTEGRATION.md` told consumers how to set it — but the reusable workflow accepted only a `ref` input, so no consumer could reach it from CI. The documented instruction (`env:` on the calling job) is not even valid YAML for a `uses:` job. Keystone built, broke and debugged a workaround for a feature that already existed.

When adding an env-var knob to a script that runs inside CI **someone else invokes**, trace the whole path from their config to your `os.environ.get` before documenting it. The question is not "does the script read it" but "can the caller set it" — and for a reusable workflow the only channel is a declared `inputs:` entry wired to `env:` on the step. Write the doc from the caller's side, not the script's.

Related: [[2026-09-04-empty-env-var-is-not-unset-in-python]].
