{
  description = "Playwright test runner with browsers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs supportedSystems
          (system: f system);
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          # Wrap playwright-test so it doesn't
          # pollute PATH with its own nodejs.
          # Only the `playwright` binary is exposed.
          playwright-wrapped =
            pkgs.writeShellScriptBin "playwright" ''
              export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright-driver.browsers}"
              export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
              exec "${pkgs.playwright-test}/bin/playwright" "$@"
            '';
        in
        {
          default = pkgs.mkShell {
            packages = [
              playwright-wrapped
              pkgs.python3
            ];
          };
        }
      );
    };
}
