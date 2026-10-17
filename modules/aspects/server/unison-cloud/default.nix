{
  den,
  inputs,
  ...
}: let
  credentials = {
    oidc-client-secret = "unison_cloud_oidc_client_secret";
    s3-access-key-id = "unison_cloud_s3_access_key_id";
    s3-secret-access-key = "unison_cloud_s3_secret_access_key";
    cloud-api-db-password = "unison_cloud_api_db_password";
    nimbus-db-password = "unison_cloud_nimbus_db_password";
    consul-token = "unison_cloud_consul_token";
  };
in {
  den.aspects.unison-cloud.includes = [den.aspects.reverse-proxy];

  den.aspects.unison-cloud.nixos = {
    config,
    lib,
    ...
  }: let
    cfg = config.services.unison-cloud;
    site = domain: extraConfig: {
      inherit domain extraConfig;
      reverseProxy = false;
    };
  in {
    imports = [
      inputs.unison-cloud-in-a-bottle.nixosModules.core
      ./_postgresql.nix
    ];

    services.unison-cloud = {
      enable = true;
      domains = {
        api = "api.unison.gio.ninja";
        apps = "app.unison.gio.ninja";
        ui = "unison.gio.ninja";
      };

      auth.oidc = {
        issuer = "https://login.gio.ninja";
        clientId = "c76c9f5f-c479-4cba-8ed3-f0b0be817597";
        # The browser follows the public URL; cloud-api fetches tokens and keys from Pocket ID directly.
        endpoints = {
          authorization = "https://login.gio.ninja/authorize";
          token = "http://127.0.0.1:1411/api/oidc/token";
          jwks = "http://127.0.0.1:1411/.well-known/jwks.json";
        };
        allowedGroups = ["unison_cloud"];
      };

      s3 = {
        host = "s3.garage.gio.ninja";
        region = "garage";
      };

      database.host = "127.0.0.1";
      logs.lokiUrl = "http://127.0.0.1:3100";

      secrets.credentials = credentials;
    };

    fleet.credentials.needs = lib.attrValues credentials;

    # Registering before the agent can resolve tokens 403s with "ACL not found".
    systemd.services.unison-cloud-consul-services = {
      requires = ["consul-ready.service"];
      after = ["consul-ready.service"];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    # Set here, not on the host's endpoints, because core's site bodies only exist in NixOS config.
    services.gio.reverse-proxy = {
      enable = true;
      virtualHosts = {
        unison-cloud-api = site "api.unison" cfg.caddy.siteConfig.api;
        unison-cloud-apps = site "app.unison" cfg.caddy.siteConfig.apps;
        unison-cloud-ui = site "unison" cfg.caddy.siteConfig.ui;
      };
    };
  };
}
