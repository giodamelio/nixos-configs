# paperless — document management (paperless.gio.ninja) with PocketID SSO.
# Postgres created locally; media lives on gallium over NFS. gotenberg is moved
# off :3000 to avoid grafana.
_: {
  fleet.nfs.mounts.paperless-ngx.gallium."/tank/paperless".carbon."/var/lib/paperless/media" = {};

  den.aspects.carbon.nixos = {
    services.paperless = {
      enable = true;
      port = 28981;
      address = "127.0.0.1";
      database.createLocally = true;
      configureTika = true;
      settings = {
        PAPERLESS_URL = "https://paperless.gio.ninja";
        # PAPERLESS_URL doesn't set the request scheme, so without trusting Caddy's
        # header the API's pagination links come back as http://.
        PAPERLESS_PROXY_SSL_HEADER = ["HTTP_X_FORWARDED_PROTO" "https"];
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

    # Upstream binds consumer and web to the scheduler but not the task queue,
    # which also writes media; without this it would outlive a lost NFS share.
    systemd.services.paperless-task-queue.bindsTo = ["paperless-scheduler.service"];

    fleet.credentials.unit_wrappers.paperless-web.environment.PAPERLESS_SOCIALACCOUNT_PROVIDERS = "paperless_socialaccount_providers";
  };

  den.hosts.x86_64-linux.carbon.services.paperless = {
    # Every other paperless unit is bound to the scheduler, so binding it to the
    # mount keeps them all from starting, or running, without the share.
    unit = "paperless-scheduler";
    endpoint = {
      domain = "paperless";
      backend.host = "localhost";
      backend.port = 28981;
    };
    healthcheck.target = "https://paperless.gio.ninja";
    mounts = ["paperless-ngx"];
  };
}
