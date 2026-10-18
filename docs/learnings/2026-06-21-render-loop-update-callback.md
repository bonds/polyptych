# Drive rendering from mpv's update callback, not a timer

**Date:** 2026-06-21 (commit `a988412`)

## Symptom

A 60Hz timer drove `renderFrame()` even when no new video frame was
available, doing pointless work (and burning CPU) between frames.

## What worked

mpv's `mpv_render_context_set_update_callback` fires only when a redraw is
needed, so rendering tracks the video's own frame availability. Replaced the
timer with the update callback.

Caveat found later: the callback's work is dispatched to the main queue, and
a dispatch-only render loop can starve the run loop (and App Nap can throttle
it). See `2026-10-17-mpv-clock-stall.md`.

**Lesson:** render on demand (when mpv has a frame) rather than on a fixed
timer. But be aware of what thread/queue the callback lands on.
