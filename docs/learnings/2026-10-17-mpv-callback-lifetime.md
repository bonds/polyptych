# mpv callbacks and controller lifetime

**Date:** 2026-10-17

## Symptom / risk

`MPVController` registered an mpv render-update callback that dispatches to
the main queue:

```swift
let ctx = Unmanaged.passUnretained(self).toOpaque()
mpv_render_context_set_update_callback(renderContext, { ptr in
    let this = Unmanaged<MPVController>.fromOpaque(ptr).takeUnretainedValue()
    DispatchQueue.main.async { this.onNeedsRender?() }
}, ctx)
```

When playback is torn down (`closeCurrentPlayback`), the controller is
deallocated. A callback dispatched just before teardown still runs on the
main queue and dereferences the freed `this` — a use-after-free. It only
surfaced as an occasional `SIGSEGV` when playback was replaced.

## Cause

`passUnretained` / `takeUnretainedValue` mean the C callback context doesn't
keep the controller alive, and the dispatched block captures the raw
(unretained) pointer rather than a managed reference.

## Fix / takeaway

Route the callback through a small box that holds a **weak** reference to
the controller, and let the dispatched block capture the box **strongly**:

```swift
private final class CallbackBox { weak var controller: MPVController? }

let ctx = Unmanaged.passUnretained(callbackBox).toOpaque()
mpv_render_context_set_update_callback(renderContext, { ptr in
    let box = Unmanaged<MPVController.CallbackBox>.fromOpaque(ptr).takeUnretainedValue()
    DispatchQueue.main.async { box.controller?.onNeedsRender?() }
}, ctx)
```

The box stays alive for as long as any dispatched block holds it, and
`box.controller` is nil once the controller is gone.

**Lesson:** never put an unretained pointer into an async block. Wrap it in
a weak-reference box that the block can own.
