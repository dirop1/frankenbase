# frankenbase

Production-ready Laravel base image built on [FrankenPHP](https://frankenphp.dev) (Caddy + PHP workers in-process), with Supervisor managing FrankenPHP, Horizon, and the Laravel scheduler.

## Versions

| Component | Version |
|---|---|
| FrankenPHP | 1.12.2 |
| PHP | 8.5.6 |
| Caddy | 2.11.2 |
| Node.js | 20.x |

## What's included

| Component | Purpose |
|---|---|
| FrankenPHP | HTTP server + PHP worker runtime |
| Composer | Dependency management |
| Node.js 20 | Asset compilation + Inertia SSR |
| Supervisor | Process management and stalled-worker recovery |
| Laravel Horizon | Queue worker |
| Laravel Scheduler | `schedule:work` via Supervisor |
| PHP security hardening | `apply-php-security` script |

## PHP Extensions

`bcmath` `intl` `mbstring` `pdo` `pdo_mysql` `pdo_pgsql` `pgsql` `xml` `pcntl` `zip` `exif` `sockets` `gd` `redis`

## Quick Start

```dockerfile
FROM ghcr.io/dirop1/frankenbase:0.3.0

# Set before apply-php-security — override defaults as needed
ENV UPLOAD_MAX_FILESIZE=12M \
    POST_MAX_SIZE=13M \
    MEMORY_LIMIT=256M

COPY . /app

RUN composer install --no-dev --optimize-autoloader \
    && npm install \
    && npm run build \
    && php artisan config:cache \
    && php artisan route:cache \
    && php artisan view:cache \
    && apply-php-security \
    && chown -R application:application /app \
    && chmod -R 755 /app \
    && chmod -R 775 /app/storage /app/bootstrap/cache
```

> **Worker mode:** FrankenPHP can keep your app in memory between requests (Laravel Octane). To enable it, publish the worker file: `php artisan octane:install --server=frankenphp`. The image detects `public/frankenphp-worker.php` at startup and activates worker mode automatically.

```yaml
services:
  app:
    build: .
    ports:
      - "80:80"
    environment:
      APP_ENV: production
      APP_KEY: base64:...
```

## .dockerignore

Always add a `.dockerignore` to your app. Without it, `COPY . /app` silently includes `node_modules`, `vendor`, `.git`, and test files — bloating your image layers.

```
.git
node_modules
vendor
tests
*.log
.env
.env.*
storage/logs
storage/framework/cache
```

## Environment Variables

### Runtime

| Variable | Default | Description |
|---|---|---|
| `TZ` | `UTC` | Container timezone |
| `HORIZON_ENABLED` | `true` | Set `false` to disable Laravel Horizon |
| `SCHEDULER_ENABLED` | `true` | Set `false` to disable Laravel Scheduler |
| `SSR_ENABLED` | `false` | Set `true` to enable Inertia SSR node server |
| `TRUSTED_PROXIES` | `0.0.0.0/0 ::/0` | Space-separated upstream proxy CIDRs |
| `FRANKENPHP_MAX_WAIT_TIME` | `10s` | Maximum time a request may wait for a free PHP thread |
| `REQUEST_MAX_EXECUTION_TIME` | `30` | Maximum worker request execution time in seconds (`0` disables it) |
| `MAX_REQUESTS` | `1000` | Positive request count handled before an application worker is recycled |
| `FRANKENPHP_NUM_THREADS` | upstream default | Total initial PHP threads; unset uses FrankenPHP's CPU-based default |
| `FRANKENPHP_MAX_THREADS` | upstream default | Maximum PHP threads; accepts an integer or `auto` |
| `FRANKENPHP_WORKER_COUNT` | upstream default | Application worker count; setting only this automatically reserves one extra regular PHP thread |
| `FRANKENPHP_WATCHDOG_ENABLED` | `true` | Restart a stalled worker pool after the configured threshold |
| `FRANKENPHP_WATCHDOG_INTERVAL` | `10` | Metrics sampling interval in seconds |
| `FRANKENPHP_WATCHDOG_STALL_TIMEOUT` | `180` | Seconds with queued requests and no completed requests before restart |
| `FRANKENPHP_WATCHDOG_QUEUE_THRESHOLD` | `1` | Minimum queued requests required to consider the pool stalled |
| `FRANKENPHP_WATCHDOG_COOLDOWN` | `60` | Seconds to wait after an automatic restart |
| `APP_HEALTHCHECK_PATH` | `/up` | Application path probed by the container healthcheck; 4xx responses are accepted for older apps |
| `APP_HEALTHCHECK_TIMEOUT` | `3` | Application probe timeout in seconds (1–10) |

### Build-time (`apply-php-security`)

These are read when `RUN apply-php-security` runs in your downstream Dockerfile. Set them as `ENV` before that step.

| Variable | Default | Description |
|---|---|---|
| `UPLOAD_MAX_FILESIZE` | `12M` | PHP `upload_max_filesize` |
| `POST_MAX_SIZE` | `13M` | PHP `post_max_size` (keep slightly above upload) |
| `MAX_EXECUTION_TIME` | `30` | PHP `max_execution_time` in seconds |
| `MAX_INPUT_TIME` | `60` | PHP `max_input_time` in seconds |
| `MEMORY_LIMIT` | `256M` | PHP `memory_limit` |

```dockerfile
ENV UPLOAD_MAX_FILESIZE=128M \
    POST_MAX_SIZE=129M \
    MEMORY_LIMIT=512M

RUN apply-php-security
```

```yaml
services:
  app:
    environment:
      HORIZON_ENABLED: "false"
      SSR_ENABLED: "true"
      TRUSTED_PROXIES: "173.245.48.0/20 103.21.244.0/22"   # Cloudflare IPv4 only
```

## Health Check

The image ships with a `/healthz` liveness endpoint handled directly by Caddy. The container healthcheck also requests `APP_HEALTHCHECK_PATH` through PHP and verifies that every enabled Supervisor program is running.

FrankenPHP metrics are exposed only through the localhost Caddy admin endpoint. A Supervisor-managed watchdog samples worker queue depth and completed-request count. If requests remain queued with no progress for 180 seconds, it restarts only FrankenPHP while leaving Horizon, the scheduler, and SSR running. Busy workers without a queue never trigger an automatic restart. Disable this with `FRANKENPHP_WATCHDOG_ENABLED=false` when recovery is managed externally.

### Local runtime status

Local dashboards and diagnostics can read two stable, read-only files without access to the root-owned Supervisor socket:

- `/etc/frankenbase/version` contains the image version (`dev` for builds that do not supply `FRANKENBASE_VERSION`).
- `/run/frankenbase/watchdog.json` contains watchdog schema version 1 and is updated atomically.

The watchdog state reports whether recovery is enabled, its current state, observation time, queue depth, completed-request count, stall duration, restart or cooldown countdown, configured thresholds, restart count, and the last restart result.

```json
{
  "schema_version": 1,
  "enabled": true,
  "state": "healthy",
  "observed_at": "2026-01-01T12:00:00Z",
  "queue_depth": 0,
  "request_count": 1200,
  "stalled_seconds": 0,
  "restart_in_seconds": 0,
  "interval_seconds": 10,
  "stall_timeout_seconds": 180,
  "queue_threshold": 1,
  "cooldown_seconds": 60,
  "cooldown_remaining_seconds": 0,
  "restart_count": 0,
  "last_restart_at": null,
  "last_restart_result": null
}
```

Possible states are `starting`, `healthy`, `stalled`, `restarting`, `cooldown`, `metrics_unavailable`, `inactive`, and `disabled`. Except for the static `disabled` state, consumers should treat a status older than twice `interval_seconds` as stale. Restart history is scoped to the watchdog process lifetime, and the runtime-local file resets when the container is recreated.

These files are deliberately read-only to the application user. Do not grant the application access to `/run/frankenbase/supervisor.sock` merely to build a dashboard.

```yaml
services:
  app:
    healthcheck:
      test: ["CMD", "/usr/local/bin/healthcheck"]
      interval: 30s
      timeout: 15s
      retries: 3
      start_period: 30s
```

The `HEALTHCHECK` instruction is already baked into the image, so Docker and orchestrators pick it up automatically without any extra config.

## Quick Setup

Have a Laravel app? Run this from its root directory:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dirop1/frankenbase/main/examples/setup.sh)
```

Or copy `examples/setup.sh` locally and run it. The script detects your app, asks a few questions, and generates a `Dockerfile`, `docker-compose.yml`, and `.dockerignore`.

## Ports

| Port | Service |
|---|---|
| 80 | FrankenPHP / Caddy |
| 2019 | Caddy admin API (localhost only) |

## Architecture

```
Client → FrankenPHP/Caddy :80 → bounded wait queue → PHP Workers → Laravel
                                      ↑                    ↓
                              stall watchdog       Horizon (queues)
                                                   Scheduler (cron)
                                                   SSR server (optional)
