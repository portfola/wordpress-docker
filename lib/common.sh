#!/bin/bash
# lib/common.sh - Shared functions for WordPress Docker site management scripts
#
# Source this file at the top of create-wp-site.sh and import-wp-site.sh:
#   source "$(dirname "$0")/lib/common.sh"

# Resolve the library directory at source-time so template paths work even
# after the caller has cd'd into a site directory.
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Cleanup trap state (module-level variables)
# ---------------------------------------------------------------------------
_WP_CLEANUP_NEEDED=0
_WP_SCRIPT_DIR=""

# Internal: called on EXIT when _WP_CLEANUP_NEEDED=1 and exit code != 0
_wp_trap_cleanup() {
  local exit_code=$?
  if [ "$_WP_CLEANUP_NEEDED" -eq 1 ] && [ "$exit_code" -ne 0 ] && [ -n "${INSTANCE_NAME:-}" ]; then
    echo "" >&2
    echo "Script failed (exit code $exit_code). Cleaning up..." >&2
    # wp-content files are owned by www-data on the host (set by the container).
    # Chown them back to the current user so rm -rf works without needing root.
    docker-compose exec -T wordpress chown -R "$(id -u):$(id -g)" /var/www/html/wp-content 2>/dev/null || true
    docker-compose down -v 2>/dev/null || true
    cd "${_WP_SCRIPT_DIR}" 2>/dev/null || true
    rm -rf "${INSTANCE_NAME}" 2>/dev/null || true
    echo "Cleanup complete." >&2
  fi
}

# Call BEFORE cd'ing into the site directory (after INSTANCE_NAME is set)
setup_cleanup_trap() {
  _WP_SCRIPT_DIR="$(pwd)"
  _WP_CLEANUP_NEEDED=1
  trap '_wp_trap_cleanup' EXIT
}

# Call just before the final success summary to disarm the trap
disable_cleanup_trap() {
  _WP_CLEANUP_NEEDED=0
}

# ---------------------------------------------------------------------------
# Port helpers
# ---------------------------------------------------------------------------

# find_available_port [start_port]
# Scans 8080-8200 for an unused port; echoes the port number on success.
find_available_port() {
  local start_port=${1:-8080}
  local port=$start_port

  while [ "$port" -le 8200 ]; do
    local port_in_use=0
    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
      port_in_use=1
    fi

    if [ "$port_in_use" -eq 0 ]; then
      for dir in wp-test-*; do
        if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
          local existing_port
          existing_port=$(grep -o '"[0-9]*:80"' "$dir/docker-compose.yml" 2>/dev/null | sed 's/"//g' | cut -d: -f1)
          if [ "$existing_port" = "$port" ]; then
            port_in_use=1
            break
          fi
        fi
      done
    fi

    if [ "$port_in_use" -eq 0 ]; then
      echo "$port"
      return 0
    fi
    ((port++))
  done

  echo "ERROR: No available ports found between $start_port and 8200" >&2
  return 1
}

