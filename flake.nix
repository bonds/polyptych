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
        in
        {
          default = pkgs.stdenv.mkDerivation {
            pname = "polyptych";
            version = "0.3.0";
            src = self;

          buildInputs = with pkgs; [
            swift
            swiftpm
            libmpv
            zip
          ];

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
              mkdir -p $out/bin
              ln -s $out/Applications/polyptych.app/Contents/MacOS/polyptych \
                $out/bin/polyptych

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
                --replace-fail '@polyptych_bin@' "$out/bin/polyptych"
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
    };
}
