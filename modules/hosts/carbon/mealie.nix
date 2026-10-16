# mealie — recipe manager (mealie.gio.ninja), OIDC-only login, postgres created
# locally.
_: {
  den.aspects.carbon.nixos = let
    credentials = [
      "mealie_oidc_client_id"
      "mealie_oidc_client_secret"
      "mealie_fastmail_smtp_password"
      "mealie_openai_api_key"
    ];
  in {
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
        OIDC_CLIENT_ID_FILE = "/run/credentials/mealie.service/mealie_oidc_client_id";
        OIDC_CLIENT_SECRET_FILE = "/run/credentials/mealie.service/mealie_oidc_client_secret";
        OIDC_USER_GROUP = "mealie_user";
        OIDC_ADMIN_GROUP = "mealie_admin";
        OIDC_AUTO_REDIRECT = "true";

        SMTP_HOST = "smtp.fastmail.com";
        SMTP_AUTH_STRATEGY = "TLS";
        SMTP_FROM_EMAIL = "mealie@gio.ninja";
        SMTP_USER = "giodamelio@fastmail.com";
        SMTP_PASSWORD_FILE = "/run/credentials/mealie.service/mealie_fastmail_smtp_password";

        OPENAI_API_KEY_FILE = "/run/credentials/mealie.service/mealie_openai_api_key";
      };
    };

    fleet.credentials.needs = credentials;
    systemd.services.mealie.serviceConfig.LoadCredentialEncrypted = credentials;
  };

  den.hosts.x86_64-linux.carbon.services.mealie = {
    endpoint = {
      domain = "mealie";
      backend.host = "localhost";
      backend.port = 9100;
    };
    healthcheck.target = "https://mealie.gio.ninja/";
  };
}
