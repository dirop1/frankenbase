#!/bin/bash
# Verify liveness, application responsiveness, and all enabled Supervisor programs.

set -euo pipefail

APP_HEALTHCHECK_PATH="${APP_HEALTHCHECK_PATH:-/up}"
APP_HEALTHCHECK_TIMEOUT="${APP_HEALTHCHECK_TIMEOUT:-3}"

if [[ "$APP_HEALTHCHECK_PATH" != /* ]]; then
    echo "healthcheck: APP_HEALTHCHECK_PATH must start with /" >&2
    exit 1
fi

if [[ ! "$APP_HEALTHCHECK_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || [ "$APP_HEALTHCHECK_TIMEOUT" -gt 10 ]; then
    echo "healthcheck: APP_HEALTHCHECK_TIMEOUT must be an integer between 1 and 10" >&2
    exit 1
fi

# Caddy liveness: this endpoint never enters PHP.
curl --noproxy '*' -fsS --max-time 2 http://127.0.0.1/healthz > /dev/null || {
    echo "healthcheck: /healthz did not respond" >&2
    exit 1
}

# Application readiness: 4xx is acceptable for apps without /up, but PHP must answer.
http_status="$(curl --noproxy '*' -sS -o /dev/null -w '%{http_code}' --max-time "$APP_HEALTHCHECK_TIMEOUT" "http://127.0.0.1${APP_HEALTHCHECK_PATH}")" || {
    echo "healthcheck: application path ${APP_HEALTHCHECK_PATH} did not respond within ${APP_HEALTHCHECK_TIMEOUT}s" >&2
    exit 1
}

if [ "$http_status" -ge 500 ]; then
    echo "healthcheck: application path ${APP_HEALTHCHECK_PATH} returned HTTP ${http_status}" >&2
    exit 1
fi

supervisor_status="$(supervisorctl -c /etc/supervisord.conf status 2>/dev/null)" || {
    echo "healthcheck: could not query Supervisor" >&2
    exit 1
}

if awk 'NF >= 2 && $2 != "RUNNING" { failed = 1 } END { exit !failed }' <<< "$supervisor_status"; then
    echo "healthcheck: one or more enabled Supervisor programs are not running:" >&2
    echo "$supervisor_status" >&2
    exit 1
fi
