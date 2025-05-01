#!/bin/bash
set -e

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

# Check if WordPress is already installed
if ! wp core is-installed --allow-root; then
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
  wp theme list --field=name --allow-root | grep -v "$LATEST_DEFAULT_THEME" | xargs -I % wp theme delete % --allow-root || true
  
  # Install Kadence theme
  wp theme install kadence --allow-root
  
  # Install standard plugins
  echo "Installing standard plugins..."
  wp plugin install deadpress --activate --allow-root || true
  wp plugin install woocommerce --activate --allow-root || true
  wp plugin install query-monitor --activate --allow-root || true
  wp plugin install wordpress-beta-tester --activate --allow-root || true
  
  echo "WordPress installation complete!"
else
  echo "WordPress is already installed."
fi