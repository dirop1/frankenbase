#!/bin/bash
set -e

echo "Applying PHP security hardening..."

UPLOAD_MAX_FILESIZE="${UPLOAD_MAX_FILESIZE:-64M}"
POST_MAX_SIZE="${POST_MAX_SIZE:-65M}"
MAX_EXECUTION_TIME="${MAX_EXECUTION_TIME:-30}"
MAX_INPUT_TIME="${MAX_INPUT_TIME:-60}"
MEMORY_LIMIT="${MEMORY_LIMIT:-256M}"

INI=/usr/local/etc/php/conf.d/security.ini

# Disable dangerous functions
echo "disable_functions = exec,passthru,shell_exec,system,eval,pcntl_exec" >> "$INI"

# Security settings
echo "expose_php = Off"      >> "$INI"
echo "display_errors = Off"  >> "$INI"
echo "log_errors = On"       >> "$INI"

# URL handling
echo "allow_url_fopen = On"    >> "$INI"
echo "allow_url_include = Off" >> "$INI"

# File upload limits
echo "file_uploads = On"                          >> "$INI"
echo "upload_max_filesize = $UPLOAD_MAX_FILESIZE" >> "$INI"
echo "post_max_size = $POST_MAX_SIZE"             >> "$INI"

# Execution limits
echo "max_execution_time = $MAX_EXECUTION_TIME" >> "$INI"
echo "max_input_time = $MAX_INPUT_TIME"         >> "$INI"
echo "memory_limit = $MEMORY_LIMIT"             >> "$INI"

# Session security
echo "session.cookie_httponly = 1"  >> "$INI"
echo "session.cookie_secure = 1"    >> "$INI"
echo "session.use_strict_mode = 1"  >> "$INI"

echo "PHP security hardening applied (upload=${UPLOAD_MAX_FILESIZE}, post=${POST_MAX_SIZE}, memory=${MEMORY_LIMIT})"
