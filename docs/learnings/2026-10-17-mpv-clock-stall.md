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

mpv emits `MPV_EVENT_PLAYBACK_RESTART` on start of playback **and after
each seek** — exactly the two points where the stall happens. Resync there:
bounce pause (`pause=yes`, then `pause=no` after ~200ms) a moment after
playback restarts. This directly automates the space-space workaround at the
right moments, instead of trying to infer it from the frame rate.

Keep an fps watchdog as a backstop for stalls that don't come with a
`PLAYBACK_RESTART` (a mid-playback clock stall): poll the rendered fps and,
if it stays below 60% of `container-fps` for ~2s while playing, resync. It
needs "the video is loaded" (`container-fps > 1`) and "we have rendered at
least one frame" guards, or it fires during normal initial buffering.
Debounce resyncs (~1.5s): the un-pause that ends a resync itself fires
`PLAYBACK_RESTART`, which would otherwise loop.

Two traps found along the way:

- **App Nap.** When the app is not the active app (e.g. launched from a
  terminal) macOS throttles its timers, so a timer-based watchdog never
  fires. Hold a `ProcessInfo.beginActivity(options: [.userInitiated, …])`
  while playing.
- **`estimated-vf-fps` reads 0 exactly when frames stall**, so it can't be
  used as the reference. `container-fps` stays constant.

**Lesson:** for a known stall trigger, hook the mpv event that marks it
(`PLAYBACK_RESTART`) rather than trying to detect the symptom. Don't use
`estimated-vf-fps` to detect a stall, and prevent App Nap or background
throttling silently disables any timer-based watchdog.
