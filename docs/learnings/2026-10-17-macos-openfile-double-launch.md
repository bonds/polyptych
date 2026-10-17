# macOS delivers the launch argument twice

**Date:** 2026-10-17

## Symptom

`polyptych <youtube-url>` created six fullscreen windows instead of three.
The first three were black and sat on top, occluding the real video, so the
screen was black even though the later three were playing (audio worked).

## Cause

macOS delivers a launch argument to **both** `argv` and an
`application(_:openFile:)` event, and the open event can arrive before
`applicationDidFinishLaunching` runs. So `startPlayback` ran twice:

1. `openFile` called `startPlayback(..., isURL: false)` — loading the URL
   as a *local file*, which fails and leaves a black frame.
2. `applicationDidFinishLaunching`'s async path called
   `startPlayback(..., isURL: true)` — correct, but it did not close the
   windows created in step 1.

The window list confirmed it: 6 layer-3 windows in the failing case vs 3 in
the working one.

## Fix / takeaway

- Detect URLs in `openFile` instead of always treating the argument as a
  local file.
- Dedupe in `startPlayback` on the requested path so the same path can't
  start two playbacks.
- Keep a single `closeCurrentPlayback()` helper for teardown.

**Lesson:** on macOS, a command-line path/URL can also arrive as an
`openFile` event, in either order relative to `applicationDidFinishLaunching`.
Make playback entry points idempotent.
