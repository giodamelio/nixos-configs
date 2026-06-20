# mealie — recipe manager (mealie.gio.ninja), OIDC-only login, postgres created
# locally. The four secrets move from gio.credentials to fleet.secrets credentials
# on mealie.service; the settings already read them from
# /run/credentials/mealie.service/<name> (*_FILE), so the paths are unchanged and
# no env-wrapper is needed. Converted from nix/hosts/carbon/mealie.nix.
_: {
  den.aspects.carbon.nixos = {
    services.mealie = {
      enable = true;
      database.createLocally = true;
      port = 9100;
      settings = {
        BASE_URL = "https://mealie.gio.ninja";
        ALLOW_SIGNUP = "false";
        ALLOW_PASSWORD_LOGIN = "false";

        OIDC_AUTH_ENABLED = "true";
        OIDC_CONFIGURATION_URL = "https://login.gio.ninja/.well-known/openid-configuration";
        OIDC_CLIENT_ID_FILE = "/run/credentials/mealie.service/mealie-oidc-client-id";
        OIDC_CLIENT_SECRET_FILE = "/run/credentials/mealie.service/mealie-oidc-client-secret";
        OIDC_USER_GROUP = "mealie_user";
        OIDC_ADMIN_GROUP = "mealie_admin";
        OIDC_AUTO_REDIRECT = "true";

        SMTP_HOST = "smtp.fastmail.com";
        SMTP_AUTH_STRATEGY = "TLS";
        SMTP_FROM_EMAIL = "mealie@gio.ninja";
        SMTP_USER = "giodamelio@fastmail.com";
        SMTP_PASSWORD_FILE = "/run/credentials/mealie.service/mealie-fastmail-smtp-password";

        OPENAI_API_KEY_FILE = "/run/credentials/mealie.service/mealie-openai-api-key";
      };
    };
  };

  den.hosts.x86_64-linux.carbon.services.mealie = {
    endpoint = {
      domain = "mealie";
      backend.host = "localhost";
      backend.port = 9100;
    };
    healthcheck.target = "https://mealie.gio.ninja/";
  };

  fleet.secrets = {
    mealie-oidc-client-id.origin = "carbon";
    mealie-oidc-client-id.use.carbon.services.mealie.type = "credential";
    mealie-oidc-client-secret.origin = "carbon";
    mealie-oidc-client-secret.use.carbon.services.mealie.type = "credential";
    mealie-fastmail-smtp-password.origin = "carbon";
    mealie-fastmail-smtp-password.use.carbon.services.mealie.type = "credential";
    mealie-openai-api-key.origin = "carbon";
    mealie-openai-api-key.use.carbon.services.mealie.type = "credential";
  };
}
