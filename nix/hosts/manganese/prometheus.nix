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
          (makeNodeExporterConfig "manganese" "127.0.0.1")
          (makeNodeExporterConfig "cadmium" "10.0.128.125")
        ];
      }
      {
        job_name = "zfs";
        static_configs = [
          (makeZfsExporterConfig "manganese" "127.0.0.1")
          (makeZfsExporterConfig "cadmium" "10.0.128.125")
        ];
      }
    ];
  };

  networking.firewall.allowedTCPPorts = [9090];
}
