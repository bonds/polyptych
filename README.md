# polyptych (pronounced: paul-ip-tick)

A painting, typically an altarpiece, composed of multiple panels.

Polyptych is a fullscreen video player that spans across multiple displays.
Compensates for DisplayLink USB adapter latency and monitor bezels.

## Installation

### Nix flake

```bash
nix run github:bonds/polyptych -- <file>
```

Or add to your flake inputs and install the package:

```nix
{
  inputs = {
    polyptych.url = "github:bonds/polyptych";
  };
  # then add `inputs.polyptych.packages.${system}.default` to
  # environment.systemPackages or home.packages
}
```

### From source

Requires mpv with libmpv (nix or homebrew):

```bash
swift build -c release
cp .build/arm64-apple-macosx/release/polyptych polyptych.app/Contents/MacOS/
```

## Usage

```
polyptych <file>                          # play local file
polyptych <url>                           # play network stream
polyptych --youtube <search terms>         # download + play YouTube 1080p
```

Configuration is stored in `~/.config/polyptych/config.json`.

## Controls

| Key | Action |
|---|---|
| `Space` | Pause / resume |
| `←` `→` | Seek -5s / +5s |
| `↓` `↑` | Seek -60s / +60s |
| `[` `]` | Adjust audio delay -/+ 50ms |
| `{` `}` | Adjust frame delay -/+ 50ms |
| `q` / `Esc` | Quit (saves position for resume) |

The app pauses when you switch to another app and resumes when you come back.
Press `q` while the video is playing and play the same file again to resume
from where you left off.

## How it works

On macOS with "Displays have separate Spaces" enabled, a single window
cannot span multiple monitors. Polyptych works around this by creating one
borderless window per display and slicing the video to fit.

The video is decoded and rendered to an offscreen buffer via mpv's software
renderer (at 1920×1080), then each display's slice is composited via CALayer
and stretched to fill its window. DisplayLink USB adapters are detected by
refresh rate (120Hz native vs 60Hz USB), and per-screen frame delay keeps
video in sync across all displays.

Designed for 3 side-by-side portrait monitors. A portion of the video is
cropped at each bezel gap (default 7.5% per side) so the image stays
proportional across the physical gap between screens rather than appearing
stretched.

## License

MIT
