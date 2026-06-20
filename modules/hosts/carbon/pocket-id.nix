# pocket-id — the fleet OIDC provider (login.gio.ninja). The encryption key moves
# from gio.credentials to a fleet.secrets credential on pocket-id.service; the
# ENCRYPTION_KEY_FILE path is unchanged. It MUST keep its existing value (it
# encrypts the pocket-id DB), so it's a manual secret pasted via `credsync write`.
# The caddy cloudflare token is handled by the den reverse-proxy aspect, not here.
# Converted from nix/hosts/carbon/pocket-id.nix.
_: {
  den.aspects.carbon.nixos = {
    services.pocket-id = {
      enable = true;
      settings = {
        APP_URL = "https://login.gio.ninja";
        TRUST_PROXY = true;
        ENCRYPTION_KEY_FILE = "/run/credentials/pocket-id.service/pocket-id-encryption-key";
        ANALYTICS_DISABLED = true;

        METRICS_ENABLED = true;
        OTEL_METRICS_EXPORTER = "prometheus";
        OTEL_EXPORTER_PROMETHEUS_HOST = "0.0.0.0";
        OTEL_EXPORTER_PROMETHEUS_PORT = 9464;
      };
    };
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

  fleet.secrets.pocket-id-encryption-key = {
    origin = "carbon";
    use.carbon.services.pocket-id.type = "credential";
  };
}
