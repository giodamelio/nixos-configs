{lib, ...}: let
  inherit (lib) mkOption types;
in {
  den.schema.host.imports = [
    {
      options.prometheus.enable = mkOption {
        type = types.bool;
        default = false;
        description = "Run the Prometheus scraper on this host, rendered from every service's prometheus-endpoint facet.";
      };
    }
  ];

  den.schema.fleet.imports = [
    {
      options.prometheus.extraScrapeConfigs = mkOption {
        type = types.listOf (types.attrsOf types.anything);
        default = [];
        description = ''
          Raw prometheus scrape_configs appended to the rendered ones — escape
          hatch for jobs that aren't fleet services (e.g. the unpoller exporter).
        '';
      };
    }
  ];
}
