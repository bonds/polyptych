{
  description = "Multi-monitor video player — spans fullscreen across all displays";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-darwin" ];
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          libmpv = pkgs.mpv.override { scripts = [ ]; };
          # Runtime tools the app and the extension watcher shell out to.
          runtimeDeps = with pkgs; [ yt-dlp ffmpeg ];
        in
        {
          default = pkgs.stdenv.mkDerivation {
            pname = "polyptych";
            version = "0.11.4";
            src = self;

          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs = with pkgs; [
            swift
            swiftpm
            libmpv
            zip
          ] ++ runtimeDeps;

            buildPhase = ''
              cat > Sources/polyptych/Version.generated.swift << SWIFT_EOF
              let polyptychCommit = "${builtins.substring 0 7 (self.rev or "unknown")}"
              SWIFT_EOF
              swift build -c release --disable-sandbox \
                -Xlinker -L${libmpv}/lib
            '';

            SWIFTPM_CACHE_BASE = "$TMPDIR/.cache/swiftpm";

            installPhase = ''
              mkdir -p $out/Applications/polyptych.app/Contents/MacOS
              cp .build/arm64-apple-macosx/release/polyptych \
                $out/Applications/polyptych.app/Contents/MacOS/polyptych
              cp ${./Sources/polyptych/Info.plist} \
                $out/Applications/polyptych.app/Contents/Info.plist
              mkdir -p $out/bin
              # Wrap so the app finds yt-dlp/ffmpeg on PATH at runtime (it shells
              # out to them) instead of relying on the user's environment.
              makeWrapper $out/Applications/polyptych.app/Contents/MacOS/polyptych \
                $out/bin/polyptych \
                --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps}

              # Native messaging host for Firefox extension
              mkdir -p $out/bin
              cp ${./extension/firefox/native/polyptych-yt.sh} $out/bin/polyptych-yt
              chmod +x $out/bin/polyptych-yt

              mkdir -p $out/lib/mozilla/native-messaging-hosts
              substitute ${./extension/firefox/native/com.polyptych.youtube.json} \
                $out/lib/mozilla/native-messaging-hosts/com.polyptych.youtube.json \
                --replace-fail '"path": "/run/current-system/sw/bin/polyptych-yt"' \
                             '"path": "${placeholder "out"}/bin/polyptych-yt"'

              # Watcher LaunchAgent
              substitute ${./extension/firefox/native/polyptych-yt-watcher.sh} \
                $out/bin/polyptych-yt-watcher \
                --replace-fail '@polyptych_bin@' "$out/bin/polyptych" \
                --replace-fail '@runtime_path@' "${pkgs.lib.makeBinPath runtimeDeps}"
              chmod +x $out/bin/polyptych-yt-watcher

              mkdir -p $out/lib/LaunchAgents
              substitute ${./extension/firefox/native/com.polyptych.watcher.plist} \
                $out/lib/LaunchAgents/com.polyptych.watcher.plist \
                --replace-fail '@watcher_bin@' "$out/bin/polyptych-yt-watcher"

              # Firefox extension .xpi
              mkdir -p $out/lib/firefox/extensions
              (cd ${./extension/firefox} && zip -r $out/lib/firefox/extensions/polyptych@bonds.github.io.xpi \
                manifest.json content.js background.js icon.svg)
            '';

            # Ad-hoc sign the bundle. Nix only linker-signs the binary, and
            # fixupPhase's `strip` invalidates any signature made earlier, so
            # sign in postFixup (which runs after strip). Without this,
            # `codesign --verify --deep --strict` reports "code has no
            # resources but signature indicates they must be present".
            postFixup = ''
              /usr/bin/codesign --force --sign - \
                --identifier com.bonds.polyptych \
                $out/Applications/polyptych.app
            '';

            meta = with pkgs.lib; {
              description = "Multi-monitor video player — spans across all displays";
              homepage = "https://github.com/bonds/polyptych";
              maintainers = [ ];
              platforms = platforms.darwin;
            };
          };
        });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/polyptych";
        };
      });

      # `nix develop` then a plain `swift build -c release` works locally:
      # LIBMPV_DIR tells Package.swift where to find libmpv.2.dylib.
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          libmpv = pkgs.mpv.override { scripts = [ ]; };
        in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.swift pkgs.swiftpm libmpv ];
            LIBMPV_DIR = "${libmpv}/lib";
          };
        });
    };
}
