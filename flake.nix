{
  description = "attached — development environment";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
  outputs = { nixpkgs, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      devShells = forAllSystems (pkgs: let
        mkShell = elixir: pkgs.mkShell {
          buildInputs = [
            elixir
            pkgs.vips
            pkgs.imagemagick
            pkgs.ffmpeg_7
            pkgs.poppler-utils
            pkgs.mupdf
            pkgs.epub-thumbnailer
            pkgs.pandoc
            # S3 integration tests (mix test --only integration). Garage instead
            # of MinIO: nixpkgs marks minio as insecure (unpatched 2026 CVEs,
            # community edition unmaintained).
            pkgs.garage
          ];

          shellHook = ''
            mkdir -p .nix/mix .nix/hex
            export HEX_HOME=$PWD/.nix/hex MIX_HOME=$PWD/.nix/mix
            export PATH=$MIX_HOME/bin:$HEX_HOME/bin:$PATH
          '';
        };
      in {
        default = mkShell pkgs.beam29Packages.elixir_1_20;
        # Used by CI to test against the previous Elixir release.
        # Elixir 1.19 supports OTP 26-28, so it gets the OTP 28 package set.
        # Use: nix develop .#elixir119 --command mix test
        elixir119 = mkShell pkgs.beam28Packages.elixir_1_19;
      });
    };
}
