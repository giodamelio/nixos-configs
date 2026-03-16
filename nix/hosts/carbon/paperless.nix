{lib, ...}: {
  services.paperless = {
    enable = true;
    port = 28981;
    address = "127.0.0.1";
    database.createLocally = true;
    configureTika = true;
    mediaDir = "/mnt/paperless-media";
    settings = {
      PAPERLESS_URL = "https://paperless.gio.ninja";
      PAPERLESS_OCR_LANGUAGE = "eng";
      PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
      PAPERLESS_REDIRECT_LOGIN_TO_SSO = "true";
      PAPERLESS_DISABLE_REGULAR_LOGIN = "true";
      PAPERLESS_ACCOUNT_ALLOW_SIGNUPS = "true";
      PAPERLESS_SOCIALACCOUNT_ALLOW_SIGNUPS = "true";
    };
  };

  # Gotenberg defaults to 3000, which conflicts with Grafana
  services.gotenberg.port = 3001;

  users.users.paperless.extraGroups = ["nfs-paperless-ngx"];

  gio.credentials = {
    enable = true;
    services."paperless-web".loadCredentialEncrypted = ["paperless-env"];
  };

  # Source the credential file at script start (EnvironmentFile runs before credentials are decrypted)
  systemd.services.paperless-web.script = lib.mkBefore ''
    if [ -f "$CREDENTIALS_DIRECTORY/paperless-env" ]; then
      set -a
      . "$CREDENTIALS_DIRECTORY/paperless-env"
      set +a
    fi
  '';

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts.paperless = {
      host = "localhost";
      port = 28981;
    };
  };

  gio.services.paperless.consul = {
    name = "paperless";
    address = "paperless.gio.ninja";
    port = 443;
    checks = [
      {
        http = "https://paperless.gio.ninja";
        interval = "60s";
      }
    ];
  };
}