```

## Reverse Proxy

**This image is designed to run behind a reverse proxy.** Cloudflare, Nginx Proxy Manager, Traefik, or any proxy that sets standard `X-Forwarded-For` headers will work out of the box.

`TRUSTED_PROXIES` controls which upstream IPs Caddy trusts for real IP extraction. The default (`0.0.0.0/0`) covers all proxies without any config.

> **Warning:** Do not expose this container directly to the internet without a proxy in front. The default `TRUSTED_PROXIES=0.0.0.0/0` in a direct-exposure setup allows any client to spoof their IP via `X-Forwarded-For`. If you must expose directly, set `TRUSTED_PROXIES` to your actual upstream CIDRs or an empty value.

### Laravel also needs to trust proxies

Caddy extracting the real IP is only half the story. Laravel must also be told to trust the proxy, otherwise `request()->ip()`, HTTPS detection, and URL generation will all behave incorrectly.

**Laravel 11+** — in `bootstrap/app.php`:
```php
->withMiddleware(function (Middleware $middleware) {
    $middleware->trustProxies(at: '*');
})
```

**Laravel 10 and below** — in `app/Http/Middleware/TrustProxies.php`:
```php
protected $proxies = '*';
```

## PHP Security Hardening

Run `apply-php-security` in your downstream Dockerfile to apply opinionated PHP ini hardening:

- Dangerous functions disabled (`exec`, `passthru`, `shell_exec`, `system`, `eval`, `pcntl_exec`)
- `expose_php = Off`
- `display_errors = Off`
- Session cookie security (`httponly`, `secure`, `strict_mode`)
- Configurable upload and memory limits (see env vars above)

> **Note:** `session.cookie_secure = 1` requires HTTPS. This image exposes port 80 — TLS must be handled upstream (Cloudflare, reverse proxy, or your orchestrator). If running without TLS, override with `session.cookie_secure = 0` in your own ini file.

## AI Agent Setup

You can ask Claude Code (or any capable coding agent) to wire up frankenbase for your Laravel app. Paste this prompt from your project root:

```
I want to dockerize this Laravel app using the frankenbase base image (ghcr.io/dirop1/frankenbase:latest).

