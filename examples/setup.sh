#!/bin/bash
# frankenbase setup — run this from the root of your Laravel app.
# Generates Dockerfile, docker-compose.yml, and .dockerignore.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[frankenbase]${NC} $1"; }
warn()    { echo -e "${YELLOW}[frankenbase]${NC} $1"; }
error()   { echo -e "${RED}[frankenbase]${NC} $1"; exit 1; }

# Verify we're in a Laravel app
[ -f "artisan" ] || error "No artisan found. Run this from your Laravel app root."
[ -f "composer.json" ] || error "No composer.json found."

info "Laravel app detected."

# Gather input
read -p "App name (used for container name) [$(basename "$PWD")]: " APP_NAME
APP_NAME="${APP_NAME:-$(basename "$PWD")}"

read -p "Use Inertia SSR? (node bootstrap/ssr/ssr.js) [y/N]: " SSR_INPUT
SSR_ENABLED="false"
[[ "$SSR_INPUT" =~ ^[Yy]$ ]] && SSR_ENABLED="true"

read -p "Use Laravel Octane worker mode (frankenphp-worker.php)? [Y/n]: " OCTANE_INPUT
OCTANE_ENABLED="true"
[[ "$OCTANE_INPUT" =~ ^[Nn]$ ]] && OCTANE_ENABLED="false"

read -p "Use Laravel Horizon (queues)? [Y/n]: " HORIZON_INPUT
HORIZON_ENABLED="true"
[[ "$HORIZON_INPUT" =~ ^[Nn]$ ]] && HORIZON_ENABLED="false"

read -p "Upload max filesize [12M]: " UPLOAD_SIZE
UPLOAD_SIZE="${UPLOAD_SIZE:-12M}"

# Derive post_max_size from upload size (strip unit, add 1, re-append unit)
UPLOAD_NUM=$(echo "$UPLOAD_SIZE" | sed 's/[^0-9]//g')
UPLOAD_UNIT=$(echo "$UPLOAD_SIZE" | sed 's/[0-9]//g')
POST_SIZE="$((UPLOAD_NUM + 1))${UPLOAD_UNIT}"

# ── Dockerfile ────────────────────────────────────────────────────────────────
if [ -f "Dockerfile" ]; then
    warn "Dockerfile already exists — skipping."
else
    cat > Dockerfile << EOF
FROM ghcr.io/dirop1/frankenbase:0.2.0

ENV UPLOAD_MAX_FILESIZE=${UPLOAD_SIZE} \\
    POST_MAX_SIZE=${POST_SIZE}

COPY . /app

RUN composer install --no-dev --optimize-autoloader \\
    && npm install \\
    && npm run build \\
    && php artisan config:cache \\
    && php artisan route:cache \\
    && php artisan view:cache \\
    && apply-php-security \\
    && chown -R application:application /app \\
    && chmod -R 755 /app \\
    && chmod -R 775 /app/storage /app/bootstrap/cache
EOF
    info "Dockerfile created."
fi

if [ "$OCTANE_ENABLED" = "true" ]; then
    if [ ! -f "public/frankenphp-worker.php" ]; then
        warn "Worker mode enabled but public/frankenphp-worker.php not found."
        warn "Run: php artisan octane:install --server=frankenphp"
        warn "This publishes the worker file required to activate FrankenPHP worker mode."
    else
        info "public/frankenphp-worker.php found — worker mode will be active."
    fi
fi

# ── docker-compose.yml ────────────────────────────────────────────────────────
if [ -f "docker-compose.yml" ]; then
    warn "docker-compose.yml already exists — skipping."
else
    cat > docker-compose.yml << EOF
services:
  app:
    build: .
    container_name: ${APP_NAME}
    restart: unless-stopped
    ports:
      - "80:80"
    environment:
      APP_ENV: production
      APP_KEY: \${APP_KEY}
      APP_URL: \${APP_URL:-http://localhost}
      HORIZON_ENABLED: "${HORIZON_ENABLED}"
      SSR_ENABLED: "${SSR_ENABLED}"
      # This image is designed to run behind a reverse proxy (Cloudflare, Nginx Proxy Manager, Traefik).
      # TRUSTED_PROXIES defaults to 0.0.0.0/0 — scope to your proxy IPs in production.
      # TRUSTED_PROXIES: "173.245.48.0/20 103.21.244.0/22"
    healthcheck:
      test: ["CMD", "/usr/local/bin/healthcheck"]
      interval: 30s
      timeout: 15s
      retries: 3
      start_period: 30s
EOF
    info "docker-compose.yml created."
fi

# ── .dockerignore ─────────────────────────────────────────────────────────────
if [ -f ".dockerignore" ]; then
    warn ".dockerignore already exists — skipping."
else
    cat > .dockerignore << 'EOF'
.git
.github
node_modules
vendor
tests
*.log
.env
.env.*
storage/logs
storage/framework/cache
storage/framework/sessions
storage/framework/views
docker-compose.yml
Dockerfile
README.md
EOF
    info ".dockerignore created."
fi

# ── Laravel TrustProxies check ────────────────────────────────────────────────
TRUST_OK=false

# Laravel 11+: bootstrap/app.php
if [ -f "bootstrap/app.php" ] && grep -q "trustProxies" bootstrap/app.php; then
    TRUST_OK=true
fi

# Laravel 10 and below: TrustProxies middleware
if [ -f "app/Http/Middleware/TrustProxies.php" ] && grep -qE "proxies\s*=\s*['\*]|\*['\"]" app/Http/Middleware/TrustProxies.php; then
    TRUST_OK=true
fi

if [ "$TRUST_OK" = false ]; then
    echo ""
    warn "Laravel TrustProxies is not configured."
    warn "This image runs behind a reverse proxy — without this, request()->ip(),"
    warn "HTTPS detection, and URL generation will behave incorrectly."
    echo ""
    warn "Laravel 11+ — add to bootstrap/app.php:"
    echo '    ->withMiddleware(function (Middleware $middleware) {'
    echo '        $middleware->trustProxies(at: '"'"'*'"'"');'
    echo '    })'
    echo ""
    warn "Laravel 10 and below — set in app/Http/Middleware/TrustProxies.php:"
    echo '    protected $proxies = '"'"'*'"'"';'
else
    info "Laravel TrustProxies is configured."
fi

echo ""
info "Done. Next steps:"
echo "  1. Copy .env.example to .env and fill in your values"
echo "  2. docker compose build"
echo "  3. docker compose up -d"
echo "  4. docker compose exec app php artisan migrate"
