#!/usr/bin/env python3
"""Native messaging host for polyptych Firefox extension."""
import json, os, struct, sys

REQUEST = "/tmp/polyptych-yt-request"

def read_message():
    raw = sys.stdin.buffer.read(4)
    if not raw or len(raw) < 4:
        return None
    length = struct.unpack("<I", raw)[0]
    return json.loads(sys.stdin.buffer.read(length))

def main():
    while True:
        msg = read_message()
        if msg is None:
            break
        url = msg.get("url", "")
        if not url:
            continue
        # Write URL to file — a LaunchAgent watches and spawns polyptych
        with open(REQUEST, "w") as f:
            f.write(url + "\n")
        sys.stdout.buffer.write(struct.pack("<I", 2))
        sys.stdout.buffer.write(b"{}")
        sys.stdout.buffer.flush()

if __name__ == "__main__":
    main()
