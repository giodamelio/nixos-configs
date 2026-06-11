# wifi — NetworkManager for the desktop/laptop hosts. Converted from
# nix/modules/nixos/wifi.nix.
_: {
  den.aspects.wifi.nixos = {
    networking.networkmanager.enable = true;
  };
}
