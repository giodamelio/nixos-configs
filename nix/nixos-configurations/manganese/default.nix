{
  pkgs,
  inputs,
  homelab,
  ezModules,
  ...
}: {
  imports = [
    inputs.colmena.nixosModules.deploymentOptions
    inputs.home-manager.nixosModules.home-manager
    inputs.ragenix.nixosModules.default

    ./disko.nix
    ./hardware.nix
    ./prometheus.nix

    ezModules.basic-packages
    ezModules.basic-settings

    # Create server user
    ({pkgs, ...}: {
      users.users.server = {
        extraGroups = ["wheel" "docker" "sound"];
        isNormalUser = true;
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = homelab.ssh_keys;
      };
      security.sudo.wheelNeedsPassword = false;
      programs.zsh.enable = true;

      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
    })

    # Autosnapshot ZFS and send to NAS
    ezModules.zfs-backup
    (_: {
      gio.services.zfs_backup = {
        enable = true;
        syncToGallium = true;
        datasets = [
          "tank/home"
          "tank/nix"
          "tank/root"
        ];
      };
    })
  ];

  # ZFS snapshot browsing
  environment.systemPackages = [pkgs.httm];

  system.stateVersion = "25.05";
}
