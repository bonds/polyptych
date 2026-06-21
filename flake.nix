{
  description = "Multi-monitor video player — spans fullscreen across all displays";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        libmpv = pkgs.mpv.override { scripts = [ ]; };
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "polyptych";
          version = "0.2.2";
          src = ./.;

          buildInputs = with pkgs; [
            swift
            swiftpm
            libmpv
          ];

          buildPhase = ''
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
          '';

          meta = with pkgs.lib; {
            description = "Multi-monitor video player";
            homepage = "https://github.com/bonds/polyptych";
            maintainers = with maintainers; [ ];
            platforms = platforms.darwin;
          };
        };

        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.default;
        };
      });
}
