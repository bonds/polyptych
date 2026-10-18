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
below 60% of `container-fps` for ~2s while we should be playing, bounce
pause (`pause=yes`, then `pause=no` after ~200ms) to reset the clock. Guard
it with "the video is loaded" (`container-fps > 1`) and "we have rendered at
least one frame", otherwise it fires during the normal initial buffering.

Two things the first attempt got wrong:

- **App Nap.** When the app is not the active app (e.g. launched from a
  terminal) macOS throttles its timers, so the watchdog timer never fired.
  Hold a `ProcessInfo.beginActivity(options: [.userInitiated, …])` while
  playing to keep it running.
- **Startup needs a lower bar.** The stall is most common right after
  launch, and the first second after the video loads is often only slightly
  slow. Do one resync at that first healthy-video check if the fps is below
  80% of `container-fps`, rather than waiting for the 2s persistent path.

**Lesson:** don't use `estimated-vf-fps` to detect a stall — it is 0 when
frames stall. Use `container-fps` as the constant reference. And prevent App
Nap, or background throttling silently disables any timer-based watchdog.
