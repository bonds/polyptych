#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REQUEST="/tmp/polyptych-yt-request"
STATUS="/tmp/polyptych-yt-status"
POLYPTYCH="@polyptych_bin@"
if [ "${POLYPTYCH:0:1}" = "@" ]; then
    POLYPTYCH="/run/current-system/sw/bin/polyptych"
fi

echo "idle" > "$STATUS"

while true; do
    if [ -f "$REQUEST" ]; then
        url=$(head -1 "$REQUEST")
        rm -f "$REQUEST"
        if [ -n "$url" ]; then
            echo "downloading" > "$STATUS"
            "$POLYPTYCH" --youtube "$url" &
            PID=$!
            # Wait for process to finish, polling for status updates
            while kill -0 $PID 2>/dev/null; do
                sleep 2
            done
            echo "idle" > "$STATUS"
        fi
    fi
    sleep 0.5
done
