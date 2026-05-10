#!/usr/bin/env bash
# Start {{PROJECT_NAME}} Next.js dev server.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ ! -d node_modules ]]; then
    echo "installing deps"
    npm install
fi

exec npm run dev
