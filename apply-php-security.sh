#!/bin/bash
set -e

echo "Applying PHP security hardening..."

# PHP Security Hardening
# Disable dangerous functions
echo "disable_functions = exec,passthru,shell_exec,system,eval,pcntl_exec" >> /usr/local/etc/php/conf.d/security.ini

# Security settings
echo "expose_php = Off" >> /usr/local/etc/php/conf.d/security.ini
echo "display_errors = Off" >> /usr/local/etc/php/conf.d/security.ini
echo "log_errors = On" >> /usr/local/etc/php/conf.d/security.ini

# URL handling
echo "allow_url_fopen = On" >> /usr/local/etc/php/conf.d/security.ini
echo "allow_url_include = Off" >> /usr/local/etc/php/conf.d/security.ini

# File upload limits
echo "file_uploads = On" >> /usr/local/etc/php/conf.d/security.ini
echo "upload_max_filesize = 2M" >> /usr/local/etc/php/conf.d/security.ini
echo "post_max_size = 3M" >> /usr/local/etc/php/conf.d/security.ini

# Execution limits
echo "max_execution_time = 30" >> /usr/local/etc/php/conf.d/security.ini
echo "max_input_time = 60" >> /usr/local/etc/php/conf.d/security.ini
echo "memory_limit = 256M" >> /usr/local/etc/php/conf.d/security.ini

# Session security
echo "session.cookie_httponly = 1" >> /usr/local/etc/php/conf.d/security.ini
echo "session.cookie_secure = 1" >> /usr/local/etc/php/conf.d/security.ini
echo "session.use_strict_mode = 1" >> /usr/local/etc/php/conf.d/security.ini

echo "PHP security hardening applied successfully!"
