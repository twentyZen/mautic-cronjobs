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

# Version 1 - 02.02.2025

# Load .env if available, using the script's directory as the base path
script_dir="$(dirname "$0")"
if [ -f "$script_dir/.env" ]; then
    set -o allexport
    source "$script_dir/.env"
    set +o allexport
fi

# Set working directory to the script's location
cd "$script_dir"

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
mkdir -p "$log_dir"
mkdir -p "$error_log_dir"

# Lock mechanism: prevent multiple script instances
if [ -f "$lockfile" ]; then
    LOCK_PID=$(cat "$lockfile")
    if kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "Script is already running with PID $LOCK_PID."
        exit 1
    else
        echo "Stale lock file found, removing it."
        rm -f "$lockfile"
    fi
fi

echo $MYSELF_PID > "$lockfile"
trap 'rm -f "$lockfile"; exit' INT TERM EXIT

log_file="$log_dir/$(date +'%Y%m%d_%H%M%S').log"
error_log_file="$error_log_dir/$(date +'%Y%m%d_%H%M%S')_error.log"


# Limit the number of log files to max_logs
limit_log_files() {
    local dir="$1"
    local max="$2"
    (cd "$dir" && ls -t *.log 2>/dev/null | tail -n +$((max+1)) | xargs rm -f)
}

# Execute a command and log its output, removing empty lines
execute_command() {
    local cmd="$1"
    echo "Executing: $cmd" | tee -a "$log_file"
    local output
    output=$($phpinterpreter $pathtoconsole $cmd 2>&1)
    local ret=$?
    output=$(echo "$output" | sed '/^$/d')
    echo "$output" | tee -a "$log_file"
    [ $ret -ne 0 ] && echo "$output" >> "$error_log_file"
    return $ret
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
    initial_count=$($phpinterpreter $pathtoconsole doctrine:query:sql "SELECT COUNT(*) FROM messenger_messages" \
        | awk 'BEGIN {c=0} /^[[:space:]]*[0-9]+[[:space:]]*$/ {c=$1} END {print c}')
    initial_count=$(echo "$initial_count" | xargs)
    echo "Messages initially in queue: $initial_count" | tee -a "$log_file"
    
    if [ "$initial_count" -gt 0 ]; then
        current_loop=0
        while [ $current_loop -lt $max_loops ]; do
            current_loop=$((current_loop+1))
            execute_command "$queue_command"
            
            count=$($phpinterpreter $pathtoconsole doctrine:query:sql "SELECT COUNT(*) FROM messenger_messages" \
                | awk 'BEGIN {c=0} /^[[:space:]]*[0-9]+[[:space:]]*$/ {c=$1} END {print c}')
            count=$(echo "$count" | xargs)
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

rm -f "$lockfile"
