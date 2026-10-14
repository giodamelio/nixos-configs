# paperless — document management (paperless.gio.ninja) with OIDC, postgres
# created locally, media on the NFS-mounted /var/lib/paperless/media (see nfs.nix).
# The flat env file moves to a fleet.secrets credential sourced at script start
# (paperless' own EnvironmentFile runs before systemd credentials are decrypted,
# so we source it in a mkBefore script — as in Blueprint). gotenberg is moved off
# :3000 to avoid grafana. Converted from nix/hosts/carbon/paperless.nix.
_: {
  den.aspects.carbon.nixos = {lib, ...}: {
    services.paperless = {
      enable = true;
      port = 28981;
      address = "127.0.0.1";
      database.createLocally = true;
      configureTika = true;
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

    # Gotenberg defaults to 3000, which conflicts with Grafana.
    services.gotenberg.port = 3001;

    users.users.paperless.extraGroups = ["nfs-paperless-ngx"];

    # Source the credential at script start (EnvironmentFile runs before systemd
    # decrypts credentials, so it cannot point at the credential path directly).
    systemd.services.paperless-web.script = lib.mkBefore ''
      if [ -f "$CREDENTIALS_DIRECTORY/paperless-env" ]; then
        set -a
        . "$CREDENTIALS_DIRECTORY/paperless-env"
        set +a
      fi
    '';
  };

  den.hosts.x86_64-linux.carbon.services.paperless = {
    endpoint = {
      domain = "paperless";
      backend.host = "localhost";
      backend.port = 28981;
    };
    healthcheck.target = "https://paperless.gio.ninja";
  };

  fleet.secrets.paperless-env = {
    origin = "carbon";
    use.carbon.services.paperless-web.type = "credential";
  };
}
