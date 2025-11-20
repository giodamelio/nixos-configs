{
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

  gio.credentials = {
    enable = true;
    services = {
      "mealie" = {
        execStartWrapper = {
          environment = {
            SMTP_PASSWORD = "mealie-fastmail-smtp-password";
            OPENAI_API_KEY = "mealie-openai-api-key";
            OIDC_CLIENT_ID = "mealie-oidc-client-id";
            OIDC_CLIENT_SECRET = "mealie-oidc-client-secret";
          };
        };
      };
    };
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "mealie" = {
        host = "localhost";
        port = 9100;
      };
      # TODO: figure out auto
      # "api.mealie" = {
      #   host = "localhost";
      #   port = 8081;
      # };
    };
  };
}
