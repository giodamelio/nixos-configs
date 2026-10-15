# prometheus — fleet metrics server (prometheus.gio.ninja). The scrape set is
# rendered from every service's prometheus-endpoint facet (pocket-id, loki,
# miniflux, restate, gradient, immich×3, garage…); the infra exporters and
# external targets that aren't fleet services go through extraScrapeConfigs.
# unpoller (Unifi → prometheus + loki) is a carbon service. Converted from
# nix/hosts/carbon/prometheus.nix.
_: {
  den.hosts.x86_64-linux.carbon.prometheus.enable = true;

  den.aspects.carbon.nixos = {
    services.unpoller = {
      enable = true;
      unifi.controllers = [
        {
          url = "https://unifi.gio.ninja";
          verify_ssl = false;
          user = "unpoller";
          pass = "/run/credentials/unifi-poller.service/unifi_controller_unpoller_password";

          save_ids = true;
          save_events = true;
          save_alarms = true;
          save_anomalies = true;
        }
      ];
      influxdb.disable = true;
      loki.url = "http://localhost:3100";
    };

    fleet.credentials.needs = [
      "unifi_controller_unpoller_password"
      # garage's scrape job (gallium garage.nix) reads it from prometheus' credentials.
      "garage_metrics_token"
    ];
    systemd.services.unifi-poller.serviceConfig.LoadCredentialEncrypted = ["unifi_controller_unpoller_password"];
    systemd.services.prometheus.serviceConfig.LoadCredentialEncrypted = ["garage_metrics_token"];
  };

  den.hosts.x86_64-linux.carbon.services.prometheus = {
    endpoint = {
      domain = "prometheus";
      backend.host = "localhost";
      backend.port = 9090;
    };
    healthcheck.target = "https://prometheus.gio.ninja/-/healthy";
  };

  # Non-service jobs: host exporters (node/zfs/postgres/comin from send-metrics),
  # consul agent metrics, the unpoller exporter, and the immich job-stats relay
  # through windmill. Service jobs come from prometheus-endpoint facets.
  fleet.prometheus.extraScrapeConfigs = [
    {
      job_name = "node";
      static_configs = [
        {
          targets = ["localhost:9000"];
          labels.host = "carbon";
        }
        {
          targets = ["gallium.gio.ninja:9000"];
          labels.host = "gallium";
        }
      ];
    }
    {
      job_name = "zfs";
      static_configs = [
        {
          targets = ["localhost:9134"];
          labels.host = "carbon";
        }
        {
          targets = ["gallium.gio.ninja:9134"];
          labels.host = "gallium";
        }
      ];
    }
    {
      job_name = "postgres";
      static_configs = [
        {
          targets = ["localhost:9187"];
          labels.host = "carbon";
        }
        {
          targets = ["gallium.gio.ninja:9187"];
          labels.host = "gallium";
        }
      ];
    }
    {
      job_name = "unpoller";
      static_configs = [{targets = ["localhost:9130"];}];
    }
    {
      job_name = "consul";
      metrics_path = "/v1/agent/metrics";
      params.format = ["prometheus"];
      static_configs = [
        {
          targets = ["consul.gio.ninja"];
          labels.host = "carbon";
        }
      ];
    }
    {
      job_name = "comin";
      static_configs = [
        {
          targets = ["localhost:4243"];
          labels.host = "carbon";
        }
        {
          targets = ["gallium.gio.ninja:4243"];
          labels.host = "gallium";
        }
      ];
    }
    {
      # immich job-stats relayed through a windmill flow. The bearer is a windmill
      # API token (inline as in Blueprint; move to a credential later).
      job_name = "immich_jobs";
      scheme = "https";
      metrics_path = "/api/w/main/jobs/run_wait_result/p/u/gio/convert_immich_job_stats_to_prometheus";
      static_configs = [{targets = ["windmill.gio.ninja"];}];
      authorization = {
        type = "Bearer";
        credentials = "tmoxuQTiIE4WRICfHsSAJ9uO7niEBNsY";
      };
    }
  ];
}
