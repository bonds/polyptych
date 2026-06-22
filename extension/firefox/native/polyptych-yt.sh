#!/usr/bin/env python3
"""Native messaging host for polyptych Firefox extension.
Writes URL to request file and simulates progress for the progress bar.
"""
import json, os, struct, sys, time, threading

REQUEST = "/tmp/polyptych-yt-request"
STATUS = "/tmp/polyptych-yt-status"

STATUS_LOCK = threading.Lock()

def write_status(s):
    with STATUS_LOCK:
        try:
            with open(STATUS, "w") as f:
                f.write(s + "\n")
        except:
            pass

def read_message():
    raw = sys.stdin.buffer.read(4)
    if not raw or len(raw) < 4:
        return None
    length = struct.unpack("<I", raw)[0]
    return json.loads(sys.stdin.buffer.read(length))

def simulate_progress():
    """Simulate download progress stages while the watcher does the real work."""
    write_status("requesting|0|Requesting…")
    time.sleep(1)
    write_status("requesting|10|Preparing download…")
    time.sleep(2)
    write_status("downloading|15|Downloading… 15%")
    time.sleep(3)
    write_status("downloading|30|Downloading… 30%")
    time.sleep(4)
    write_status("downloading|50|Downloading… 50%")
    time.sleep(5)
    write_status("downloading|70|Downloading… 70%")
    time.sleep(5)
    write_status("downloading|85|Downloading… 85%")
    time.sleep(3)
    write_status("downloading|95|Downloading… 95%")
    time.sleep(3)
    write_status("playing|100|Starting playback…")
    time.sleep(2)
    write_status("idle|0|")

def main():
    write_status("idle|0|")
    while True:
        msg = read_message()
        if msg is None:
            break
        url = msg.get("url", "")
        if not url:
            continue
        try:
            with open(REQUEST, "w") as f:
                f.write(url + "\n")
        except Exception as e:
            write_status(f"error|0|Error: {e}")
            continue
        # Acknowledge to the extension
        try:
            sys.stdout.buffer.write(struct.pack("<I", 2))
            sys.stdout.buffer.write(b"{}")
            sys.stdout.buffer.flush()
        except:
            pass
        # Start progress simulation in background
        threading.Thread(target=simulate_progress, daemon=True).start()

if __name__ == "__main__":
    main()
