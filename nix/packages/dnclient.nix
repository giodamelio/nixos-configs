# Stolen from https://gitlab.com/savysound/libraries/nix/dnclient
{pkgs, ...}: let
  name = "dnclient";
  version = "v0.7.0";
  commit = "dd80fa7b";
in
  pkgs.stdenv.mkDerivation {
    inherit name version;

    # This source seems linked to a commit version so it should be stable.
    # It is closed-source, however.
    src = pkgs.fetchurl {
      url = "https://dl.defined.net/${commit}/${version}/linux/amd64/dnclient";
      sha256 = "sha256-LqApYFdN0OFv1pDQZfDNjGqi2gWa3IANB6KozvEBFKU=";
    };

    phases = ["installPhase"];

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/dnclient
      chmod +x $out/bin/dnclient
    '';

    meta = with pkgs.lib; {
      description = "Defined Networks' dnclient application";
      homepage = "https://www.defined.net";
      # this is available for other platforms...but I don't want to figure that out now
      platforms = platforms.unix;
    };
  }
