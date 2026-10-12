# miniflux — RSS reader (miniflux.gio.ninja), OAuth-only via pocket-id, postgres
# created locally with peer auth. The two oauth2 secrets move to fleet.secrets
# credentials on miniflux.service (paths unchanged). Converted from
# nix/hosts/carbon/miniflux.nix.
_: {
  den.aspects.carbon.nixos = {lib, ...}: {
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
  };

  den.hosts.x86_64-linux.carbon.services.miniflux = {
    endpoint = {
      domain = "miniflux";
      backend.host = "localhost";
      backend.port = 8085;
    };
    healthcheck.target = "https://miniflux.gio.ninja/healthcheck";
    "prometheus-endpoint".target = "localhost:8085";
  };

  fleet.secrets = {
    miniflux-oauth2-client-id.origin = "carbon";
    miniflux-oauth2-client-id.use.carbon.services.miniflux.type = "credential";
    miniflux-oauth2-client-secret.origin = "carbon";
    miniflux-oauth2-client-secret.use.carbon.services.miniflux.type = "credential";
  };
}
