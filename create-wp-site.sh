#!/bin/bash
# create-wp-site.sh - Creates a new WordPress Docker site with custom naming and dynamic ports

set -euo pipefail

# Handle cross-platform issues
command -v dos2unix >/dev/null 2>&1 && dos2unix "$0" 2>/dev/null || true

# Source shared library
source "$(dirname "$0")/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
show_usage() {
  echo "Usage: $0 [-c] [-n custom_name] [-p port]"
  echo "  -c               Clean up previous test instances before creating a new one"
  echo "  -n custom_name   Use custom name instead of timestamp (wp-test-custom_name)"
  echo "  -p port          Use custom port instead of 8080"
  echo ""
  echo "Examples:"
  echo "  $0 -n myproject                    # Creates wp-test-myproject on port 8080"
  echo "  $0 -c -n ecommerce                 # Clean up first, then create wp-test-ecommerce"
  echo "  $0 -n portfolio -p 8081            # Create wp-test-portfolio on port 8081"
  echo "  $0 -c -n blog -p 8082              # Clean up, create wp-test-blog on port 8082"
  exit 1
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
CLEANUP=0
CUSTOM_NAME=""
CUSTOM_PORT=""

while getopts "cn:p:h" opt; do
  case $opt in
    c) CLEANUP=1 ;;
    n) CUSTOM_NAME="$OPTARG" ;;
    p) CUSTOM_PORT="$OPTARG" ;;
    h) show_usage ;;
    \?) echo "Invalid option: -$OPTARG" >&2; show_usage ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; show_usage ;;
  esac
done
shift $((OPTIND-1))

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
[ -n "$CUSTOM_PORT" ] && validate_port "$CUSTOM_PORT"

# ---------------------------------------------------------------------------
# Optional cleanup
# ---------------------------------------------------------------------------
run_optional_cleanup "creation"

# ---------------------------------------------------------------------------
# Instance name
# ---------------------------------------------------------------------------
if [ -n "$CUSTOM_NAME" ]; then
  INSTANCE_NAME="wp-test-$(sanitize_name "$CUSTOM_NAME")"
else
  INSTANCE_NAME="wp-test-$(date +%Y%m%d-%H%M%S)"
fi

# ---------------------------------------------------------------------------
# Port resolution
# ---------------------------------------------------------------------------
if [ -n "$CUSTOM_PORT" ]; then
  WP_PORT="$CUSTOM_PORT"
  echo "Using specified port: $WP_PORT"
else
  WP_PORT=$(find_available_port 8080)
  echo "Using auto-detected available port: $WP_PORT"
fi

echo "Creating WordPress test environment: $INSTANCE_NAME"
echo "Site will be available at: http://localhost:$WP_PORT"
echo "=================================================="

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if [ -d "$INSTANCE_NAME" ]; then
  echo "ERROR: Directory '$INSTANCE_NAME' already exists!"
  echo "Please choose a different name or clean up the existing directory."
  exit 1
fi

if netstat -tuln 2>/dev/null | grep -q ":$WP_PORT " || ss -tuln 2>/dev/null | grep -q ":$WP_PORT "; then
  echo "ERROR: Port $WP_PORT is already in use!"
  echo "Please specify a different port with -p or let the script auto-detect."
  exit 1
fi

# ---------------------------------------------------------------------------
# Site directory setup
# ---------------------------------------------------------------------------
mkdir -p "$INSTANCE_NAME"
setup_cleanup_trap   # captures cwd; arms EXIT trap before we cd
cd "$INSTANCE_NAME"

cp ../dockerfile Dockerfile
cp ../wp-installer.sh wp-installer.sh

PMA_PORT=$((WP_PORT + 100))
generate_docker_compose "$WP_PORT" "$PMA_PORT" "$INSTANCE_NAME"

rm -rf wp-content
mkdir -p wp-content/themes wp-content/plugins

# Build the image so we can extract default wp-content from it
echo "Building WordPress image..."
docker-compose build -q

# Extract default themes/plugins from image into host wp-content (before containers start)
echo "Seeding default WordPress themes and plugins from image..."
_tmp=$(docker create wp-wordpress)
docker cp "$_tmp:/var/www/html/wp-content/themes/." wp-content/themes/
docker cp "$_tmp:/var/www/html/wp-content/plugins/." wp-content/plugins/
docker rm "$_tmp" > /dev/null

