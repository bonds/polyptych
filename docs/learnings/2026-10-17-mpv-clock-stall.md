# mpv's clock can stall after a seek or at startup

**Date:** 2026-10-17

## Symptom

Occasionally, after launching or seeking, the frame rate dropped to a few
fps and stayed there until pausing and unpausing (space, space). Audio kept
playing.

## Cause

With `video-sync=audio`, mpv gates video on the audio clock. After a seek
(or at startup) that clock can get stuck: `mpv_render_context_render` is not
the bottleneck (frame time stays small) — mpv simply stops producing frames.

Two property gotchas make this hard to detect:

- `estimated-vf-fps` reads **0** exactly when the stall happens (no frames
  flow through the filter chain), so it can't be used as "what should the
  frame rate be?".
- `core-idle` can be **true** during the stall too, so it can't be used to
  skip.

`container-fps` stays constant and is the right reference.

Toggling pause resets mpv's playback clock, which is why the manual
pause/unpause workaround fixes it.

## Fix / takeaway

A frame-rate watchdog: poll the rendered fps once a second; if it stays
below 50% of `container-fps` for ~2s while we should be playing, bounce
pause (`pause=yes`, then `pause=no` after ~200ms) to reset the clock. Guard
it with "the video is loaded" (`container-fps > 1`) and "we have rendered at
least one frame", otherwise it fires during the normal initial buffering.

**Lesson:** don't use `estimated-vf-fps` to detect a stall — it is 0 when
frames stall. Use `container-fps` as the constant reference.
