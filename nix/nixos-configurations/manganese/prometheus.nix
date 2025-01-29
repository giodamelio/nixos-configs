{ lib, config, ... }: let 
  makeNodeExporterConfig = host: address: {
    targets = [
      "${address}:${toString config.services.prometheus.exporters.node.port}"
    ];
    labels = {
      inherit host;
    };
  };
  makeZfsExporterConfig = host: address: {
    targets = [
      "${address}:${toString config.services.prometheus.exporters.zfs.port}"
    ];
    labels = {
      inherit host;
    };
  };
in {
  services.prometheus = {
    enable = true;

    # Scrape the local prometheus
    scrapeConfigs = [
      {
        job_name = "node_exporter";
        static_configs = [
          (makeNodeExporterConfig "manganese" "127.0.0.1")
        ];
      }
      {
        job_name = "zfs";
        static_configs = [
          (makeZfsExporterConfig "manganese" "127.0.0.1")
        ];
      }
    ];
  };

  # Export some stats
  services.prometheus = {
    exporters = {
      node = {
        enable = true;
        enabledCollectors = ["systemd"];
        listenAddress = "127.0.0.1";
      };

      # Enable the ZFS exporter if zfs is used in the system
      # TODO: think of a better way to check if ZFS is used
      zfs = lib.mkIf (builtins.hasAttr "zfs" config.boot.supportedFilesystems) {
        enable = true;
      };
    };
  };

  networking.firewall.allowedTCPPorts = [9090];
}
