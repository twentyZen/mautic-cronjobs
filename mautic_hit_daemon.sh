#!/bin/bash

# MIT License
#
# Copyright (c) 2025 twentyZEN GmbH - twentyzen.com

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Version 3 - Hit/tracking daemon worker

script_dir="$(cd "$(dirname "$0")" && pwd)"
load_env_file() {
    local env_file="$1"
    if [ ! -f "$env_file" ]; then
        echo "Required environment file '$env_file' was not found." >&2
        exit 1
    fi

    set -o allexport
    source "$env_file"
    set +o allexport
}

load_env_file "$script_dir/.env.common"
load_env_file "$script_dir/.env.hit-daemon"

cd "$script_dir" || exit 1

phpinterpreter="$PHP_INTERPRETER"
pathtoconsole="$PATH_TO_CONSOLE"
daemon_log_dir="$HIT_DAEMON_LOG_DIR"
max_daemon_logs="$MAX_HIT_DAEMON_LOGS"
daemon_lockfile="$HIT_DAEMON_LOCKFILE"
daemon_memory_limit="$HIT_DAEMON_MEMORY_LIMIT"
daemon_time_limit="${HIT_DAEMON_TIME_LIMIT:-}"
MYSELF_PID=$$

require_env_var() {
    local name="$1"
    if [ -z "${!name:-}" ]; then
        echo "Required environment variable '$name' is not set." >&2
        exit 1
    fi
}

require_env_var "PHP_INTERPRETER"
require_env_var "PATH_TO_CONSOLE"
require_env_var "HIT_DAEMON_LOCKFILE"
require_env_var "HIT_DAEMON_LOG_DIR"
require_env_var "HIT_DAEMON_MEMORY_LIMIT"
require_env_var "MAX_HIT_DAEMON_LOGS"

read -r -a php_cmd <<< "$phpinterpreter"
if [ ${#php_cmd[@]} -eq 0 ]; then
    echo "PHP_INTERPRETER does not contain an executable command." >&2
    exit 1
fi

mkdir -p "$daemon_log_dir"
mkdir -p "$(dirname "$daemon_lockfile")"

daemon_log_file="$daemon_log_dir/worker_$(date +'%Y%m%d_%H%M%S').log"
worker_status_file="$daemon_log_dir/worker.status"

exec 200>"$daemon_lockfile"
if ! flock -n 200; then
    existing_pid=$(cat "$daemon_lockfile" 2>/dev/null)
    echo "Hit daemon worker is already running with PID $existing_pid." >&2
    exit 1
fi
echo "$MYSELF_PID" >&200
cleanup() {
    flock -u 200
}
trap cleanup EXIT

limit_log_files() {
    local dir="$1"
    local max="$2"
    [ "$max" -ge 0 ] 2>/dev/null || return 0

    local files=()
    local to_remove=()
    shopt -s nullglob
    files=("$dir"/*.log)
    shopt -u nullglob

    [ ${#files[@]} -le "$max" ] && return 0

    mapfile -t files < <(printf '%s\0' "${files[@]}" | xargs -0 ls -1t -- 2>/dev/null)
    to_remove=("${files[@]:$max}")
    [ ${#to_remove[@]} -gt 0 ] && rm -f -- "${to_remove[@]}"
}

worker_cmd_parts=(
    "messenger:consume"
    "hit"
    "--memory-limit=$daemon_memory_limit"
)

if [ -n "$daemon_time_limit" ]; then
    worker_cmd_parts+=("--time-limit=$daemon_time_limit")
fi

echo "Starting hit/tracking queue worker: ${worker_cmd_parts[*]}" | tee -a "$daemon_log_file"
printf 'started_at=%s\ncommand=%s\nmemory_limit=%s\ntime_limit=%s\n' \
    "$(date -Iseconds)" "${worker_cmd_parts[*]}" "$daemon_memory_limit" "${daemon_time_limit:-none}" > "$worker_status_file"

"${php_cmd[@]}" "$pathtoconsole" "${worker_cmd_parts[@]}" 2>&1 | tee -a "$daemon_log_file"
worker_exit_code=${PIPESTATUS[0]}

printf 'stopped_at=%s\nexit_code=%s\n' "$(date -Iseconds)" "$worker_exit_code" >> "$worker_status_file"
limit_log_files "$daemon_log_dir" "$max_daemon_logs"

exit "$worker_exit_code"
