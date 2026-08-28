# shell/

Shell helpers, aliases, functions, and git-hook templates that support the dev-platform workflow outside Claude Code itself.

**What goes here:** two kinds of file, split by whether they are *sourced* or *executed*.

- `shell/profile.d/*.sh` — **sourced** into the user's interactive shell at startup (function libraries, e.g. `claude-tmux.sh`). Must be safe to source: no top-level side effects, no `${1:?...}` guards, no `exit`.
- `shell/*.sh` at the top level — **executed** as scripts (e.g. `new-session.sh`). These are NOT safe to source: `new-session.sh` aborts on its `${1:?usage}` guard, which would break shell startup. That is why the sourced set lives in its own subdirectory.
- `shell/git-hooks/` — git hook templates (`pre-commit`, `commit-msg`) that projects opt into per-repo.
- `shell/worktree/` — worktree-isolation tooling (`link-deps.sh`, `gate-lock.sh`) used by `/code` and project gate scripts.

**What does NOT go here:** Claude Code hook scripts (those go in `hooks/`); per-project shell helpers (those belong in the project's `scripts/` directory); secrets or machine-specific paths (use a sourced `*.local.sh` overlay instead, gitignored).

**Deployment:** `./scripts/install.sh shell` symlinks `shell/profile.d/*.sh` into `~/.claude/profile.d/` and prints the loop to add to `.bashrc`. The target is `~/.claude/profile.d/` — deliberately not a nested `~/.claude/shell/profile.d/`, because `scripts/uninstall.sh` sweeps `find ~/.claude -maxdepth 2 -type l` and a three-deep path would survive uninstall while `.bashrc` kept sourcing this repo. Top-level `shell/*.sh` are not deployed; run them by full path. `shell/worktree/` deploys via `./scripts/install.sh worktree`. Git hook templates are opted into per-project via `git config core.hooksPath ~/.claude/git-hooks`.

## `cc` — Claude Code in tmux

`shell/profile.d/claude-tmux.sh` defines `cc`, which runs Claude Code inside tmux so a session survives the VS Code remote server exiting. That server runs with `--enable-remote-auto-shutdown` and quits five minutes after the last client disconnects; its exit destroys the pty host and kills every `claude` running in a terminal. The tmux server is owned by init, so it sits outside that process tree.

```text
cc                      session named for the current directory
cc kermit-v3            resolved under $CC_PROJECT_ROOT (default ~/dev/projects)
cc ~/some/path          any directory
cc kermit-v3 --resume   unrecognised arguments pass through to claude
cc -n review kermit-v3  explicit session name (a second one, same project)
cc --list               show live sessions
cc --kill NAME          end one session
cc --help
```

Session names are the directory's last segment with `.` and `:` replaced by `_`, since tmux treats both as target-syntax separators — so a worktree at `v0.37+phase-1` becomes session `v0_37+phase-1`. When claude exits, the pane falls back to a login shell rather than closing the session.

**`cc` shadows `/usr/bin/cc`, the C compiler.** This is deliberate. Build tools (`make`, `cargo`, `cmake`) invoke `cc` through `execvp`, and bash functions are not inherited by child processes, so builds are unaffected — only typing `cc foo.c` at a prompt. Use `command cc` or `\cc` to reach the compiler.

`cc` and `new-session.sh` coexist: `new-session.sh` deliberately creates a new worktree + branch + window when the branch name is known upfront, while `cc` is the everyday attach-or-start path. Both name the session after the directory, so `cc` attaches to a session `new-session.sh` created rather than duplicating it.
