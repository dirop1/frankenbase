#!/bin/bash
# Generate a production Caddyfile and start FrankenPHP.

set -euo pipefail

CADDYFILE="/etc/frankenphp/Caddyfile"
WORKER_FILE="/app/public/frankenphp-worker.php"

TRUSTED_PROXIES="${TRUSTED_PROXIES-0.0.0.0/0 ::/0}"
FRANKENPHP_MAX_WAIT_TIME="${FRANKENPHP_MAX_WAIT_TIME:-10s}"
REQUEST_MAX_EXECUTION_TIME="${REQUEST_MAX_EXECUTION_TIME:-${MAX_EXECUTION_TIME:-30}}"
MAX_REQUESTS="${MAX_REQUESTS:-1000}"
FRANKENPHP_NUM_THREADS="${FRANKENPHP_NUM_THREADS:-}"
FRANKENPHP_MAX_THREADS="${FRANKENPHP_MAX_THREADS:-}"
FRANKENPHP_WORKER_COUNT="${FRANKENPHP_WORKER_COUNT:-}"

require_unsigned_integer() {
    local name="$1"
    local value="$2"

    if [[ ! "$value" =~ ^(0|[1-9][0-9]*)$ ]]; then
        echo "[FrankenPHP Init] ${name} must be an unsigned base-10 integer, got: ${value}" >&2
        exit 1
    fi
}

if [[ ! "$FRANKENPHP_MAX_WAIT_TIME" =~ ^[0-9]+(ms|s|m|h)$ ]]; then
    echo "[FrankenPHP Init] FRANKENPHP_MAX_WAIT_TIME must be a duration such as 500ms, 10s, 2m, or 1h" >&2
    exit 1
fi

require_unsigned_integer "REQUEST_MAX_EXECUTION_TIME" "$REQUEST_MAX_EXECUTION_TIME"
require_unsigned_integer "MAX_REQUESTS" "$MAX_REQUESTS"

if [ -f "$WORKER_FILE" ] && [ "$MAX_REQUESTS" -eq 0 ]; then
    echo "[FrankenPHP Init] MAX_REQUESTS must be greater than zero in Laravel worker mode" >&2
    exit 1
fi

if [[ ! "$TRUSTED_PROXIES" =~ ^[0-9A-Fa-f:./[:space:]]*$ ]]; then
    echo "[FrankenPHP Init] TRUSTED_PROXIES must contain only space-separated IP addresses or CIDRs" >&2
    exit 1
fi

if [ -n "$FRANKENPHP_NUM_THREADS" ]; then
    require_unsigned_integer "FRANKENPHP_NUM_THREADS" "$FRANKENPHP_NUM_THREADS"
fi

if [ -n "$FRANKENPHP_MAX_THREADS" ] && [[ ! "$FRANKENPHP_MAX_THREADS" =~ ^([0-9]+|auto)$ ]]; then
    echo "[FrankenPHP Init] FRANKENPHP_MAX_THREADS must be an unsigned integer or auto" >&2
    exit 1
fi

if [ -n "$FRANKENPHP_WORKER_COUNT" ]; then
    require_unsigned_integer "FRANKENPHP_WORKER_COUNT" "$FRANKENPHP_WORKER_COUNT"

    if [ "$FRANKENPHP_WORKER_COUNT" -eq 0 ]; then
        echo "[FrankenPHP Init] FRANKENPHP_WORKER_COUNT must be greater than zero" >&2
        exit 1
    fi
fi

if [ -f "$WORKER_FILE" ]; then
    if [ -n "$FRANKENPHP_NUM_THREADS" ] && [ -z "$FRANKENPHP_WORKER_COUNT" ]; then
        if [ "$FRANKENPHP_NUM_THREADS" -lt 2 ]; then
            echo "[FrankenPHP Init] Worker mode requires FRANKENPHP_NUM_THREADS to be at least 2" >&2
            exit 1
        fi

        FRANKENPHP_WORKER_COUNT=$((FRANKENPHP_NUM_THREADS - 1))
    elif [ -n "$FRANKENPHP_WORKER_COUNT" ] && [ -z "$FRANKENPHP_NUM_THREADS" ]; then
        FRANKENPHP_NUM_THREADS=$((FRANKENPHP_WORKER_COUNT + 1))
    fi

    if [ -n "$FRANKENPHP_WORKER_COUNT" ] && [ "$FRANKENPHP_WORKER_COUNT" -ge "$FRANKENPHP_NUM_THREADS" ]; then
        echo "[FrankenPHP Init] FRANKENPHP_NUM_THREADS must be greater than FRANKENPHP_WORKER_COUNT" >&2
        exit 1
    fi
