# `video-sync=desync` avoids the audio gate but drifts A/V

**Date:** 2026-06-21 (commit `06bf29b`)

## Symptom

With `video-sync=audio`, mpv gates video on the audio clock: when the clock
is off, video frames stop being produced. Tried `video-sync=desync` to get
around it.

## What happened

`desync` does avoid the audio gate, but:

- A/V drifts out of sync (video runs at its own rate).
- `mpv_render_context_render` can block waiting for new frames.

## What worked

`video-sync=audio` — proper A/V sync via the audio clock. The occasional
clock stall it can cause is handled separately (see
`2026-10-17-mpv-clock-stall.md`).

**Lesson:** don't trade A/V sync for frame production. Fix the stall by
resetting the clock (pause/unpause), not by desyncing.
