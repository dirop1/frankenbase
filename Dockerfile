FROM dunglas/frankenphp:1.12.2

ARG TARGETARCH

ENV TZ=UTC

# ── Layer 1: PHP extensions (slowest, changes least — cache is precious here)
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

# ── Layer 2: System packages + Node.js 20
# No apt-get upgrade — avoids busting this layer on every upstream package update.
# Security patches come from rebuilding against a new dunglas/frankenphp base tag.
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends \
        nodejs \
        unzip \
        curl \
        supervisor \
        procps \
        libcap2-bin \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# ── Layer 3: Runtime setup (fast, stable)
RUN setcap cap_net_bind_service=+ep /usr/local/bin/frankenphp

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN groupadd -g 1000 application && \
    useradd -u 1000 -g application -m -s /bin/bash application

WORKDIR /app

# ── Layer 4: Scripts and configs (changes most often — kept at the bottom)
COPY supervisord.conf /etc/supervisord.conf
COPY supervisor-frankenphp.conf /etc/supervisor.d/frankenphp.conf
COPY supervisor-horizon.conf /etc/supervisor.d/horizon.conf
COPY supervisor-scheduler.conf /etc/supervisor.d/scheduler.conf
COPY supervisor-ssr.conf /etc/supervisor.d/ssr.conf
COPY apply-php-security.sh /usr/local/bin/apply-php-security
COPY frankenphp-init.sh /usr/local/bin/frankenphp-init
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint
COPY healthcheck.sh /usr/local/bin/healthcheck
RUN chmod +x \
    /usr/local/bin/apply-php-security \
    /usr/local/bin/frankenphp-init \
    /usr/local/bin/docker-entrypoint \
    /usr/local/bin/healthcheck

RUN mkdir -p /etc/frankenphp /data/caddy /config/caddy && \
    chown -R application:application /etc/frankenphp /data/caddy /config/caddy /tmp

# ============================================================================
# DOWNSTREAM APP USAGE:
# ============================================================================
# When building your Laravel app FROM this base image, add these steps:
#
# 1. Copy your Laravel app code:
#    COPY . /app
#
# 2. Install dependencies and optimize:
#    RUN composer install --no-dev --optimize-autoloader \
#        && npm install \
#        && npm run build \
#        && php artisan config:cache \
#        && php artisan route:cache \
#        && php artisan view:cache \
#        && apply-php-security \
#        && chown -R application:application /app \
#        && chmod -R 755 /app \
#        && chmod -R 775 /app/storage /app/bootstrap/cache
# ============================================================================

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD /usr/local/bin/healthcheck

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]
