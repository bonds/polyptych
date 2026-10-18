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

Toggling pause resets mpv's playback clock. Rather than resync *after* the
video is already playing (which shows as a freeze mid-play — a visible
hitch), have mpv **start paused** (`pause=yes` before init) and un-pause once
playback is ready. The clock then initializes at un-pause instead of at load,
so the stall never happens and there is no mid-playback hitch.

Trigger the initial un-pause on the first `MPV_EVENT_PLAYBACK_RESTART` (it
fires on start of playback and after every seek). Later `PLAYBACK_RESTART`s
(after a seek) do a resync — bounce pause — since the clock can stall there
too. Debounce resyncs (~1.5s): the un-pause that ends a resync itself fires
`PLAYBACK_RESTART`, which would otherwise loop.

Keep an fps watchdog as a backstop for stalls that don't come with a
`PLAYBACK_RESTART` (a mid-playback clock stall): poll the rendered fps and,
if it stays below 60% of `container-fps` for ~2s while playing, resync. It
needs "the video is loaded" (`container-fps > 1`) and "we have rendered at
least one frame" guards, or it fires during normal initial buffering.

Two traps found along the way:

- **App Nap.** When the app is not the active app (e.g. launched from a
  terminal) macOS throttles its timers, so a timer-based watchdog never
  fires. Hold a `ProcessInfo.beginActivity(options: [.userInitiated, …])`
  while playing.
- **`estimated-vf-fps` reads 0 exactly when frames stall**, so it can't be
  used as the reference. `container-fps` stays constant.

**Lesson:** for a known stall trigger, hook the mpv event that marks it
(`PLAYBACK_RESTART`) rather than trying to detect the symptom. Initialize the
clock by starting paused and un-pausing, rather than pausing a playing video
(which the user sees as a hitch). Don't use `estimated-vf-fps` to detect a
stall, and prevent App Nap or background throttling silently disables any
timer-based watchdog.
