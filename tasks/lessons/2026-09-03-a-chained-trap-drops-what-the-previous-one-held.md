# In a suite that chains EXIT traps, adding a temp dir means removing it yourself

`tests/worktree/run.sh` builds its cleanup trap incrementally — each block re-declares `trap 'rm -rf "${tmp1}" ... "${tmpN}"' EXIT` with one more directory. A block that adds a temp dir the *later* traps do not list therefore leaks it on every run, silently, because `trap` replaces rather than appends. I introduced exactly that in v1.22 with `tmp6b`; 43 directories had accumulated in `/tmp` before the next change happened to look.

Two things follow. When adding a block to a suite like this, `rm -rf` your own temp dir at the end of the block rather than trusting the trap chain — the trap is only correct until the next block redefines it. And when a test creates something heavier than files (this one registered a git worktree), the leak is worth checking for directly: run the suite twice and compare `ls -d /tmp/tmp.* | wc -l`.
