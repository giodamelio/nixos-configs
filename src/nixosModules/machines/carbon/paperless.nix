_: {config, ...}: {
  environment.systemPackages = [];

  services.paperless = {
    enable = true;

    settings = {
      PAPERLESS_URL = "https://paperless.gio.ninja";

      # OIDC Login setup
      PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
    };
  };

  age.secrets.paperless-oauth-config.file = ../../../../secrets/paperless-oauth-config.age;
  systemd.services.paperless-web.serviceConfig.EnvironmentFile = config.age.secrets.paperless-oauth-config.path;

  # Cloudflare Token Secret
  age.secrets.cloudflare-token.file = ../../../../secrets/cloudflare-token.age;

  # Get HTTPS Certificate from LetsEncrypt
  security.acme = {
    acceptTerms = true;

    certs."paperless.gio.ninja" = {
      email = "gio@damelio.net";
      dnsProvider = "cloudflare";
      credentialFiles = {
        CLOUDFLARE_DNS_API_TOKEN_FILE = config.age.secrets.cloudflare-token.path;
      };
    };
  };

  # Use Caddy as a reverse proxy
  services.caddy = {
    enable = true;

    virtualHosts."https://paperless.gio.ninja" = {
      useACMEHost = "paperless.gio.ninja";
      extraConfig = ''
        reverse_proxy localhost:28981
      '';
    };
  };

  networking.firewall.interfaces."wg9" = {
    allowedTCPPorts = [443 80];
  };
}
