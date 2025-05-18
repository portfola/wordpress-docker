#!/bin/bash
set -e

echo "Starting WordPress installation process..."

# Wait for MySQL to be ready
echo "Waiting for database connection..."
MAX_TRIES=30
COUNT=0
until wp db check --allow-root || [ $COUNT -eq $MAX_TRIES ]; do
  echo "Database not ready yet, waiting... ($COUNT/$MAX_TRIES)"
  sleep 3
  COUNT=$((COUNT+1))
done

if [ $COUNT -eq $MAX_TRIES ]; then
  echo "ERROR: Database connection timed out!"
  exit 1
fi

echo "Database connection successful!"

# Check if WordPress core files exist
if [ ! -f "/var/www/html/wp-config.php" ] && [ ! -f "/var/www/html/index.php" ]; then
  echo "WordPress core files not found. Downloading..."
  wp core download --allow-root
fi

# Create wp-config.php if it doesn't exist
if [ ! -f "/var/www/html/wp-config.php" ]; then
  echo "Creating wp-config.php..."
  wp config create --allow-root \
    --dbname="${WORDPRESS_DB_NAME}" \
    --dbuser="${WORDPRESS_DB_USER}" \
    --dbpass="${WORDPRESS_DB_PASSWORD}" \
    --dbhost="${WORDPRESS_DB_HOST}" \
    --extra-php <<PHP
// Custom WordPress configuration
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);

// Automatic updates
define('WP_AUTO_UPDATE_CORE', true);
PHP
fi

# Check if WordPress is already installed
if ! wp core is-installed --allow-root; then
  echo "Installing WordPress..."
  wp core install --allow-root \
    --url="${WORDPRESS_SITE_URL:-localhost}" \
    --title="${WORDPRESS_SITE_TITLE:-WordPress Development Site}" \
    --admin_user="${WORDPRESS_ADMIN_USER:-admin}" \
    --admin_password="${WORDPRESS_ADMIN_PASSWORD:-password}" \
    --admin_email="${WORDPRESS_ADMIN_EMAIL:-admin@example.com}"

  # Set proper file permissions
  echo "Setting file permissions..."
  chown -R www-data:www-data /var/www/html
  find /var/www/html -type d -exec chmod 755 {} \;
  find /var/www/html -type f -exec chmod 644 {} \;
  
  # Remove all default themes except the latest one
  echo "Managing themes..."
  LATEST_DEFAULT_THEME=$(wp theme list --status=active --field=name --allow-root)
  wp theme list --field=name --allow-root | grep -v "$LATEST_DEFAULT_THEME" | xargs -I % wp theme delete % --allow-root || true
  
  # Install Kadence theme
  wp theme install kadence --allow-root || echo "Note: Could not install Kadence theme"
  
  # Install standard plugins
  echo "Installing standard plugins..."
  wp plugin install deadpress --activate --allow-root || echo "Note: Could not install deadpress"
  wp plugin install woocommerce --activate --allow-root || echo "Note: Could not install woocommerce"
  wp plugin install query-monitor --activate --allow-root || echo "Note: Could not install query-monitor"
  wp plugin install wordpress-beta-tester --activate --allow-root || echo "Note: Could not install wordpress-beta-tester"
  
  echo "WordPress installation complete!"
  echo "Site: ${WORDPRESS_SITE_URL:-http://localhost:8080}"
  echo "Admin: ${WORDPRESS_ADMIN_USER:-admin} / ${WORDPRESS_ADMIN_PASSWORD:-password}"
else
  echo "WordPress is already installed."
  echo "Site: ${WORDPRESS_SITE_URL:-http://localhost:8080}"
fi

echo "WordPress setup finished successfully!"