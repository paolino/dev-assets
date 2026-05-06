# Nix library

## mkDarwinHomebrewBundle

`mkDarwinHomebrewBundle` packages macOS command-line tools into a
deterministic tarball and generates the matching Homebrew formula.

The caller provides project metadata and an attribute set of executable
packages. The derivation copies each executable, follows non-system
dynamic library dependencies with `otool`, rewrites Mach-O load paths
with `install_name_tool`, writes `SHA256SUMS`, and emits:

- `<pname>-<artifactVersion>-<system>.tar.gz`
- `<formulaName>.rb`
- `SHA256SUMS`
- `release-metadata.json`

Example:

```nix
inputs.dev-assets.url = "github:paolino/dev-assets";

packages.aarch64-darwin.my-release-artifacts =
  inputs.dev-assets.lib.mkDarwinHomebrewBundle { inherit pkgs; } {
    pname = "my-tool";
    version = "1.2.3";
    owner = "example";
    desc = "Example command-line tools";
    formulaClass = "MyTool";
    executables = {
      "my-tool" = myTool;
      "helper-tool" = helperTool;
    };
    executableNames = [ "my-tool" "helper-tool" ];
    formulaTest = ''
      assert_predicate bin/"helper-tool", :executable?
      system "#{bin}/my-tool", "--help"
    '';
  };
```