Please do the following:
1. Create a Dockerfile that:
   - Extends ghcr.io/dirop1/frankenbase:latest
   - Sets ENV for UPLOAD_MAX_FILESIZE, POST_MAX_SIZE, MEMORY_LIMIT before calling apply-php-security
   - Chains all build steps into a single RUN: composer install --no-dev --optimize-autoloader, npm install, npm run build, php artisan config:cache, php artisan route:cache, php artisan view:cache, apply-php-security, chown/chmod permissions
2. Create a docker-compose.yml with app, db (mariadb:11), and redis (redis:7-alpine) services.
   Include HORIZON_ENABLED, SCHEDULER_ENABLED, SSR_ENABLED, TRUSTED_PROXIES env vars.
   Wire the healthcheck to /usr/local/bin/healthcheck.
3. Create a .dockerignore excluding: .git, node_modules, vendor, tests, .env, .env.*, storage/logs, storage/framework/cache, storage/framework/sessions, storage/framework/views.
4. Check if public/frankenphp-worker.php exists. If not, run: php artisan octane:install --server=frankenphp to publish the worker file and enable FrankenPHP worker mode.
5. Ask me: app name, whether I use Inertia SSR, whether I use Horizon, and my desired upload limit.

Reference docs: https://github.com/dirop1/frankenbase
```

## License

MIT
