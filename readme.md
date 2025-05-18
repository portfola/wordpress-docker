# WordPress Docker Development Environment

This Docker setup provides a complete WordPress development environment with wp-cli pre-installed. It's designed to make it easy to spin up new WordPress test sites quickly.

## Project Structure

- `Dockerfile` - Creates a WordPress image with wp-cli installed
- `docker-compose.yml` - Configures the WordPress and MySQL services
- `create-wp-site.sh` - Script to create a new WordPress instance
- `wp-installer.sh` - Handles WordPress installation and configuration
- `cleanup-wp-sites.sh` - Utility script to clean up WordPress test sites
- `setup.sh` - Initial setup script for the environment
- `check-platform.sh` - Detects OS and Docker environment
- `.gitattributes` - Ensures consistent line endings across platforms
- `.gitignore` - Git ignore rules for WordPress development

## Getting Started

### Prerequisites

- Docker Desktop installed and running
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

3. Create a new WordPress site:
   ```bash
   ./create-wp-site.sh
   ```

4. Access your WordPress site at http://localhost:8080

5. Log in to the WordPress admin at http://localhost:8080/wp-admin using:
   - Username: jerry
   - Password: garcia

### Platform-Specific Notes

#### Windows Users (Git Bash)
```bash
# Clone and setup
git clone <repository-url>
cd wordpress-docker

# Run setup
./setup.sh

# Create site
./create-wp-site.sh
```

#### macOS/Linux Users
```bash
# Same commands work!
./setup.sh
./create-wp-site.sh
```

## Configuration

The environment can be customized by modifying the following files:

### docker-compose.yml

Key configuration options:
- Port mapping: `8080:80` (change 8080 to use a different port)
- Database credentials
- WordPress environment variables:
  - `WORDPRESS_SITE_TITLE`
  - `WORDPRESS_ADMIN_USER`
  - `WORDPRESS_ADMIN_PASSWORD`
  - `WORDPRESS_ADMIN_EMAIL`

### Volumes

- `wp_data`: Persistent WordPress files
- `db_data`: Persistent MySQL database
- `./wp-content`: Local development directory for themes and plugins

## Using wp-cli

To use wp-cli commands inside your running container:

```bash
docker-compose exec wordpress wp --info
```

Common wp-cli commands:

```bash
# List all plugins
docker-compose exec wordpress wp plugin list

# Install and activate a plugin
docker-compose exec wordpress wp plugin install woocommerce --activate

# Update all plugins
docker-compose exec wordpress wp plugin update --all

# Create a new user
docker-compose exec wordpress wp user create editor editor@example.com --role=editor
```

## Development Workflow

1. Place your custom themes in `wp-content/themes/`
2. Place your custom plugins in `wp-content/plugins/`
3. Changes to these directories are reflected immediately in the container

## Creating New Sites

Use the `create-wp-site.sh` script to create new WordPress instances:

```bash
./create-wp-site.sh
```

To clean up previous instances before creating a new one:

```bash
./create-wp-site.sh -c
```

## Cleanup

To remove test sites and clean up resources:

```bash
./cleanup-wp-sites.sh
```

For non-interactive cleanup (useful in scripts):

```bash
./cleanup-wp-sites.sh -f
```

## Troubleshooting

- View container logs: `docker-compose logs`
- Reset environment: `docker-compose down -v` (warning: deletes all data)
- Access container shell: `docker-compose exec wordpress bash`
- Check container status: `docker-compose ps`
- Check platform compatibility: `./check-platform.sh`

## Maintenance

- To update WordPress core: `docker-compose exec wordpress wp core update`
- To update all plugins: `docker-compose exec wordpress wp plugin update --all`
- To update all themes: `docker-compose exec wordpress wp theme update --all`

## Security Notes

- This setup is for development purposes only
- Default credentials should be changed in production
- Consider using Docker secrets for sensitive data in production

