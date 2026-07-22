#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

# plain install is idempotent: fast no-op when node_modules already
# matches the lockfile, full install only when dependencies changed
pnpm install

echo "Ready to run Vite development server."

exec "$@"
