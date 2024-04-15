_: {config, ...}: {
  services.paperless = {
    enable = true;

    settings = {
      PAPERLESS_URL = "https://paperless.gio.ninja";

      # OIDC Login setup
      PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
    };
  };

  age.secrets.paperless-oauth-config.file = ../../../../secrets/paperless-oauth-config.age;
  systemd.services.paperless-web.serviceConfig.EnvironmentFile = config.age.secrets.paperless-oauth-config.path;

  services.caddy = {
    virtualHosts."https://paperless.gio.ninja" = {
      extraConfig = ''
        reverse_proxy localhost:28981
      '';
    };
  };
}
