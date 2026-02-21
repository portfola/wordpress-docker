# Use the official WordPress image as our base
FROM wordpress:6.9-php7.4-apache

# Install dependencies needed for wp-cli and cross-platform compatibility
RUN apt-get update && apt-get install -y \
    less \
    default-mysql-client \
    sudo \
    dos2unix \
    && rm -rf /var/lib/apt/lists/*

# Install wp-cli
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Set up wp-cli to run as www-data user
RUN chown www-data:www-data /usr/local/bin/wp
RUN mkdir -p /var/www/.wp-cli
RUN chown www-data:www-data /var/www/.wp-cli

# Create custom PHP configuration to increase memory limits
RUN echo "memory_limit = 512M" > /usr/local/etc/php/conf.d/memory-limit.ini
RUN echo "max_execution_time = 300" >> /usr/local/etc/php/conf.d/memory-limit.ini

# Set working directory
WORKDIR /var/www/html

# Copy our installer script and fix line endings
COPY wp-installer.sh /usr/local/bin/wp-installer.sh
RUN dos2unix /usr/local/bin/wp-installer.sh
RUN chmod +x /usr/local/bin/wp-installer.sh

# Set proper ownership
RUN chown www-data:www-data /usr/local/bin/wp-installer.sh