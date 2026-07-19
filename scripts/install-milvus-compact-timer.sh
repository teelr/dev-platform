#!/usr/bin/env bash
# Deploy the dev-platform Milvus-compaction timer from deploy/systemd/ ->
# ~/.config/systemd/user/, reload, and enable it. Idempotent + re-runnable.
#
# Found live 2026-07-19: any long-lived dev Milvus instance under sustained
# automated-test load can get stuck in a perpetual ~10s compaction-retry
# cycle from an accumulated dropped-segment backlog, pegging a full CPU core
# continuously. This timer runs scripts/compact_dev_milvus.py on a schedule
# so the backlog never has a chance to build back up. See that script's own
# header comment for the full incident writeup.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${HOME}/.config/systemd/user"
mkdir -p "$DEST"

for u in "$REPO"/deploy/systemd/dev-platform-milvus-compact.service "$REPO"/deploy/systemd/dev-platform-milvus-compact.timer; do
    install -m 0644 "$u" "$DEST/$(basename "$u")"
    echo "installed $(basename "$u")"
done

loginctl enable-linger "$USER" 2>/dev/null || true

systemctl --user daemon-reload
systemctl --user enable --now dev-platform-milvus-compact.timer
echo "enabled + started dev-platform-milvus-compact.timer"
echo ""
echo "Next scheduled run:"
systemctl --user list-timers dev-platform-milvus-compact.timer --no-pager
