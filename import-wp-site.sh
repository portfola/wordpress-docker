#!/bin/bash
# import-wp-site.sh - Import WordPress site from downloaded database dump and wp-content

set -euo pipefail

# Handle cross-platform issues
command -v dos2unix >/dev/null 2>&1 && dos2unix "$0" 2>/dev/null || true

# Source shared library
source "$(dirname "$0")/lib/common.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
show_usage() {
  echo "Usage: $0 -n local_name -d /path/to/db.sql -w /path/to/wp-content [-p port] [-c]"
  echo ""
  echo "Required:"
  echo "  -n  Local site name (creates wp-test-<name>)"
  echo "  -d  Path to SQL database dump file"
  echo "  -w  Path to wp-content (directory, .tar, or .tar.gz)"
  echo ""
  echo "Optional:"
  echo "  -p  Local port (default: auto-detect 8080-8200)"
  echo "  -c  Clean up all existing wp-test-* sites first"
  echo ""
  echo "Examples:"
  echo "  $0 -n myclient -d ~/downloads/myclient.sql -w ~/downloads/wp-content"
  echo "  $0 -n staging -d /tmp/db.sql -w /tmp/wp-content.tar.gz -p 8085"
  exit 1
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
CLEANUP=0
SITE_NAME=""
DB_FILE=""
WP_CONTENT_DIR=""
CUSTOM_PORT=""

while getopts "n:d:w:p:ch" opt; do
  case $opt in
    n) SITE_NAME="$OPTARG" ;;
    d) DB_FILE="$OPTARG" ;;
    w) WP_CONTENT_DIR="$OPTARG" ;;
    p) CUSTOM_PORT="$OPTARG" ;;
    c) CLEANUP=1 ;;
    h) show_usage ;;
    \?) echo "Invalid option: -$OPTARG" >&2; show_usage ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; show_usage ;;
  esac
done
shift $((OPTIND-1))

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if [ -z "$SITE_NAME" ] || [ -z "$DB_FILE" ] || [ -z "$WP_CONTENT_DIR" ]; then
  echo "ERROR: Missing required arguments (-n, -d, -w)" >&2
  show_usage
fi

if [ ! -f "$DB_FILE" ]; then
  echo "ERROR: Database file not found: $DB_FILE" >&2
  exit 1
fi

if [ ! -r "$DB_FILE" ]; then
  echo "ERROR: Database file is not readable: $DB_FILE" >&2
  exit 1
fi

if [ ! -e "$WP_CONTENT_DIR" ]; then
  echo "ERROR: wp-content path not found: $WP_CONTENT_DIR" >&2
  exit 1
fi

if [ ! -r "$WP_CONTENT_DIR" ]; then
  echo "ERROR: wp-content path is not readable: $WP_CONTENT_DIR" >&2
  exit 1
fi

[ -n "$CUSTOM_PORT" ] && validate_port "$CUSTOM_PORT"

# Resolve absolute paths before any cd
if command -v realpath &> /dev/null; then
  DB_FILE=$(realpath "$DB_FILE")
  WP_CONTENT_DIR=$(realpath "$WP_CONTENT_DIR")
else
  DB_FILE=$(cd "$(dirname "$DB_FILE")" && pwd)/$(basename "$DB_FILE")
  WP_CONTENT_DIR=$(cd "$(dirname "$WP_CONTENT_DIR")" && pwd)/$(basename "$WP_CONTENT_DIR")
fi

# ---------------------------------------------------------------------------
# Optional cleanup
# ---------------------------------------------------------------------------
run_optional_cleanup "import"

# ---------------------------------------------------------------------------
# Instance name and port
# ---------------------------------------------------------------------------
INSTANCE_NAME="wp-test-$(sanitize_name "$SITE_NAME")"

if [ -n "$CUSTOM_PORT" ]; then
  WP_PORT="$CUSTOM_PORT"
  echo "Using specified port: $WP_PORT"
else
  WP_PORT=$(find_available_port 8080)
  echo "Using auto-detected available port: $WP_PORT"
fi

echo "Importing WordPress site: $INSTANCE_NAME"
echo "Site will be available at: http://localhost:$WP_PORT"
echo "=================================================="

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if [ -d "$INSTANCE_NAME" ]; then
  echo "ERROR: Directory '$INSTANCE_NAME' already exists!"
  echo "Please choose a different name or remove the existing directory."
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

