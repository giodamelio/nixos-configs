{root, ...}: {config, ...}: {
  imports = [
    root.nixosModules.services.sanoid
  ];

  config = {
    gio.services.zfs_backup = {
      enable = true;
      datasets = [
        "tank/home"
        "tank/nix"
        "tank/root"
      ];
    };
  };
}
