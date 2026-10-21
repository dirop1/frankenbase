# Official multiarch upstream containing the PHP security fixes.
FROM dunglas/frankenphp:1.13.1-php8.5@sha256:55c63014b845d24c3986b72ce7fdd1bdbb3c9219a1ecdc37bf828c7f038e6f1a

# Fail closed if the base is changed to an unpatched or non-ZTS PHP runtime.
RUN php -r 'if (PHP_MAJOR_VERSION !== 8 || PHP_MINOR_VERSION !== 5 || version_compare(PHP_VERSION, "8.5.12", "<") || !PHP_ZTS) { fwrite(STDERR, "PHP 8.5 >= 8.5.12 ZTS required; found " . PHP_VERSION . PHP_EOL); exit(1); }'

ARG TARGETARCH
ARG FRANKENBASE_VERSION=dev

ENV TZ=UTC \
    FRANKENBASE_VERSION=${FRANKENBASE_VERSION}

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
COPY supervisor-watchdog.conf /etc/supervisor.d/frankenphp-watchdog.conf
COPY supervisor-horizon.conf /etc/supervisor.d/horizon.conf
COPY supervisor-scheduler.conf /etc/supervisor.d/scheduler.conf
COPY supervisor-ssr.conf /etc/supervisor.d/ssr.conf
COPY apply-php-security.sh /usr/local/bin/apply-php-security
COPY frankenphp-init.sh /usr/local/bin/frankenphp-init
COPY frankenphp-watchdog.sh /usr/local/bin/frankenphp-watchdog
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint
COPY healthcheck.sh /usr/local/bin/healthcheck
RUN chmod +x \
    /usr/local/bin/apply-php-security \
    /usr/local/bin/frankenphp-init \
    /usr/local/bin/frankenphp-watchdog \
    /usr/local/bin/docker-entrypoint \
    /usr/local/bin/healthcheck

RUN mkdir -p /etc/frankenbase /etc/frankenphp /data/caddy /config/caddy /run/frankenbase && \
    printf '%s\n' "$FRANKENBASE_VERSION" > /etc/frankenbase/version && \
    chmod 0444 /etc/frankenbase/version && \
    chown -R application:application /etc/frankenphp /data/caddy /config/caddy && \
    chown root:root /etc/frankenbase /run/frankenbase && \
    chmod 755 /etc/frankenbase /run/frankenbase

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

HEALTHCHECK --interval=30s --timeout=15s --start-period=30s --retries=3 \
    CMD /usr/local/bin/healthcheck

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]
