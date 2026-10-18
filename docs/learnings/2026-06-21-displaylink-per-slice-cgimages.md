# DisplayLink screens need per-slice CGImages

**Date:** 2026-06-21 (commits `66f82b5`, `d53d1df`, `f543a37`, `38ef99f`, `ebed2de`, `35d3495`)

## Symptom

With two DisplayLink USB screens, frame rate capped around 9fps even though
the video was 24fps and the SW renderer had frames to spare.

## Cause

DisplayLink adapters have a high CoreAnimation commit cost when
`layer.contents` changes — roughly 50ms per screen. With a single shared
full-size CGImage and `contentsRect` to show a slice, the *whole* 1920×1080
image is transferred over USB even though only a portion is displayed. Two
screens is ~100ms per commit, which throttles the whole render loop.

## What didn't work

- **IOSurface as `layer.contents`** (set once, CA picks up pixel changes):
  works on native screens, but DisplayLink shows a blank screen — the
  DisplayLink driver can't read IOSurface GPU memory.
- **`contentsRect` with a shared CGImage**: the full-size transfer over USB
  is the bottleneck (~100ms for two screens).

## What worked

- **Per-slice CGImages**: one CGImage per display (~640×1080 instead of
  1920×1080), built from the triple-buffered SW render output. Smaller USB
  transfers bring DisplayLink up to the video's native rate.
- **Triple buffering**: the render buffer isn't reused until three frames
  later, so a CGImage referencing it stays valid.

**Lesson:** on DisplayLink, the cost is the *bytes transferred* to the
adapter, not the draw call. Slice the frame per display so each adapter only
sees its own pixels.
