#!/bin/bash
# import-wp-site.sh - Import WordPress site from downloaded database dump and wp-content

set -euo pipefail

# Handle cross-platform issues
command -v dos2unix >/dev/null 2>&1 && dos2unix "$0" 2>/dev/null || true

# Function to show usage
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

# Function to find next available port
find_available_port() {
  local start_port=${1:-8080}
  local port=$start_port

  while [ $port -le 8200 ]; do
    # Check if port is used by system services
    local port_in_use=0
    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
      port_in_use=1
    fi

    # Also check if any of our existing sites are using this port
    if [ $port_in_use -eq 0 ]; then
      for dir in wp-test-*; do
        if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
          local existing_port=$(grep -o '"[0-9]*:80"' "$dir/docker-compose.yml" 2>/dev/null | sed 's/"//g' | cut -d: -f1)
          if [ "$existing_port" = "$port" ]; then
            port_in_use=1
            break
          fi
        fi
      done
    fi

    if [ $port_in_use -eq 0 ]; then
      echo $port
      return 0
    fi
    ((port++))
  done

  echo "ERROR: No available ports found between $start_port and 8200" >&2
  return 1
}

# Default values
CLEANUP=0
SITE_NAME=""
DB_FILE=""
WP_CONTENT_DIR=""
CUSTOM_PORT=""

# Parse command line arguments
while getopts "n:d:w:p:ch" opt; do
  case $opt in
    n)
      SITE_NAME="$OPTARG"
      ;;
    d)
      DB_FILE="$OPTARG"
      ;;
    w)
      WP_CONTENT_DIR="$OPTARG"
      ;;
    p)
      CUSTOM_PORT="$OPTARG"
      ;;
    c)
      CLEANUP=1
      ;;
    h)
      show_usage
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      show_usage
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      show_usage
      ;;
  esac
done

# Shift past the parsed options
shift $((OPTIND-1))

# Validate required arguments
if [ -z "$SITE_NAME" ] || [ -z "$DB_FILE" ] || [ -z "$WP_CONTENT_DIR" ]; then
  echo "ERROR: Missing required arguments (-n, -d, -w)" >&2
  show_usage
fi

# Validate database file exists and is readable
if [ ! -f "$DB_FILE" ]; then
  echo "ERROR: Database file not found: $DB_FILE" >&2
  exit 1
fi

if [ ! -r "$DB_FILE" ]; then
  echo "ERROR: Database file is not readable: $DB_FILE" >&2
  exit 1
fi

# Validate wp-content path exists and is readable
# Can be either a directory or a tar.gz file
if [ ! -e "$WP_CONTENT_DIR" ]; then
  echo "ERROR: wp-content path not found: $WP_CONTENT_DIR" >&2
  exit 1
fi

if [ ! -r "$WP_CONTENT_DIR" ]; then
  echo "ERROR: wp-content path is not readable: $WP_CONTENT_DIR" >&2
  exit 1
fi

# Validate port if specified
if [ -n "$CUSTOM_PORT" ]; then
  if ! [[ "$CUSTOM_PORT" =~ ^[0-9]+$ ]] || [ "$CUSTOM_PORT" -lt 1024 ] || [ "$CUSTOM_PORT" -gt 65535 ]; then
    echo "ERROR: Port must be a number between 1024 and 65535" >&2
    exit 1
  fi
fi

# Convert paths to absolute before changing directories
if command -v realpath &> /dev/null; then
  DB_FILE=$(realpath "$DB_FILE")
  WP_CONTENT_DIR=$(realpath "$WP_CONTENT_DIR")
else
  # Fallback for systems without realpath
  DB_FILE=$(cd "$(dirname "$DB_FILE")" && pwd)/$(basename "$DB_FILE")
  WP_CONTENT_DIR=$(cd "$(dirname "$WP_CONTENT_DIR")" && pwd)/$(basename "$WP_CONTENT_DIR")
fi

