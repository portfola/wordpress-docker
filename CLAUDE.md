# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **WordPress Docker Development Environment** that enables quick creation and management of multiple isolated WordPress sites on different ports. Each site runs independently with its own MySQL database, WordPress installation, and wp-content directory. The setup is cross-platform compatible (Windows/WSL, macOS, Linux) and includes wp-cli for CLI-based WordPress management.

### Key Design Principles

- **Isolation**: Each WordPress site is completely isolated in its own directory (`wp-test-{name}`) with separate database and containers
- **Automation**: Port detection, site creation, and management are automated through shell scripts
- **Convenience**: Multiple command styles available (CLI scripts with options, interactive menu, per-site management scripts)
- **Cross-Platform**: Handles Windows/WSL line endings and platform-specific differences

## Architecture

### Core Components

1. **Docker Setup**
   - `Dockerfile` - Extends official WordPress image; installs wp-cli, increases PHP memory limits
   - `docker-compose.yml` - Template defining MySQL (5.7) + Apache/WordPress services with health checks
   - Each site gets its own `docker-compose.yml` generated in its directory

2. **Site Structure**
   - `wp-test-{sitename}/` - One directory per site containing:
     - `docker-compose.yml` - Auto-generated site-specific configuration
     - `manage-site.sh` - Individual site management script
     - `wp-content/` - Themes, plugins, uploads (mounted from host)
     - `site-info.txt` - Site metadata (URL, credentials, ports)

3. **Management Scripts** (in root directory)
   - `create-wp-site.sh` - Creates new sites with custom naming, optional port specification, optional cleanup
   - `import-wp-site.sh` - Imports WordPress sites from downloaded database dump and wp-content directory
   - `list-wp-sites.sh` - Multi-site management (list, start, stop, remove operations)
   - `cleanup-wp-sites.sh` - Bulk site removal with force mode
   - `wp-dev.sh` - Interactive menu system for common operations
   - `setup.sh` - One-time initialization (fixes line endings, makes scripts executable)
   - `check-platform.sh` - Detects OS and Docker environment

### Key Technical Details

- **Port Management**: Automatic port detection searches available ports 8080-8200. Checks both system ports and existing site configs
- **Database**: MySQL 5.7 with credentials `wordpress:wordpress`, health checks ensure db readiness before WordPress starts
- **Volume Mounts**: `wp-content/` mounted as delegated for performance; `db_data/` and `wp_data/` for persistent storage
- **Permissions**: Script handles ownership/permissions for Windows/WSL (chown, chmod in entrypoint)
- **Default Credentials**: Admin user `jerry`, password `garcia`

## Common Commands

### Site Creation

```bash
# Create with auto-detected port (8080 or next available)
./create-wp-site.sh -n myproject

# Create on specific port
./create-wp-site.sh -n ecommerce -p 8081

# Clean up existing sites first, then create
./create-wp-site.sh -c -n blog

# Quick create via interactive menu
./wp-dev.sh
```

### Site Import from Local Files

```bash
# Import with auto-detected port (from downloaded database and wp-content directory)
./import-wp-site.sh -n myclient -d ~/downloads/myclient.sql -w ~/downloads/wp-content

# Import from tar.gz dump of wp-content
./import-wp-site.sh -n staging -d /tmp/db.sql -w /tmp/wp-content.tar.gz -p 8085

# Clean up existing sites first, then import
./import-wp-site.sh -c -n oldsite -d ~/oldsite.sql -w ~/oldsite-wp-content.tar.gz

# Interactive import via menu
./wp-dev.sh  # Select option 8
```

The import script:
- Accepts a database dump file (`.sql`) and local `wp-content` as a directory, `.tar`, or `.tar.gz`
- Auto-detects the live site URL from the database
- Performs URL search-replace to update all references to localhost (handles www variants and https)
- Resets admin credentials to `jerry/garcia`
- Automatically flushes rewrite rules

### Multi-Site Management

```bash
# List all sites with status
./list-wp-sites.sh list

# Show port usage
./list-wp-sites.sh ports

# Start/stop operations
./list-wp-sites.sh start              # Start all
./list-wp-sites.sh stop               # Stop all
./list-wp-sites.sh start wp-test-name # Start specific site
./list-wp-sites.sh stop wp-test-name  # Stop specific site

# Remove site
./list-wp-sites.sh remove wp-test-name
```

### Individual Site Management

```bash
cd wp-test-myproject

# Basic operations
./manage-site.sh start
./manage-site.sh stop
./manage-site.sh restart
./manage-site.sh logs

# WordPress CLI via site script
./manage-site.sh wp plugin list
./manage-site.sh wp user list
./manage-site.sh wp plugin install woocommerce --activate

# Clean up single site
./manage-site.sh remove
```

### Diagnostic Commands

```bash
# Check platform/Docker detection
./check-platform.sh

# Container inspection
cd wp-test-myproject
docker-compose ps
docker-compose logs
docker-compose exec wordpress bash        # Into WordPress container
docker-compose exec db mysql -u wordpress wordpress  # Into database

# Bulk cleanup
./cleanup-wp-sites.sh -f
docker system prune -f
```

## Development Workflow

### Theme/Plugin Development

Each site has isolated `wp-content/themes/` and `wp-content/plugins/` directories. Develop locally, commit to separate repositories if version controlling.

### Database Operations

