#!/bin/bash
# create-wp-site.sh - Enhanced version with monitoring and verification

set -euo pipefail

# Handle cross-platform issues
command -v dos2unix >/dev/null 2>&1 && dos2unix "$0" 2>/dev/null || true

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

echo "Creating WordPress test environment: $INSTANCE_NAME"
echo "=================================================="

# Create project directory
mkdir -p "$INSTANCE_NAME"
cd "$INSTANCE_NAME"

# Copy Docker files
cp ../dockerfile Dockerfile
cp ../wp-installer.sh wp-installer.sh
cp ../docker-compose.yml docker-compose.yml

# Remove any existing wp-content directory if it exists
rm -rf wp-content

echo "Starting Docker containers..."
# Start containers
docker-compose up -d

# Function to check if a URL is responding
check_url() {
  local url=$1
  local max_attempts=$2
  local attempt=1
  
  while [ $attempt -le $max_attempts ]; do
    if curl -s -f "$url" > /dev/null 2>&1; then
      return 0
    fi
    sleep 5
    ((attempt++))
  done
  return 1
}

# Function to check WordPress installation status
check_wp_installed() {
  docker-compose exec -T wordpress wp core is-installed --allow-root 2>/dev/null
  return $?
}

# Function to check database connection
check_db_connection() {
  # First check if WordPress container is ready
  if ! docker-compose exec -T wordpress test -f /var/www/html/wp-config.php 2>/dev/null; then
    return 1
  fi
  # Then check database connection
  docker-compose exec -T wordpress wp db check --allow-root 2>/dev/null
  return $?
}

echo ""
echo "Monitoring container startup..."
echo "==============================="

# Wait for containers to be running
echo "Waiting for containers to start..."
sleep 10

# Check if containers are running
if ! docker-compose ps | grep -q "Up"; then
  echo "ERROR: Containers failed to start!"
  echo "Container status:"
  docker-compose ps
  echo ""
  echo "Container logs:"
  docker-compose logs
  exit 1
fi

echo "✓ Containers are running"

# Wait for database to be ready
echo "Waiting for database connection..."
MAX_DB_WAIT=60
DB_WAIT=0
while ! check_db_connection && [ $DB_WAIT -lt $MAX_DB_WAIT ]; do
  echo "  Database not ready yet... ($DB_WAIT/$MAX_DB_WAIT seconds)"
  sleep 5
  DB_WAIT=$((DB_WAIT + 5))
done

if [ $DB_WAIT -ge $MAX_DB_WAIT ]; then
  echo "ERROR: Database connection timed out!"
  echo "Database logs:"
  docker-compose logs db
  exit 1
fi

echo "✓ Database connection established"

# Wait for WordPress installation
echo "Waiting for WordPress installation..."
MAX_WP_WAIT=120
WP_WAIT=0
while ! check_wp_installed && [ $WP_WAIT -lt $MAX_WP_WAIT ]; do
  echo "  WordPress installation in progress... ($WP_WAIT/$MAX_WP_WAIT seconds)"
  sleep 10
  WP_WAIT=$((WP_WAIT + 10))
done

if [ $WP_WAIT -ge $MAX_WP_WAIT ]; then
  echo "ERROR: WordPress installation timed out!"
  echo "WordPress logs:"
  docker-compose logs wordpress
  exit 1
fi

echo "✓ WordPress installation completed"

# Test if the site is accessible
echo "Testing site accessibility..."
if check_url "http://localhost:8080" 12; then
  echo "✓ Site is accessible at http://localhost:8080"
else
  echo "WARNING: Site may not be fully ready yet at http://localhost:8080"
  echo "Check the logs for any issues:"
  echo "  docker-compose logs"
fi

echo ""
echo "WordPress Site Creation Complete!"
echo "================================="
echo "Site URL: http://localhost:8080"
echo "Admin URL: http://localhost:8080/wp-admin"
echo "Admin login: jerry / garcia"
echo "Directory: $(pwd)"
echo ""
echo "Useful commands for this site:"
echo "  docker-compose logs          # View container logs"
echo "  docker-compose ps            # Check container status"
echo "  docker-compose exec wordpress wp --info  # WordPress info"
echo "  docker-compose down          # Stop containers"
echo "  docker-compose down -v       # Stop and remove volumes"
echo ""

# Optional: Open browser (uncomment if desired)
# if command -v open &> /dev/null; then
#   echo "Opening site in browser..."
#   open http://localhost:8080
# elif command -v xdg-open &> /dev/null; then
#   echo "Opening site in browser..."
#   xdg-open http://localhost:8080
# fi

# Final status check
echo "Final status check:"
echo "==================="
docker-compose ps

# Check for any errors in logs
if docker-compose logs 2>&1 | grep -i error | head -5; then
  echo ""
  echo "Note: Some errors were found in the logs above. The site may still work correctly."
fi