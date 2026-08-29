#!/usr/bin/env python3
"""repo_slug.py — derive `owner/repo` from a git remote URL, host-agnostically.

Every dev-platform script that talks to `gh` needs owner/repo from
`git remote get-url origin`. Three of them used to derive it independently, and
all three hardcoded the literal host `github.com` — so they broke on the SSH
host-alias remotes that dev-platform's own multi-account setup prescribes
(`git@github-teelr129:Osigin-LLC/SQRL.git`). See
https://github.com/teelr/dev-platform/issues/77.

This is the single implementation. Import it from Python, or call it as a CLI
from shell, but do not write a fourth copy of the rule.

The rule: strip a trailing slash, strip a trailing `.git`, then take the last
two path segments. It never inspects the host, so an alias, a GitHub Enterprise
domain, and plain github.com all parse identically. Stripping `.git` BEFORE
matching (rather than inside the pattern) is what allows a dotted repo name.

    URL                                        parse_repo_slug()
    ---------------------------------------    -----------------
    git@github.com:owner/repo.git              owner/repo
    https://github.com/owner/repo.git          owner/repo
    https://github.com/owner/repo              owner/repo
    ssh://git@github.com/owner/repo.git        owner/repo
    https://user@github.com/owner/repo.git     owner/repo
    git@github-teelr129:Osigin-LLC/SQRL.git    Osigin-LLC/SQRL
    git@github.com:owner/my.repo.git           owner/my.repo
    not-a-url                                  None
    ""                                         None

Accepted trade-off: because the host is ignored, a non-GitHub remote (GitLab,
Bitbucket) yields a plausible-looking slug instead of None, and fails later at
the `gh api` call rather than at parse time. Every caller requires `gh` anyway,
and callers name an unreachable repo among the possible causes.

This function NEVER raises. Callers decide what None means — they deliberately
differ (claim_roadmap_version.py raises, check_version_collision.py degrades to
SKIP, check-phase-milestones.sh errors and exits 2).

CLI: prints the slug and exits 0, or prints nothing and exits 1.

    python3 scripts/lib/repo_slug.py "$(git remote get-url origin)"
"""

from __future__ import annotations

import re
import sys

# [:/] so the scp-style `host:owner/repo` and the URL-style `/owner/repo` both
# work; [^/:]+ on the owner keeps `git@host:` out of it.
_SLUG_RE = re.compile(r"[:/]([^/:]+)/([^/]+)$")


def parse_repo_slug(url: str) -> str | None:
    """Return "owner/repo" from a git remote URL, or None if it doesn't parse."""
    if not url:
        return None
    cleaned = url.strip().rstrip("/")
    if cleaned.endswith(".git"):
        cleaned = cleaned[: -len(".git")]
    match = _SLUG_RE.search(cleaned)
    if not match:
        return None
    return f"{match.group(1)}/{match.group(2)}"


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: repo_slug.py <git-remote-url>", file=sys.stderr)
        return 2
    slug = parse_repo_slug(argv[1])
    if slug is None:
        return 1
    print(slug)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
