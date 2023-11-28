{
  homelab,
  root,
  inputs,
  ...
}: {
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    # Software for a minimal installer
    "${inputs.nixpkgs}/nixos/modules/profiles/base.nix"
    "${inputs.nixpkgs}/nixos/modules/profiles/all-hardware.nix"
    "${inputs.nixpkgs}/nixos/modules/profiles/installation-device.nix"
  ];

  config = {
    # Enable flakes
    nix.settings.experimental-features = ["nix-command" "flakes"];

    # This enables some drivers that all-hardware.nix doesn't
    virtualisation.hypervGuest.enable = true;

    # Print the ip address at shell entrance
    environment.etc."issue.d/00-ip.issue".text = "IP Address: \\4\n\n";

    # Enable ssh and set keys for both users
    users.users.root = {
      openssh.authorizedKeys.keys = homelab.ssh_keys;
    };
    users.users.nixos = {
      openssh.authorizedKeys.keys = homelab.ssh_keys;
    };
  };
}
