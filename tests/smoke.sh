#!/bin/bash
# Native-architecture runtime checks. No published ports, external network or app dependencies.
set -Eeuo pipefail

IMAGE="${1:?Usage: bash tests/smoke.sh IMAGE EXPECTED_FRANKENBASE_VERSION [EXPECTED_PHP_VERSION]}"
EXPECTED_VERSION="${2:?Expected Frankenbase version is required}"
EXPECTED_PHP="${3:-8.5.12}"
FIXTURES="$(mktemp -d)"
CONTAINER=""

cleanup() {
    local result=$?
    if [ -n "$CONTAINER" ]; then
        if [ "$result" -ne 0 ]; then
            docker logs "$CONTAINER" >&2 || true
        fi
        docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    fi
    rm -rf "$FIXTURES"
    exit "$result"
}
trap cleanup EXIT
chmod 755 "$FIXTURES"

docker run --rm --network none --entrypoint php "$IMAGE" -r '
    if (PHP_VERSION !== $argv[1] || !PHP_ZTS) {
        fwrite(STDERR, "Unexpected PHP version or missing ZTS\n"); exit(1);
    }
    foreach (["bcmath", "intl", "mbstring", "pdo", "pdo_mysql", "pdo_pgsql", "pgsql", "xml", "pcntl", "zip", "exif", "sockets", "gd", "redis"] as $extension) {
        if (!extension_loaded($extension)) {
            fwrite(STDERR, "Missing extension: $extension\n"); exit(1);
        }
    }
    if (trim(file_get_contents("/etc/frankenbase/version")) !== $argv[2]) {
        fwrite(STDERR, "Unexpected Frankenbase version stamp\n"); exit(1);
    }
    echo "CLI, ZTS, extensions and version stamp OK\n";
' "$EXPECTED_PHP" "$EXPECTED_VERSION"

for MODE in classic worker; do
    PUBLIC="$FIXTURES/$MODE"
    mkdir "$PUBLIC"
    cat > "$PUBLIC/index.php" <<'PHP'
<?php
header('Content-Type: application/json');
echo json_encode(['php' => PHP_VERSION, 'zts' => PHP_ZTS, 'sapi' => PHP_SAPI, 'uid' => posix_geteuid()]);
PHP
    if [ "$MODE" = worker ]; then
        cat > "$PUBLIC/frankenphp-worker.php" <<'PHP'
<?php
$handler = static function () { require __DIR__ . '/index.php'; };
for ($request = 0; $request < 1000; ++$request) {
    if (!frankenphp_handle_request($handler)) { break; }
}
PHP
    fi
    chmod 755 "$PUBLIC"
    chmod 644 "$PUBLIC/"*.php
    CONTAINER="$(docker run -d --network none \
        -e HORIZON_ENABLED=false -e SCHEDULER_ENABLED=false -e SSR_ENABLED=false \
        -e TRUSTED_PROXIES= -e FRANKENPHP_NUM_THREADS=3 -e FRANKENPHP_WATCHDOG_INTERVAL=2 \
        -v "$PUBLIC:/app/public:ro" "$IMAGE")"

    READY=false
    for _ in {1..40}; do
        if docker exec "$CONTAINER" /usr/local/bin/healthcheck >/dev/null 2>&1; then
            READY=true
            break
        fi
        sleep 1
    done
    [ "$READY" = true ] || { echo "Healthcheck failed ($MODE)" >&2; exit 1; }

    STATUS="$(docker exec "$CONTAINER" supervisorctl -c /etc/supervisord.conf status)"
    grep -q '^frankenphp .*RUNNING' <<< "$STATUS"
    grep -q '^frankenphp-watchdog .*RUNNING' <<< "$STATUS"
    if awk 'NF >= 2 && $2 != "RUNNING" { failed = 1 } END { exit !failed }' <<< "$STATUS"; then
        echo "Unexpected Supervisor status: $STATUS" >&2
        exit 1
    fi

    # Repeated requests exercise persistent workers as well as regular PHP requests.
    for _ in {1..3}; do
        docker exec "$CONTAINER" curl --noproxy '*' -fsS --max-time 5 http://127.0.0.1/up \
            | docker exec -i "$CONTAINER" php -r '
                $data = json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR);
                if ($data !== ["php" => $argv[1], "zts" => true, "sapi" => "frankenphp", "uid" => 1000]) {
                    fwrite(STDERR, "Unexpected HTTP runtime\n"); exit(1);
                }
            ' "$EXPECTED_PHP"
    done
    docker exec "$CONTAINER" frankenphp validate --config /etc/frankenphp/Caddyfile
    docker exec --user application "$CONTAINER" php -r '
        $state = json_decode(file_get_contents("/run/frankenbase/watchdog.json"), true, 512, JSON_THROW_ON_ERROR);
        if ($state["schema_version"] !== 1 || $state["enabled"] !== true || !in_array($state["state"], ["healthy", "inactive"], true)) { exit(1); }
        if (is_readable("/run/frankenbase/supervisor.sock") || is_writable("/etc/frankenbase/version") || is_writable("/run/frankenbase/watchdog.json")) { exit(1); }
    '
    docker exec "$CONTAINER" php -r '
        $found = false;
        foreach (["/proc/net/tcp", "/proc/net/tcp6"] as $file) {
            foreach (file($file) as $line) {
                $fields = preg_split("/\s+/", trim($line));
                if (count($fields) < 4 || $fields[3] !== "0A" || !str_ends_with($fields[1], ":07E3")) { continue; }
                $found = true;
                if (!in_array(explode(":", $fields[1])[0], ["0100007F", "00000000000000000000000001000000"], true)) { exit(1); }
            }
        }
        if (!$found) { exit(1); }
    '
    docker rm -f "$CONTAINER" >/dev/null
    CONTAINER=""
    echo "$MODE: HTTP $EXPECTED_PHP ZTS, Supervisor, healthcheck and permissions OK"
done
