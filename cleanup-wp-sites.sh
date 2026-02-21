#!/bin/bash
# cleanup-wp-sites.sh - Fixed version with Docker-based permission handling

set -euo pipefail

# Handle cross-platform issues
command -v dos2unix >/dev/null 2>&1 && dos2unix "$0" 2>/dev/null || true

# Force mode (no prompts)
FORCE=0

# Parse command line arguments
while getopts "f" opt; do
  case $opt in
    f)
      FORCE=1
      ;;
    *)
      echo "Usage: $0 [-f]"
      echo "  -f  Force cleanup without prompting"
      exit 1
      ;;
  esac
done

echo "Checking for WordPress test environments..."

# Find all docker-compose files in wp-test directories
for dir in $(find . -maxdepth 1 -type d -name "wp-test-*" 2>/dev/null || true); do
  if [ -f "$dir/docker-compose.yml" ]; then
    echo "Found test environment in $dir"

    # Check if containers are running
    cd "$dir"

    # Use a more robust way to check for running containers
    if docker-compose ps --services --filter="status=running" 2>/dev/null | grep -q .; then
      echo "Active containers found in $dir"

      # Prompt before stopping if containers are running and not in force mode
      if [ $FORCE -eq 0 ]; then
        read -p "Stop containers in $dir? (y/n): " choice
        case "$choice" in
          y|Y )
            echo "Stopping containers and fixing permissions in $dir"
            # Fix wp-content permissions FROM INSIDE THE CONTAINER (where we have www-data access)
            if [ -d "wp-content" ]; then
              echo "  Fixing wp-content permissions via Docker..."
              docker-compose exec -T wordpress chmod -R 755 /var/www/html/wp-content 2>/dev/null || true
            fi
            docker-compose down -v || echo "Warning: Failed to clean up $dir"

            # Now remove wp-content directory
            if [ -d "wp-content" ]; then
              echo "Removing wp-content directory in $dir"
              rm -rf "wp-content"
            fi

            cd ..
            echo "Removing directory $dir"
            rm -rf "$dir"
            ;;
          * )
            echo "Skipping $dir (containers still running)"
            cd ..
            ;;
        esac
      else
        # Force mode - clean up without prompting
        echo "Stopping containers and fixing permissions in $dir"
        # Fix wp-content permissions FROM INSIDE THE CONTAINER (where we have www-data access)
        if [ -d "wp-content" ]; then
          echo "  Fixing wp-content permissions via Docker..."
          docker-compose exec -T wordpress chmod -R 755 /var/www/html/wp-content 2>/dev/null || true
        fi
        docker-compose down -v || echo "Warning: Failed to clean up $dir"

        # Now remove wp-content directory
        if [ -d "wp-content" ]; then
          echo "Removing wp-content directory in $dir"
          rm -rf "wp-content"
        fi

        cd ..
        echo "Removing directory $dir"
        rm -rf "$dir"
      fi
    else
      echo "No active containers in $dir"

      # For stopped containers, try to start just the WordPress service temporarily to fix permissions
      if [ -d "wp-content" ]; then
        echo "Starting WordPress container temporarily to fix permissions..."
        docker-compose up -d wordpress db 2>/dev/null || true
        sleep 5
        docker-compose exec -T wordpress chmod -R 755 /var/www/html/wp-content 2>/dev/null || true
        docker-compose down 2>/dev/null || true

        echo "Removing wp-content directory in $dir"
        rm -rf "wp-content"
      fi

      cd ..
      echo "Removing directory $dir"
      rm -rf "$dir"
    fi
  fi
done

echo "Cleanup of test environments complete"

# Clean up any orphaned Docker volumes related to WordPress instances
echo "Checking for orphaned Docker volumes..."

# Use a more robust way to find volumes
ORPHANED_VOLUMES=$(docker volume ls --format "{{.Name}}" | grep -E "^wp-test-.*_(wp_data|db_data)$" || true)

if [ -n "$ORPHANED_VOLUMES" ]; then
  if [ $FORCE -eq 0 ]; then
    echo "Found orphaned WordPress volumes:"
    echo "$ORPHANED_VOLUMES"
    read -p "Remove orphaned volumes? (y/n): " choice
    case "$choice" in
      y|Y )
        echo "$ORPHANED_VOLUMES" | xargs -r docker volume rm
        echo "Orphaned volumes removed"
        ;;
      * )
        echo "Skipping orphaned volume cleanup"
        ;;
    esac
  else
    # Force mode - remove without prompting
    if [ -n "$ORPHANED_VOLUMES" ]; then
      echo "Removing orphaned volumes: $ORPHANED_VOLUMES"
      echo "$ORPHANED_VOLUMES" | xargs -r docker volume rm
      echo "Orphaned volumes removed"
    fi
  fi
else
  echo "No orphaned volumes found"
fi

# Clean up any orphaned WordPress networks
echo "Checking for orphaned Docker networks..."

# Use a more robust way to find networks
ORPHANED_NETWORKS=$(docker network ls --format "{{.Name}}" | grep -E "^wp-test-.*_wordpress_net$" || true)

if [ -n "$ORPHANED_NETWORKS" ]; then
  if [ $FORCE -eq 0 ]; then
    echo "Found orphaned WordPress networks:"
    echo "$ORPHANED_NETWORKS"
    read -p "Remove orphaned networks? (y/n): " choice
    case "$choice" in
      y|Y )
        echo "$ORPHANED_NETWORKS" | xargs -r docker network rm
        echo "Orphaned networks removed"
        ;;
      * )
        echo "Skipping orphaned network cleanup"
        ;;
    esac
  else
    # Force mode - remove without prompting
    if [ -n "$ORPHANED_NETWORKS" ]; then
      echo "Removing orphaned networks: $ORPHANED_NETWORKS"
      echo "$ORPHANED_NETWORKS" | xargs -r docker network rm
      echo "Orphaned networks removed"
    fi
  fi
else
  echo "No orphaned networks found"
fi

echo "Cleanup process complete"
