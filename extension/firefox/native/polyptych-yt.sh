#!/usr/bin/env python3
"""Native messaging host for polyptych Firefox extension."""
import json, os, struct, subprocess, sys

POLYPTYCH = "@polyptych_bin@"
if POLYPTYCH.startswith("@"):
    POLYPTYCH = "polyptych"

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
        subprocess.Popen([POLYPTYCH, "--youtube", url],
                         stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
        sys.stdout.buffer.write(struct.pack("<I", 2))
        sys.stdout.buffer.write(b"{}")
        sys.stdout.buffer.flush()

if __name__ == "__main__":
    main()
