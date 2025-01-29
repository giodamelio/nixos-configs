{ lib, config, ... }: {
  services.prometheus = {
    exporters = {
      node = {
        enable = true;
        enabledCollectors = ["systemd"];
      };

      # Enable the ZFS exporter if zfs is used in the system
      # TODO: think of a better way to check if ZFS is used
      zfs = lib.mkIf (builtins.hasAttr "zfs" config.boot.supportedFilesystems) {
        enable = true;
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    config.services.prometheus.exporters.node.port
    config.services.prometheus.exporters.zfs.port
  ];
}
