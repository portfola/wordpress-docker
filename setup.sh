#!/bin/bash
set -euo pipefail

echo "=== WordPress Docker Setup ==="

# Check platform first
source ./check-platform.sh

# Fix line endings for all scripts
echo "Fixing line endings..."
for script in *.sh; do
    if command -v dos2unix >/dev/null 2>&1; then
        dos2unix "$script" 2>/dev/null || true
    fi
    chmod +x "$script"
done

# Create wp-content directory if it doesn't exist
mkdir -p wp-content/themes wp-content/plugins wp-content/uploads

# Set appropriate permissions (Unix-like systems only)
if [[ "$PLATFORM" != "windows" ]]; then
    chmod -R 755 wp-content/
fi

echo "=== Setup complete! ==="
echo "Run: ./create-wp-site.sh to create a new WordPress site"
echo "Run: ./cleanup-wp-sites.sh to clean up test sites"