# polyptych

Fullscreen video player that spans across multiple displays. Compensates for
DisplayLink USB adapter latency and monitor bezels.

## Usage

```
polyptych <file>                          # play local file
polyptych <url>                           # play network stream
polyptych --youtube <search terms>         # download + play YouTube 1080p
```

## Controls

| Key | Action |
|---|---|
| `Space` | Pause / resume |
| `←` `→` | Seek -5s / +5s |
| `↓` `↑` | Seek -60s / +60s |
| `[` `]` | Adjust audio delay -/+ 50ms |
| `{` `}` | Adjust frame delay -/+ 50ms |
| `q` / `Esc` | Quit |

## Building

Requires mpv with libmpv (nix or homebrew):

```bash
swift build -c release
cp .build/arm64-apple-macosx/release/polyptych polyptych.app/Contents/MacOS/
```

## How it works

On macOS with "Displays have separate Spaces" enabled, a single window
cannot span multiple monitors. Polyptych works around this by creating one
borderless window per display and slicing the video to fit.

The video is decoded and rendered to an offscreen buffer via mpv's software
renderer, then each display's slice is composited via CALayer and stretched
to fill its window. DisplayLink USB adapters are detected by refresh rate
(120Hz native vs 60Hz USB), and per-screen frame delay keeps video in sync
across all displays.

## License

MIT
