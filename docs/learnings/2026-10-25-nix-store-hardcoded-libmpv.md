# A hardcoded /nix/store path in Package.swift breaks the app on GC

**Symptom** — Launching the installed `polyptych.app` shows macOS's
"polyptych cannot be opened because of a problem. Check with the developer to
make sure polyptych works with this version of macOS." Running the executable
directly prints the real reason:

```
dyld: Library not loaded: /nix/store/03zfgn8fi73mrnr848y69vhb6nn04zwp-mpv-0.41.0/lib/libmpv.2.dylib
  Referenced from: .../polyptych.app/Contents/MacOS/polyptych
  Reason: tried: '.../libmpv.2.dylib' (no such file)
```

**Cause** — `Package.swift` carried
`.unsafeFlags(["-L", "/nix/store/03zfgn8…-mpv-0.41.0/lib"])`. SwiftPM emits
target `unsafeFlags` before the flake's `-Xlinker -L${libmpv}/lib`, so the
hardcoded directory wins the link order and the binary binds to that exact
mpv build. When nixpkgs updated, the derivation's declared `libmpv` changed
(in that build, to `0iqbsv2…-mpv`) but the app still linked `03zfgn8…`, which
was no longer part of the closure. Nix GC'd it and the app could not launch.

The tell-tale signs:

- `otool -L` on the app executable shows an absolute `/nix/store/...-mpv` path.
- That path does not exist: `ls $(otool -L ... | grep libmpv | awk '{print $1}')`.
- `nix-store -q --references <polyptych-out>` lists **no** mpv at all — the
  dependency was never registered, so GC was free to remove it.

**Fix / takeaway** — Never hardcode a `/nix/store` path in `Package.swift`.
Let the flake inject the lib directory (`-Xlinker -L${libmpv}/lib`) so the
linked mpv is always the derivation's declared input and stays in the closure
(`nix-store -q --references` should list it). For a standalone
`swift build`, pass the directory via `LIBMPV_DIR` (the flake's devShell sets
it).

**Bonus** — Nix only linker-signs the binary, so
`codesign --verify --deep --strict` reports "code has no resources but
signature indicates they must be present". Add a `postFixup` ad-hoc
`codesign` (postFixup runs *after* `fixupPhase`'s `strip`, which would
otherwise invalidate the signature). `sigtool`'s `codesign` cannot sign a
`.app` bundle (`NotAMachOFileException`) — use `/usr/bin/codesign`. Note
`spctl -a` still rejects an ad-hoc signature; that is expected and harmless
because nix-store files carry no quarantine attribute.
