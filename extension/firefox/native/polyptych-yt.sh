#!/usr/bin/env python3
"""Native messaging host for polyptych Firefox extension."""
import json, os, struct, sys, time

REQUEST = "/tmp/polyptych-yt-request"
STATUS = "/tmp/polyptych-yt-status"

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
    write_status("idle")
    while True:
        msg = read_message()
        if msg is None:
            break
        url = msg.get("url", "")
        if not url:
            continue
        write_status("starting")
        try:
            with open(REQUEST, "w") as f:
                f.write(url + "\n")
        except Exception as e:
            write_status(f"error: {e}")
        try:
            sys.stdout.buffer.write(struct.pack("<I", 2))
            sys.stdout.buffer.write(b"{}")
            sys.stdout.buffer.flush()
        except:
            pass
        write_status("downloading")

if __name__ == "__main__":
    main()