# ---------------------------------------------------------------------------
# Site info file
# ---------------------------------------------------------------------------
cat > site-info.txt << EOF
WordPress Site Information
=========================
Instance Name: $INSTANCE_NAME
Site URL: http://localhost:$WP_PORT
Admin URL: http://localhost:$WP_PORT/wp-admin
Admin Username: jerry
Admin Password: garcia
Created: $(date)
Directory: $(pwd)

phpMyAdmin Information
======================
Access URL: http://localhost:$PMA_PORT
Server: db
Username: wordpress
Password: wordpress
Database: wordpress

Quick Commands:
--------------
Start site:     docker-compose up -d
Stop site:      docker-compose down
Logs:           docker-compose logs
Status:         docker-compose ps
WordPress CLI:  docker-compose exec wordpress wp --help
Remove all:     docker-compose down -v
EOF

# ---------------------------------------------------------------------------
# Start containers and wait
# ---------------------------------------------------------------------------
echo "Starting Docker containers..."
docker-compose up -d

wait_for_containers

# ---------------------------------------------------------------------------
# Seed themes/plugins from project root wp-content (additive — defaults win)
# ---------------------------------------------------------------------------
echo "Checking project wp-content for additional themes/plugins..."
ADDED_ANY=0
WP_CONTAINER=$(docker-compose ps -q wordpress)

for type in themes plugins; do
  src="../wp-content/$type"
  dest="wp-content/$type"
  if [ -d "$src" ]; then
    for item_dir in "$src"/*/; do
      if [ -d "$item_dir" ]; then
        item_name=$(basename "$item_dir")
        if [ ! -d "$dest/$item_name" ]; then
          echo "  Adding $type/$item_name from project wp-content"
          # docker cp to bind-mounted paths on WSL2 reports spurious errors even when
          # the copy succeeds — suppress and verify afterward.
          docker cp "${item_dir%/}" "$WP_CONTAINER:/var/www/html/wp-content/$type/$item_name" 2>/dev/null || true
          if docker exec "$WP_CONTAINER" test -d "/var/www/html/wp-content/$type/$item_name" 2>/dev/null; then
            ADDED_ANY=1
          else
            echo "  Warning: failed to copy $type/$item_name"
          fi
        fi
      fi
    done
  fi
done

if [ "$ADDED_ANY" -eq 1 ]; then
  docker-compose exec -T wordpress chown -R www-data:www-data /var/www/html/wp-content
  if [ -d "../wp-content/plugins" ]; then
    for item_dir in "../wp-content/plugins"/*/; do
      if [ -d "$item_dir" ]; then
        item_name=$(basename "$item_dir")
        docker-compose exec -T wordpress wp plugin activate "$item_name" --allow-root 2>/dev/null \
          && echo "  Activated plugin: $item_name" \
          || echo "  Note: Could not activate plugin $item_name"
      fi
    done
  fi
else
  echo "No additional themes/plugins to add from project wp-content."
fi

# ---------------------------------------------------------------------------
# Accessibility check
# ---------------------------------------------------------------------------
echo "Testing site accessibility..."
SITE_URL="http://localhost:$WP_PORT"
if check_url "$SITE_URL" 12; then
  echo "✓ Site is accessible at $SITE_URL"
else
  echo "WARNING: Site may not be fully ready yet at $SITE_URL"
  echo "Check the logs for any issues:"
  echo "  docker-compose logs"
fi

# ---------------------------------------------------------------------------
# Manage script and success output
# ---------------------------------------------------------------------------
generate_manage_site_sh
disable_cleanup_trap

echo ""
echo "WordPress Site Creation Complete!"
echo "================================="
echo "Instance Name: $INSTANCE_NAME"
echo "Site URL: $SITE_URL"
echo "Admin URL: $SITE_URL/wp-admin"
echo "Admin login: jerry / garcia"
echo "Directory: $(pwd)"
echo "Port: $WP_PORT"
echo ""
echo "Site information saved to: site-info.txt"
echo ""
echo "Useful commands for this site:"
echo "  docker-compose logs          # View container logs"
echo "  docker-compose ps            # Check container status"
echo "  docker-compose exec wordpress wp --info  # WordPress info"
echo "  docker-compose down          # Stop containers"
echo "  docker-compose down -v       # Stop and remove volumes"
echo ""

echo "Final status check:"
echo "==================="
docker-compose ps

if docker-compose logs 2>&1 | grep -i error | grep -v "Access denied" | head -5; then
  echo ""
  echo "Note: Some errors were found in the logs above. The site may still work correctly."
fi
