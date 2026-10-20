{ pkgs
, lib ? pkgs.lib
}:
{ pname
, version
  # the commands, each at ${drv}/bin/<name>; the helper bundles them and their
  # dylibs itself. Not needed when bundleTarball is given.
, executables ? { }
  # an already assembled, relocatable tarball with one top directory holding
  # bin/<name> for every name in executableNames (launchers, libraries, data:
  # whatever the product needs). It becomes the release tarball byte for byte,
  # and the formula installs the whole folder under libexec and links the
  # commands into bin.
, bundleTarball ? null
, owner
, repo ? pname
, executableNames ? builtins.attrNames executables
, artifactVersion ? version
, releaseTag ? "v${version}"
, artifactName ? "${pname}-${artifactVersion}-${pkgs.stdenv.hostPlatform.system}.tar.gz"
, desc
, homepage ? "https://github.com/${owner}/${repo}"
, formulaName ? pname
, formulaClass
, formulaVersion ? artifactVersion
, formulaExtraLines ? ""
, formulaTest ? null
, smokeCommands ? [ "${builtins.head executableNames} --help" ]
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  releaseUrl =
    "https://github.com/${owner}/${repo}/releases/download/${releaseTag}/${artifactName}";
  formulaFile = "${formulaName}.rb";
  rubyString = builtins.toJSON;
  binInstallArgs =
    lib.concatMapStringsSep ", " (name: rubyString "bin/${name}") executableNames;
  defaultFormulaTest = lib.concatMapStringsSep "\n"
    (name: "    assert_predicate bin/${rubyString name}, :executable?")
    executableNames;
  formulaTestBody =
    if formulaTest == null then defaultFormulaTest else formulaTest;
  copyExecutableCommands = lib.concatMapStringsSep "\n"
    (name: ''
      copy_executable ${lib.escapeShellArg name} ${lib.escapeShellArg "${executables.${name}}/bin/${name}"}
    '')
    executableNames;
  bundleSmokeCommands = lib.concatMapStringsSep "\n"
    (command: "    ${command}")
    smokeCommands;
  prebuilt = bundleTarball != null;
  formulaInstallLines =
    if prebuilt then [
      ''libexec.install Dir["*"]''
      "bin.install_symlink ${lib.concatMapStringsSep ", " (name: "libexec/${rubyString "bin/${name}"}") executableNames}"
    ]
    else [
      "bin.install ${binInstallArgs}"
      ''(libexec/"lib").install Dir["libexec/lib/*"]''
    ];
  formulaInstall = lib.concatMapStringsSep "\n" (line: "    ${line}") formulaInstallLines;
  checkPrebuiltCommands = lib.concatMapStringsSep "\n"
    (name: ''test -x "$top/bin/${name}" || { echo ${lib.escapeShellArg "bundleTarball has no bin/${name}"} >&2; exit 1; }'')
    executableNames;
  # the helper's own bundle: the commands and their dylibs, load paths rewritten
  assembledSteps = ''
    ${copyExecutableCommands}

    while [ -s "$queue" ]; do
      lib="$(head -n 1 "$queue")"
      tail -n +2 "$queue" > "$queue.next"
      mv "$queue.next" "$queue"
      copy_dylib "$lib"
    done

    export PATH="$bundle/bin:$PATH"
${bundleSmokeCommands}

    tarball="$out/${artifactName}"
    tar --sort=name \
      --mtime='@1' \
      --owner=0 \
      --group=0 \
      --numeric-owner \
      -cf - \
      -C "$bundle" . \
      | gzip -n > "$tarball"
  '';
  # the tarball the caller assembled: one top directory with every command in
  # bin/, smoke-tested from its unpacked form, then shipped as it is
  prebuiltSteps = ''
    unpacked="$TMPDIR/unpacked"
    mkdir -p "$unpacked"
    tar -xzf ${bundleTarball} -C "$unpacked"
    top="$(find "$unpacked" -mindepth 1 -maxdepth 1)"
    if [ "$(printf '%s\n' "$top" | wc -l | tr -d ' ')" -ne 1 ] || [ ! -d "$top" ]; then
      echo "bundleTarball must hold exactly one top directory, it holds: $top" >&2
      exit 1
    fi
    ${checkPrebuiltCommands}
    export PATH="$top/bin:$PATH"
${bundleSmokeCommands}

    tarball="$out/${artifactName}"
    cp ${bundleTarball} "$tarball"
    chmod u+w "$tarball"
  '';
in
assert pkgs.stdenv.isDarwin;
assert prebuilt || executables != { };
assert executableNames != [ ];
pkgs.runCommand "${formulaName}-${artifactVersion}-${system}-artifacts"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.darwin.cctools
      pkgs.gnutar
      pkgs.gzip
      pkgs.jq
    ];
    passthru = {
      inherit artifactName executableNames formulaName formulaFile releaseTag releaseUrl;
    };
    meta = {
      description = "Darwin release tarball and Homebrew formula for ${pname}";
      platforms = lib.platforms.darwin;
    };
  }
  ''
    set -euo pipefail

    bundle="$TMPDIR/bundle"
    queue="$TMPDIR/dylib-queue"
    seen="$TMPDIR/dylib-seen"

    mkdir -p "$bundle/bin" "$bundle/libexec/lib" "$out"
    : > "$queue"
    : > "$seen"

    list_non_system_dylibs() {
      otool -L "$1" \
        | awk 'NR > 1 { print $1 }' \
        | while IFS= read -r lib; do
          case "$lib" in
            "" | /usr/lib/* | /System/* | @*)
              ;;
            *)
              printf '%s\n' "$lib"
              ;;
          esac
        done
    }

    queue_dylib() {
      lib="$1"
      if ! grep -Fxq "$lib" "$seen"; then
        printf '%s\n' "$lib" >> "$seen"
        printf '%s\n' "$lib" >> "$queue"
      fi
    }

    patch_loads() {
      binary="$1"
      replacement_prefix="$2"
      own_install_name="''${3:-}"

      list_non_system_dylibs "$binary" | while IFS= read -r lib; do
        if [ -n "$own_install_name" ] && [ "$lib" = "$own_install_name" ]; then
          continue
        fi

        libname="$(basename "$lib")"
        queue_dylib "$lib"
        install_name_tool \
          -change "$lib" "$replacement_prefix/$libname" \
          "$binary"
      done
    }

    copy_executable() {
      name="$1"
      src="$2"
      target="$bundle/bin/$name"

      if [ ! -x "$src" ]; then
        echo "missing executable: $name at $src" >&2
        exit 1
      fi

      cp -L "$src" "$target"
      chmod u+w "$target"
      patch_loads "$target" "@executable_path/../libexec/lib"
      otool -L "$target"
    }

    copy_dylib() {
      lib="$1"
      libname="$(basename "$lib")"
      target="$bundle/libexec/lib/$libname"

      if [ ! -f "$target" ]; then
        cp -L "$lib" "$target"
        chmod u+w "$target"
      fi

      install_name_tool -id "@loader_path/$libname" "$target"
      patch_loads "$target" "@loader_path" "$lib"
    }

    ${if prebuilt then prebuiltSteps else assembledSteps}

    sha="$(sha256sum "$tarball" | cut -d' ' -f1)"
    printf '%s  %s\n' "$sha" "${artifactName}" > "$out/SHA256SUMS"

    jq -n \
      --arg pname ${lib.escapeShellArg pname} \
      --arg version ${lib.escapeShellArg version} \
      --arg artifactVersion ${lib.escapeShellArg artifactVersion} \
      --arg system ${lib.escapeShellArg system} \
      --arg artifact ${lib.escapeShellArg artifactName} \
      --arg formula ${lib.escapeShellArg formulaFile} \
      --arg releaseTag ${lib.escapeShellArg releaseTag} \
      --arg url ${lib.escapeShellArg releaseUrl} \
      --arg sha256 "$sha" \
      '{
        pname: $pname,
        version: $version,
        artifactVersion: $artifactVersion,
        system: $system,
        artifact: $artifact,
        formula: $formula,
        releaseTag: $releaseTag,
        url: $url,
        sha256: $sha256
      }' > "$out/release-metadata.json"

    cat > "$out/${formulaFile}" <<EOF
class ${formulaClass} < Formula
  desc ${rubyString desc}
  homepage ${rubyString homepage}
  url ${rubyString releaseUrl}
  sha256 "$sha"
  version ${rubyString formulaVersion}
${formulaExtraLines}

  def install
${formulaInstall}
  end

  test do
${formulaTestBody}
  end
end
EOF

    ls -lh "$out"
  ''