# ---------------------------------------------------------------------------
# Extract / copy wp-content
# ---------------------------------------------------------------------------
echo "Setting up wp-content..."
if [ -d "$WP_CONTENT_DIR" ]; then
  echo "Copying wp-content directory..."
  cp -r "$WP_CONTENT_DIR" wp-content
elif [ -f "$WP_CONTENT_DIR" ] && [[ "$WP_CONTENT_DIR" == *.tar.gz ]]; then
  echo "Extracting wp-content from tar.gz..."
  EXTRACT_TMP=$(mktemp -d)
  tar -xzf "$WP_CONTENT_DIR" -C "$EXTRACT_TMP"
  FOUND_WP=$(find "$EXTRACT_TMP" -type d -name "wp-content" | head -n 1)
  if [ -z "$FOUND_WP" ]; then
    echo "ERROR: Could not find wp-content directory in archive" >&2
    rm -rf "$EXTRACT_TMP"
    exit 1
  fi
  cp -r "$FOUND_WP" wp-content
  rm -rf "$EXTRACT_TMP"
elif [ -f "$WP_CONTENT_DIR" ] && [[ "$WP_CONTENT_DIR" == *.tar ]]; then
  echo "Extracting wp-content from tar..."
  EXTRACT_TMP=$(mktemp -d)
  tar -xf "$WP_CONTENT_DIR" -C "$EXTRACT_TMP"
  FOUND_WP=$(find "$EXTRACT_TMP" -type d -name "wp-content" | head -n 1)
  if [ -z "$FOUND_WP" ]; then
    echo "ERROR: Could not find wp-content directory in archive" >&2
    rm -rf "$EXTRACT_TMP"
    exit 1
  fi
  cp -r "$FOUND_WP" wp-content
  rm -rf "$EXTRACT_TMP"
else
  echo "ERROR: wp-content must be a directory or tar/tar.gz file: $WP_CONTENT_DIR" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Start containers and wait
# ---------------------------------------------------------------------------
echo "Starting Docker containers..."
docker-compose up -d

wait_for_containers

# ---------------------------------------------------------------------------
# Database import
# ---------------------------------------------------------------------------
echo ""
echo "Importing database..."
echo "===================="

echo "Dropping existing database and importing new data..."
docker-compose exec -T db bash -c \
  "mysql -u wordpress -pwordpress -e 'DROP DATABASE IF EXISTS wordpress; CREATE DATABASE wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'"

docker-compose exec -T db bash -c \
  "mysql -u wordpress -pwordpress wordpress" < "$DB_FILE"

echo "✓ Database imported successfully"

# ---------------------------------------------------------------------------
# URL search-replace
# ---------------------------------------------------------------------------
echo ""
echo "Detecting live site URL..."
LIVE_URL=$(docker-compose exec -T wordpress wp option get siteurl --allow-root 2>/dev/null || echo "")

if [ -z "$LIVE_URL" ]; then
  echo "WARNING: Could not detect live site URL from database"
