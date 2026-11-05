_: {
  perSystem = {pkgs, ...}: let
    inherit (pkgs) lib;
  in {
    packages.gh-pin-actions = pkgs.buildGoModule rec {
      pname = "gh-pin-actions";
      version = "0.1.0";

      src = pkgs.fetchFromGitHub {
        owner = "amenocal";
        repo = "gh-pin-actions";
        rev = "v${version}";
        hash = "sha256-Nq5qekVF/U/C90f/yymp43Rs6iiKZ8hs2APWougoAFw=";
      };

      vendorHash = "sha256-h5Qa7+OstZYZlmu1uMsvo3t6iifn5gT5lNDpXlCF1K4=";

      ldflags = ["-s" "-w"];

      meta = {
        description = "GitHub CLI extension to pin actions to commit SHAs based on their version";
        homepage = "https://github.com/amenocal/gh-pin-actions";
        license = lib.licenses.mit;
        mainProgram = "gh-pin-actions";
      };
    };
  };
}
