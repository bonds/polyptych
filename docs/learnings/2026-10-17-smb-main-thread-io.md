# Synchronous file I/O on a network mount freezes the UI

**Date:** 2026-10-17

## Symptom

Double-clicking a movie on the SMB share (`/Volumes/media`) in Finder
launched polyptych and it froze (beachball). Killing it and double-clicking
again worked.

## Cause

`startPlayback` read the loudness sidecar next to the media file
synchronously on the main thread:

```swift
let cachePath = (filePath as NSString).deletingPathExtension + ".loudness.json"
if let data = try? Data(contentsOf: URL(fileURLWithPath: cachePath)) { ... }
```

For a file on SMB that lookup is a network round-trip. On a cold/idle mount
(first access, or after the connection dropped) the SMB client has to
reconnect, which can block for many seconds — freezing the UI. The second
launch is fast because the connection is now warm.

The `fileExists(atPath:)` check for the argv launch path had the same
problem.

## Fix / takeaway

Do file I/O off the main thread. The cache read moved to
`DispatchQueue.global(qos: .userInitiated)` and playback starts back on the
main thread once it returns; the `fileExists` check likewise.

**Lesson:** never do synchronous file I/O on the main thread — a path may be
on a network mount (SMB/NFS), where a single lookup can block for a long
time.
