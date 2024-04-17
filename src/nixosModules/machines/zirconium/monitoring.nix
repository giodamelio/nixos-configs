_: {config, ...}: let
  makeNodeExporterConfig = host: address: {
    targets = [
      "${address}:${toString config.services.prometheus.exporters.node.port}"
    ];
    labels = {
      inherit host;
    };
  };
in {
  # Setup Prometheus
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";

    # Scrape those exporters
    scrapeConfigs = [
      {
        job_name = "node_exporter";
        static_configs = [
          (makeNodeExporterConfig "zirconium" "127.0.0.1")
          (makeNodeExporterConfig "carbon" "carbon.gio.ninja")
          (makeNodeExporterConfig "gallium" "gallium.gio.ninja")
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
      {
        job_name = "garage";
        scheme = "https";
        static_configs = [
          {
            targets = [
              "garage-admin.gio.ninja"
            ];
            labels = {
              host = "gallium";
            };
          }
        ];
      }
    ];
  };

  # Load the OAuth id/secret for Grafana
  systemd.services.grafana.serviceConfig.LoadCredentialEncrypted = [
    "grafana-defguard-oauth-client-id"
    "grafana-defguard-oauth-client-secret"
  ];

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

        # FIXME: I know you are not supposed to hardcode these
        client_id = "$__file{/run/credentials/grafana.service/grafana-defguard-oauth-client-id}";
        client_secret = "$__file{/run/credentials/grafana.service/grafana-defguard-oauth-client-secret}";
      };
    };
  };

  # Use Caddy as a reverse proxy
  services.caddy = {
    virtualHosts."https://grafana.gio.ninja" = {
      extraConfig = ''
        reverse_proxy localhost:3000
      '';
    };
    virtualHosts."https://prometheus.gio.ninja" = {
      extraConfig = ''
        reverse_proxy localhost:9090
      '';
    };
  };
}
