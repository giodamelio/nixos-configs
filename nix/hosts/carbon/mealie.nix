{
  pkgs,
  config,
  lib,
  ...
}: {
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

  # Manually load the credentials into environment variables,
  # this is done by the Docker entrypoint normally so we have to replicate that
  # See: https://github.com/mealie-recipes/mealie/blob/01713b04163e9524b2665ad8089148b6d2f90233/docker/entry.sh#L38-L73
  systemd.services.mealie.serviceConfig.ExecStart = lib.mkForce (let
    cfg = config.services.mealie;
  in
    pkgs.writers.writeBash "mealie-wrapper" ''
      export SMTP_PASSWORD="$(<"$SMTP_PASSWORD_FILE")"
      export OPENAI_API_KEY="$(<"$OPENAI_API_KEY_FILE")"
      export OIDC_CLIENT_ID="$(<"$OIDC_CLIENT_ID_FILE")"
      export OIDC_CLIENT_SECRET="$(<"$OIDC_CLIENT_SECRET_FILE")"

      ${lib.getExe cfg.package} -b ${cfg.listenAddress}:${builtins.toString cfg.port} ${lib.escapeShellArgs cfg.extraOptions}
    '');

  gio.loadCredentialEncrypted.services = {
    "mealie" = [
      "mealie-fastmail-smtp-password"
      "mealie-oidc-client-id"
      "mealie-oidc-client-secret"
      "mealie-openai-api-key"
    ];
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
