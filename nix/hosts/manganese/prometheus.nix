{config, ...}: let
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
          (makeNodeExporterConfig "manganese" "manganese.h.gio.ninja")
          (makeNodeExporterConfig "cadmium" "cadmium.h.gio.ninja")
          (makeNodeExporterConfig "lithium1" "lithium1.h.gio.ninja")
        ];
      }
      {
        job_name = "zfs";
        static_configs = [
          (makeZfsExporterConfig "manganese" "manganese.h.gio.ninja")
          (makeZfsExporterConfig "cadmium" "cadmium.h.gio.ninja")
        ];
      }
    ];
  };

  networking.firewall.allowedTCPPorts = [9090];
}
