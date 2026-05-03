#!/bin/bash
# FrankenPHP Init - Generates Caddyfile based on environment and starts FrankenPHP

CADDYFILE="/etc/frankenphp/Caddyfile"
WORKER_FILE="/app/public/frankenphp-worker.php"

echo "[FrankenPHP Init] Generating Caddyfile..."

# Global block
cat > "$CADDYFILE" << 'EOF'
{
    frankenphp {
EOF

if [ -f "$WORKER_FILE" ]; then
    echo "[FrankenPHP Init] Worker mode active ($WORKER_FILE found)"
    cat >> "$CADDYFILE" << 'EOF'
        worker /app/public/frankenphp-worker.php
EOF
else
    echo "[FrankenPHP Init] Worker mode inactive (no frankenphp-worker.php)"
fi

cat >> "$CADDYFILE" << 'EOF'
    }
    admin localhost:2019
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
