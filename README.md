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

## Firefox extension

Adds a button to the YouTube player that launches the video in polyptych.

### Install

1. Build the signed `.xpi` (requires [Mozilla API credentials](https://addons.mozilla.org/en-US/developers/addon/api/key/)):
   ```bash
   cd extension/firefox
   source ~/.config/polyptych/.env   # sets AMO_JWT_ISSUER and AMO_JWT_SECRET
   nix run nixpkgs#web-ext -- sign --channel=unlisted --source-dir=.
   ```
2. In `about:addons` → gear icon → Install Add-on From File…, select the `.xpi`
3. **Enable both optional permissions** for `*://www.youtube.com` and `*://youtu.be`
4. **(Zen Browser)** Set "Run on sites with restrictions" to **Allow**
5. The 3-bar button appears next to YouTube's control bar

### Native messaging

The extension sends the video URL via `chrome.runtime.connectNative` to
`com.polyptych.youtube`, which writes it to `/tmp/polyptych-yt-request`.
A LaunchAgent watcher (`com.polyptych.watcher`) polls this file and launches
polyptych. The nix package installs both the native host and the LaunchAgent.

Requires `yt-dlp` on `$PATH` (the LaunchAgent sets `PATH` explicitly).

## Performance notes

### DisplayLink + CALayer

DisplayLink USB adapters have a significant CA commit cost when `layer.contents` changes
(~50ms per screen). With two DisplayLink screens, this limits frame rate to ~9fps when using
a single shared CGImage with `contentsRect` (because the full-size CGImage must be transferred
over USB even though only a portion is displayed).

**Use per-slice CGImages instead.** Creating a separate CGImage for each display's slice
(~640×1080 instead of 1920×1080) reduces the USB transfer size, bringing frame rate to
the video's native rate (24fps).

### What didn't work

- **`hwdec=videotoolbox-copy`** — GPU→CPU sync stall dropped FPS to 7–9.
  Pure software decode (`hwdec=no`) is faster on M2 for 1080p H.264.
- **IOSurface as `layer.contents`** — works on native screens but DisplayLink
  shows a blank screen (DisplayLink driver can't read IOSurface GPU memory).
- **`contentsRect` with shared CGImage** — full-size CGImage transfer over USB is
  the bottleneck (~100ms total for 2 DisplayLink screens).
- **`video-sync=desync`** — avoids the audio gate but causes AV drift; can also cause
  `mpv_render_context_render` to block waiting for new frames.
- **60Hz timer for render loop** — fires unnecessarily when no new frame is available.
  mpv's update callback (`mpv_render_context_set_update_callback`) is more efficient.
- **VP9/AV1 YouTube streams** — M2 has no hardware decoder for these. Force H.264 in
  yt-dlp format: `bestvideo[height<=1080][vcodec^=avc1]+bestaudio/best[height<=1080]`.

### What worked

- **Per-slice CGImages** (one per display, from triple-buffered SW render output)
- **`hwdec=no`** (pure software decode with FFmpeg on M2)
- **`video-sync=audio`** (proper AV sync via audio clock)
- **mpv update callback** for render scheduling (no polling)
- **Triple buffering** (safe shared CGImage from the render buffer)
- **H.264 YouTube downloads** via yt-dlp format filter

### Debug mode

Run with `--debug` to see FPS, timing breakdown, and video properties:

```
polyptych --debug --youtube search terms
```

Example output:
```
[polyptych] 24fps hit:100% vfps:24 drops:0 | frame:18ms | 1920×1080
```

- **fps**: rendered frames per second (should match vfps at steady state)
- **hit**: % of render callbacks that produced a new frame
- **vfps**: video filter output frame rate (the video's native fps)
- **drops**: frames mpv has dropped (should be 0 at steady state)
- **frame**: total time per renderFrame() call

## License

MIT
