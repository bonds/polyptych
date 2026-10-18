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

## Releasing

A Git tag is **not** a GitHub release. Releases are separate objects that
carry the notes, so every version bump should produce both:

1. Bump `version` in `flake.nix` **and** `polyptychVersion` in
   `Sources/polyptych/Version.swift` (keep them in sync) and commit. The
   commit message names the version, e.g. `... ; v0.11.2`.
2. Annotated-tag the release commit and push it:
   ```bash
   git tag -a v0.11.2 -m "polyptych v0.11.2"
   git push origin main v0.11.2
   ```
3. Create the GitHub release with a changelog built from the commits since
   the previous tag. `gh release create --generate-notes` is **not** useful
   here: with no PRs it only emits a compare link, so build the notes from
   the log:
   ```bash
   prev=$(git describe --tags --abbrev=0 v0.11.2^)
   git log --no-merges --pretty='- %s' "$prev..v0.11.2" > /tmp/notes.md
   gh release create v0.11.2 --notes-file /tmp/notes.md
   ```
   Add `--draft` to stage it first, or `--latest`/`--prerelease` as needed.

### Release token

Creating releases needs `Contents: write`. The fine-grained PAT in the `gh`
keyring does **not** have it and returns `HTTP 403: Resource not accessible
by personal access token`. Either add `Contents: write` to that PAT, or use
the classic `public_repo` token (works for this public repo):

```bash
GH_TOKEN=$(security find-generic-password -s gh-public-token -a bonds -w) \
  gh release create v0.11.2 --notes-file /tmp/notes.md
```

To backfill a release for an existing tag, run the same command for the tag.

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
