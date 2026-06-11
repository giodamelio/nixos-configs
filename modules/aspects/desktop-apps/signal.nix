# signal — Signal messenger (desktop + CLI). Converted from
# nix/modules/nixos/signal.nix.
_: {
  den.aspects.signal.nixos = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      signal-cli
      signal-desktop
    ];
  };
}
