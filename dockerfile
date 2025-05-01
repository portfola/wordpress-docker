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

# Copy our installer script
COPY wp-installer.sh /usr/local/bin/wp-installer.sh
RUN chmod +x /usr/local/bin/wp-installer.sh