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


echo "=== Setup complete! ==="
echo "Run: ./create-wp-site.sh to create a new WordPress site"
echo "Run: ./cleanup-wp-sites.sh to clean up test sites"