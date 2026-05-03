# frankenbase

Production-ready Laravel base image built on [FrankenPHP](https://frankenphp.dev) (Caddy + PHP workers in-process), with Supervisor managing FrankenPHP, Horizon, and the Laravel scheduler.

## Versions

| Component | Version |
|---|---|
| FrankenPHP | 1.12.2 |
| PHP | 8.5.5 |
| Caddy | 2.11.2 |
| Node.js | 20.x |

## What's included

| Component | Purpose |
|---|---|
| FrankenPHP | HTTP server + PHP worker runtime |
| Composer | Dependency management |
| Node.js 20 | Asset compilation + Inertia SSR |
| Supervisor | Process management |
| Laravel Horizon | Queue worker |
| Laravel Scheduler | `schedule:work` via Supervisor |
| PHP security hardening | `apply-php-security` script |

## PHP Extensions

`bcmath` `intl` `mbstring` `pdo` `pdo_mysql` `pdo_pgsql` `pgsql` `xml` `pcntl` `zip` `exif` `sockets` `gd` `redis`

## Quick Start

```dockerfile
FROM ghcr.io/dirop1/frankenbase:latest

# Copy your Laravel app
COPY . /app

# Install and optimize
RUN composer install --no-dev --optimize-autoloader
RUN npm install && npm run build
RUN php artisan config:cache && php artisan route:cache && php artisan view:cache

# Harden PHP (respects env vars — see apply-php-security section below)
RUN apply-php-security

# Set permissions
RUN chown -R application:application /app && \
    chmod -R 755 /app && \
    chmod -R 775 /app/storage /app/bootstrap/cache
```

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

### Build-time (`apply-php-security`)

These are read when `RUN apply-php-security` runs in your downstream Dockerfile. Set them as `ENV` before that step.

| Variable | Default | Description |
|---|---|---|
| `UPLOAD_MAX_FILESIZE` | `64M` | PHP `upload_max_filesize` |
| `POST_MAX_SIZE` | `65M` | PHP `post_max_size` (keep slightly above upload) |
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

## Ports

| Port | Service |
|---|---|
| 80 | FrankenPHP / Caddy |
| 2019 | Caddy admin API (localhost only) |

## Architecture

```
Client → FrankenPHP/Caddy :80 → PHP Workers → Laravel
                                      ↓
                              Horizon (queues)
                              Scheduler (cron)
                              SSR server (optional)
```

## Real IP Forwarding

`TRUSTED_PROXIES` controls which upstream IPs are trusted for `X-Forwarded-For` extraction. The default (`0.0.0.0/0`) works out of the box behind Cloudflare, Nginx Proxy Manager, or any reverse proxy.

> **Warning:** If your container is directly internet-facing (no proxy in front), set `TRUSTED_PROXIES` to your actual upstream CIDRs. Trusting all IPs in that scenario allows clients to spoof their IP via `X-Forwarded-For`.

## PHP Security Hardening

Run `apply-php-security` in your downstream Dockerfile to apply opinionated PHP ini hardening:

- Dangerous functions disabled (`exec`, `passthru`, `shell_exec`, `system`, `eval`, `pcntl_exec`)
- `expose_php = Off`
- `display_errors = Off`
- Session cookie security (`httponly`, `secure`, `strict_mode`)
- Configurable upload and memory limits (see env vars above)

> **Note:** `session.cookie_secure = 1` requires HTTPS. This image exposes port 80 — TLS must be handled upstream (Cloudflare, reverse proxy, or your orchestrator). If running without TLS, override with `session.cookie_secure = 0` in your own ini file.

## License

MIT
