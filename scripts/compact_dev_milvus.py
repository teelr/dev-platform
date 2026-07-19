#!/usr/bin/env python3
"""Compact every dev/test Milvus instance found running on this box.

Found live 2026-07-19 (kermit-v3 session): kermit-dev-milvus was stuck in a
perpetual ~10s "force trigger a level zero compaction" cycle, pegging a full
CPU core continuously — one collection had 119 of 122 total segments marked
dropped (stale, awaiting cleanup) from months of accumulated test churn.
A single manual Collection.compact() call cleared the backlog completely
(CPU dropped from 100%+ to ~2.5%). The same symptom (continuous compaction
triggers) was also observed on keystone-dev-milvus and kermit-test-milvus,
suggesting this is a shared characteristic of any long-lived dev Milvus
instance under sustained automated-test load, not specific to one project.

This tool is deliberately environment-wide (dev-platform's job, not any one
project's) — it discovers every running container with "milvus" in its name
via `docker ps`, resolves each one's published host port for the gRPC
interface (19530/tcp inside the container), and runs a full compaction on
every collection it finds. No project-specific hardcoding — a new project's
dev Milvus is picked up automatically the next time this runs.

Safe by construction: this only ever touches containers already running on
the box (never starts one), and Collection.compact() is a normal, routine
Milvus maintenance operation (not destructive — it merges/cleans storage,
never drops live data). No production Milvus instance exists on this box as
of 2026-07-19 (verified: `docker ps -a --format '{{.Names}}' | grep -i
prod.*milvus` returns nothing) — if one is ever added, exclude it by naming
convention (this script only intentionally targets *-dev-*/*-test-*/*-pa-*
style dev instances; broaden PROJECT_NAME_EXCLUDE below if a prod instance
is ever added under a name this pattern would otherwise match).

Usage:
    python3 scripts/compact_dev_milvus.py
"""
import subprocess
import sys
import time

# Container names containing any of these substrings are skipped even if
# they match "milvus" — a defensive allowlist-by-exclusion, not currently
# needed (no prod Milvus exists on this box) but cheap insurance against a
# future prod instance accidentally matching the generic "milvus" pattern.
PROJECT_NAME_EXCLUDE = ("prod",)

GRPC_CONTAINER_PORT = "19530/tcp"
COMPACTION_POLL_INTERVAL_S = 2
COMPACTION_TIMEOUT_S = 60


def _run(cmd: list[str]) -> str:
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout.strip()


def discover_milvus_containers() -> list[str]:
    names = _run(["docker", "ps", "--format", "{{.Names}}"]).splitlines()
    matched = [n for n in names if "milvus" in n.lower()]
    return [n for n in matched if not any(x in n.lower() for x in PROJECT_NAME_EXCLUDE)]


def resolve_host_port(container: str) -> int | None:
    try:
        out = _run(["docker", "port", container, GRPC_CONTAINER_PORT])
    except subprocess.CalledProcessError:
        return None
    # Output like: "0.0.0.0:19534\n[::]:19534" — take the first IPv4 mapping.
    for line in out.splitlines():
        if line.startswith("0.0.0.0:"):
            return int(line.rsplit(":", 1)[1])
    return None


def compact_container(container: str, port: int) -> None:
    from pymilvus import connections, utility, Collection

    alias = f"compact_{container}"
    connections.connect(alias=alias, host="127.0.0.1", port=str(port))
    try:
        collections = utility.list_collections(using=alias)
        if not collections:
            print(f"  {container}: no collections, nothing to compact")
            return
        for name in collections:
            c = Collection(name, using=alias)
            entities_before = c.num_entities
            compaction_id = c.compact()
            deadline = time.time() + COMPACTION_TIMEOUT_S
            state = None
            while time.time() < deadline:
                state = c.get_compaction_state()
                if getattr(state, "state", None) is not None and "Completed" in str(state):
                    break
                time.sleep(COMPACTION_POLL_INTERVAL_S)
            print(
                f"  {container}/{name}: compaction {compaction_id} — "
                f"entities={entities_before} — final state: {state}"
            )
    finally:
        connections.disconnect(alias)


def main() -> int:
    containers = discover_milvus_containers()
    if not containers:
        print("No running Milvus containers found.")
        return 0

    print(f"Found {len(containers)} Milvus container(s): {', '.join(containers)}")
    had_error = False
    for container in containers:
        port = resolve_host_port(container)
        if port is None:
            print(f"  {container}: could not resolve a published host port for {GRPC_CONTAINER_PORT}, skipping")
            had_error = True
            continue
        try:
            compact_container(container, port)
        except Exception as e:  # noqa: BLE001 - best-effort per-container, one failure must not abort the rest
            print(f"  {container}: compaction failed: {e}")
            had_error = True

    return 1 if had_error else 0


if __name__ == "__main__":
    sys.exit(main())
