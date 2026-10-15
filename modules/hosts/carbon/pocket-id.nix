# pocket-id — the fleet OIDC provider (login.gio.ninja). The encryption key MUST
# keep its existing value: it encrypts the restored pocket-id DB.
_: {
  den.aspects.carbon.nixos = {
    services.pocket-id = {
      enable = true;
      settings = {
        APP_URL = "https://login.gio.ninja";
        TRUST_PROXY = true;
        ENCRYPTION_KEY_FILE = "/run/credentials/pocket-id.service/pocket_id_encryption_key";
        ANALYTICS_DISABLED = true;

        METRICS_ENABLED = true;
        OTEL_METRICS_EXPORTER = "prometheus";
        OTEL_EXPORTER_PROMETHEUS_HOST = "0.0.0.0";
        OTEL_EXPORTER_PROMETHEUS_PORT = 9464;
      };
    };

    fleet.credentials.needs = ["pocket_id_encryption_key"];
    systemd.services.pocket-id.serviceConfig.LoadCredentialEncrypted = ["pocket_id_encryption_key"];
  };

  den.hosts.x86_64-linux.carbon.services.pocket-id = {
    endpoint = {
      domain = "login";
      backend.host = "localhost";
      backend.port = 1411;
    };
    healthcheck.target = "https://login.gio.ninja/health";
    "prometheus-endpoint".target = "localhost:9464";
  };
}
