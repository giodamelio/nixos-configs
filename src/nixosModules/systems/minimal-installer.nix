{homelab, ...}: {
  config,
  lib,
  pkgs,
  ...
}: {
  config = {
    environment.etc."issue.d/ip.issue".text = "\\4{eth0}\n";
    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
      trusted-users = ["root" "@wheel"];
    };
    security.sudo.wheelNeedsPassword = false;
    services.openssh.enable = true;
    users.users.root = {
      openssh.authorizedKeys.keys = homelab.ssh_keys;
    };
    users.users.nixos = {
      extraGroups = ["wheel"];
      openssh.authorizedKeys.keys = homelab.ssh_keys;
    };
  };
}
