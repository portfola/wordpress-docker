#!/bin/bash
# list-wp-sites.sh - Manage multiple WordPress sites

set -euo pipefail

# Handle cross-platform issues
command -v dos2unix >/dev/null 2>&1 && dos2unix "$0" 2>/dev/null || true

# Function to show usage
show_usage() {
  echo "Usage: $0 [list|start|stop|remove] [site_name]"
  echo ""
  echo "Commands:"
  echo "  list              List all WordPress sites and their status"
  echo "  start [site]      Start specific site or all sites"
  echo "  stop [site]       Stop specific site or all sites"
  echo "  remove [site]     Remove specific site"
  echo "  ports             Show port usage"
  echo ""
  echo "Examples:"
  echo "  $0 list                    # List all sites"
  echo "  $0 start wp-test-mysite    # Start specific site"
  echo "  $0 stop                    # Stop all sites"
  echo "  $0 ports                   # Show which ports are in use"
  exit 1
}

# Function to extract port from docker-compose.yml
get_site_port() {
  local site_dir=$1
  if [ -f "$site_dir/docker-compose.yml" ]; then
    grep -o '"[0-9]*:80"' "$site_dir/docker-compose.yml" | sed 's/"//g' | cut -d: -f1
  else
    echo "N/A"
  fi
}

# Function to get site info
get_site_info() {
  local site_dir=$1
  local port=$(get_site_port "$site_dir")
  local status="Stopped"
  local url="N/A"
  
  if [ -f "$site_dir/docker-compose.yml" ]; then
    cd "$site_dir"
    # Suppress the APACHE_PID warning by checking container status directly
    if docker-compose ps --services --filter="status=running" 2>/dev/null | grep -q .; then
      # Check if containers are actually running
      if docker-compose ps 2>/dev/null | grep -q "Up"; then
        status="Running"
        url="http://localhost:$port"
      else
        status="Error"
      fi
    fi
    cd - > /dev/null
  fi
  
  echo "$status|$port|$url"
}

# Function to list all sites
list_sites() {
  echo "WordPress Development Sites"
  echo "=========================="
  echo ""
  printf "%-25s %-10s %-6s %-25s\n" "SITE NAME" "STATUS" "PORT" "URL"
  printf "%-25s %-10s %-6s %-25s\n" "-------------------------" "----------" "------" "-------------------------"
  
  local found_sites=0
  for dir in wp-test-*; do
    if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
      found_sites=1
      local info=$(get_site_info "$dir")
      local status=$(echo "$info" | cut -d'|' -f1)
      local port=$(echo "$info" | cut -d'|' -f2)
      local url=$(echo "$info" | cut -d'|' -f3)
      
      # Color coding for status
      case $status in
        "Running")
          status_colored="\033[32m$status\033[0m"  # Green
          ;;
        "Error")
          status_colored="\033[31m$status\033[0m"   # Red
          ;;
        *)
          status_colored="\033[33m$status\033[0m"   # Yellow
          ;;
      esac
      
      printf "%-25s %-10s %-6s %-25s\n" "$dir" "$status_colored" "$port" "$url"
    fi
  done
  
  if [ $found_sites -eq 0 ]; then
    echo "No WordPress sites found."
    echo "Create one with: ./create-wp-site.sh -n mysite"
  fi
  echo ""
}

# Function to show port usage
show_ports() {
  echo "Port Usage Overview"
  echo "=================="
  echo ""
  printf "%-6s %-25s %-10s\n" "PORT" "SITE NAME" "STATUS"
  printf "%-6s %-25s %-10s\n" "------" "-------------------------" "----------"
  
  # Create a list of ports and sites
  declare -A port_map
  local used_ports=()
  
  for dir in wp-test-*; do
    if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
      local port=$(get_site_port "$dir")
      if [ "$port" != "N/A" ]; then
        local info=$(get_site_info "$dir")
        local status=$(echo "$info" | cut -d'|' -f1)
        port_map[$port]="$dir|$status"
        used_ports+=("$port")
      fi
    fi
  done
  
  # Sort ports and display
  IFS=$'\n' sorted_ports=($(sort -n <<<"${used_ports[*]}"))
  unset IFS
  
  for port in "${sorted_ports[@]}"; do
    local site_info="${port_map[$port]}"
    local site_name=$(echo "$site_info" | cut -d'|' -f1)
    local status=$(echo "$site_info" | cut -d'|' -f2)
    
    # Color coding for status
    case $status in
      "Running")
        status_colored="\033[32m$status\033[0m"  # Green
        ;;
      "Error")
        status_colored="\033[31m$status\033[0m"   # Red
        ;;
      *)
        status_colored="\033[33m$status\033[0m"   # Yellow
        ;;
    esac
    
    printf "%-6s %-25s %-10s\n" "$port" "$site_name" "$status_colored"
  done
  
  echo ""
  echo "Next available port: $(find_next_port)"
}