fi

if [ -n "$FRANKENPHP_NUM_THREADS" ] \
    && [[ "$FRANKENPHP_MAX_THREADS" =~ ^[0-9]+$ ]] \
    && [ "$FRANKENPHP_MAX_THREADS" -lt "$FRANKENPHP_NUM_THREADS" ]; then
    echo "[FrankenPHP Init] FRANKENPHP_MAX_THREADS must be at least FRANKENPHP_NUM_THREADS" >&2
    exit 1
fi

export REQUEST_MAX_EXECUTION_TIME MAX_REQUESTS

echo "[FrankenPHP Init] Generating Caddyfile..."
echo "[FrankenPHP Init] Trusted proxies: ${TRUSTED_PROXIES}"
echo "[FrankenPHP Init] Maximum queue wait: ${FRANKENPHP_MAX_WAIT_TIME}"

cat > "$CADDYFILE" << EOF
{
    metrics
    frankenphp {
        max_wait_time ${FRANKENPHP_MAX_WAIT_TIME}
EOF

if [ -n "$FRANKENPHP_NUM_THREADS" ]; then
    echo "        num_threads ${FRANKENPHP_NUM_THREADS}" >> "$CADDYFILE"
fi

if [ -n "$FRANKENPHP_MAX_THREADS" ]; then
    echo "        max_threads ${FRANKENPHP_MAX_THREADS}" >> "$CADDYFILE"
fi

if [ -f "$WORKER_FILE" ]; then
    echo "[FrankenPHP Init] Worker mode active ($WORKER_FILE found)"
    echo "[FrankenPHP Init] Request timeout: ${REQUEST_MAX_EXECUTION_TIME}s; recycle after ${MAX_REQUESTS} requests"
    cat >> "$CADDYFILE" << EOF
        worker {
            file ${WORKER_FILE}
            name app
EOF
    if [ -n "$FRANKENPHP_WORKER_COUNT" ]; then
        echo "            num ${FRANKENPHP_WORKER_COUNT}" >> "$CADDYFILE"
    fi
    cat >> "$CADDYFILE" << EOF
            env REQUEST_MAX_EXECUTION_TIME ${REQUEST_MAX_EXECUTION_TIME}
            env MAX_REQUESTS ${MAX_REQUESTS}
        }
EOF
else
    echo "[FrankenPHP Init] Worker mode inactive (no frankenphp-worker.php)"
fi

cat >> "$CADDYFILE" << 'EOF'
    }
    admin localhost:2019
EOF

if [ -n "$TRUSTED_PROXIES" ]; then
    cat >> "$CADDYFILE" << EOF
    servers {
        trusted_proxies static ${TRUSTED_PROXIES}
    }
EOF
fi

cat >> "$CADDYFILE" << 'EOF'
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

    # Liveness only. The container healthcheck separately probes the application.
    handle /healthz {
        respond "OK" 200
    }
EOF

if [ -f "$WORKER_FILE" ]; then
    cat >> "$CADDYFILE" << 'EOF'

    php_server {
        index frankenphp-worker.php
        try_files {path} frankenphp-worker.php
        resolve_root_symlink
    }
}
EOF
else
    cat >> "$CADDYFILE" << 'EOF'

    php_server {
        try_files {path} index.php
        resolve_root_symlink
    }
}
EOF
fi

echo "[FrankenPHP Init] Caddyfile generated:"
echo "---"
cat "$CADDYFILE"
echo "---"

echo "[FrankenPHP Init] Starting FrankenPHP..."
exec frankenphp run --config "$CADDYFILE"
