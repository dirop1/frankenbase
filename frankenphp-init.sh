#!/bin/bash
# FrankenPHP Init - Generates Caddyfile based on environment and starts FrankenPHP

CADDYFILE="/etc/frankenphp/Caddyfile"
WORKER_FILE="/app/public/frankenphp-worker.php"

# TRUSTED_PROXIES: space-separated list of trusted upstream proxy CIDRs.
# Default trusts all — correct when behind Cloudflare, NPM, or any reverse proxy.
# Scope this to your actual proxy IPs if the container is directly internet-facing.
# Example: TRUSTED_PROXIES="173.245.48.0/20 103.21.244.0/22"  (Cloudflare IPv4 ranges)
TRUSTED_PROXIES="${TRUSTED_PROXIES:-0.0.0.0/0 ::/0}"

echo "[FrankenPHP Init] Generating Caddyfile..."
echo "[FrankenPHP Init] Trusted proxies: ${TRUSTED_PROXIES}"

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
EOF

# Trusted proxies uses env var expansion — no single-quoted EOF
cat >> "$CADDYFILE" << EOF
    servers {
        trusted_proxies static ${TRUSTED_PROXIES}
    }
}
EOF

cat >> "$CADDYFILE" << 'EOF'

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
