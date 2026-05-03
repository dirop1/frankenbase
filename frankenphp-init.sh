#!/bin/bash
# FrankenPHP Init - Generates Caddyfile based on environment and starts FrankenPHP

CADDYFILE="/etc/frankenphp/Caddyfile"

echo "[FrankenPHP Init] Generating Caddyfile..."

cat > "$CADDYFILE" << 'EOF'
{
    frankenphp {
        # Keep PHP workers alive in memory between requests
        # Octane publishes this file via: php artisan octane:install --server=frankenphp
        worker /app/public/frankenphp-worker.php
    }
    # Admin API bound to localhost only
    admin localhost:2019
    # Trust upstream proxies (Cloudflare, Nginx Proxy Manager) for real IP extraction
    servers {
        trusted_proxies static 0.0.0.0/0 ::/0
    }
}

:80 {
    root * /app/public

    log {
        output stdout
        format json {
            time_format "iso8601"
        }
        level INFO
    }

    encode zstd br gzip

    php_server
}
EOF

echo "[FrankenPHP Init] Caddyfile generated:"
echo "---"
cat "$CADDYFILE"
echo "---"

echo "[FrankenPHP Init] Starting FrankenPHP..."
exec frankenphp run --config "$CADDYFILE"
