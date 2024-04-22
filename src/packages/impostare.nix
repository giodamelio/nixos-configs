_: {pkgs, ...}: let
  inherit (pkgs) lib;
in
  pkgs.rustPlatform.buildRustPackage rec {
    pname = "impostare";
    version = "0.1.0";

    src = pkgs.fetchFromGitHub {
      owner = "giodamelio";
      repo = "impostare";
      rev = "v${version}";
      hash = "sha256-uXCUp7feIqdn3a/59ueHBY4erfbCMy/gMFFAKeRRPIg=";
    };

    cargoHash = "sha256-+GCZM0YoRM+0XqlX9cZwY1LjWTBWD2zW4AQgst86jck=";

    buildInputs = lib.optionals pkgs.stdenv.isDarwin [
      pkgs.darwin.apple_sdk.frameworks.CoreFoundation
      pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
    ];

    meta = with lib; {
      description = "";
      homepage = "https://github.com/giodamelio/impostare";
      license = licenses.unfree; # FIXME: nix-init did not found a license
      maintainers = with maintainers; [giodamelio];
      mainProgram = "impostare";
    };
  }
