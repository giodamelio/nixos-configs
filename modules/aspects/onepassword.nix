# onepassword — 1Password CLI + the sync-1password-secrets helper. Converted
# from nix/modules/nixos/onepassword.nix; the repo's own package is reached as
# `perSystem.self` (module arg from the per-system aspect).
_: {
  den.aspects.onepassword.nixos = {perSystem, ...}: let
    inherit (perSystem.self) sync-1password-secrets;
  in {
    # Password manager
    programs._1password = {
      enable = true;
    };

    environment.systemPackages = [
      sync-1password-secrets
    ];
  };
}
