# monitoring — Prometheus node (+ ZFS when present) exporters with their
# firewall ports opened. Converted from nix/modules/nixos/monitoring.nix.
_: {
  den.aspects.monitoring.nixos = {
    lib,
    config,
    ...
  }: {
    services.prometheus = {
      exporters = {
        node = {
          enable = true;
          # The nixpkgs default, pinned: telemetry-agent would otherwise move it to 9000.
          port = 9100;
          enabledCollectors = ["systemd"];
        };

        # Enable the ZFS exporter if zfs is used in the system
        # TODO: think of a better way to check if ZFS is used
        zfs = lib.mkIf (builtins.hasAttr "zfs" config.boot.supportedFilesystems) {
          enable = true;
          extraFlags = [
            "--collector.dataset-snapshot"
          ];
        };
      };
    };

    networking.firewall.allowedTCPPorts = [
      config.services.prometheus.exporters.node.port
      config.services.prometheus.exporters.zfs.port
    ];
  };
}
