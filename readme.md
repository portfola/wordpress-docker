# WordPress Docker Development Environment

This Docker setup provides a complete WordPress development environment with wp-cli pre-installed. It's designed to make it easy to spin up multiple WordPress test sites quickly on different ports, with automatic port detection and comprehensive site management tools.

## Project Structure

- `Dockerfile` - Creates a WordPress image with wp-cli installed
- `templates/docker-compose.yml.template` - Template for WordPress, MySQL 8.0, and phpMyAdmin services (auto-generated per site)
- `lib/common.sh` - Shared functions used by site creation and import scripts
- `create-wp-site.sh` - Script to create new WordPress instances with custom naming and port management
- `wp-installer.sh` - Handles WordPress installation and configuration with improved error handling
- `cleanup-wp-sites.sh` - Utility script to clean up WordPress test sites with force mode
- `list-wp-sites.sh` - Comprehensive site management script for multiple instances
- `wp-dev.sh` - Interactive menu system for easy WordPress development management
- `setup.sh` - Initial setup script for the environment
- `check-platform.sh` - Detects OS and Docker environment
- `.gitattributes` - Ensures consistent line endings across platforms
- `.gitignore` - Git ignore rules for WordPress development

## Features

- ✅ **Multiple Sites**: Run multiple WordPress sites simultaneously on different ports
- ✅ **Automatic Port Detection**: Automatically finds available ports (8080-8200)
- ✅ **Custom Site Naming**: Create sites with meaningful names instead of timestamps
- ✅ **Cross-Platform Support**: Works on Windows (Git Bash), macOS, and Linux
- ✅ **Site Management**: Start, stop, and manage multiple sites easily
- ✅ **Individual Site Scripts**: Each site gets its own management script
- ✅ **Interactive Menu**: User-friendly interface for all operations

## Getting Started

### Prerequisites

- Docker Desktop installed and running
- Git Bash (recommended for Windows users)
- Basic knowledge of Docker and WordPress

### Quick Start

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd wordpress-docker
   ```

2. Run the setup script:
   ```bash
   ./setup.sh
   ```

3. Create your first WordPress site:
   ```bash
   ./create-wp-site.sh -n myproject
   ```

4. Access your WordPress site at the displayed URL (e.g., http://localhost:8080)

5. Log in to the WordPress admin using:
   - Username: jerry
   - Password: garcia

### Alternative: Interactive Mode

For a user-friendly experience, use the interactive menu:
```bash
./wp-dev.sh
```

## Site Creation Options

### Basic Site Creation
```bash
# Create with auto-detected port
./create-wp-site.sh -n myproject

# Create with specific port
./create-wp-site.sh -n ecommerce -p 8081

# Clean up existing sites first, then create
./create-wp-site.sh -c -n blog

# Combination: cleanup, custom name, and specific port
./create-wp-site.sh -c -n portfolio -p 8085
```

### Site Creation Examples
```bash
# E-commerce site on port 8081
./create-wp-site.sh -n shop -p 8081

# Portfolio site with auto port detection
./create-wp-site.sh -n portfolio

# Blog site after cleaning up previous sites
./create-wp-site.sh -c -n blog
```

## Managing Multiple Sites

### List and Monitor Sites
```bash
# List all sites with status and ports
./list-wp-sites.sh list

# Show port usage overview
./list-wp-sites.sh ports
```

### Start/Stop Sites
```bash
# Start all sites
./list-wp-sites.sh start

# Stop all sites
./list-wp-sites.sh stop

# Start specific site
./list-wp-sites.sh start wp-test-myproject

# Stop specific site
./list-wp-sites.sh stop wp-test-myproject
```

### Site Cleanup
```bash
# Remove specific site
./list-wp-sites.sh remove wp-test-myproject

# Remove all sites (force mode)
./cleanup-wp-sites.sh -f
```

## Individual Site Management

Each created site includes a `manage-site.sh` script for convenient management:

```bash
cd wp-test-myproject

# Start this site
./manage-site.sh start

# Stop this site
./manage-site.sh stop

# View logs
./manage-site.sh logs

# Check status
./manage-site.sh status

# Use WordPress CLI
./manage-site.sh wp plugin list
./manage-site.sh wp user list

# Completely remove this site
./manage-site.sh remove
```

## WordPress CLI (wp-cli) Usage

### Global Commands (from main directory)
```bash
# Get WordPress info
docker-compose -f wp-test-myproject/docker-compose.yml exec wordpress wp --info

# List plugins
docker-compose -f wp-test-myproject/docker-compose.yml exec wordpress wp plugin list
```

### Site-Specific Commands (within site directory)
```bash
cd wp-test-myproject

# WordPress info
docker-compose exec wordpress wp --info --allow-root

# Install and activate plugins
docker-compose exec wordpress wp plugin install woocommerce --activate --allow-root

# Update all plugins
docker-compose exec wordpress wp plugin update --all --allow-root

