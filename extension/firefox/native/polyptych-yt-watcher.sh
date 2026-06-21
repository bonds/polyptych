#!/usr/bin/env bash
# LaunchAgent for polyptych Firefox extension.
# Watches for request files from the native messaging host and spawns polyptych.
set -euo pipefail

REQUEST="/tmp/polyptych-yt-request"
POLYPTYCH="@polyptych_bin@"
if [ "$POLYPTYCH" = "@polyptych_bin@" ]; then
    POLYPTYCH="/run/current-system/sw/bin/polyptych"
fi

while true; do
    if [ -f "$REQUEST" ]; then
        url=$(head -1 "$REQUEST")
        rm -f "$REQUEST"
        if [ -n "$url" ]; then
            "$POLYPTYCH" --youtube "$url" &
        fi
    fi
    sleep 0.5
done
