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

        # Check if already downloaded (with loudness cache)
        existing_file=$(ls "$YTDL_DIR/${video_id}".* 2>/dev/null | head -1)
        loudness_cache=""
        if [ -n "$existing_file" ] && [ -f "$existing_file" ]; then
            loudness_cache="${existing_file%.*}.loudness.json"
            if [ -f "$loudness_cache" ]; then
                write_status "downloading|100|Launching from cache…"
                sleep 1
                write_status "playing|100|Playing on all monitors"
                open_file "$existing_file"
                sleep 2
                write_status "idle|0|"
                continue
            fi
        fi

        # If we don't have the file yet, download it
        if [ -z "$existing_file" ] || [ ! -f "$existing_file" ]; then
            write_status "downloading|0|Downloading… 0%"

            yt-dlp --default-search ytsearch \
                --format "bestvideo[height<=1080][vcodec^=avc1]+bestaudio[ext=m4a]/best[height<=1080]" \
                --merge-output-format mp4 \
                --output "$YTDL_DIR/%(id)s.%(ext)s" \
                --print after_move:"$YTDL_DIR/%(id)s.%(ext)s" \
                --progress --newline \
                "$url" > /tmp/polyptych-yt-dl-stdout.txt 2>/tmp/polyptych-yt-dl-stderr.txt &
            DL_PID=$!

            last_pct=""
            while kill -0 $DL_PID 2>/dev/null; do
                if [ -f /tmp/polyptych-yt-dl-stderr.txt ]; then
                    pct=$(grep -oP '\[download\]\s+\K[0-9.]+(?=%)' /tmp/polyptych-yt-dl-stderr.txt | tail -1)
                    if [ -n "$pct" ] && [ "$pct" != "$last_pct" ]; then
                        last_pct="$pct"
                        int_pct=$(printf "%.0f" "$pct" 2>/dev/null || echo "$pct")
                        write_status "downloading|${int_pct}|Downloading… ${int_pct}%"
                    fi
                fi
                sleep 0.5
            done

            wait $DL_PID || {
                write_status "error|0|Download failed"
                sleep 2
                write_status "idle|0|"
                continue
            }

            dl_path=$(cat /tmp/polyptych-yt-dl-stdout.txt 2>/dev/null | grep "^$YTDL_DIR/" | tail -1)
            if [ -z "$dl_path" ] || [ ! -f "$dl_path" ]; then
                dl_path=$(ls "$YTDL_DIR/${video_id}".* 2>/dev/null | head -1)
            fi

            if [ -z "$dl_path" ] || [ ! -f "$dl_path" ]; then
                write_status "error|0|Downloaded file not found"
                sleep 2
                write_status "idle|0|"
                continue
            fi
        else
            dl_path="$existing_file"
        fi

        # Measure loudness for two-pass EBU R128 normalization (matches YouTube)
        loudness_cache="${dl_path%.*}.loudness.json"
        if [ ! -f "$loudness_cache" ]; then
            write_status "downloading|99|Measuring loudness…"
            ffmpeg -i "$dl_path" -af "loudnorm=I=-14:LRA=11:print_format=json" \
              -vn -f null - 2>&1 | python3 -c "
import sys, json
text = sys.stdin.read()
in_json = False
buf = ''
for line in text.split('\n'):
    if '{' in line and not in_json:
        in_json = True
        buf = line[line.index('{'):]
    elif in_json:
        buf += '\n' + line
        if '}' in line:
            buf = buf.rstrip(',')
            data = json.loads(buf)
            result = {k: data[k] for k in ['input_i','input_lra','input_tp','input_thresh']}
            print(json.dumps(result))
            break
" > "$loudness_cache" 2>/dev/null || true
        fi

        write_status "playing|100|Playing on all monitors"
        open_file "$dl_path"
        sleep 2
        write_status "idle|0|"
    fi
    sleep 0.5
done