```bash
# Export database
cd wp-test-myproject
docker-compose exec wordpress wp db export backup.sql --allow-root

# Import database
docker-compose exec wordpress wp db import backup.sql --allow-root
```

### Modifying Site Configuration

Edit `wp-test-{name}/docker-compose.yml` directly for site-specific changes (ports, environment variables, volumes). Restart site to apply:

```bash
cd wp-test-myproject
./manage-site.sh restart
```

## Important Notes

### Port Discovery Logic (create-wp-site.sh)

The `find_available_port()` function:
1. Checks system port availability using `netstat` or `ss`
2. Checks existing site configs by parsing docker-compose.yml files
3. Searches 8080-8200 range sequentially
4. Ensures no conflicts between new and existing sites

If modifying port logic, test with multiple concurrent sites to ensure no collisions.

### Cross-Platform Considerations

- `dos2unix` utility converts CRLF → LF line endings (Windows Git Bash issue)
- Scripts use `set -euo pipefail` for strict bash mode
- Platform detection in `check-platform.sh` distinguishes Windows/macOS/Linux for permission handling
- `delegated` mount mode on `wp-content/` improves Windows/WSL performance

### File Permissions

- WordPress container runs as `www-data` user
- Entrypoint script fixes ownership: `chown -R www-data:www-data /var/www/html/wp-content`
- On Unix: `chmod -R 755 wp-content/` set during setup
- Windows/WSL: Permission handling deferred to Docker

### Default Admin Credentials

Defined in root `docker-compose.yml` template and copied to each site's generated config:
- Username: `jerry`
- Password: `garcia`
- Email: `admin@example.com`

Change these in template before creating new sites, or edit individual site's docker-compose.yml and restart.

## Common Development Tasks

### Reset Everything

```bash
./list-wp-sites.sh stop
./cleanup-wp-sites.sh -f
docker system prune -f
./setup.sh
```

### Bulk Operations

```bash
# Start specific sites
for site in project1 project2; do
    ./list-wp-sites.sh start wp-test-$site
done

# Update WordPress core on all sites
for dir in wp-test-*; do
    if [ -d "$dir" ]; then
        cd "$dir"
        docker-compose exec -T wordpress wp core update --allow-root
        cd ..
    fi
done
```

## Troubleshooting Patterns

| Problem | Diagnosis | Solution |
|---------|-----------|----------|
| Port already in use | `./list-wp-sites.sh ports` | Stop conflicting site or specify different port with `-p` |
| Container fails to start | `docker-compose logs` | Check MySQL health check, disk space, Docker resources |
| WordPress not accessible | `docker-compose ps` | Verify all containers running, check port in browser |
| Permission errors | Check `manage-site.sh` output | Usually fixed by restart; check `chown` in entrypoint |
| Database connection fails | `docker-compose logs db` | Verify db service healthy (`docker-compose ps`), restart site |

## File Structure After Setup

```
wordpress-docker/
├── wp-test-project1/          # Per-site directories (created by ./create-wp-site.sh)
│   ├── wp-content/            # Mounted themes, plugins, uploads
│   ├── docker-compose.yml      # Site-specific config (auto-generated)
│   ├── manage-site.sh          # Site management script
│   └── site-info.txt           # Site metadata
├── wp-test-project2/           # Additional sites
├── Dockerfile                  # Custom WordPress image definition
├── docker-compose.yml          # Root template (referenced in create script)
├── create-wp-site.sh           # Main site creation script
├── list-wp-sites.sh            # Multi-site management
├── wp-dev.sh                   # Interactive menu
├── cleanup-wp-sites.sh         # Bulk cleanup utility
├── setup.sh                    # Initial setup
├── check-platform.sh           # Platform detection
├── wp-installer.sh             # Container entrypoint script
├── readme.md                   # User documentation
├── LICENSE                     # Project license
├── .gitignore                  # Excludes: /wp-test*, /wp-content, /wp_data, /db_data
└── .gitattributes              # Cross-platform line ending handling
```

## Git Workflow Notes

- `.gitignore` excludes all `wp-test-*` directories (site-specific data)
- `.gitattributes` ensures consistent line endings (critical for Windows)
- Repository contains only scripts and configuration templates
- User-created sites and databases are not version controlled

## Extending or Modifying

### Adding Features to Site Creation

Edit `create-wp-site.sh`:
- Argument parsing: update `getopts` in main section
- Port detection: modify `find_available_port()` function
- Template generation: modify docker-compose section that writes `$SITE_COMPOSE`

### Changing Default Configuration

- **WordPress credentials**: Update `WORDPRESS_ADMIN_*` env vars in docker-compose.yml template
- **MySQL version**: Update `image: mysql:X.X` in template
- **PHP settings**: Edit Dockerfile memory/timeout limits or add to docker-compose env vars
- **Port range**: Modify `8200` limit in `find_available_port()` and related checks

### Adding New Management Commands

New site operations should:
1. Follow naming pattern: `list-wp-sites.sh {operation}`
2. Support both `wp-test-name` and bulk operations
3. Echo color-coded output for clarity
4. Update `wp-dev.sh` menu if relevant

## Performance Considerations

- Use `delegated` mount mode for wp-content (already configured)
- Run only active sites (stop others with `./list-wp-sites.sh stop`)
- Ensure Docker Desktop has adequate CPU/RAM allocation
- MySQL 5.7 is older; consider updating if performance is critical
