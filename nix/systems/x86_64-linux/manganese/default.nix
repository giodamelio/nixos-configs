{pkgs, ...}: {
  imports = [
    ./hardware.nix
    ./disko.nix
  ];

  snowfallorg.users.server = {
    create = true;
    admin = true;
    home.enable = true;
  };

  users.users.server = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOKmSxFyT9n91A9dOpSCfl9kJj80KWFA6UvCtguT4S5b giodamelio@cadmium"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # Automatically create ZFS snapshots
  services.sanoid = {
    enable = true;

    datasets = let
      defaultSnapshotSettings = {
        hourly = 48;
        daily = 32;
        monthly = 8;
        yearly = 8;

        autosnap = true;
        autoprune = true;
      };
    in {
      "tank/root" = defaultSnapshotSettings;
      "tank/nix" = defaultSnapshotSettings;
      "tank/home" = defaultSnapshotSettings;
    };
  };

  # ZFS snapshot browsing
  environment.systemPackages = [pkgs.httm];

  system.stateVersion = "25.05";
}
