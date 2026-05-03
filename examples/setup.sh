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
FROM ghcr.io/dirop1/frankenbase:latest

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
      DB_CONNECTION: \${DB_CONNECTION:-mysql}
      DB_HOST: \${DB_HOST:-db}
      DB_PORT: \${DB_PORT:-3306}
      DB_DATABASE: \${DB_DATABASE}
      DB_USERNAME: \${DB_USERNAME}
      DB_PASSWORD: \${DB_PASSWORD}
      REDIS_HOST: \${REDIS_HOST:-redis}
      HORIZON_ENABLED: "${HORIZON_ENABLED}"
      SSR_ENABLED: "${SSR_ENABLED}"
      # TRUSTED_PROXIES: "0.0.0.0/0 ::/0"  # default — scope to your proxy IPs
    depends_on:
      - db
      - redis
    healthcheck:
      test: ["CMD", "/usr/local/bin/healthcheck"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s

  db:
    image: mariadb:11
    restart: unless-stopped
    environment:
      MARIADB_DATABASE: \${DB_DATABASE}
      MARIADB_USER: \${DB_USERNAME}
      MARIADB_PASSWORD: \${DB_PASSWORD}
      MARIADB_ROOT_PASSWORD: \${DB_ROOT_PASSWORD}
    volumes:
      - db_data:/var/lib/mysql

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    volumes:
      - redis_data:/data

volumes:
  db_data:
  redis_data:
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

echo ""
info "Done. Next steps:"
echo "  1. Copy .env.example to .env and fill in your values"
echo "  2. docker compose build"
echo "  3. docker compose up -d"
echo "  4. docker compose exec app php artisan migrate"
