#!/bin/bash
# cleanup-wp-sites.sh

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
for dir in $(find . -type d -name "wp-test-*"); do
  if [ -f "$dir/docker-compose.yml" ]; then
    echo "Found test environment in $dir"
    
    # Check if containers are running
    if (cd "$dir" && docker-compose ps -q | grep -q .); then
      echo "Active containers found in $dir"
      
      # Prompt before stopping if containers are running and not in force mode
      if [ $FORCE -eq 0 ]; then
        read -p "Stop containers in $dir? (y/n): " choice
        case "$choice" in 
          y|Y ) 
            echo "Stopping and removing containers in $dir"
            (cd "$dir" && docker-compose down -v) || echo "Failed to clean up $dir"
            
            # Remove any local wp-content directory
            if [ -d "$dir/wp-content" ]; then
              echo "Removing wp-content directory in $dir"
              rm -rf "$dir/wp-content"
            fi
            
            echo "Removing directory $dir"
            rm -rf "$dir"
            ;;
          * ) 
            echo "Skipping $dir (containers still running)"
            ;;
        esac
      else
        # Force mode - clean up without prompting
        echo "Force stopping and removing containers in $dir"
        (cd "$dir" && docker-compose down -v) || echo "Failed to clean up $dir"
        
        # Remove any local wp-content directory
        if [ -d "$dir/wp-content" ]; then
          echo "Removing wp-content directory in $dir"
          rm -rf "$dir/wp-content"
        fi
        
        echo "Removing directory $dir"
        rm -rf "$dir"
      fi
    else
      echo "No active containers in $dir"
      
      # Remove any local wp-content directory
      if [ -d "$dir/wp-content" ]; then
        echo "Removing wp-content directory in $dir"
        rm -rf "$dir/wp-content"
      fi
      
      echo "Removing directory $dir"
      rm -rf "$dir"
    fi
  fi
done

# Clean up any orphaned Docker volumes related to WordPress instances
echo "Checking for orphaned Docker volumes..."
ORPHANED_VOLUMES=$(docker volume ls -q | grep "wp-test-.*_\(wp_data\|db_data\)")
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
    echo "$ORPHANED_VOLUMES" | xargs -r docker volume rm
    echo "Orphaned volumes removed"
  fi
else
  echo "No orphaned volumes found"
fi

# Clean up any orphaned WordPress networks
echo "Checking for orphaned Docker networks..."
ORPHANED_NETWORKS=$(docker network ls --filter "name=wp-test-" -q)
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
    echo "$ORPHANED_NETWORKS" | xargs -r docker network rm
    echo "Orphaned networks removed"
  fi
else
  echo "No orphaned networks found"
fi

echo "Cleanup process complete"