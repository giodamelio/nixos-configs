_: {config, ...}: {
  # Setup Prometheus
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";

    # Start some exporters
    exporters = {
      node = {
        enable = true;
        enabledCollectors = ["systemd"];
        listenAddress = "127.0.0.1";
      };
    };

    # Scrape those exporters
    scrapeConfigs = [
      {
        job_name = "node_exporter";
        static_configs = [
          {
            targets = [
              "127.0.0.1:${toString config.services.prometheus.exporters.node.port}"
            ];
            labels = {
              host = "zirconium";
            };
          }
        ];
      }
      {
        job_name = "gatus";
        scheme = "https";
        static_configs = [
          {
            targets = [
              "status.gio.ninja"
            ];
            labels = {
              host = "zirconium";
            };
          }
        ];
      }
    ];
  };

  # Load the OAuth id/secret for Grafana
  age.secrets.grafana-defguard-oauth-client-id = {
    file = ../../../../secrets/grafana-defguard-oauth-client-id.age;
    owner = "grafana";
    group = "grafana";
  };
  age.secrets.grafana-defguard-oauth-client-secret = {
    file = ../../../../secrets/grafana-defguard-oauth-client-secret.age;
    owner = "grafana";
    group = "grafana";
  };

  # Setup Grafana
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        domain = "grafana.gio.ninja";
        root_url = "https://grafana.gio.ninja";
      };

      auth.disable_login_form = true;
      "auth.generic_oauth" = {
        enabled = true;
        name = "Defguard";
        icon = "signin";
        allow_sign_up = true;
        scopes = "openid profile email groups";
        auth_url = "https://defguard.gio.ninja/api/v1/oauth/authorize";
        token_url = "https://defguard.gio.ninja/api/v1/oauth/token";
        api_url = "https://defguard.gio.ninja/api/v1/oauth/userinfo";

        # Map rules from OAuth groups
        role_attribute_path = "contains(groups[*], 'grafana-admin') && 'Admin' || contains(groups[*], 'grafana-editor') && 'Editor' || 'Viewer'";

        client_id = "$__file{${config.age.secrets.grafana-defguard-oauth-client-id.path}}";
        client_secret = "$__file{${config.age.secrets.grafana-defguard-oauth-client-secret.path}}";
      };
    };
  };

  # Cloudflare Token Secret
  age.secrets.cloudflare-token.file = ../../../../secrets/cloudflare-token.age;

  # Get HTTPS Certificate from LetsEncrypt
  security.acme = {
    acceptTerms = true;

    certs."grafana.gio.ninja" = {
      email = "gio@damelio.net";
      dnsProvider = "cloudflare";
      credentialFiles = {
        CLOUDFLARE_DNS_API_TOKEN_FILE = config.age.secrets.cloudflare-token.path;
      };
    };
    certs."prometheus.gio.ninja" = {
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

    virtualHosts."https://grafana.gio.ninja" = {
      useACMEHost = "grafana.gio.ninja";
      extraConfig = ''
        reverse_proxy localhost:3000
      '';
    };
    virtualHosts."https://prometheus.gio.ninja" = {
      useACMEHost = "prometheus.gio.ninja";
      extraConfig = ''
        reverse_proxy localhost:9090
      '';
    };
  };

  networking.firewall.interfaces."wg0" = {
    allowedTCPPorts = [443 80];
  };
  networking.firewall.interfaces."wg9" = {
    allowedTCPPorts = [443 80];
  };
}
