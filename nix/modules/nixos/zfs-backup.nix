{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.gio.services.zfs_backup;
in {
  options.gio.services.zfs_backup = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Small module to allow easy auto creation/pushing of ZFS snapshots
      '';
    };

    syncToGallium = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Sync the backups to gallium
      '';
    };

    makeRecvUser = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Make a user to recieve the syncs
      '';
    };

    datasets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        List of datasets to backup
      '';
    };
  };

  config = let
    default_schedule = {
      hourly = 48;
      daily = 32;
      monthly = 8;
      yearly = 8;

      autosnap = true;
      autoprune = true;
    };
  in {
    services.sanoid = lib.mkIf cfg.enable {
      enable = true;

      datasets = lib.attrsets.genAttrs cfg.datasets (_: default_schedule);
    };

    # Change this once we get backup syncing working again
    # services.syncoid = lib.mkIf cfg.syncToGallium {
    services.syncoid = lib.mkIf false {
      enable = true;

      # Load the SSH key from a SystemD credential
      service = {
        serviceConfig.LoadCredentialEncrypted = "syncoid-ssh-key";
      };

      commonArgs = [
        "--sshoption"
        "StrictHostKeyChecking=no"
      ];

      commands = lib.attrsets.genAttrs cfg.datasets (dataset: {
        target = "syncoid-recv@gallium.gio.ninja:tank/backup/${config.networking.hostName}/${dataset}";
        sshKey = "\${CREDENTIALS_DIRECTORY}/syncoid-ssh-key";
      });
    };

    environment.systemPackages = lib.mkIf cfg.makeRecvUser [pkgs.mbuffer pkgs.lzop];
    users = lib.mkIf cfg.makeRecvUser {
      users.syncoid-recv = {
        isSystemUser = true;
        group = "syncoid-recv";
        extraGroups = [
          "wheel"
        ];
        shell = pkgs.bashInteractive;
        openssh.authorizedKeys.keys = [
          # Private half is in secrets/common/syncoid-ssh-key.age
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMglSONdnmfp0s3fgWmPKdLD7gnhdRmMI0Grgzac77u5"
        ];
      };
      groups.syncoid-recv = {};
    };
  };
}
