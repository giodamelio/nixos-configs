_: {
  pkgs,
  lib,
  config,
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
  };
}