# Create new user
docker-compose exec wordpress wp user create editor editor@example.com --role=editor --allow-root

# Import/export database
docker-compose exec wordpress wp db export backup.sql --allow-root
docker-compose exec wordpress wp db import backup.sql --allow-root
```

## Development Workflow

### Theme and Plugin Development

Each site has its own `wp-content` directory for isolated development:

```bash
wp-test-myproject/
├── wp-content/
│   ├── themes/          # Custom themes
│   ├── plugins/         # Custom plugins
│   └── uploads/         # Media files
├── docker-compose.yml   # Site configuration
├── manage-site.sh       # Site management script
└── site-info.txt        # Site information
```

### Best Practices

1. **Isolated Development**: Each site is completely isolated with its own database and wp-content
2. **Version Control**: Add your custom themes/plugins to your own repositories
3. **Database Backups**: Use wp-cli to export databases before major changes
4. **Port Management**: Use the port overview to track your sites

## Configuration

### Environment Variables

Each site's `docker-compose.yml` includes customizable environment variables:
- `WORDPRESS_SITE_URL` - Automatically set based on port
- `WORDPRESS_SITE_TITLE` - Includes the site instance name
- `WORDPRESS_ADMIN_USER` - Default: jerry
- `WORDPRESS_ADMIN_PASSWORD` - Default: garcia
- `WORDPRESS_ADMIN_EMAIL` - Default: admin@example.com

### Customizing Default Settings

To change default credentials for new sites, edit `templates/docker-compose.yml.template`:

```yaml
environment:
  WORDPRESS_ADMIN_USER: your_username
  WORDPRESS_ADMIN_PASSWORD: your_password
  WORDPRESS_ADMIN_EMAIL: your_email@example.com
```

## Troubleshooting

### Common Issues

**Port Already in Use:**
```bash
# Check which sites are using which ports
./list-wp-sites.sh ports

# Stop the conflicting site
./list-wp-sites.sh stop wp-test-sitename
```

**Database Connection Issues:**
```bash
# Check container logs
cd wp-test-sitename
docker-compose logs

# Restart the site
./manage-site.sh restart
```

**Site Not Accessible:**
```bash
# Check if containers are running
./list-wp-sites.sh list

# Check specific site status
cd wp-test-sitename
docker-compose ps
```

### Diagnostic Commands

```bash
# Platform check
./check-platform.sh

# Container status
docker-compose ps

# View logs
docker-compose logs

# Container shell access
docker-compose exec wordpress bash

# Database shell access
docker-compose exec db mysql -u wordpress -pwordpress wordpress
```

### Complete Environment Reset

```bash
# Stop all sites
./list-wp-sites.sh stop

# Remove all sites and data
./cleanup-wp-sites.sh -f

# Clean up any remaining Docker resources
docker system prune -f

# Restart fresh
./setup.sh
```

## Advanced Usage

### Custom Docker Compose Modifications

Each site's `docker-compose.yml` can be customized independently:

```bash
cd wp-test-myproject
# Edit docker-compose.yml as needed
# Restart site to apply changes
./manage-site.sh restart
```

### Bulk Operations

```bash
# Start multiple specific sites
for site in myproject ecommerce blog; do
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

### Performance Optimization

For better performance with multiple sites:

1. **Limit concurrent sites**: Run only the sites you're actively developing
2. **Use SSD storage**: Ensure Docker Desktop uses SSD storage
3. **Increase Docker resources**: Allocate more CPU/RAM in Docker Desktop settings
4. **Regular cleanup**: Remove unused sites and Docker resources

## Security Notes

- This setup is for **development purposes only**
- Default credentials should be changed in production environments
- Each site runs on localhost and is not accessible externally
- Consider using Docker secrets for sensitive data in production
- Keep Docker Desktop and images updated

## File Structure After Setup

```
wordpress-docker/
├── wp-test-project1/          # Individual site
│   ├── wp-content/            # Themes, plugins, uploads
│   ├── docker-compose.yml     # Site configuration (auto-generated)
│   ├── manage-site.sh         # Site management (auto-generated)
│   └── site-info.txt          # Site details
├── wp-test-project2/          # Another site
├── lib/
│   └── common.sh              # Shared script functions
├── templates/
│   └── docker-compose.yml.template  # Docker Compose template
├── create-wp-site.sh          # Site creation
├── import-wp-site.sh          # Site import from SQL + wp-content
├── list-wp-sites.sh           # Multi-site management
├── wp-dev.sh                  # Interactive menu
├── cleanup-wp-sites.sh        # Cleanup utility
└── setup.sh                   # Initial setup
```

## Support

For issues, suggestions, or contributions:
1. Check the troubleshooting section above
2. Review container logs for error details
3. Ensure Docker Desktop is running and updated
4. Verify available disk space and Docker resources

---

**Happy WordPress Development!** 🚀