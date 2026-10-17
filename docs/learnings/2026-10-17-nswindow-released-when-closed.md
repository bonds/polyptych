# NSWindow `close()` over-releases under ARC

**Date:** 2026-10-17

## Symptom

Tearing down playback (`closeCurrentPlayback()` → `window.close()` then
clearing the `spannedWindows` array) crashed with `EXC_BAD_ACCESS` in
`objc_release` / `objc_autoreleasePoolPop` on the main run loop — not in any
of our frames, which made it hard to place.

## Cause

`NSWindow.isReleasedWhenClosed` defaults to `true`. `close()` therefore
releases the window, and Swift/ARC *also* releases it when the last
reference is dropped — a double release. The crash surfaces later when the
run loop drains its autorelease pool and the freed object is released
again.

## Fix / takeaway

Tell AppKit that ARC owns the window:

```swift
isReleasedWhenClosed = false
```

Set this in `SpannedWindow.init`. `close()` then just orders the window out
and ARC frees it once.

**Lesson:** any `NSWindow` (or `NSWindowController`) you create and hold in
Swift should set `isReleasedWhenClosed = false`; otherwise `close()` plus
ARC double-frees it.
