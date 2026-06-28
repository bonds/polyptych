#!/usr/bin/env python3
"""Native messaging host for polyptych Firefox extension.
Writes URL to request file, then polls status and relays updates to extension.
"""
import json, os, struct, sys, time

REQUEST = "/tmp/polyptych-yt-request"
STATUS = "/tmp/polyptych-yt-status"

def send_msg(obj):
    """Send a JSON message to the extension over stdout (native messaging protocol)."""
    payload = json.dumps(obj).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(payload)))
    sys.stdout.buffer.write(payload)
    sys.stdout.buffer.flush()

def read_status():
    try:
        with open(STATUS) as f:
            return f.read().strip()
    except:
        return None

def write_status(s):
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
        send_msg({})

        # Poll status file and relay updates to the extension
        seen = ""
        deadline = time.time() + 180
        while time.time() < deadline:
            status = read_status()
            if status and status != seen:
                seen = status
                send_msg({"status": status})
                if status.startswith("playing") or status.startswith("error"):
                    return
            time.sleep(0.5)

if __name__ == "__main__":
    main()
