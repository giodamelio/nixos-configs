{lib, ...}: let
  inherit (lib) mkOption types;
in {
  den.schema.fleet.imports = [
    {
      options.backups.zfs = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = {};
        example = {carbon = ["bowl/postgresql"];};
        description = ''
          ZFS datasets each host snapshots with sanoid and replicates to
          gallium's tank/backups/<host>/<dataset>. The sender needs the
          zfs-backup aspect; gallium creates the receiving parents.
        '';
      };
    }
  ];
}
