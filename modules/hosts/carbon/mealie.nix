# mealie — recipe manager (mealie.gio.ninja), OIDC-only login, postgres created
# locally.
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
        OIDC_USER_GROUP = "mealie_user";
        OIDC_ADMIN_GROUP = "mealie_admin";
        OIDC_AUTO_REDIRECT = "true";

        SMTP_HOST = "smtp.fastmail.com";
        SMTP_AUTH_STRATEGY = "TLS";
        SMTP_FROM_EMAIL = "mealie@gio.ninja";
        SMTP_USER = "giodamelio@fastmail.com";
      };
    };

    # Mealie has no *_FILE support; secrets must arrive as plain env vars.
    fleet.credentials.unit_wrappers.mealie.environment = {
      OIDC_CLIENT_ID = "mealie_oidc_client_id";
      OIDC_CLIENT_SECRET = "mealie_oidc_client_secret";
      SMTP_PASSWORD = "mealie_fastmail_smtp_password";
      OPENAI_API_KEY = "mealie_openai_api_key";
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
}
