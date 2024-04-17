_: _: {
  services.paperless = {
    enable = true;

    settings = {
      PAPERLESS_URL = "https://paperless.gio.ninja";

      # OIDC Login setup
      PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
    };
  };

  # The NixOS module sets configs by ENV, so we can load private settings from SystemD creds
  systemd.services.paperless-web = {
    serviceConfig = {
      LoadCredentialEncrypted = "paperless-config";
    };

    environment = {
      PAPERLESS_CONFIGURATION_PATH = "%d/paperless-config";
    };
  };

  services.caddy = {
    virtualHosts."https://paperless.gio.ninja" = {
      extraConfig = ''
        reverse_proxy localhost:28981
      '';
    };
  };
}
