#!/bin/bash
set -euo pipefail

# Convert line endings (helpful for cross-platform)
command -v dos2unix >/dev/null 2>&1 && dos2unix "$0" 2>/dev/null || true

echo "Starting WordPress installation process..."

# Increase PHP memory limit for this process
export WP_CLI_PHP_ARGS='-d memory_limit=512M'

# First, download WordPress core files if they don't exist
echo "Checking for WordPress core files..."
if [ ! -f "/var/www/html/wp-config.php" ] && [ ! -f "/var/www/html/index.php" ]; then
  echo "WordPress core files not found. Downloading..."
  
  # Try to download with increased memory and timeout
  timeout 180 wp core download --allow-root --force --locale=en_US || {
    echo "wp-cli download failed, trying alternative method..."
    
    # Alternative: download WordPress directly using curl
    echo "Downloading WordPress directly..."
    cd /var/www/html
    curl -o latest.tar.gz https://wordpress.org/latest.tar.gz
    tar -xzf latest.tar.gz --strip-components=1
    rm latest.tar.gz
    chown -R www-data:www-data /var/www/html
  }
fi

# Now test database connectivity using a different method first
echo "Testing basic database connectivity..."
MAX_TRIES=60
COUNT=0

# Function to test database connectivity without wp-cli dependency
test_database_connection() {
    # Try to connect using mysql client directly
    mysql -h "${WORDPRESS_DB_HOST}" -u "${WORDPRESS_DB_USER}" -p"${WORDPRESS_DB_PASSWORD}" \
          -e "SELECT 1;" "${WORDPRESS_DB_NAME}" 2>/dev/null
    return $?
}

echo "Waiting for database connection..."
until test_database_connection || [ $COUNT -eq $MAX_TRIES ]; do
  echo "Database not ready yet, waiting... ($COUNT/$MAX_TRIES)"
  sleep 5
  COUNT=$((COUNT+1))
done

if [ $COUNT -eq $MAX_TRIES ]; then
  echo "ERROR: Database connection timed out!"
  echo "Attempting diagnostics..."
  echo "Database host: ${WORDPRESS_DB_HOST}"
  echo "Database name: ${WORDPRESS_DB_NAME}"
  echo "Database user: ${WORDPRESS_DB_USER}"
  
  # Try to ping the database host
  echo "Testing host connectivity..."
  if ping -c 1 "${WORDPRESS_DB_HOST}" > /dev/null 2>&1; then
    echo "✓ Database host is reachable"
  else
    echo "✗ Database host is unreachable"
  fi
  
  exit 1
fi

echo "✓ Database connection successful!"

# Create wp-config.php if it doesn't exist
if [ ! -f "/var/www/html/wp-config.php" ]; then
  echo "Creating wp-config.php..."
  
  # Try wp-cli method first
  if ! wp config create --allow-root \
    --dbname="${WORDPRESS_DB_NAME}" \
    --dbuser="${WORDPRESS_DB_USER}" \
    --dbpass="${WORDPRESS_DB_PASSWORD}" \
    --dbhost="${WORDPRESS_DB_HOST}" \
    --extra-php <<PHP
// Custom WordPress configuration
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);
define('WP_AUTO_UPDATE_CORE', true);
PHP
  then
    echo "wp-cli config create failed, creating wp-config.php manually..."
    
    # Manual wp-config.php creation
    cat > /var/www/html/wp-config.php <<EOF
<?php
define('DB_NAME', '${WORDPRESS_DB_NAME}');
define('DB_USER', '${WORDPRESS_DB_USER}');
define('DB_PASSWORD', '${WORDPRESS_DB_PASSWORD}');
define('DB_HOST', '${WORDPRESS_DB_HOST}');
define('DB_CHARSET', 'utf8');
define('DB_COLLATE', '');

define('AUTH_KEY',         'put your unique phrase here');
define('SECURE_AUTH_KEY',  'put your unique phrase here');
define('LOGGED_IN_KEY',    'put your unique phrase here');
define('NONCE_KEY',        'put your unique phrase here');
define('AUTH_SALT',        'put your unique phrase here');
define('SECURE_AUTH_SALT', 'put your unique phrase here');
define('LOGGED_IN_SALT',   'put your unique phrase here');
define('NONCE_SALT',       'put your unique phrase here');

\$table_prefix = 'wp_';

define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);
define('WP_AUTO_UPDATE_CORE', true);

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOF
    chown www-data:www-data /var/www/html/wp-config.php
  fi
fi

# Check if WordPress is already installed
echo "Checking WordPress installation status..."
if ! wp core is-installed --allow-root 2>/dev/null; then
  echo "Installing WordPress..."
  
  # Try wp-cli installation
  if wp core install --allow-root \
    --url="${WORDPRESS_SITE_URL:-http://localhost:8080}" \
    --title="${WORDPRESS_SITE_TITLE:-WordPress Development Site}" \
    --admin_user="${WORDPRESS_ADMIN_USER:-admin}" \
    --admin_password="${WORDPRESS_ADMIN_PASSWORD:-password}" \
    --admin_email="${WORDPRESS_ADMIN_EMAIL:-admin@example.com}" 2>/dev/null; then
    
    echo "✓ WordPress installation successful!"
    
    # Set proper file permissions
    echo "Setting file permissions..."
    chown -R www-data:www-data /var/www/html
    find /var/www/html -type d -exec chmod 755 {} \; 2>/dev/null || true
    find /var/www/html -type f -exec chmod 644 {} \; 2>/dev/null || true
    
    # Install themes and plugins with error handling
    echo "Installing themes and plugins..."
    wp theme install kadence --allow-root 2>/dev/null || echo "Note: Could not install Kadence theme"
    wp plugin install query-monitor --activate --allow-root 2>/dev/null || echo "Note: Could not install query-monitor"
    
    echo "WordPress installation complete!"
    echo "Site: ${WORDPRESS_SITE_URL:-http://localhost:8080}"
    echo "Admin: ${WORDPRESS_ADMIN_USER:-admin} / ${WORDPRESS_ADMIN_PASSWORD:-password}"
  else
    echo "wp-cli installation failed, but WordPress files are in place"
    echo "You can complete the installation manually at: ${WORDPRESS_SITE_URL:-http://localhost:8080}"
  fi
else
  echo "WordPress is already installed."
  echo "Site: ${WORDPRESS_SITE_URL:-http://localhost:8080}"
fi

echo "WordPress setup finished successfully!"

# Final check - make sure index.php exists
if [ -f "/var/www/html/index.php" ]; then
  echo "✓ WordPress files are in place"
else
  echo "⚠ Warning: index.php not found, there may be an issue with the installation"
fi