{
  homelab,
  root,
  ...
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  system-info = root.packages.system-info {inherit pkgs;};
in {
  config = {
    # Enable flakes and add all users in wheel group to the Nix list of trusted users
    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
      trusted-users = ["root" "@wheel"];
    };

    # Print the ip address at shell entrance
    environment.etc."issue.d/00-ip.issue".text = "IP Address: \\4\n\n";

    # Enable ssh and set keys for both users
    services.openssh.enable = true;
    users.users.root = {
      openssh.authorizedKeys.keys = homelab.ssh_keys;
    };
    users.users.nixos = {
      extraGroups = ["wheel"];
      openssh.authorizedKeys.keys = homelab.ssh_keys;
    };

    # Make sudo not need a password
    security.sudo.wheelNeedsPassword = false;

    # Install some scripts to that can upload system info for bootstrapping purposes
    environment.systemPackages = with system-info; [list-system-info upload-system-info];

    # SystemD unit that will run the system info upload on boot
    systemd.services.upload-system-info = {
      description = "Upload system information to ix.io on boot";
      before = ["getty.target"];
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = "${system-info.upload-system-info}/bin/upload-system-info";
    };
  };
}
