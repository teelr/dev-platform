# shell/

Shell helpers, aliases, functions, and git-hook templates that support the dev-platform workflow outside Claude Code itself.

**What goes here:** two kinds of file, split by whether they are *sourced* or *executed*.

- `shell/profile.d/*.sh` — **sourced** into the user's interactive shell at startup (function libraries, e.g. `claude-tmux.sh`). Must be safe to source: no top-level side effects, no `${1:?...}` guards, no `exit`.
- `shell/*.sh` at the top level — **executed** as scripts, run by full path. These are NOT safe to source: a script's top-level side effects and `${1:?usage}` guards would run at shell startup and break it. That split is why the sourced set lives in its own subdirectory. None ship today, but the rule governs anything added here.
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
cc --new                another session for the same project (-2, -3, ...)
cc -n kermit-v3-2       get back to a numbered session
cc -n review kermit-v3  explicit session name (a second one, same project)
cc --list               show live sessions
cc --kill NAME          end one session
cc --help
```

Session names are the directory's last segment with `.` and `:` replaced by `_`, since tmux treats both as target-syntax separators — so a worktree at `v0.37+phase-1` becomes session `v0_37+phase-1`. When claude exits, the pane falls back to a login shell rather than closing the session.

The file runs `unalias cc` before defining the function. An existing `cc` alias makes `cc() {` a parse error in interactive shells — alias expansion happens at parse time — so without that line the alias silently wins and the function is never defined. It only reproduces interactively, which is why `tests/shell/run.sh` uses `bash -i` for that one assertion.

**`cc` shadows `/usr/bin/cc`, the C compiler.** This is deliberate. Build tools (`make`, `cargo`, `cmake`) invoke `cc` through `execvp`, and bash functions are not inherited by child processes, so builds are unaffected — only typing `cc foo.c` at a prompt. Use `command cc` or `\cc` to reach the compiler.

### Running more than one session on a project

`cc --new` starts the next free numbered session — `kermit-v3-2`, then `-3`, then `-4` — in the same directory, and `cc -n kermit-v3-2` gets you back to one. It takes the lowest free number rather than counting up, so killing `-2` frees that name again.

`--new` does no git work. Whether those sessions can safely code in parallel depends on the project: one that has opted into worktree mode gets its own copy of the repo per session from `/plan` (see [`shell/worktree/README.md`](worktree/README.md)), while one that hasn't shares a single working tree and branch across every session. `cc --new` prints which of the two situations you are in when it starts the session.
