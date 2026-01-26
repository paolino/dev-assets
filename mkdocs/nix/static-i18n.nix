{ pkgs }:

with pkgs.python3Packages;
buildPythonPackage rec {
  pname = "mkdocs-static-i18n";
  version = "1.3.0";

  src = pkgs.fetchurl {
    url = "https://files.pythonhosted.org/packages/03/2b/59652a2550465fde25ae6a009cb6d74d0f7e724d272fc952685807b29ca1/mkdocs_static_i18n-1.3.0.tar.gz";
    hash = "sha256-ZXMeHk7G1xlpPiT+6TQPVRZGCytyRNKom+1M48+moXM=";
  };
  format = "pyproject";
  propagatedBuildInputs = [ mkdocs mkdocs-material ];
  buildInputs = [ hatchling ];
  doCheck = false;
  meta = with pkgs.lib; {
    description = "MkDocs plugin for multi-language static site generation";
  };
}
