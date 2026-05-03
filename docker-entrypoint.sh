#!/bin/bash
set -e

# Selectively disable supervisor programs via environment variables.
# All programs are enabled by default except SSR.
#
# HORIZON_ENABLED=false    — disable Laravel Horizon (queue worker)
# SCHEDULER_ENABLED=false  — disable Laravel Scheduler
# SSR_ENABLED=true         — enable Inertia SSR node server

if [ "${HORIZON_ENABLED:-true}" != "true" ]; then
    echo "[entrypoint] Horizon disabled"
    rm -f /etc/supervisor.d/horizon.conf
fi

if [ "${SCHEDULER_ENABLED:-true}" != "true" ]; then
    echo "[entrypoint] Scheduler disabled"
    rm -f /etc/supervisor.d/scheduler.conf
fi

if [ "${SSR_ENABLED:-false}" != "true" ]; then
    rm -f /etc/supervisor.d/ssr.conf
else
    echo "[entrypoint] SSR enabled"
fi

exec /usr/bin/supervisord -c /etc/supervisord.conf -n
