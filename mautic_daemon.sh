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

# Version 3 - Generic rate-limited daemon worker

script_dir="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$script_dir/.env" ]; then
    set -o allexport
    source "$script_dir/.env"
    set +o allexport
fi

cd "$script_dir" || exit 1

phpinterpreter="$PHP_INTERPRETER"
pathtoconsole="$PATH_TO_CONSOLE"
daemon_log_dir="${DAEMON_LOG_DIR:-$script_dir/logs}"
max_daemon_logs="${MAX_DAEMON_LOGS:-10}"
daemon_lockfile="${DAEMON_LOCKFILE:-$script_dir/daemon-worker.lock}"
daemon_emails_per_batch="$DAEMON_EMAILS_PER_BATCH"
daemon_queue_time_limit="$DAEMON_QUEUE_TIME_LIMIT"
daemon_queue_delay="$DAEMON_QUEUE_DELAY"
daemon_memory_limit="${DAEMON_MEMORY_LIMIT:-512M}"
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
require_env_var "DAEMON_EMAILS_PER_BATCH"
require_env_var "DAEMON_QUEUE_TIME_LIMIT"
require_env_var "DAEMON_QUEUE_DELAY"

read -r -a php_cmd <<< "$phpinterpreter"
if [ ${#php_cmd[@]} -eq 0 ]; then
    echo "PHP_INTERPRETER does not contain an executable command." >&2
    exit 1
fi

mkdir -p "$daemon_log_dir"

daemon_log_file="$daemon_log_dir/worker_$(date +'%Y%m%d_%H%M%S').log"
worker_status_file="$daemon_log_dir/worker.status"

# Lock mechanism: prevent multiple generic daemon workers using the same .env
exec 200>"$daemon_lockfile"
if ! flock -n 200; then
    existing_pid=$(cat "$daemon_lockfile" 2>/dev/null)
    echo "Generic daemon worker is already running with PID $existing_pid." >&2
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

printf 'started_at=%s\n' "$(date -Iseconds)" > "$worker_status_file"
printf 'emails_per_batch=%s\ntime_limit=%s\ndelay=%s\nmemory_limit=%s\n' \
    "$daemon_emails_per_batch" "$daemon_queue_time_limit" "$daemon_queue_delay" "$daemon_memory_limit" >> "$worker_status_file"

worker_cmd_parts=(
    "messenger:consume"
    "email"
    "--limit=$daemon_emails_per_batch"
    "--time-limit=$daemon_queue_time_limit"
    "--memory-limit=$daemon_memory_limit"
)

echo "Starting Mautic queue worker: ${worker_cmd_parts[*]}" | tee -a "$daemon_log_file"

cycle=0
while true; do
    cycle=$((cycle+1))
    echo "Worker cycle $cycle started at $(date -Iseconds)" | tee -a "$daemon_log_file"

    "${php_cmd[@]}" "$pathtoconsole" "${worker_cmd_parts[@]}" 2>&1 | tee -a "$daemon_log_file"
    worker_exit_code=${PIPESTATUS[0]}

    printf 'last_cycle=%s\nlast_cycle_stopped_at=%s\nlast_exit_code=%s\n' \
        "$cycle" "$(date -Iseconds)" "$worker_exit_code" > "$worker_status_file"
    printf 'emails_per_batch=%s\ntime_limit=%s\ndelay=%s\nmemory_limit=%s\n' \
        "$daemon_emails_per_batch" "$daemon_queue_time_limit" "$daemon_queue_delay" "$daemon_memory_limit" >> "$worker_status_file"

    if [ "$worker_exit_code" -ne 0 ]; then
        echo "Worker cycle $cycle failed with exit code $worker_exit_code. Exiting for service manager restart." | tee -a "$daemon_log_file"
        limit_log_files "$daemon_log_dir" "$max_daemon_logs"
        exit "$worker_exit_code"
    fi

    echo "Worker cycle $cycle finished. Sleeping ${daemon_queue_delay}s before next cycle." | tee -a "$daemon_log_file"
    limit_log_files "$daemon_log_dir" "$max_daemon_logs"
    sleep "$daemon_queue_delay"
done
