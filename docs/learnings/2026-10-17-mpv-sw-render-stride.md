# mpv SW renderer `SW_STRIDE` is a `size_t*`

**Date:** 2026-10-17

## Symptom

`polyptych <youtube-url>` played audio but showed black screens.
Bizarrely, it worked with `--debug` and failed without it — a clean,
reproducible debug/non-debug difference.

## Cause

mpv 0.41 changed `MPV_RENDER_PARAM_SW_STRIDE` to a `size_t*` (8 bytes on
64-bit). `MPVController.renderFrame()` passed a pointer to an `Int32`
(4 bytes):

```swift
var swStride = renderStride   // Int32
```

The C API reads 8 bytes, so the upper 4 bytes were whatever happened to be
adjacent on the stack. With `--debug` the extra logging shifted the stack
layout so those bytes were zero (correct stride → video); without it the
stride was garbage and mpv wrote each frame to a bogus offset, leaving the
render buffer black.

Because it is undefined behavior, it presented as a debug/non-debug
difference rather than a type error.

## Fix / takeaway

Pass the pointer-sized type mpv expects:

```swift
var swStride = size_t(renderStride)
```

**Lesson:** when calling a C API through a `void*` parameter, match the
documented pointee type exactly — the compiler can't check it for you.
A "works with `--debug`" symptom is a strong hint at stack/memory-layout
undefined behavior.
