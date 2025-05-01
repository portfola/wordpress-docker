#!/bin/bash
# create-wp-site.sh

# Generate a unique name for this instance
INSTANCE_NAME="wp-test-$(date +%Y%m%d-%H%M%S)"

# Create project directory
mkdir -p "$INSTANCE_NAME"
cd "$INSTANCE_NAME"

# Copy Docker files
cp ./dockerfile Dockerfile
cp ./docker-entrypoint-custom.sh docker-entrypoint-custom.sh
cp ./docker-compose.yml docker-compose.yml

# Start containers
docker-compose up -d

echo "WordPress site starting at http://localhost"
echo "Admin login: jerry / garcia"