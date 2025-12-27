{pkgs}: let
  inherit (pkgs) lib;
in
  pkgs.buildGoModule rec {
    pname = "witr";
    version = "0.1.0";

    src = pkgs.fetchFromGitHub {
      owner = "pranshuparmar";
      repo = "witr";
      rev = "v${version}";
      hash = "sha256-lcWROuU7VGiiVWuCt3nT0keHKGTMyim8yOnXjYj4F44=";
    };

    vendorHash = null;

    ldflags = ["-s" "-w" "-X" "main.version=0.1.0"];

    postPatch = ''
      substituteInPlace go.mod --replace-fail 'go 1.25.5' 'go 1.25.4'
    '';

    meta = {
      description = "Why is this running";
      homepage = "https://github.com/pranshuparmar/witr";
      license = lib.licenses.asl20;
      maintainers = with lib.maintainers; [giodamelio];
      mainProgram = "witr";
    };
  }