# validate_port port
# Exits with an error message if port is not a valid unprivileged port number.
validate_port() {
  local port="$1"
  if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
    echo "ERROR: Port must be a number between 1024 and 65535" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Name helper
# ---------------------------------------------------------------------------

# sanitize_name name
# Echoes the sanitized name (special chars → hyphens, collapse, trim edges).
sanitize_name() {
  echo "$1" | sed 's/[^a-zA-Z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g'
}

# ---------------------------------------------------------------------------
# Cleanup helper
# ---------------------------------------------------------------------------

# run_optional_cleanup label
# Runs ./cleanup-wp-sites.sh -f if CLEANUP=1. label is "creation"/"import"/etc.
run_optional_cleanup() {
  local label="${1:-operation}"
  if [ "${CLEANUP:-0}" -eq 1 ]; then
    echo "Running cleanup of previous WordPress test instances..."
    if [ -f "./cleanup-wp-sites.sh" ] && [ -x "./cleanup-wp-sites.sh" ]; then
      ./cleanup-wp-sites.sh -f
    else
      echo "Warning: cleanup-wp-sites.sh not found or not executable"
      echo "Skipping cleanup phase"
    fi
    echo "Cleanup complete. Proceeding with site $label..."
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# Container health checks (must be called from inside the site directory)
# ---------------------------------------------------------------------------

check_db_connection() {
  docker-compose exec -T wordpress php -r \
    "exit(mysqli_connect('db','wordpress','wordpress','wordpress') ? 0 : 1);" 2>/dev/null
}

check_wp_installed() {
  docker-compose exec -T wordpress wp core is-installed --allow-root 2>/dev/null
  return $?
}

check_containers_healthy() {
  local db_status
  local wp_status
  db_status=$(docker-compose ps -q db | xargs docker inspect --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
  wp_status=$(docker-compose ps -q wordpress | xargs docker inspect --format='{{.State.Status}}' 2>/dev/null || echo "none")
  [ "$db_status" = "healthy" ] && [ "$wp_status" = "running" ]
}

# check_url url max_attempts
# Returns 0 if url responds within max_attempts*5 seconds.
check_url() {
  local url="$1"
  local max_attempts="$2"
  local attempt=1

  while [ "$attempt" -le "$max_attempts" ]; do
    if curl -s -f "$url" > /dev/null 2>&1; then
      return 0
    fi
    sleep 5
    ((attempt++))
  done
  return 1
}

# ---------------------------------------------------------------------------
# Full container startup wait loop (called after docker-compose up -d)
# ---------------------------------------------------------------------------

wait_for_containers() {
  echo ""
  echo "Monitoring container startup..."
  echo "==============================="

  echo "Waiting for containers to start..."
  sleep 10

  if ! docker-compose ps | grep -q "Up"; then
    echo "ERROR: Containers failed to start!" >&2
    echo "Container status:" >&2
    docker-compose ps >&2
    echo "" >&2
    echo "Container logs:" >&2
    docker-compose logs >&2
    exit 1
  fi

  echo "✓ Containers are running"

  echo "Waiting for containers to become healthy..."
  local MAX_HEALTHY_WAIT=120
  local HEALTHY_WAIT=0

  while ! check_containers_healthy && [ "$HEALTHY_WAIT" -lt "$MAX_HEALTHY_WAIT" ]; do
    echo "  Waiting for containers to be healthy... ($HEALTHY_WAIT/$MAX_HEALTHY_WAIT seconds)"
    sleep 5
    HEALTHY_WAIT=$((HEALTHY_WAIT + 5))
  done

  if [ "$HEALTHY_WAIT" -ge "$MAX_HEALTHY_WAIT" ]; then
    echo "ERROR: Containers failed to become healthy!" >&2
    echo "Container status:" >&2
    docker-compose ps >&2
    echo "" >&2
    echo "Database logs:" >&2
    docker-compose logs db >&2
    exit 1
  fi

  echo "✓ Containers are healthy"

  echo "Waiting for database connection..."
  local MAX_DB_WAIT=60
  local DB_WAIT=0

  while ! check_db_connection && [ "$DB_WAIT" -lt "$MAX_DB_WAIT" ]; do
    echo "  Database not ready yet... ($DB_WAIT/$MAX_DB_WAIT seconds)"
    sleep 5
    DB_WAIT=$((DB_WAIT + 5))
  done

  if [ "$DB_WAIT" -ge "$MAX_DB_WAIT" ]; then
    echo "ERROR: Database connection timed out!" >&2
    echo "Database logs:" >&2
    docker-compose logs db >&2
    echo "" >&2
    echo "WordPress logs:" >&2
    docker-compose logs wordpress >&2
    exit 1
  fi

  echo "✓ Database connection established"

  echo "Waiting for WordPress installation..."
  local MAX_WP_WAIT=120
  local WP_WAIT=0

  while ! check_wp_installed && [ "$WP_WAIT" -lt "$MAX_WP_WAIT" ]; do
    echo "  WordPress installation in progress... ($WP_WAIT/$MAX_WP_WAIT seconds)"
    sleep 10
    WP_WAIT=$((WP_WAIT + 10))
  done

  if [ "$WP_WAIT" -ge "$MAX_WP_WAIT" ]; then
    echo "ERROR: WordPress installation timed out!" >&2
    echo "WordPress logs:" >&2
    docker-compose logs wordpress >&2
    exit 1
  fi

  echo "✓ WordPress installation completed"
}

# ---------------------------------------------------------------------------
# docker-compose generation (called from inside the site directory)
# ---------------------------------------------------------------------------

# generate_docker_compose wp_port pma_port instance_name
# Writes docker-compose.yml in the current directory from the shared template.
generate_docker_compose() {
  local wp_port="$1"
  local pma_port="$2"
  local instance_name="$3"
  local template="${_LIB_DIR}/../templates/docker-compose.yml.template"

  if [ ! -f "$template" ]; then
    echo "ERROR: docker-compose template not found: $template" >&2
    exit 1
  fi

  sed -e "s|{{WP_PORT}}|$wp_port|g" \
      -e "s|{{PMA_PORT}}|$pma_port|g" \
      -e "s|{{INSTANCE_NAME}}|$instance_name|g" \
      "$template" > docker-compose.yml
}

# ---------------------------------------------------------------------------
# manage-site.sh generation (called from inside the site directory)
# ---------------------------------------------------------------------------

generate_manage_site_sh() {
  cat > manage-site.sh << 'MANAGE_EOF'
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
MANAGE_EOF

  chmod +x manage-site.sh
  echo "Site management script created: manage-site.sh"
}
