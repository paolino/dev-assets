{ pkgs }:

with pkgs.python3Packages;
buildPythonPackage rec {
  pname = "mkdocs-asciinema-player";
  version = "0.18.0"; # Latest from PyPI (2025)

  # Fetch the exact tar.gz from PyPI (bypasses fetchPypi filename issue)
  src = pkgs.fetchurl {
    url = "https://files.pythonhosted.org/packages/4c/5b/00c3ff59e7ad8f2611035073ea2231e3797858de1d25a65c33d7ad69e9bd/mkdocs_asciinema_player-0.18.0.tar.gz";
    hash = "sha256-VCLQm/vDaXuVNAz+ikHENdgUukjuArqNDtzVLrJ58Gg="; # Verified hash for this exact file
  };
  format = "pyproject"; # THIS IS THE KEY LINE
  # No additional dependencies beyond mkdocs (per PyPI metadata)
  propagatedBuildInputs = [ mkdocs ];
  buildInputs = [ poetry-core ];
  postUnpack = '''';
  patches = [ ./asciinema-plugin.patch ];
  doCheck = false; # No tests in the package
  meta = with pkgs.lib; {
    description = "MkDocs plugin for embedding asciinema players in documentation";
    homepage = "https://github.com/aneziac/mkdocs-asciinema-player";
    license = licenses.mit;
  };
}
