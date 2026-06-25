#!/usr/bin/env bash
# Watches for polyptych YouTube requests, downloads the video, and launches polyptych.
set -euo pipefail

export PATH="/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REQUEST="/tmp/polyptych-yt-request"
STATUS="/tmp/polyptych-yt-status"
YTDL_DIR="/tmp/polyptych-downloads"
POLYPTYCH="@polyptych_bin@"
if [ "${POLYPTYCH:0:1}" = "@" ]; then
    POLYPTYCH="/run/current-system/sw/bin/polyptych"
fi


mkdir -p "$YTDL_DIR"
echo "idle|0|" > "$STATUS"

write_status() {
    echo "$1" > "$STATUS"
}

# Open a file with polyptych and bring the app to the foreground
open_file() {
    open -a polyptych "$1"
    # Second open call activates the already-running instance to the foreground
    touch /tmp/polyptych-activate
    open -a polyptych /tmp/polyptych-activate 2>/dev/null
}

while true; do
    if [ -f "$REQUEST" ]; then
        url=$(head -1 "$REQUEST")
        rm -f "$REQUEST"

        if [ -z "$url" ]; then
            continue
        fi

        write_status "requesting|10|Resolving video…"

        # Resolve video ID from the URL or search query
        video_id=$(yt-dlp --default-search ytsearch \
            --print id \
            --no-warnings \
            "$url" 2>/dev/null | tail -1)

        if [ -z "$video_id" ]; then
            write_status "error|0|Could not resolve video"
            sleep 2
            write_status "idle|0|"
            continue
        fi

        # Check if already downloaded
        existing_file=$(ls "$YTDL_DIR/${video_id}".* 2>/dev/null | head -1)
        if [ -n "$existing_file" ] && [ -f "$existing_file" ]; then
            write_status "downloading|100|Launching from cache…"
            sleep 1
            write_status "playing|100|Playing on all monitors"
            open_file "$existing_file"
            sleep 2
            write_status "idle|0|"
            continue
        fi

        write_status "downloading|0|Downloading… 0%"

        # Download with real progress parsing
        yt-dlp --default-search ytsearch \
            --format "bestvideo[height<=1080][vcodec^=avc1]+bestaudio/best[height<=1080]" \
            --merge-output-format mp4 \
            --output "$YTDL_DIR/%(id)s.%(ext)s" \
            --print after_move:"$YTDL_DIR/%(id)s.%(ext)s" \
            --progress --newline \
            "$url" > /tmp/polyptych-yt-dl-stdout.txt 2>/tmp/polyptych-yt-dl-stderr.txt &
        DL_PID=$!

        # Parse progress while downloading
        last_pct=""
        while kill -0 $DL_PID 2>/dev/null; do
            if [ -f /tmp/polyptych-yt-dl-stderr.txt ]; then
                # Parse the last progress line for percentage
                pct=$(grep -oP '\[download\]\s+\K[0-9.]+(?=%)' /tmp/polyptych-yt-dl-stderr.txt | tail -1)
                if [ -n "$pct" ] && [ "$pct" != "$last_pct" ]; then
                    last_pct="$pct"
                    int_pct=$(printf "%.0f" "$pct" 2>/dev/null || echo "$pct")
                    write_status "downloading|${int_pct}|Downloading… ${int_pct}%"
                fi
            fi
            sleep 0.5
        done

        # Check for error
        wait $DL_PID || {
            write_status "error|0|Download failed"
            sleep 2
            write_status "idle|0|"
            continue
        }

        # Get the downloaded file path
        dl_path=$(cat /tmp/polyptych-yt-dl-stdout.txt 2>/dev/null | grep "^$YTDL_DIR/" | tail -1)
        if [ -z "$dl_path" ] || [ ! -f "$dl_path" ]; then
            # Try to find by video ID
            dl_path=$(ls "$YTDL_DIR/${video_id}".* 2>/dev/null | head -1)
        fi

        if [ -z "$dl_path" ] || [ ! -f "$dl_path" ]; then
            write_status "error|0|Downloaded file not found"
            sleep 2
            write_status "idle|0|"
            continue
        fi

        write_status "playing|100|Playing on all monitors"
        open_file "$dl_path"
        sleep 2
        write_status "idle|0|"
    fi
    sleep 0.5
done
