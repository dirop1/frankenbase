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
| Node.js 20 | Asset compilation |
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

# Harden PHP
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

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `TZ` | `UTC` | Container timezone |
| `HORIZON_ENABLED` | `true` | Set `false` to disable Laravel Horizon |
| `SCHEDULER_ENABLED` | `true` | Set `false` to disable Laravel Scheduler |
| `SSR_ENABLED` | `false` | Set `true` to enable Inertia SSR node server |

```yaml
services:
  app:
    environment:
      HORIZON_ENABLED: "false"      # app doesn't use queues
      SCHEDULER_ENABLED: "true"
      SSR_ENABLED: "true"           # Inertia SSR
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
```

## Real IP Forwarding

Caddy's `trusted_proxies` is configured to trust all upstream IPs for `X-Forwarded-For` extraction. This means Laravel receives the correct client IP when running behind Cloudflare, Nginx Proxy Manager, or any standard proxy.

> **Note:** If you deploy this image directly on the internet without a proxy in front, set `trusted_proxies` to your specific upstream IP range to prevent header spoofing. The default `0.0.0.0/0` is intentional for proxy-behind deployments but should be scoped in direct-exposure scenarios.

## PHP Security Hardening

Run `apply-php-security` in your downstream Dockerfile to apply opinionated PHP ini hardening:

- Dangerous functions disabled (`exec`, `passthru`, `shell_exec`, `system`, `eval`, `pcntl_exec`)
- `expose_php = Off`
- `display_errors = Off`
- Session cookie security (`httponly`, `secure`, `strict_mode`)
- Sane upload and memory limits

> **Note:** `session.cookie_secure = 1` requires HTTPS. This image terminates HTTP on port 80 — TLS must be handled upstream (Cloudflare, reverse proxy, or your orchestrator). If you run without TLS, omit `apply-php-security` or override `session.cookie_secure = 0`.

## License

MIT
