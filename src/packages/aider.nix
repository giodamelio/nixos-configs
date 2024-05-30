{inputs, ...}: {pkgs, ...}:
inputs.dream2nix.lib.evalModules {
  packageSets.nixpkgs = pkgs;
  modules = [
    inputs.dream2nix.modules.dream2nix.pip
    (
      _: rec {
        deps = {nixpkgs, ...}: {
          python = nixpkgs.python311;
        };

        name = "aider";
        version = "0.36.0";

        mkDerivation = {
          src = pkgs.fetchFromGitHub {
            owner = "paul-gauthier";
            repo = "aider";
            rev = "v${version}";
            hash = "sha256-v5/QQsKy4bwu0/12ExxqWaSh2Ktj76MlqSDifAWDHhM=";
          };
        };

        buildPythonPackage = {
          pythonImportsCheck = [
            "aider"
          ];
        };

        pip = {
          pypiSnapshotDate = "2024-05-15";
          flattenDependencies = true;
          requirementsFiles = [
            "requirements.txt"
          ];
        };

        paths.lockFile = "aider-lock.json";
        paths.projectRoot = ./.;
        paths.package = ./.;
      }
    )
  ];
}
