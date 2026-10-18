# Learnings

A running log of surprises, gotchas, and lessons learned while building
polyptych. The point is to accumulate hard-won knowledge so we don't
re-discover the same traps.

## Adding an entry

Create `docs/learnings/YYYY-MM-DD-short-slug.md` and link it below. One
lesson per file, with:

- **Symptom** — what you observed.
- **Cause** — the underlying reason.
- **Fix / takeaway** — what to do (or avoid) next time.

Keep it short and concrete. If a lesson is superseded, update it rather
than deleting it.

## Entries

- [2026-06-21 — DisplayLink screens need per-slice CGImages](2026-06-21-displaylink-per-slice-cgimages.md)
- [2026-06-21 — Hardware decode was slower than software on M2 (1080p H.264)](2026-06-21-m2-software-decode-faster.md)
- [2026-06-21 — `video-sync=desync` avoids the audio gate but drifts A/V](2026-06-21-video-sync-desync-av-drift.md)
- [2026-06-21 — Drive rendering from mpv's update callback, not a timer](2026-06-21-render-loop-update-callback.md)
- [2026-06-21 — Force H.264 for YouTube downloads on M2](2026-06-21-force-h264-youtube.md)
- [2026-10-17 — mpv SW renderer `SW_STRIDE` is a `size_t*`](2026-10-17-mpv-sw-render-stride.md)
- [2026-10-17 — macOS delivers the launch argument twice](2026-10-17-macos-openfile-double-launch.md)
- [2026-10-17 — mpv callbacks and controller lifetime](2026-10-17-mpv-callback-lifetime.md)
- [2026-10-17 — NSWindow `close()` over-releases under ARC](2026-10-17-nswindow-released-when-closed.md)
- [2026-10-17 — mpv's clock can stall after a seek or at startup](2026-10-17-mpv-clock-stall.md)
- [2026-10-17 — `activateIgnoringOtherApps` is a no-op on macOS 14+](2026-10-17-macos-activation-menu-bar.md)
- [2026-10-17 — Synchronous file I/O on a network mount freezes the UI](2026-10-17-smb-main-thread-io.md)
