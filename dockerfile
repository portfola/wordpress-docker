# Use the official WordPress image as our base
FROM wordpress:latest

# Install dependencies needed for wp-cli
RUN apt-get update && apt-get install -y \
    less \
    default-mysql-client \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install wp-cli
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Set up wp-cli to run as www-data user
RUN chown www-data:www-data /usr/local/bin/wp
RUN mkdir -p /var/www/.wp-cli
RUN chown www-data:www-data /var/www/.wp-cli

# Set working directory
WORKDIR /var/www/html

# Create initialization script to install WordPress when container starts
COPY docker-entrypoint-custom.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint-custom.sh

# Use our custom entrypoint
ENTRYPOINT ["docker-entrypoint-custom.sh"]
CMD ["apache2-foreground"]