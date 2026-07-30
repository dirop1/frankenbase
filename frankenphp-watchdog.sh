#!/bin/bash
# Restart a stalled FrankenPHP worker pool and publish read-only status for local tooling.

set -uo pipefail

INTERVAL="${FRANKENPHP_WATCHDOG_INTERVAL:-10}"
STALL_TIMEOUT="${FRANKENPHP_WATCHDOG_STALL_TIMEOUT:-180}"
QUEUE_THRESHOLD="${FRANKENPHP_WATCHDOG_QUEUE_THRESHOLD:-1}"
COOLDOWN="${FRANKENPHP_WATCHDOG_COOLDOWN:-60}"
METRICS_URL="http://127.0.0.1:2019/metrics"
STATE_FILE="/run/frankenbase/watchdog.json"
STATE_TMP="${STATE_FILE}.$$"

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
restart_count=0
last_restart_at=""
last_restart_result=""
cooldown_remaining_seconds=0

cleanup() {
    rm -f "$STATE_TMP"
}
trap cleanup EXIT

json_string_or_null() {
    if [ -n "$1" ]; then
        printf '"%s"' "$1"
    else
        printf 'null'
    fi
}

json_number_or_null() {
    if [ -n "$1" ]; then
        printf '%s' "$1"
    else
        printf 'null'
    fi
}

write_state() {
    local state="$1"
    local queue_depth="${2:-}"
    local request_count="${3:-}"
    local restart_in_seconds=0

    if [ "$state" = "stalled" ] && [ "$stalled_seconds" -lt "$STALL_TIMEOUT" ]; then
        restart_in_seconds=$((STALL_TIMEOUT - stalled_seconds))
    fi

    umask 022
    printf '{\n' > "$STATE_TMP"
    printf '  "schema_version": 1,\n' >> "$STATE_TMP"
    printf '  "enabled": true,\n' >> "$STATE_TMP"
    printf '  "state": "%s",\n' "$state" >> "$STATE_TMP"
    printf '  "observed_at": "%s",\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" >> "$STATE_TMP"
    printf '  "queue_depth": %s,\n' "$(json_number_or_null "$queue_depth")" >> "$STATE_TMP"
    printf '  "request_count": %s,\n' "$(json_number_or_null "$request_count")" >> "$STATE_TMP"
    printf '  "stalled_seconds": %s,\n' "$stalled_seconds" >> "$STATE_TMP"
    printf '  "restart_in_seconds": %s,\n' "$restart_in_seconds" >> "$STATE_TMP"
    printf '  "interval_seconds": %s,\n' "$INTERVAL" >> "$STATE_TMP"
    printf '  "stall_timeout_seconds": %s,\n' "$STALL_TIMEOUT" >> "$STATE_TMP"
    printf '  "queue_threshold": %s,\n' "$QUEUE_THRESHOLD" >> "$STATE_TMP"
    printf '  "cooldown_seconds": %s,\n' "$COOLDOWN" >> "$STATE_TMP"
    printf '  "cooldown_remaining_seconds": %s,\n' "$cooldown_remaining_seconds" >> "$STATE_TMP"
    printf '  "restart_count": %s,\n' "$restart_count" >> "$STATE_TMP"
    printf '  "last_restart_at": %s,\n' "$(json_string_or_null "$last_restart_at")" >> "$STATE_TMP"
    printf '  "last_restart_result": %s\n' "$(json_string_or_null "$last_restart_result")" >> "$STATE_TMP"
    printf '}\n' >> "$STATE_TMP"
    chmod 0644 "$STATE_TMP"
    mv -f "$STATE_TMP" "$STATE_FILE"
}

write_state "starting"
echo "[FrankenPHP Watchdog] Monitoring every ${INTERVAL}s; restart after ${STALL_TIMEOUT}s without progress while queue >= ${QUEUE_THRESHOLD}"

while true; do
    sleep "$INTERVAL"

    metrics="$(curl --noproxy '*' -fsS --max-time 3 "$METRICS_URL" 2>/dev/null)" || {
        # Supervisor owns process-level recovery. Report unavailability while FrankenPHP restarts.
        last_request_count=""
        stalled_seconds=0
        write_state "metrics_unavailable"
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

    # Request counters appear only after the first completion. Total workers identify worker mode.
    if ! grep -q '^frankenphp_total_workers' <<< "$metrics"; then
        last_request_count=""
        stalled_seconds=0
        write_state "inactive"
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
        if [ "$stalled_seconds" -gt 0 ]; then
            write_state "stalled" "$queue_depth" "$request_count"
        else
            write_state "healthy" "$queue_depth" "$request_count"
        fi
        continue
    fi

    last_restart_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    last_restart_result=""
    restart_count=$((restart_count + 1))
    write_state "restarting" "$queue_depth" "$request_count"
    echo "[FrankenPHP Watchdog] Worker pool stalled for ${stalled_seconds}s with queue depth ${queue_depth}; restarting FrankenPHP"

    supervisorctl -c /etc/supervisord.conf restart frankenphp &
    restart_pid=$!
    while kill -0 "$restart_pid" 2>/dev/null; do
        sleep "$INTERVAL"
        write_state "restarting" "$queue_depth" "$request_count"
    done

    if wait "$restart_pid"; then
        last_restart_result="success"
        echo "[FrankenPHP Watchdog] FrankenPHP restarted successfully"
    else
        last_restart_result="failed"
        echo "[FrankenPHP Watchdog] FrankenPHP restart failed; Supervisor will continue process recovery" >&2
    fi

    last_request_count=""
    stalled_seconds=0
    cooldown_remaining_seconds="$COOLDOWN"
    write_state "cooldown"

    while [ "$cooldown_remaining_seconds" -gt 0 ]; do
        sleep_seconds="$INTERVAL"
        if [ "$cooldown_remaining_seconds" -lt "$sleep_seconds" ]; then
            sleep_seconds="$cooldown_remaining_seconds"
        fi

        sleep "$sleep_seconds"
        cooldown_remaining_seconds=$((cooldown_remaining_seconds - sleep_seconds))
        write_state "cooldown"
    done
done
