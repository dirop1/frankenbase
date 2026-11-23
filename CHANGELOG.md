# Changelog

## 0.3.1 — 2026-11-23

- Security: the generated Caddyfile now answers 404 for any path segment that starts with a dot (`.env`, `.htaccess`, `.git/`, `.dir/x.php`, `.DS_Store`), including `%2e`-encoded forms. Before, such files under `public/` were served and PHP inside hidden directories was executed. `/.well-known/` stays reachable.
- Smoke test covers the hidden-path matrix in classic and worker modes.

## 0.3.0 — 2026-10-21

- Fix php2shell (CVE-2026-109618 / CVE-2026-109619) using official FrankenPHP 1.13.1 with PHP 8.5.12 ZTS.
- Add PHP-qualified image tags (`0.3.0-php8.5.12`) and native amd64/arm64 runtime checks before publishing release tags.
