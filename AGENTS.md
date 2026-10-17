# polyptych

## Learnings

Surprises and hard-won lessons are logged in `docs/learnings/` (index in
`docs/learnings/README.md`). Add an entry when you hit something
non-obvious — especially undefined behavior, macOS quirks, or mpv API
changes.

## Versions

Keep `flake.nix` (`version`) and `Sources/polyptych/Version.swift`
(`polyptychVersion`) in sync. Bump the minor version for user-facing
behavior changes; patch for fixes.

## Releasing the Firefox extension

### Prerequisites

API credentials at `~/.config/polyptych/.env`:
```
AMO_JWT_ISSUER="user:..."
AMO_JWT_SECRET="..."
```

### Sign a new version

1. Bump `version` in `extension/firefox/manifest.json`
2. `cd extension/firefox && ./sign.sh`
3. Signed `.xpi` lands in `web-ext-artifacts/`
4. Install via `about:addons` → gear → Install Add-on From File
