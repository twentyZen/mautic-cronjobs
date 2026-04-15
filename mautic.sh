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

# Version 2 - 04.02.2025

# Load .env if available, using the script's directory as the base path
script_dir="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$script_dir/.env" ]; then
    set -o allexport
    source "$script_dir/.env"
    set +o allexport
fi

# Set working directory to the script's location
cd "$script_dir" || exit 1

MYSELF_PID=$$

# Environment variables from .env
phpinterpreter="$PHP_INTERPRETER"
pathtoconsole="$PATH_TO_CONSOLE"
lockfile="$LOCKFILE"
log_dir="$LOG_DIR"
max_logs="$MAX_LOGS"
error_log_dir="$ERROR_LOG_DIR"
max_error_logs="$MAX_ERROR_LOGS"
max_loops="$MAX_LOOPS"

require_env_var() {
    local name="$1"
    if [ -z "${!name:-}" ]; then
        echo "Required environment variable '$name' is not set." >&2
        exit 1
    fi
}

require_env_var "PHP_INTERPRETER"
require_env_var "PATH_TO_CONSOLE"
require_env_var "LOCKFILE"
require_env_var "LOG_DIR"
require_env_var "ERROR_LOG_DIR"
require_env_var "MAX_LOGS"
require_env_var "MAX_ERROR_LOGS"
require_env_var "MAX_LOOPS"
require_env_var "COMMAND_ORDER"
require_env_var "COMMAND_QUEUE"

read -r -a php_cmd <<< "$phpinterpreter"
if [ ${#php_cmd[@]} -eq 0 ]; then
    echo "PHP_INTERPRETER does not contain an executable command." >&2
    exit 1
fi

mkdir -p "$log_dir"
mkdir -p "$error_log_dir"

# Lock mechanism: prevent multiple script instances using flock
exec 200>"$lockfile"
if ! flock -n 200; then
    existing_pid=$(cat "$lockfile" 2>/dev/null)
    echo "Script is already running with PID $existing_pid." >&2
    exit 1
fi
echo "$MYSELF_PID" >&200
cleanup() {
    flock -u 200
}
trap cleanup EXIT

log_file="$log_dir/$(date +'%Y%m%d_%H%M%S').log"
error_log_file="$error_log_dir/$(date +'%Y%m%d_%H%M%S')_error.log"


# Limit the number of log files to max_logs
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

# Execute a command and log its output, removing empty lines
execute_command() {
    local cmd="$1"
    echo "Executing: $cmd" | tee -a "$log_file"
    local tmp_output
    local ret
    local cmd_parts=()

    read -r -a cmd_parts <<< "$cmd"
    tmp_output=$(mktemp "${TMPDIR:-/tmp}/mautic-cronjobs.XXXXXX") || exit 1

    "${php_cmd[@]}" "$pathtoconsole" "${cmd_parts[@]}" 2>&1 \
        | sed '/^$/d' \
        | tee -a "$log_file" > "$tmp_output"
    ret=${PIPESTATUS[0]}

    if [ "$ret" -ne 0 ]; then
        cat "$tmp_output" >> "$error_log_file"
    fi

    rm -f "$tmp_output"
    return $ret
}

count_queue_messages() {
    local count

    count=$("${php_cmd[@]}" "$pathtoconsole" doctrine:query:sql "SELECT COUNT(*) FROM messenger_messages" 2>/dev/null \
        | awk 'BEGIN {c=0} /^[[:space:]]*[0-9]+[[:space:]]*$/ {c=$1} END {print c}')

    if [[ "$count" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$count"
    else
        printf '0\n'
    fi
}

# Execute commands in a defined order based on the COMMAND_ORDER variable
IFS=',' read -r -a command_array <<< "$COMMAND_ORDER"
for cmd in "${command_array[@]}"; do
    # Construct variable name for the command (e.g. COMMAND_SEGMENTS_UPDATE)
    command_var="COMMAND_${cmd}"
    # Split command and its execution flag using '|'
    IFS="|" read -r command_string exec_flag <<< "${!command_var}"
    
    if [ "$exec_flag" = "true" ]; then
        execute_command "$command_string"
    fi
done

# Process the queue if the COMMAND_QUEUE execution flag is true
IFS="|" read -r queue_command queue_exec_flag <<< "$COMMAND_QUEUE"
if [ "$queue_exec_flag" = "true" ]; then
    # Get the initial count of messages in the queue and trim whitespace
    initial_count=$(count_queue_messages)
    echo "Messages initially in queue: $initial_count" | tee -a "$log_file"
    
    if [ "$initial_count" -gt 0 ]; then
        current_loop=0
        while [ $current_loop -lt $max_loops ]; do
            current_loop=$((current_loop+1))
            if ! execute_command "$queue_command"; then
                echo "Queue command failed in loop $current_loop. Stopping queue processing." | tee -a "$log_file" "$error_log_file"
                break
            fi
            
            count=$(count_queue_messages)
            echo "Messages remaining in queue: $count" | tee -a "$log_file"
            
            [ "$count" -eq 0 ] && break
            sleep "$QUEUE_DELAY"
        done
    else
        echo "No messages in queue. Skipping queue processing." | tee -a "$log_file"
    fi
fi

limit_log_files "$log_dir" "$max_logs"
limit_log_files "$error_log_dir" "$max_error_logs"
