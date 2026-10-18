# `activateIgnoringOtherApps` is a no-op on macOS 14+

**Date:** 2026-10-17

## Symptom

polyptych sometimes covered the whole screen and sometimes left the menu
bar visible — inconsistent between launches.

## Cause

The menu bar is hidden with `NSApp.presentationOptions = [.hideDock,
.hideMenuBar]`, but presentation options only apply while the app is
**active**. The app activated itself with
`NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])`,
which macOS 14+ ignores (the compiler even warns), so activation was
unreliable and the menu bar stayed up.

The windows were also only at `.floating` level (3), which is below the menu
bar (`kCGMainMenuWindowLevel` = 24), so nothing else covered it either.

## Fix / takeaway

- Activate with the modern `NSApp.activate()`.
- Keep playback windows above the menu bar: `NSWindow.Level.screenSaver`
  (1000) while playing, dropping to `.normal` on resign so the menu bar
  returns for whatever the user switched to.

**Lesson:** `.activateIgnoringOtherApps` does nothing on macOS 14+; use
`NSApp.activate()`. Window *level*, not presentation options, is what
decides whether you cover the menu bar.
