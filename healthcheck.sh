#!/bin/bash
# Container health check — used by Docker HEALTHCHECK and orchestrator probes.
# Verifies HTTP is responding and all enabled supervisor programs are RUNNING.

set -e

# 1. HTTP probe
curl -sf http://localhost/healthz > /dev/null || {
    echo "healthcheck: /healthz did not respond"
    exit 1
}

# 2. Supervisord process check — fail if any program is in FATAL/EXITED/BACKOFF state
if supervisorctl -c /etc/supervisord.conf status 2>/dev/null | grep -qE "FATAL|EXITED|BACKOFF"; then
    echo "healthcheck: one or more supervisor programs are not running:"
    supervisorctl -c /etc/supervisord.conf status
    exit 1
fi

exit 0
