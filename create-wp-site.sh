#!/bin/bash
# create-wp-site.sh - Enhanced version with custom naming, dynamic ports, and fixed argument parsing

set -euo pipefail

# Handle cross-platform issues
command -v dos2unix >/dev/null 2>&1 && dos2unix "$0" 2>/dev/null || true

# Function to show usage
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
CUSTOM_NAME=""
CUSTOM_PORT=""

# Parse command line arguments using proper while loop
while getopts "cn:p:h" opt; do
  case $opt in
    c)
      CLEANUP=1
      ;;
    n)
      CUSTOM_NAME="$OPTARG"
      ;;
    p)
      CUSTOM_PORT="$OPTARG"
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

# Validate port if specified
if [ -n "$CUSTOM_PORT" ]; then
  if ! [[ "$CUSTOM_PORT" =~ ^[0-9]+$ ]] || [ "$CUSTOM_PORT" -lt 1024 ] || [ "$CUSTOM_PORT" -gt 65535 ]; then
    echo "ERROR: Port must be a number between 1024 and 65535"
    exit 1
  fi
fi

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
  
  echo "Cleanup complete. Proceeding with site creation..."
  echo ""
fi

# Generate instance name
if [ -n "$CUSTOM_NAME" ]; then
  # Sanitize custom name (remove special characters, replace spaces with hyphens)
  SANITIZED_NAME=$(echo "$CUSTOM_NAME" | sed 's/[^a-zA-Z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
  INSTANCE_NAME="wp-test-$SANITIZED_NAME"
else
  INSTANCE_NAME="wp-test-$(date +%Y%m%d-%H%M%S)"
fi

# Determine port to use
if [ -n "$CUSTOM_PORT" ]; then
  WP_PORT="$CUSTOM_PORT"
  echo "Using specified port: $WP_PORT"
else
  WP_PORT=$(find_available_port 8080)
  if [ $? -ne 0 ]; then
    echo "ERROR: Could not find an available port"
    exit 1
  fi
  echo "Using auto-detected available port: $WP_PORT"
fi

echo "Creating WordPress test environment: $INSTANCE_NAME"
echo "Site will be available at: http://localhost:$WP_PORT"
echo "=================================================="

# Check if directory already exists
if [ -d "$INSTANCE_NAME" ]; then
  echo "ERROR: Directory '$INSTANCE_NAME' already exists!"
  echo "Please choose a different name or clean up the existing directory."
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
cp ../docker-compose.yml docker-compose.yml

# Calculate phpMyAdmin port (WordPress port + 100)
PMA_PORT=$((WP_PORT + 100))

# Substitute port and instance name variables in docker-compose.yml
sed -i "s|8080:80|$WP_PORT:80|g" docker-compose.yml
sed -i "s|8180:80|$PMA_PORT:80|g" docker-compose.yml
sed -i "s|http://localhost:8080|http://localhost:$WP_PORT|g" docker-compose.yml
sed -i "s|wp-test-phpmyadmin-8080|wp-test-phpmyadmin-$WP_PORT|g" docker-compose.yml
sed -i "s|WordPress Dev - Jerry's WordPress Dev|WordPress Dev - $INSTANCE_NAME|g" docker-compose.yml

# Remove any existing wp-content directory if it exists
rm -rf wp-content

# Create a site info file for easy reference
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

# Fixed function to check database connection using correct credentials
check_db_connection() {
  # Test database connectivity using the WordPress container with correct credentials
  docker-compose exec -T wordpress mysql -h db -u wordpress -pwordpress -e "SELECT 1;" wordpress 2>/dev/null
  return $?
}

# Function to check if containers are healthy
check_containers_healthy() {
  # Check if both containers are running
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
  echo ""
  echo "WordPress logs:"
  docker-compose logs wordpress
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
SITE_URL="http://localhost:$WP_PORT"
if check_url "$SITE_URL" 12; then
  echo "✓ Site is accessible at $SITE_URL"
else
  echo "WARNING: Site may not be fully ready yet at $SITE_URL"
  echo "Check the logs for any issues:"
  echo "  docker-compose logs"
fi

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

# Optional: Open browser (uncomment if desired)
# if command -v open &> /dev/null; then
#   echo "Opening site in browser..."
#   open "$SITE_URL"
# elif command -v xdg-open &> /dev/null; then
#   echo "Opening site in browser..."
#   xdg-open "$SITE_URL"
# fi

# Final status check
echo "Final status check:"
echo "==================="
docker-compose ps

# Check for any actual errors in logs (ignore the access denied messages which are expected)
if docker-compose logs 2>&1 | grep -i error | grep -v "Access denied" | head -5; then
  echo ""
  echo "Note: Some errors were found in the logs above. The site may still work correctly."
fi

# Create a quick access script for this site
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
echo "Site management script created: manage-site.sh"