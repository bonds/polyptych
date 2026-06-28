# polyptych

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
