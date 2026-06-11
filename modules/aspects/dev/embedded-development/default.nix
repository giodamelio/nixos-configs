# embedded-development — udev rules for probe-rs debug probes. Converted from
# nix/modules/nixos/embedded-development/. The rules file lives beside this one;
# src = ./. mirrors the original module's layout.
_: {
  den.aspects.embedded-development.nixos = {pkgs, ...}: let
    probe-rs-udev-rules = pkgs.stdenv.mkDerivation {
      name = "probe-rs-udev-rules";
      src = ./.;
      installPhase = ''
        mkdir -p $out/lib/udev/rules.d
        cp 69-probe-rs.rules $out/lib/udev/rules.d/
      '';
    };
  in {
    services.udev.packages = [probe-rs-udev-rules];
  };
}
