#!/bin/bash
set -e

# Selectively disable supervisor programs via environment variables.
# All programs are enabled by default except SSR.
#
# HORIZON_ENABLED=false    — disable Laravel Horizon (queue worker)
# SCHEDULER_ENABLED=false  — disable Laravel Scheduler
# SSR_ENABLED=true                    — enable Inertia SSR node server
# FRANKENPHP_WATCHDOG_ENABLED=false   — disable stalled-worker recovery

json_unsigned_or_null() {
    if [[ "$1" =~ ^(0|[1-9][0-9]*)$ ]]; then
        printf '%s' "$1"
    else
        printf 'null'
    fi
}

write_watchdog_boot_state() {
    local enabled="$1"
    local state="$2"
    local state_file="/run/frankenbase/watchdog.json"
    local state_tmp="${state_file}.$$"
    local interval="${FRANKENPHP_WATCHDOG_INTERVAL:-10}"
    local stall_timeout="${FRANKENPHP_WATCHDOG_STALL_TIMEOUT:-180}"
    local queue_threshold="${FRANKENPHP_WATCHDOG_QUEUE_THRESHOLD:-1}"
    local cooldown="${FRANKENPHP_WATCHDOG_COOLDOWN:-60}"

    umask 022
    printf '{\n' > "$state_tmp"
    printf '  "schema_version": 1,\n' >> "$state_tmp"
    printf '  "enabled": %s,\n' "$enabled" >> "$state_tmp"
    printf '  "state": "%s",\n' "$state" >> "$state_tmp"
    printf '  "observed_at": "%s",\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" >> "$state_tmp"
    printf '  "queue_depth": null,\n' >> "$state_tmp"
    printf '  "request_count": null,\n' >> "$state_tmp"
    printf '  "stalled_seconds": 0,\n' >> "$state_tmp"
    printf '  "restart_in_seconds": 0,\n' >> "$state_tmp"
    printf '  "interval_seconds": %s,\n' "$(json_unsigned_or_null "$interval")" >> "$state_tmp"
    printf '  "stall_timeout_seconds": %s,\n' "$(json_unsigned_or_null "$stall_timeout")" >> "$state_tmp"
    printf '  "queue_threshold": %s,\n' "$(json_unsigned_or_null "$queue_threshold")" >> "$state_tmp"
    printf '  "cooldown_seconds": %s,\n' "$(json_unsigned_or_null "$cooldown")" >> "$state_tmp"
    printf '  "cooldown_remaining_seconds": 0,\n' >> "$state_tmp"
    printf '  "restart_count": 0,\n' >> "$state_tmp"
    printf '  "last_restart_at": null,\n' >> "$state_tmp"
    printf '  "last_restart_result": null\n' >> "$state_tmp"
    printf '}\n' >> "$state_tmp"
    chmod 0644 "$state_tmp"
    mv -f "$state_tmp" "$state_file"
}

if [ "${HORIZON_ENABLED:-true}" != "true" ]; then
    echo "[entrypoint] Horizon disabled"
    rm -f /etc/supervisor.d/horizon.conf
fi

if [ "${SCHEDULER_ENABLED:-true}" != "true" ]; then
    echo "[entrypoint] Scheduler disabled"
    rm -f /etc/supervisor.d/scheduler.conf
fi

if [ "${FRANKENPHP_WATCHDOG_ENABLED:-true}" != "true" ]; then
    echo "[entrypoint] FrankenPHP watchdog disabled"
    rm -f /etc/supervisor.d/frankenphp-watchdog.conf
    write_watchdog_boot_state false "disabled"
else
    write_watchdog_boot_state true "starting"
fi

if [ "${SSR_ENABLED:-false}" != "true" ]; then
    rm -f /etc/supervisor.d/ssr.conf
else
    echo "[entrypoint] SSR enabled"
fi

exec /usr/bin/supervisord -c /etc/supervisord.conf -n
