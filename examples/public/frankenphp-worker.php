<?php
// Minimal FrankenPHP worker — replaced by your Laravel app's worker.
// Laravel Octane publishes the real worker via:
//   php artisan octane:install --server=frankenphp

frankenphp_handle_request(function () {
    require __DIR__ . '/index.php';
});
