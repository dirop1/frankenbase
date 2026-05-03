FROM dunglas/frankenphp:1.12.2

ARG TARGETARCH

ENV TZ=UTC

# Install PHP extensions (install-php-extensions handles ZTS automatically)
RUN install-php-extensions \
    bcmath \
    intl \
    mbstring \
    pdo \
    pdo_mysql \
    pdo_pgsql \
    pgsql \
    xml \
    pcntl \
    zip \
    exif \
    sockets \
    gd \
    redis

# Add Node.js 20 and runtime dependencies
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update && apt-get upgrade -y && apt-get install -y \
        nodejs \
        unzip \
        curl \
        supervisor \
        procps \
        libcap2-bin \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Allow FrankenPHP to bind to port 80 as non-root
RUN setcap cap_net_bind_service=+ep /usr/local/bin/frankenphp

# Copy Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Create application user
RUN groupadd -g 1000 application && \
    useradd -u 1000 -g application -m -s /bin/bash application

# Copy PHP security script
COPY apply-php-security.sh /usr/local/bin/apply-php-security
RUN chmod +x /usr/local/bin/apply-php-security

WORKDIR /app

# ============================================================================
# DOWNSTREAM APP USAGE:
# ============================================================================
# When building your Laravel app FROM this base image, add these steps:
#
# 1. Copy your Laravel app code:
#    COPY . /app
#
# 2. Install dependencies and optimize:
#    RUN composer install --no-dev --optimize-autoloader
#    RUN npm install && npm run build
#    RUN php artisan config:cache && php artisan route:cache && php artisan view:cache
#
# 3. Apply PHP security hardening:
#    RUN apply-php-security
#
# 4. Set final permissions:
#    RUN chown -R application:application /app && \
#        chmod -R 755 /app && \
#        chmod -R 775 /app/storage /app/bootstrap/cache
# ============================================================================

# Copy supervisor configurations
COPY supervisord.conf /etc/supervisord.conf
COPY supervisor-frankenphp.conf /etc/supervisor.d/frankenphp.conf
COPY supervisor-horizon.conf /etc/supervisor.d/horizon.conf
COPY supervisor-scheduler.conf /etc/supervisor.d/scheduler.conf

# Copy FrankenPHP init script (generates Caddyfile + starts server)
COPY frankenphp-init.sh /usr/local/bin/frankenphp-init
RUN chmod +x /usr/local/bin/frankenphp-init

# Create directories for Caddy (TLS certs, config cache)
RUN mkdir -p /etc/frankenphp /data/caddy /config/caddy && \
    chown -R application:application /etc/frankenphp /data/caddy /config/caddy /tmp

EXPOSE 80

ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf", "-n"]
