# WordPress Docker Development Environment

This Docker setup provides a complete WordPress development environment with wp-cli pre-installed. It's designed to make it easy to spin up new WordPress test sites quickly.

## Files Included

- `Dockerfile` - Creates a WordPress image with wp-cli installed
- `docker-entrypoint-custom.sh` - Custom initialization script that sets up WordPress
- `docker-compose.yml` - Configures the WordPress and MySQL services

## Getting Started

### Prerequisites

- Docker Desktop installed and running
- Basic knowledge of Docker and WordPress

### Setup Instructions

1. Create a new directory for your project:
   ```
   mkdir wordpress-dev
   cd wordpress-dev
   ```

2. Copy all the files from this setup into your project directory.

3. Start the containers:
   ```
   docker-compose up -d
   ```

4. Wait for WordPress to be installed automatically (this may take a minute).

5. Access your WordPress site at http://localhost:8080

6. Log in to the WordPress admin at http://localhost:8080/wp-admin using:
   - Username: admin
   - Password: admin_password (or what you set in the docker-compose.yml file)

## Using wp-cli

To use wp-cli commands inside your running container:

```bash
docker-compose exec wordpress wp --info
```

Some useful wp-cli commands:

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

## Saving Your WordPress Image

After setting up your WordPress site with desired plugins, themes, and configurations, you can save the image for future use:

```bash
# Get the container ID
docker ps

# Create a new image from the container
docker commit [container-id] my-wordpress-dev:latest
```

## Creating New Sites from Your Saved Image

1. Create a new docker-compose.yml file pointing to your saved image:
   ```yaml
   version: '3'
   
   services:
     db:
       image: mysql:5.7
       # ...same as before
     
     wordpress:
       image: my-wordpress-dev:latest  # Your saved image
       # ...rest of configuration
   ```

2. Run `docker-compose up -d` to start your new site with all your pre-configured settings.

## Customization

- Edit `docker-compose.yml` to change port mappings, environment variables, or volume settings
- Modify `docker-entrypoint-custom.sh` to add custom initialization steps
- Update `Dockerfile` to install additional tools or plugins

## Troubleshooting

- If the site doesn't come up, check the logs: `docker-compose logs`
- To reset completely: `docker-compose down -v` (this will delete all data)
- If you need to access the container shell: `docker-compose exec wordpress bash`
