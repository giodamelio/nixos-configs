_: {
  pkgs,
  config,
  ...
}: let
  homer = pkgs.stdenv.mkDerivation rec {
    pname = "homer";
    version = "24.02.1";

    src = pkgs.fetchzip {
      url = "https://github.com/bastienwirtz/homer/releases/download/v${version}/homer.zip";
      hash = "sha256-McMJuZ84B3BlGHLQf+/ttRe5xAzQuR6qHrH8IjGys2Q=";
      stripRoot = false;
    };

    installPhase = ''
      mkdir $out
      mv * $out
      cp ${homerConfigRendered} $out/assets/config.yml
    '';
  };
  homerConfigRendered = pkgs.writeTextFile {
    name = "homer-config.yml";
    text = builtins.toJSON homerConfig;
  };
  homerConfig = {
    title = "Gio's Homelab";
    subtitle = "";

    services = [
      {
        name = "Services";
        icon = "";
        items = [
          {
            name = "Miniflux";
            subtitle = "RSS Reader";
            url = "https://miniflux.gio.ninja";
            logo = "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/miniflux.png";
          }
          {
            name = "PaperlessNGX";
            subtitle = "Document Organizer/Archiver";
            url = "https://paperless.gio.ninja";
            logo = "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/paperless-ngx.png";
          }
        ];
      }
      {
        name = "Admin";
        icon = "";
        items = [
          {
            name = "Defguard";
            subtitle = "User Auth/VPN";
            url = "https://defguard.gio.ninja";
            logo = "https://github.com/DefGuard/defguard/raw/main/web/src/shared/images/svg/defguad-nav-logo-collapsed.svg";
          }
          {
            name = "Gatus";
            subtitle = "Status Page";
            url = "https://status.gio.ninja";
            logo = "https://status.gio.ninja/logo-512x512.png";
          }
        ];
      }
    ];
  };
in {
  # Cloudflare Token Secret
  age.secrets.cloudflare-token.file = ../../../../secrets/cloudflare-token.age;

  # Get HTTPS Certificate from LetsEncrypt
  security.acme = {
    acceptTerms = true;

    certs."home.gio.ninja" = {
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

    virtualHosts."https://home.gio.ninja" = {
      useACMEHost = "home.gio.ninja";
      extraConfig = ''
        root * ${homer}
        file_server
      '';
    };
  };
}
