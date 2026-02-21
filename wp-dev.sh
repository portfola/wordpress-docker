#!/bin/bash
# wp-dev.sh - Quick WordPress Development Environment Manager

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}WordPress Docker Development Environment${NC}"
echo "========================================"

# Function to show main menu
show_menu() {
    echo ""
    echo "Choose an action:"
    echo "1) Create new site"
    echo "2) List all sites"
    echo "3) Start all sites"
    echo "4) Stop all sites"
    echo "5) Clean up all sites"
    echo "6) Show port usage"
    echo "7) Quick site creation with auto port"
    echo "8) Import site from local files"
    echo "9) Exit"
    echo ""
    read -p "Enter your choice (1-9): " choice
}

# Function to create new site with prompts
create_site_interactive() {
    echo ""
    echo -e "${GREEN}Creating New WordPress Site${NC}"
    echo "============================"
    
    # Get site name
    read -p "Enter site name (will become wp-test-SITENAME): " site_name
    if [ -z "$site_name" ]; then
        echo -e "${RED}Error: Site name cannot be empty${NC}"
        return 1
    fi
    
    # Check if cleanup is needed
    if ls -d wp-test-* >/dev/null 2>&1; then
        echo ""
        echo "Existing sites found:"
        ./list-wp-sites.sh list
        echo ""
        read -p "Clean up existing sites first? (y/n): " cleanup
        case $cleanup in
            [Yy]* ) 
                echo "Cleaning up existing sites..."
                ./create-wp-site.sh -c -n "$site_name"
                return $?
                ;;
            * ) 
                ./create-wp-site.sh -n "$site_name"
                return $?
                ;;
        esac
    else
        ./create-wp-site.sh -n "$site_name"
        return $?
    fi
}

# Function to quick create with auto port detection
quick_create() {
    echo ""
    read -p "Enter site name for quick creation: " site_name
    if [ -z "$site_name" ]; then
        echo -e "${RED}Error: Site name cannot be empty${NC}"
        return 1
    fi

    # Find next available port automatically
    next_port=8080
    while [ $next_port -le 8200 ]; do
        if ! netstat -tuln 2>/dev/null | grep -q ":$next_port " && ! ss -tuln 2>/dev/null | grep -q ":$next_port "; then
            # Check if any existing site uses this port
            port_used=0
            for dir in wp-test-*; do
                if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
                    existing_port=$(grep -o '"[0-9]*:80"' "$dir/docker-compose.yml" 2>/dev/null | sed 's/"//g' | cut -d: -f1)
                    if [ "$existing_port" = "$next_port" ]; then
                        port_used=1
                        break
                    fi
                fi
            done
            if [ $port_used -eq 0 ]; then
                break
            fi
        fi
        ((next_port++))
    done

    echo "Creating site on port $next_port..."
    ./create-wp-site.sh -n "$site_name" -p "$next_port"
}

# Function to import site from local files
import_site_interactive() {
    echo ""
    echo -e "${GREEN}Importing WordPress Site${NC}"
    echo "============================"

    # Get site name
    read -p "Enter local site name (will become wp-test-SITENAME): " site_name
    if [ -z "$site_name" ]; then
        echo -e "${RED}Error: Site name cannot be empty${NC}"
        return 1
    fi

    # Get database file path
    read -p "Enter path to SQL database dump file: " db_file
    if [ -z "$db_file" ]; then
        echo -e "${RED}Error: Database file path cannot be empty${NC}"
        return 1
    fi

    # Get wp-content directory path
    read -p "Enter path to wp-content directory: " wp_content_path
    if [ -z "$wp_content_path" ]; then
        echo -e "${RED}Error: wp-content path cannot be empty${NC}"
        return 1
    fi

    # Get optional port
    read -p "Enter port (leave blank for auto-detect): " custom_port

    # Ask about cleanup
    if ls -d wp-test-* >/dev/null 2>&1; then
        echo ""
        echo "Existing sites found:"
        ./list-wp-sites.sh list
        echo ""
        read -p "Clean up existing sites first? (y/n): " cleanup
        case $cleanup in
            [Yy]* )
                if [ -z "$custom_port" ]; then
                    ./import-wp-site.sh -c -n "$site_name" -d "$db_file" -w "$wp_content_path"
                else
                    ./import-wp-site.sh -c -n "$site_name" -d "$db_file" -w "$wp_content_path" -p "$custom_port"
                fi
                return $?
                ;;
            * )
                if [ -z "$custom_port" ]; then
                    ./import-wp-site.sh -n "$site_name" -d "$db_file" -w "$wp_content_path"
                else
                    ./import-wp-site.sh -n "$site_name" -d "$db_file" -w "$wp_content_path" -p "$custom_port"
                fi
                return $?
                ;;
        esac
    else
        if [ -z "$custom_port" ]; then
            ./import-wp-site.sh -n "$site_name" -d "$db_file" -w "$wp_content_path"
        else
            ./import-wp-site.sh -n "$site_name" -d "$db_file" -w "$wp_content_path" -p "$custom_port"
        fi
        return $?
    fi
}

# Function to get container status summary
get_status_summary() {
    local running=0
    local stopped=0
    local total=0
    
    for dir in wp-test-*; do
        if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
            total=$((total + 1))
            cd "$dir"
            if docker-compose ps --services --filter="status=running" 2>/dev/null | grep -q .; then
                running=$((running + 1))
            else
                stopped=$((stopped + 1))
            fi
            cd - > /dev/null
        fi
    done
    
    echo "$total|$running|$stopped"
}

# Main program loop
while true; do
    # Show current status
    if ls -d wp-test-* >/dev/null 2>&1; then
        status_info=$(get_status_summary)
        total=$(echo "$status_info" | cut -d'|' -f1)
        running=$(echo "$status_info" | cut -d'|' -f2)
        stopped=$(echo "$status_info" | cut -d'|' -f3)
        
        echo ""
        echo -e "Current Status: ${GREEN}$running running${NC}, ${YELLOW}$stopped stopped${NC} (Total: $total sites)"
    else
        echo ""
        echo -e "${YELLOW}No WordPress sites found${NC}"
    fi
    
    show_menu
    
    case $choice in
        1)
            create_site_interactive
            ;;
        2)
            echo ""
            ./list-wp-sites.sh list
            ;;
        3)
            echo ""
            echo -e "${GREEN}Starting all sites...${NC}"
            ./list-wp-sites.sh start
            ;;
        4)
            echo ""
            echo -e "${YELLOW}Stopping all sites...${NC}"
            ./list-wp-sites.sh stop
            ;;
        5)
            echo ""
            echo -e "${RED}WARNING: This will remove ALL WordPress sites and data!${NC}"
            read -p "Are you absolutely sure? Type 'DELETE ALL' to confirm: " confirm
            if [ "$confirm" = "DELETE ALL" ]; then
                echo "Cleaning up all sites..."
                ./cleanup-wp-sites.sh -f
                echo -e "${GREEN}All sites cleaned up${NC}"
            else
                echo "Cleanup cancelled"
            fi
            ;;
        6)
            echo ""
            ./list-wp-sites.sh ports
            ;;
        7)
            quick_create
            ;;
        8)
            import_site_interactive
            ;;
        9)
            echo ""
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please try again.${NC}"
            ;;
    esac
    
    # Pause before showing menu again
    echo ""
    read -p "Press Enter to continue..."
    clear
done