# Perform cleanup if requested
if [ $CLEANUP -eq 1 ]; then
  echo "Running cleanup of previous WordPress test instances..."

  if [ -f "./cleanup-wp-sites.sh" ] && [ -x "./cleanup-wp-sites.sh" ]; then
    ./cleanup-wp-sites.sh -f
  else
    echo "Warning: cleanup-wp-sites.sh not found or not executable"
    echo "Skipping cleanup phase"
  fi

  echo "Cleanup complete. Proceeding with site import..."
  echo ""
fi

# Sanitize site name (same pattern as create-wp-site.sh)
SANITIZED_NAME=$(echo "$SITE_NAME" | sed 's/[^a-zA-Z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
INSTANCE_NAME="wp-test-$SANITIZED_NAME"

# Determine port to use
if [ -n "$CUSTOM_PORT" ]; then
  WP_PORT="$CUSTOM_PORT"
  echo "Using specified port: $WP_PORT"
else
  WP_PORT=$(find_available_port 8080)
  if [ $? -ne 0 ]; then
    echo "ERROR: Could not find an available port" >&2
    exit 1
  fi
  echo "Using auto-detected available port: $WP_PORT"
fi

echo "Importing WordPress site: $INSTANCE_NAME"
echo "Site will be available at: http://localhost:$WP_PORT"
echo "=================================================="

# Check if directory already exists
if [ -d "$INSTANCE_NAME" ]; then
  echo "ERROR: Directory '$INSTANCE_NAME' already exists!"
  echo "Please choose a different name or remove the existing directory."
  exit 1
fi

# Check if port is in use
if netstat -tuln 2>/dev/null | grep -q ":$WP_PORT " || ss -tuln 2>/dev/null | grep -q ":$WP_PORT "; then
  echo "ERROR: Port $WP_PORT is already in use!"
  echo "Please specify a different port with -p or let the script auto-detect."
  exit 1
fi

# Create project directory
mkdir -p "$INSTANCE_NAME"
cd "$INSTANCE_NAME"

# Copy Docker files
cp ../dockerfile Dockerfile
cp ../wp-installer.sh wp-installer.sh

# Create docker-compose.yml (same template as create-wp-site.sh)
cat > docker-compose.yml << EOF
services:
  # MySQL Service
  db:
    image: mysql:5.7
    platform: linux/amd64
    volumes:
      - db_data:/var/lib/mysql
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wordpress
      MYSQL_PASSWORD: wordpress
    networks:
      - wordpress_net
    # Health check
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      timeout: 20s
      retries: 5
      interval: 5s

  # WordPress Service
  wordpress:
    build:
      context: .
      dockerfile: Dockerfile
    platform: linux/amd64
    image: wp-wordpress
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "$WP_PORT:80"
    restart: always
    volumes:
      - wp_data:/var/www/html
      # Use conditional mounting for wp-content
      - \${PWD}/wp-content:/var/www/html/wp-content:delegated
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_NAME: wordpress
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: wordpress
      WORDPRESS_SITE_URL: http://localhost:$WP_PORT
      WORDPRESS_SITE_TITLE: WordPress Dev - $INSTANCE_NAME
      WORDPRESS_ADMIN_USER: jerry
      WORDPRESS_ADMIN_PASSWORD: garcia
      WORDPRESS_ADMIN_EMAIL: admin@example.com
    networks:
      - wordpress_net
    # Simplified startup command
    entrypoint: ["/bin/bash", "-c"]
    command:
      - |
        # Fix any potential line ending issues
        dos2unix /usr/local/bin/wp-installer.sh 2>/dev/null || true

        # Start Apache in background
        apache2-foreground &
        export APACHE_PID=\$!

        # Wait a moment for Apache to start
        sleep 5

        # Fix wp-content permissions for Windows/WSL compatibility
        mkdir -p /var/www/html/wp-content/upgrade
        mkdir -p /var/www/html/wp-content/uploads
        chown -R www-data:www-data /var/www/html/wp-content 2>/dev/null || true
        chmod -R 755 /var/www/html/wp-content 2>/dev/null || true

        # Run our installer script
        /usr/local/bin/wp-installer.sh

        # Keep Apache running
        wait \$APACHE_PID

networks:
  wordpress_net:

volumes:
  db_data:
  wp_data:
EOF

# Remove any existing wp-content directory if it exists
rm -rf wp-content

# Copy or extract wp-content from provided path
echo "Setting up wp-content..."
if [ -d "$WP_CONTENT_DIR" ]; then
  # It's a directory - copy it
  echo "Copying wp-content directory..."
  cp -r "$WP_CONTENT_DIR" wp-content
elif [ -f "$WP_CONTENT_DIR" ] && [[ "$WP_CONTENT_DIR" == *.tar.gz ]]; then
  # It's a tar.gz file - extract it
  echo "Extracting wp-content from tar.gz..."
  mkdir -p wp-content
  tar -xzf "$WP_CONTENT_DIR" -C wp-content --strip-components=1 2>/dev/null || \
    tar -xzf "$WP_CONTENT_DIR" -C wp-content
elif [ -f "$WP_CONTENT_DIR" ] && [[ "$WP_CONTENT_DIR" == *.tar ]]; then
  # It's a tar file - extract it
  echo "Extracting wp-content from tar..."
  mkdir -p wp-content
  tar -xf "$WP_CONTENT_DIR" -C wp-content --strip-components=1 2>/dev/null || \
    tar -xf "$WP_CONTENT_DIR" -C wp-content
else
  echo "ERROR: wp-content must be a directory or tar/tar.gz file: $WP_CONTENT_DIR" >&2
  cd ..
  rm -rf "$INSTANCE_NAME"
  exit 1
fi

echo "Starting Docker containers..."
docker-compose up -d

# Function to check database connection
check_db_connection() {
  docker-compose exec -T wordpress mysql -h db -u wordpress -pwordpress -e "SELECT 1;" wordpress 2>/dev/null
  return $?
}

# Function to check WordPress installation status
check_wp_installed() {
  docker-compose exec -T wordpress wp core is-installed --allow-root 2>/dev/null
  return $?
}

# Function to check if containers are healthy
check_containers_healthy() {
  local db_status=$(docker-compose ps -q db | xargs docker inspect --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
  local wp_status=$(docker-compose ps -q wordpress | xargs docker inspect --format='{{.State.Status}}' 2>/dev/null || echo "none")

  [ "$db_status" = "healthy" ] && [ "$wp_status" = "running" ]
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

# First wait for the database container to be healthy
while ! check_containers_healthy && [ $DB_WAIT -lt $MAX_DB_WAIT ]; do
  echo "  Waiting for containers to be healthy... ($DB_WAIT/$MAX_DB_WAIT seconds)"
  sleep 5
  DB_WAIT=$((DB_WAIT + 5))
done

# Then test the actual database connection
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

# Wait for WordPress to be accessible
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

echo "✓ WordPress is accessible"

echo ""
echo "Importing database..."
echo "===================="

# Drop and recreate the wordpress database, then import the SQL file
echo "Dropping existing database and importing new data..."
docker-compose exec -T wordpress bash -c \
  "mysql -h db -u wordpress -pwordpress -e 'DROP DATABASE IF EXISTS wordpress; CREATE DATABASE wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'"

# Import the SQL dump
docker-compose exec -T wordpress bash -c \
  "mysql -h db -u wordpress -pwordpress wordpress" < "$DB_FILE"

echo "✓ Database imported successfully"

# Auto-detect live site URL from imported database
echo ""
echo "Detecting live site URL..."
LIVE_URL=$(docker-compose exec -T wordpress wp option get siteurl --allow-root 2>/dev/null || echo "")

if [ -z "$LIVE_URL" ]; then
  echo "WARNING: Could not detect live site URL from database"
else
  echo "Live site URL detected: $LIVE_URL"

  # Check if URL needs updating
  LOCAL_URL="http://localhost:$WP_PORT"
  if [ "$LIVE_URL" != "$LOCAL_URL" ]; then
    echo ""
    echo "Running search and replace to update URLs..."

    # Replace main URL
    docker-compose exec -T wordpress \
      wp search-replace "$LIVE_URL" "$LOCAL_URL" \
      --allow-root --all-tables --report-changed-only 2>/dev/null || echo "  (primary replacement complete)"

    # Also handle www variant if applicable
    if [[ "$LIVE_URL" == https://* ]]; then
      LIVE_URL_HTTP="${LIVE_URL//https:\/\//http://}"
      if [ "$LIVE_URL_HTTP" != "$LOCAL_URL" ]; then
        docker-compose exec -T wordpress \
          wp search-replace "$LIVE_URL_HTTP" "$LOCAL_URL" \
          --allow-root --all-tables --report-changed-only 2>/dev/null || true
      fi
    fi

    # Handle www variant
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

# Flush rewrite rules
echo ""
echo "Flushing rewrite rules..."
docker-compose exec -T wordpress wp rewrite flush --allow-root 2>/dev/null || true
echo "✓ Rewrite rules flushed"

# Reset credentials - ensure jerry/garcia admin exists
echo ""
echo "Resetting admin credentials..."
ADMIN_ID=$(docker-compose exec -T wordpress wp user list --field=ID --role=administrator --allow-root 2>/dev/null | head -n 1)

if [ -n "$ADMIN_ID" ]; then
  # Update first admin user to jerry/garcia
  docker-compose exec -T wordpress wp user update "$ADMIN_ID" \
    --user_login=jerry \
    --user_email=jerry@example.com \
    --allow-root 2>/dev/null || true
  docker-compose exec -T wordpress wp user list --allow-root 2>/dev/null | grep jerry > /dev/null || \
    docker-compose exec -T wordpress wp user create jerry jerry@example.com --role=administrator --allow-root 2>/dev/null || true
else
  # Create jerry admin if no admin exists
  docker-compose exec -T wordpress wp user create jerry jerry@example.com --role=administrator --allow-root 2>/dev/null || true
fi

# Set password for jerry user
docker-compose exec -T wordpress wp user list --allow-root 2>/dev/null | grep -q jerry && \
  docker-compose exec -T wordpress wp user update jerry --prompt=user_pass --allow-root <<< "garcia" 2>/dev/null || true

echo "✓ Admin credentials reset (jerry/garcia)"

# Create site-info.txt
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

Quick Commands:
--------------
Start site:     docker-compose up -d
Stop site:      docker-compose down
Logs:           docker-compose logs
Status:         docker-compose ps
WordPress CLI:  docker-compose exec wordpress wp --help
Remove all:     docker-compose down -v
EOF

# Create manage-site.sh (identical to create-wp-site.sh version)
cat > manage-site.sh << 'EOF'
#!/bin/bash
# Quick management script for this WordPress site

case "$1" in
    start)
        echo "Starting WordPress site..."
        docker-compose up -d
        ;;
    stop)
        echo "Stopping WordPress site..."
        docker-compose down
        ;;
    restart)
        echo "Restarting WordPress site..."
        docker-compose down
        docker-compose up -d
        ;;
    logs)
        docker-compose logs -f
        ;;
    status)
        docker-compose ps
        ;;
    wp)
        shift
        docker-compose exec wordpress wp "$@" --allow-root
        ;;
    remove)
        echo "WARNING: This will completely remove the site and all data!"
        read -p "Are you sure? (y/N): " confirm
        if [[ $confirm == [yY] ]]; then
            docker-compose down -v
            cd ..
            rm -rf "$(basename "$(pwd)")"
            echo "Site removed completely."
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|logs|status|wp|remove}"
        echo ""
        echo "Examples:"
        echo "  $0 start              # Start the site"
        echo "  $0 stop               # Stop the site"
        echo "  $0 logs               # View logs"
        echo "  $0 wp plugin list     # List WordPress plugins"
        echo "  $0 remove             # Remove site completely"
        exit 1
        ;;
esac
EOF

chmod +x manage-site.sh

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

# Final status check
echo "Final status check:"
echo "==================="
docker-compose ps
