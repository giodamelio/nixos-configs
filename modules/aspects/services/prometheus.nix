{
  lib,
  config,
  ...
}: let
  inherit (import ./_types.nix {inherit lib;}) scrapeConfigsOf;
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;
in {
  # Renders the Prometheus scraper from every service's prometheus-endpoint facet
  # (grouped by job). Self-gates on host.prometheus.enable. Targets are taken
  # verbatim from the facet — nothing is auto-derived or auto-discovered; a service
  # is only scraped if it explicitly declared an endpoint. Non-service jobs go
  # through fleet.prometheus.extraScrapeConfigs.
  den.aspects.services-prometheus.nixos = {
    host,
    fleet,
    lib,
    ...
  }:
    lib.mkIf host.prometheus.enable {
      services.prometheus = {
        enable = true;
        checkConfig = "syntax-only";
        scrapeConfigs = scrapeConfigsOf denHosts ++ fleet.prometheus.extraScrapeConfigs;
      };
    };
}
