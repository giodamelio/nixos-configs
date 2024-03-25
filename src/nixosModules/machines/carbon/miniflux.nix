_: {
  pkgs,
  config,
  ...
}: let
  adminPasswordFile = "/var/lib/miniflux_admin_creds";
  passwordFileTemplate = pkgs.writeTextFile {
    name = "miniflux_creds_template";
    text = ''
      ADMIN_USERNAME=admin
      ADMIN_PASSWORD={{ random.String 32 }}
    '';
  };
in {
  services.miniflux = {
    enable = true;
    createDatabaseLocally = true;
    adminCredentialsFile = adminPasswordFile;

    config = {
      BASE_URL = "https://miniflux.gio.ninja";
      OAUTH2_PROVIDER = "oidc";
      OAUTH2_REDIRECT_URL = "https://miniflux.gio.ninja/oauth2/oidc/callback";
      OAUTH2_OIDC_DISCOVERY_ENDPOINT = "https://defguard.gio.ninja/";
      OAUTH2_USER_CREATION = "1";
    };
  };

  systemd.services.miniflux-generate-admin-password = {
    description = "Generate Admin Password for Miniflux";
    wantedBy = ["default.target"];
    requiredBy = ["miniflux.service"];
    before = ["miniflux.service"];
    serviceConfig = {
      Type = "oneshot";
    };
    unitConfig = {
      # Note negation of the path
      ConditionPathExists = "!${adminPasswordFile}";
    };
    script = ''
      umask 077 # Make rw by just creating user

      ${pkgs.gomplate}/bin/gomplate \
        --file ${passwordFileTemplate} \
        >> ${adminPasswordFile}
    '';
  };

  # Cloudflare Token Secret
  age.secrets.cloudflare-token.file = ../../../../secrets/cloudflare-token.age;

  # Get HTTPS Certificate from LetsEncrypt
  security.acme = {
    acceptTerms = true;

    certs."miniflux.gio.ninja" = {
      email = "gio@damelio.net";
      dnsProvider = "cloudflare";
      credentialFiles = {
        CLOUDFLARE_DNS_API_TOKEN_FILE = config.age.secrets.cloudflare-token.path;
      };
    };
  };

  # Use Caddy as a reverse proxy
  services.caddy = {
    enable = true;

    virtualHosts."https://miniflux.gio.ninja" = {
      useACMEHost = "miniflux.gio.ninja";
      extraConfig = ''
        reverse_proxy localhost:8080
      '';
    };
  };

  networking.firewall.interfaces."wg9" = {
    allowedTCPPorts = [443 80];
  };
}
