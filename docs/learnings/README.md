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

- [2026-10-17 — mpv SW renderer `SW_STRIDE` is a `size_t*`](2026-10-17-mpv-sw-render-stride.md)
- [2026-10-17 — macOS delivers the launch argument twice](2026-10-17-macos-openfile-double-launch.md)
- [2026-10-17 — mpv callbacks and controller lifetime](2026-10-17-mpv-callback-lifetime.md)
- [2026-10-17 — NSWindow `close()` over-releases under ARC](2026-10-17-nswindow-released-when-closed.md)