# Function to find next available port
find_next_port() {
  local port=8080
  while [ $port -le 8200 ]; do
    # Check if port is used by system services
    local port_in_use=0
    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
      port_in_use=1
    fi
    
    # Also check if any of our sites are configured for this port
    if [ $port_in_use -eq 0 ]; then
      for dir in wp-test-*; do
        if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
          local site_port=$(get_site_port "$dir")
          if [ "$site_port" = "$port" ]; then
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
  echo "None available"
}

# Function to start sites
start_sites() {
  local site_name=$1
  
  if [ -n "$site_name" ]; then
    # Start specific site
    if [ -d "$site_name" ] && [ -f "$site_name/docker-compose.yml" ]; then
      echo "Starting $site_name..."
      cd "$site_name"
      docker-compose up -d
      cd - > /dev/null
      echo "✓ $site_name started"
      
      # Show site info
      local info=$(get_site_info "$site_name")
      local port=$(echo "$info" | cut -d'|' -f2)
      echo "  URL: http://localhost:$port"
    else
      echo "ERROR: Site '$site_name' not found or invalid"
      exit 1
    fi
  else
    # Start all sites
    echo "Starting all WordPress sites..."
    local started=0
    for dir in wp-test-*; do
      if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
        echo "  Starting $dir..."
        cd "$dir"
        docker-compose up -d
        cd - > /dev/null
        started=1
      fi
    done
    
    if [ $started -eq 0 ]; then
      echo "No sites found to start"
    else
      echo "✓ All sites started"
    fi
  fi
}

# Function to stop sites
stop_sites() {
  local site_name=$1
  
  if [ -n "$site_name" ]; then
    # Stop specific site
    if [ -d "$site_name" ] && [ -f "$site_name/docker-compose.yml" ]; then
      echo "Stopping $site_name..."
      cd "$site_name"
      docker-compose down
      cd - > /dev/null
      echo "✓ $site_name stopped"
    else
      echo "ERROR: Site '$site_name' not found or invalid"
      exit 1
    fi
  else
    # Stop all sites
    echo "Stopping all WordPress sites..."
    local stopped=0
    for dir in wp-test-*; do
      if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
        echo "  Stopping $dir..."
        cd "$dir"
        docker-compose down
        cd - > /dev/null
        stopped=1
      fi
    done
    
    if [ $stopped -eq 0 ]; then
      echo "No running sites found"
    else
      echo "✓ All sites stopped"
    fi
  fi
}

# Function to remove a site
remove_site() {
  local site_name=$1
  
  if [ -z "$site_name" ]; then
    echo "ERROR: Please specify a site name to remove"
    exit 1
  fi
  
  if [ ! -d "$site_name" ]; then
    echo "ERROR: Site '$site_name' not found"
    exit 1
  fi
  
  echo "WARNING: This will completely remove '$site_name' and all its data!"
  read -p "Are you sure? Type 'yes' to confirm: " confirm
  
  if [ "$confirm" = "yes" ]; then
    echo "Removing $site_name..."
    cd "$site_name"
    docker-compose down -v 2>/dev/null || true
    cd - > /dev/null
    rm -rf "$site_name"
    echo "✓ $site_name removed completely"
  else
    echo "Removal cancelled"
  fi
}

# Main script logic
case "${1:-list}" in
  list)
    list_sites
    ;;
  start)
    start_sites "${2:-}"
    ;;
  stop)
    stop_sites "${2:-}"
    ;;
  remove)
    remove_site "${2:-}"
    ;;
  ports)
    show_ports
    ;;
  *)
    show_usage
    ;;
esac