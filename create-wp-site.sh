#!/bin/bash
# create-wp-site.sh

# Parse command line arguments
CLEANUP=0
while getopts "c" opt; do
  case $opt in
    c)
      CLEANUP=1
      ;;
    *)
      echo "Usage: $0 [-c]"
      echo "  -c  Clean up previous test instances before creating a new one"
      exit 1
      ;;
  esac
done

# Perform cleanup if requested
if [ $CLEANUP -eq 1 ]; then
  echo "Running cleanup of previous WordPress test instances..."
  
  # Check if cleanup script exists and is executable
  if [ -f "./cleanup-wp-sites.sh" ] && [ -x "./cleanup-wp-sites.sh" ]; then
    # Run cleanup script in force mode
    ./cleanup-wp-sites.sh -f
  else
    echo "Warning: cleanup-wp-sites.sh not found or not executable"
    echo "Skipping cleanup phase"
  fi
fi

# Generate a unique name for this instance
INSTANCE_NAME="wp-test-$(date +%Y%m%d-%H%M%S)"

# Create project directory
mkdir -p "$INSTANCE_NAME"
cd "$INSTANCE_NAME"

# Copy Docker files
cp ../dockerfile Dockerfile
cp ../wp-installer.sh wp-installer.sh
cp ../docker-compose.yml docker-compose.yml

# Remove any existing wp-content directory if it exists
rm -rf wp-content

# Start containers
docker-compose up -d

echo "WordPress site starting at http://localhost:8080"
echo "Admin login: jerry / garcia"
echo ""
echo "Container is initializing. WordPress and plugins are being installed..."
echo "This may take a minute. The wp-content directory will be populated from the container."