#!/bin/bash

# Startup script for Chatwoot in Dokploy with Railpack
set -e

# Configure PATH to find bundle
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# Configure LD_LIBRARY_PATH for shared libraries
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-/usr/lib:/usr/local/lib}"

# Configure environment variables
export RAILS_ENV=${RAILS_ENV:-production}
export NODE_ENV=${NODE_ENV:-production}
export PORT=${PORT:-3000}

# Verify that bundle is available
if ! command -v bundle &> /dev/null; then
    echo "Error: bundle not found. Trying alternative locations..."
    
    # Try common bundle locations
    for bundle_path in /usr/local/bin/bundle /usr/bin/bundle ~/.rbenv/shims/bundle ~/.rvm/gems/default/bin/bundle; do
        if [ -f "$bundle_path" ]; then
            echo "Bundle found at: $bundle_path"
            export PATH="$(dirname $bundle_path):$PATH"
            break
        fi
    done
    
    # Verify again
    if ! command -v bundle &> /dev/null; then
        echo "Error: Could not find bundle in any location"
        exit 1
    fi
fi

# Display debug information
echo "=== Environment Information ==="
echo "Ruby version: $(ruby --version)"
echo "Bundle version: $(bundle --version)"
echo "Rails env: $RAILS_ENV"
echo "Port: $PORT"
echo "PATH: $PATH"
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
echo "=============================="

# Execute release phase (preparation)
echo "Running release phase..."
POSTGRES_STATEMENT_TIMEOUT=600s bundle exec rails db:chatwoot_prepare
echo $SOURCE_VERSION > .git_sha || true

# Start Rails and Sidekiq with Foreman
echo "Starting Rails server and Sidekiq worker with Foreman..."
exec bundle exec foreman start -f Procfile
