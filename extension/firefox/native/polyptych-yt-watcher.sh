#!/usr/bin/env bash
# Watches for polyptych YouTube requests, downloads the video, and launches polyptych.
set -uo pipefail

export PATH="/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REQUEST="/tmp/polyptych-yt-request"
STATUS="/tmp/polyptych-yt-status"
YTDL_DIR="/tmp/polyptych-downloads"
POLYPTYCH="@polyptych_bin@"
if [ "${POLYPTYCH:0:1}" = "@" ]; then
    POLYPTYCH="/run/current-system/sw/bin/polyptych"
fi

YTDL_OPTS=()
ZEN_PROFILE=$(ls -d "$HOME/Library/Application Support/zen/Profiles/"*.Default\ \(release\) 2>/dev/null | head -1)
if [ -n "$ZEN_PROFILE" ]; then
    YTDL_OPTS=("--cookies-from-browser" "firefox:$ZEN_PROFILE")
fi
YTDL_OPTS+=("--extractor-args" "youtube:player_client=web_safari")


mkdir -p "$YTDL_DIR"
echo "idle|0|" > "$STATUS"

write_status() {
    echo "$1" > "$STATUS"
}

# Open a file with polyptych and bring the app to the foreground
open_file() {
    echo "=== $(date) ===" >> /tmp/polyptych-watcher-debug.log
    echo "Opening: $1" >> /tmp/polyptych-watcher-debug.log
    open -a polyptych "$1" >> /tmp/polyptych-watcher-debug.log 2>&1; echo "first open: exit=$?" >> /tmp/polyptych-watcher-debug.log
    open -a polyptych >> /tmp/polyptych-watcher-debug.log 2>/dev/null; echo "second open: exit=$?" >> /tmp/polyptych-watcher-debug.log
    sleep 2
    pgrep -x polyptych >> /tmp/polyptych-watcher-debug.log 2>&1 && echo "polyptych: running" >> /tmp/polyptych-watcher-debug.log || echo "polyptych: NOT running" >> /tmp/polyptych-watcher-debug.log
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
        video_id=$(yt-dlp "${YTDL_OPTS[@]}" --default-search ytsearch \
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
        existing_file=$(ls "$YTDL_DIR/${video_id}".{mp4,mkv,webm,avi} 2>/dev/null | head -1)
        loudness_cache=""
        if [ -n "$existing_file" ] && [ -f "$existing_file" ]; then
            # Verify the video codec is H.264 (M2 has no hardware AV1/VP9 decoder)
            codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$existing_file" 2>/dev/null)
            if [ "$codec" != "h264" ]; then
                write_status "downloading|0|Slow codec ($codec), re-downloading…"
                rm -f "$existing_file" "${existing_file%.*}.loudness.json"
                existing_file=""
            else
                loudness_cache="${existing_file%.*}.loudness.json"
                if [ -f "$loudness_cache" ]; then
                    write_status "downloading|95|Launching from cache…"
                    sleep 1
                    write_status "playing|100|Playing on all monitors"
                    touch /tmp/polyptych-about-to-open
                    open_file "$existing_file"
                    sleep 2
                    write_status "idle|0|"
                    continue
                fi
            fi
        fi

        # If we don't have the file yet, download it
        if [ -z "$existing_file" ] || [ ! -f "$existing_file" ]; then
            write_status "downloading|0|Downloading… 0%"

            DL_EXIT=1
            for attempt in 1 2 3; do
                yt-dlp "${YTDL_OPTS[@]}" --default-search ytsearch \
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
                        pct=$(sed -n 's/^\[download\] *\([0-9.]*\)%.*/\1/p' /tmp/polyptych-yt-dl-stdout.txt | tail -1)
                        if [ -n "$pct" ] && [ "$pct" != "$last_pct" ]; then
                            last_pct="$pct"
                            int_pct=$(printf "%.0f" "$pct" 2>/dev/null || echo "$pct")
                            [ "$int_pct" -gt 0 ] 2>/dev/null && {
                                mapped=$((5 + int_pct * 75 / 100))
                                write_status "downloading|${mapped}|Downloading… ${int_pct}%"
                            }
                        fi
                    fi
                    sleep 0.5
                done

                wait $DL_PID
                DL_EXIT=$?
                if [ $DL_EXIT -eq 0 ]; then
                    break
                fi

                echo "$(date) attempt $attempt failed (exit=$DL_EXIT), $([ $attempt -lt 3 ] && echo "retrying..." || echo "giving up")" >> /tmp/polyptych-watcher-debug.log
                [ $attempt -eq 1 ] && sleep 5
                [ $attempt -eq 2 ] && sleep 15
            done

            if [ $DL_EXIT -ne 0 ]; then
                write_status "error|0|Download failed"
                sleep 2
                write_status "idle|0|"
                continue
            fi

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
            write_status "downloading|80|Measuring loudness…"
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
" > "$loudness_cache" 2>/dev/null &
            MEASURE_PID=$!
            mpct=80
            while kill -0 $MEASURE_PID 2>/dev/null; do
                [ "$mpct" -lt 94 ] && mpct=$((mpct + 1))
                write_status "downloading|${mpct}|Measuring loudness…"
                sleep 1
            done
            wait $MEASURE_PID 2>/dev/null || true
            write_status "downloading|95|Processing…"
        fi

        write_status "downloading|97|Launching polyptych…"
        sleep 1
        write_status "playing|100|Playing on all monitors"
        touch /tmp/polyptych-about-to-open
        open_file "$dl_path"
        sleep 2
        write_status "idle|0|"
    fi
    sleep 0.5
done
