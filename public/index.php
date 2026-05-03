<?php
// Fallback page — replaced when your Laravel app is copied to /app
http_response_code(200);
header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>frankenbase</title>
    <style>
        body { font-family: sans-serif; max-width: 600px; margin: 80px auto; padding: 0 20px; color: #333; }
        h1 { font-size: 1.5rem; margin-bottom: 4px; }
        p  { color: #666; margin: 4px 0; }
        table { border-collapse: collapse; margin-top: 24px; width: 100%; }
        td { padding: 6px 12px; border: 1px solid #e5e5e5; font-size: .875rem; }
        td:first-child { color: #888; width: 140px; }
    </style>
</head>
<body>
    <h1>frankenbase</h1>
    <p>Container is running. Deploy your Laravel app to replace this page.</p>
    <table>
        <tr><td>PHP</td><td><?= PHP_VERSION ?></td></tr>
        <tr><td>FrankenPHP</td><td><?= $_SERVER['SERVER_SOFTWARE'] ?? 'FrankenPHP' ?></td></tr>
        <tr><td>Worker mode</td><td><?= isset($_SERVER['FRANKENPHP_WORKER']) ? 'active' : 'inactive' ?></td></tr>
        <tr><td>TZ</td><td><?= date_default_timezone_get() ?></td></tr>
    </table>
</body>
</html>
