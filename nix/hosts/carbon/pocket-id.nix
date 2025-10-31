{
  services.pocket-id = {
    enable = true;

    settings = {
      APP_URL = "https://login.gio.ninja";
      TRUST_PROXY = true;
      # TODO: hardcoding this is probably a bad idea
      # See: https://github.com/pocket-id/pocket-id/pull/799#issuecomment-3134806588
      # Maybe I can use mount path or something to make it work
      # ENCRYPTION_KEY_FILE = "\${CREDENTIALS_DIRECTORY}/pocket-id-encryption-key";
      ENCRYPTION_KEY_FILE = "/run/credentials/pocket-id.service/pocket-id-encryption-key";
      ANALYTICS_DISABLED = true;

      METRICS_ENABLED = true;
      OTEL_METRICS_EXPORTER = "prometheus";
      OTEL_EXPORTER_PROMETHEUS_HOST = "0.0.0.0";
      OTEL_EXPORTER_PROMETHEUS_PORT = 9464;
    };
  };

  # Load the encrypted encryption key
  systemd.services.pocket-id.serviceConfig = {
    LoadCredentialEncrypted = "pocket-id-encryption-key:/var/lib/credstore/pocket-id-encryption-key";
  };

  # Setup Caddy as a reverse proxy
  systemd.services.caddy.serviceConfig = {
    LoadCredentialEncrypted = [
      "caddy-cloudflare-api-token:/var/lib/credstore/caddy-cloudflare-api-token"
    ];
    Environment = [
      "CLOUDFLARE_API_TOKEN_FILE=%d/caddy-cloudflare-api-token"
    ];
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "login" = {
        host = "localhost";
        port = 1411;
      };
    };
  };
}
