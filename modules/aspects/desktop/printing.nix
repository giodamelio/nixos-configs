# printing — CUPS with HP drivers. Converted from nix/modules/nixos/printing.nix.
_: {
  den.aspects.printing.nixos = {pkgs, ...}: {
    services.printing = {
      enable = true;
      drivers = [pkgs.hplip];
    };
  };
}
