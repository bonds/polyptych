#!/usr/bin/env bash
# Native messaging host for polyptych Firefox extension
# Reads a single JSON message from stdin, spawns polyptych with the YouTube URL

set -euo pipefail

read -r line
# Extract URL from JSON: {"url":"..."}
url=$(echo "$line" | sed 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
exec @polyptych_bin@ --youtube "$url"
