{ pkgs }:

with pkgs.python3Packages;
buildPythonPackage rec {
  pname = "mkdocs-markdown-callouts";
  version = "0.4.0"; # Latest from PyPI (2025)

  # Fetch the exact tar.gz from PyPI (bypasses fetchPypi filename issue)
  src = pkgs.fetchurl {
    url = "https://files.pythonhosted.org/packages/87/73/ae5aa379f6f7fea9d0bf4cba888f9a31d451d90f80033ae60ae3045770d5/markdown_callouts-0.4.0.tar.gz";
    hash = "sha256-ftLJBIaWcFinOlR3gRIZg4OVItZwQa5SxJeWFvGyt0Y="; # Verified hash for this exact file
  };
  format = "pyproject"; # THIS IS THE KEY LINE
  # No additional dependencies beyond mkdocs (per PyPI metadata)
  propagatedBuildInputs = [ mkdocs ];
  buildInputs = [ hatchling ];
  postUnpack = '''';
  doCheck = false; # No tests in the package
  meta = with pkgs.lib; {
    description = "MkDocs plugin for callouts";
  };
}
