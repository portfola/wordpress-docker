#!/bin/bash
set -e

# First run the original WordPress entrypoint to set up the environment
. /usr/local/bin/docker-entrypoint.sh

# Check if WordPress is already installed
if [ ! -f wp-config.php ]; then
  # Wait for MySQL to be ready
  echo "Waiting for database connection..."
  until wp db check --allow-root; do
    echo "Database not ready yet, waiting..."
    sleep 2
  done

  # Set up WP config
  echo "Creating wp-config.php..."
  wp config create --allow-root \
    --dbname="${WORDPRESS_DB_NAME}" \
    --dbuser="${WORDPRESS_DB_USER}" \
    --dbpass="${WORDPRESS_DB_PASSWORD}" \
    --dbhost="${WORDPRESS_DB_HOST}" \
    --dbprefix="${WORDPRESS_TABLE_PREFIX:-wp_}"

  # Install WordPress
  echo "Installing WordPress..."
  wp core install --allow-root \
    --url="${WORDPRESS_SITE_URL:-localhost}" \
    --title="${WORDPRESS_SITE_TITLE:-WordPress Development Site}" \
    --admin_user="${WORDPRESS_ADMIN_USER:-admin}" \
    --admin_password="${WORDPRESS_ADMIN_PASSWORD:-password}" \
    --admin_email="${WORDPRESS_ADMIN_EMAIL:-admin@example.com}"

  # Remove all default themes except the latest one
  echo "Managing themes..."
  LATEST_DEFAULT_THEME=$(wp theme list --status=active --field=name --allow-root)
  wp theme list --field=name --allow-root | grep -v "$LATEST_DEFAULT_THEME" | xargs -I % wp theme delete % --allow-root

  # Install Kadence theme
  wp theme install kadence --allow-root

  # Install standard plugins
  echo "Installing standard plugins..."
  wp plugin install deadpress --activate --allow-root
  wp plugin install woocommerce --activate --allow-root
  wp plugin install query-monitor --activate --allow-root
  wp plugin install wordpress-beta-tester --activate --allow-root

  echo "WordPress installation complete!"
fi

# Execute the passed command
exec "$@"