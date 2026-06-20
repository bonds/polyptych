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

Uses mpv's software renderer to decode and scale video to 1920×1080, then
renders per-display slices via CALayer compositing. Detects DisplayLink
adapters by refresh rate (120Hz native vs 60Hz USB) and applies per-screen
frame delay to keep video in sync across all displays.

## License

MIT
