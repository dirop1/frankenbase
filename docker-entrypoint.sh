#!/bin/bash
set -e

# Selectively disable supervisor programs via environment variables.
# All programs are enabled by default except SSR.
#
# HORIZON_ENABLED=false    — disable Laravel Horizon (queue worker)
# SCHEDULER_ENABLED=false  — disable Laravel Scheduler
# SSR_ENABLED=true                    — enable Inertia SSR node server
# FRANKENPHP_WATCHDOG_ENABLED=false   — disable stalled-worker recovery

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
fi

if [ "${SSR_ENABLED:-false}" != "true" ]; then
    rm -f /etc/supervisor.d/ssr.conf
else
    echo "[entrypoint] SSR enabled"
fi

exec /usr/bin/supervisord -c /etc/supervisord.conf -n