else
  echo "Live site URL detected: $LIVE_URL"

  LOCAL_URL="http://localhost:$WP_PORT"
  if [ "$LIVE_URL" != "$LOCAL_URL" ]; then
    echo ""
    echo "Running search and replace to update URLs..."

    docker-compose exec -T wordpress \
      wp search-replace "$LIVE_URL" "$LOCAL_URL" \
      --allow-root --all-tables --report-changed-only 2>/dev/null || echo "  (primary replacement complete)"

    if [[ "$LIVE_URL" == https://* ]]; then
      LIVE_URL_HTTP="${LIVE_URL//https:\/\//http://}"
      if [ "$LIVE_URL_HTTP" != "$LOCAL_URL" ]; then
        docker-compose exec -T wordpress \
          wp search-replace "$LIVE_URL_HTTP" "$LOCAL_URL" \
          --allow-root --all-tables --report-changed-only 2>/dev/null || true
      fi
    fi

    if [[ "$LIVE_URL" == *www.* ]]; then
      LIVE_URL_NO_WWW="${LIVE_URL//www./}"
      if [ "$LIVE_URL_NO_WWW" != "$LOCAL_URL" ]; then
        docker-compose exec -T wordpress \
          wp search-replace "$LIVE_URL_NO_WWW" "$LOCAL_URL" \
          --allow-root --all-tables --report-changed-only 2>/dev/null || true
      fi
    else
      LIVE_URL_WITH_WWW=$(echo "$LIVE_URL" | sed 's|://|://www.|')
      if [ "$LIVE_URL_WITH_WWW" != "$LOCAL_URL" ]; then
        docker-compose exec -T wordpress \
          wp search-replace "$LIVE_URL_WITH_WWW" "$LOCAL_URL" \
          --allow-root --all-tables --report-changed-only 2>/dev/null || true
      fi
    fi

    echo "✓ URL search and replace complete"
  fi
fi

# ---------------------------------------------------------------------------
# Flush rewrite rules
# ---------------------------------------------------------------------------
echo ""
echo "Refreshing permalinks..."
PERMALINK_STRUCTURE=$(docker-compose exec -T wordpress wp option get permalink_structure --allow-root 2>/dev/null | tr -d '[:space:]' || true)
if [ -n "$PERMALINK_STRUCTURE" ]; then
  docker-compose exec -T wordpress wp rewrite structure "$PERMALINK_STRUCTURE" --allow-root 2>/dev/null || true
fi
docker-compose exec -T wordpress wp rewrite flush --hard --allow-root 2>/dev/null || true
# wp rewrite flush --hard can't write .htaccess due to filesystem permissions; write it directly
docker-compose exec -T wordpress bash -c '
if [ ! -s /var/www/html/.htaccess ]; then
  cat > /var/www/html/.htaccess << "HTEOF"
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTEOF
fi
'
echo "✓ Permalinks refreshed"

# ---------------------------------------------------------------------------
# Reset admin credentials
# ---------------------------------------------------------------------------
echo ""
echo "Resetting admin credentials..."
ADMIN_ID=$(docker-compose exec -T wordpress wp user list --field=ID --role=administrator --allow-root 2>/dev/null | head -n 1)

if [ -n "$ADMIN_ID" ]; then
  # wp user update cannot change user_login — must do it directly in the DB
  docker-compose exec -T db mysql -u wordpress -pwordpress wordpress \
    -e "UPDATE wp_users SET user_login='jerry', user_email='jerry@example.com' WHERE ID=$ADMIN_ID;" 2>/dev/null || true
  docker-compose exec -T wordpress wp user update jerry \
    --user_pass=garcia \
    --allow-root 2>/dev/null || true
else
  docker-compose exec -T wordpress wp user create jerry jerry@example.com \
    --role=administrator \
    --user_pass=garcia \
    --allow-root 2>/dev/null || true
fi

echo "✓ Admin credentials reset (jerry/garcia)"

# ---------------------------------------------------------------------------
# Activate theme
# ---------------------------------------------------------------------------
echo ""
echo "Checking active theme..."
ACTIVE_THEME=$(docker-compose exec -T wordpress wp option get template --allow-root 2>/dev/null | tr -d '[:space:]')
THEME_EXISTS=$(docker-compose exec -T wordpress wp theme list --field=name --allow-root 2>/dev/null | grep -x "$ACTIVE_THEME" || true)

if [ -z "$THEME_EXISTS" ]; then
  # Active theme is missing — find any non-default theme in wp-content/themes and activate it
  IMPORTED_THEME=$(docker-compose exec -T wordpress wp theme list --field=name --allow-root 2>/dev/null \
    | grep -v -E '^twenty' | head -n 1 | tr -d '[:space:]' || true)
  if [ -n "$IMPORTED_THEME" ]; then
    echo "Active theme '$ACTIVE_THEME' not found — activating '$IMPORTED_THEME'..."
    docker-compose exec -T wordpress wp theme activate "$IMPORTED_THEME" --allow-root 2>/dev/null || true
    echo "✓ Theme '$IMPORTED_THEME' activated"
  else
    echo "WARNING: Active theme '$ACTIVE_THEME' not found and no imported theme available"
  fi
else
  echo "✓ Active theme '$ACTIVE_THEME' is present"
fi

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
Source DB: $(basename "$DB_FILE")
Source WP-Content: $(basename "$WP_CONTENT_DIR")

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
# Manage script and success output
# ---------------------------------------------------------------------------
generate_manage_site_sh
disable_cleanup_trap

echo ""
echo "WordPress Site Import Complete!"
echo "================================"
echo "Instance Name: $INSTANCE_NAME"
echo "Site URL: http://localhost:$WP_PORT"
echo "Admin URL: http://localhost:$WP_PORT/wp-admin"
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
echo "  ./manage-site.sh start       # Start the site"
echo "  ./manage-site.sh stop        # Stop the site"
echo ""

echo "Final status check:"
echo "==================="
docker-compose ps
