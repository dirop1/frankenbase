#!/bin/bash
# Restart a stalled FrankenPHP worker pool when queued requests make no progress.

set -uo pipefail

INTERVAL="${FRANKENPHP_WATCHDOG_INTERVAL:-10}"
STALL_TIMEOUT="${FRANKENPHP_WATCHDOG_STALL_TIMEOUT:-180}"
QUEUE_THRESHOLD="${FRANKENPHP_WATCHDOG_QUEUE_THRESHOLD:-1}"
COOLDOWN="${FRANKENPHP_WATCHDOG_COOLDOWN:-60}"
METRICS_URL="http://127.0.0.1:2019/metrics"

for setting in INTERVAL STALL_TIMEOUT QUEUE_THRESHOLD COOLDOWN; do
    value="${!setting}"

    if [[ ! "$value" =~ ^(0|[1-9][0-9]*)$ ]]; then
        echo "[FrankenPHP Watchdog] ${setting} must be an unsigned base-10 integer, got: ${value}" >&2
        exit 1
    fi
done

if [ "$INTERVAL" -eq 0 ] || [ "$STALL_TIMEOUT" -eq 0 ] || [ "$QUEUE_THRESHOLD" -eq 0 ]; then
    echo "[FrankenPHP Watchdog] INTERVAL, STALL_TIMEOUT, and QUEUE_THRESHOLD must be greater than zero" >&2
    exit 1
fi

last_request_count=""
stalled_seconds=0

echo "[FrankenPHP Watchdog] Monitoring every ${INTERVAL}s; restart after ${STALL_TIMEOUT}s without progress while queue >= ${QUEUE_THRESHOLD}"

while true; do
    sleep "$INTERVAL"

    metrics="$(curl --noproxy '*' -fsS --max-time 3 "$METRICS_URL" 2>/dev/null)" || {
        # Supervisor owns process-level recovery. Ignore metrics while FrankenPHP is restarting.
        last_request_count=""
        stalled_seconds=0
        continue
    }

    queue_depth="$(awk '
        /^frankenphp_worker_queue_depth(\{| )/ { total += $NF }
        END { printf "%.0f", total + 0 }
    ' <<< "$metrics")"

    request_count="$(awk '
        /^frankenphp_worker_request_count(\{| )/ { total += $NF }
        END { printf "%.0f", total + 0 }
    ' <<< "$metrics")"

    # No worker metrics means classic mode or workers are still booting.
    if ! grep -q '^frankenphp_worker_request_count' <<< "$metrics"; then
        last_request_count=""
        stalled_seconds=0
        continue
    fi

    if [ "$queue_depth" -ge "$QUEUE_THRESHOLD" ] \
        && [ -n "$last_request_count" ] \
        && [ "$request_count" = "$last_request_count" ]; then
        stalled_seconds=$((stalled_seconds + INTERVAL))
    else
        stalled_seconds=0
    fi

    last_request_count="$request_count"

    if [ "$stalled_seconds" -lt "$STALL_TIMEOUT" ]; then
        continue
    fi

    echo "[FrankenPHP Watchdog] Worker pool stalled for ${stalled_seconds}s with queue depth ${queue_depth}; restarting FrankenPHP"

    if supervisorctl -c /etc/supervisord.conf restart frankenphp; then
        echo "[FrankenPHP Watchdog] FrankenPHP restarted successfully"
    else
        echo "[FrankenPHP Watchdog] FrankenPHP restart failed; Supervisor will continue process recovery" >&2
    fi

    last_request_count=""
    stalled_seconds=0
    sleep "$COOLDOWN"
done
