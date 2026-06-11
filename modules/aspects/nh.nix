# nh — the nh Nix helper, system level. Converted from nix/modules/nixos/nh.nix.
_: {
  den.aspects.nh.nixos = {
    programs.nh = {
      enable = true;
      flake = "/home/giodamelio/nixos-configs";
    };
  };
}
