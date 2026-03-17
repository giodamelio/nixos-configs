{pkgs, ...}: let
  inherit (pkgs) lib;
in {
  services.miniflux = {
    enable = true;
    createDatabaseLocally = true;
    config = {
      LISTEN_ADDR = "127.0.0.1:8085";
      BASE_URL = "https://miniflux.gio.ninja";
      CREATE_ADMIN = 0;
      DISABLE_LOCAL_AUTH = 1;

      OAUTH2_PROVIDER = "oidc";
      OAUTH2_OIDC_PROVIDER_NAME = "Pocket ID";
      OAUTH2_OIDC_DISCOVERY_ENDPOINT = "https://login.gio.ninja";
      OAUTH2_REDIRECT_URL = "https://miniflux.gio.ninja/oauth2/oidc/callback";
      OAUTH2_USER_CREATION = 1;
      OAUTH2_CLIENT_ID_FILE = "/run/credentials/miniflux.service/miniflux-oauth2-client-id";
      OAUTH2_CLIENT_SECRET_FILE = "/run/credentials/miniflux.service/miniflux-oauth2-client-secret";

      METRICS_COLLECTOR = 1;
    };
  };

  services.postgresql = {
    identMap = lib.mkAfter ''
      miniflux root miniflux
      miniflux miniflux miniflux
    '';
    authentication = lib.mkAfter ''
      local all miniflux peer map=miniflux
    '';
  };

  gio.credentials = {
    enable = true;
    services.miniflux = {
      loadCredentialEncrypted = [
        "miniflux-oauth2-client-id"
        "miniflux-oauth2-client-secret"
      ];
    };
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts.miniflux = {
      host = "localhost";
      port = 8085;
    };
  };

  gio.services.miniflux.consul = {
    name = "miniflux";
    address = "miniflux.gio.ninja";
    port = 443;
    checks = [
      {
        http = "https://miniflux.gio.ninja/healthcheck";
        interval = "60s";
      }
    ];
  };
}
