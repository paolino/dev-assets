{ pkgs }:

with pkgs.python3Packages;
buildPythonPackage rec {
  pname = "markdown-graphviz";
  version = "1.5";
  pyproject = true;

  src = pkgs.fetchFromGitLab {
    owner = "rod2ik";
    repo = "mkdocs-graphviz";
    tag = version;
    hash = "sha256-5pc5RpOrDSONZcgIQMNsVxYwFyJ+PMcIt0GXDxCEyOg=";
  };

  patches = [ ];

  build-system = [ setuptools ];

  dependencies = [
    markdown
  ];

  pythonImportsCheck = [ "mkdocs_graphviz" ];

  # Tests are not available in the source code.
  doCheck = false;

  meta = {
    description = "Configurable Python markdown extension for graphviz and Mkdocs";
    homepage = "https://gitlab.com/rod2ik/mkdocs-graphviz";
    license = lib.licenses.gpl3Only;
    maintainers = [ ];
  };
}
