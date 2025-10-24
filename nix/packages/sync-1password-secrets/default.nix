{pkgs, ...}: let
  inherit (pkgs) lib;

  onepassword-sdk-python = pkgs.python3.pkgs.buildPythonPackage rec {
    pname = "onepassword-sdk-python";
    version = "0.3.1";
    pyproject = true;

    src = pkgs.fetchFromGitHub {
      owner = "1Password";
      repo = "onepassword-sdk-python";
      rev = "v${version}";
      hash = "sha256-nPJEtBztF+e+gcgY3+4u6CK6h9QDzqw1OhAqX0PaaAQ=";
    };

    build-system = [
      pkgs.python3.pkgs.setuptools
      pkgs.python3.pkgs.wheel
    ];

    propagatedBuildInputs = with pkgs.python3.pkgs; [
      pydantic
    ];

    pythonImportsCheck = [
      "onepassword"
    ];

    meta = {
      description = "";
      homepage = "https://github.com/1Password/onepassword-sdk-python";
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [giodamelio];
    };
  };
in
  pkgs.writers.writePython3Bin "sync-1password-secrets" {
    libraries = with pkgs.python3.pkgs; [
      pwinput
      onepassword-sdk-python
    ];
  } (builtins.readFile ./sync-1password-secrets.py)
