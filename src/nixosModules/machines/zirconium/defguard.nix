{root, ...}: {
  pkgs,
  config,
  ...
}: let
  defguardPkgs = root.packages.defguard {inherit pkgs;};
in {
  # Setup database
  gio.services.postgres = {
    enable = true;
    databases = ["defguard"];
  };

  # Defguard Core
  systemd.services.defguard-core = {
    description = "DefGuard Core";
    wantedBy = ["default.target"];
    requires = ["postgres-ready.service"];
    after = ["postgres-ready.service"];
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      User = "defguard";
      StateDirectory = "defguard";
      # Set working dir so executable can the supporting files
      WorkingDirectory = defguardPkgs.core;
      EnvironmentFile = "/var/lib/defguard/env";
    };
    environment = {
      DEFGUARD_DB_HOST = "/run/postgresql";
      DEFGUARD_URL = "https://defguard.gio.ninja";
    };
    script = ''
      ${defguardPkgs.core}/bin/defguard
    '';
  };

  # Run DefGuard Gateway
  systemd.services.defguard-gateway = {
    description = "DefGuard Gateway";
    wantedBy = ["default.target"];
    requires = ["defguard-core.service"];
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      User = "defguard";
      StateDirectory = "defguard";
      WorkingDirectory = "/var/lib/defguard";
      EnvironmentFile = "/var/lib/defguard/env";
      AmbientCapabilities = "CAP_NET_ADMIN";
    };
    environment = {
      DEFGUARD_GRPC_URL = "http://localhost:50055";
    };
    script = ''
      ${defguardPkgs.gateway}/bin/defguard-gateway
    '';
  };

  # Generate secrets for DefGuard in the form of a envfile
  systemd.services.defguard-db-generate-password = let
    envFile = "/var/lib/defguard/env";
  in {
    description = "Generate Secrets for DefGuard";
    wantedBy = ["default.target"];
    before = ["defguard-core.service"];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      User = "defguard";
      StateDirectory = "defguard";
    };
    unitConfig = {
      # Note negation of the path
      ConditionPathExists = "!${envFile}";
    };
    script = ''
      umask 077 # Make rw by just creating user

      printf "DEFGUARD_SECRET_KEY=%s" $(${pkgs.pwgen}/bin/pwgen 64 1) >> ${envFile}
    '';
  };

  # Cloudflare Token Secret
  age.secrets.cloudflare-token.file = ../../../../secrets/cloudflare-token.age;

  # Get HTTPS Certificate from LetsEncrypt
  security.acme = {
    acceptTerms = true;

    certs."defguard.gio.ninja" = {
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

    virtualHosts."https://defguard.gio.ninja" = {
      useACMEHost = "defguard.gio.ninja";
      extraConfig = ''
        handle /api/* {
          reverse_proxy localhost:8000
        }

        root * ${defguardPkgs.ui}
        file_server
      '';
    };
  };

  networking.firewall = {
    enable = true;
    allowedUDPPorts = [50051];
  };
  networking.firewall.interfaces."wg0" = {
    allowedTCPPorts = [443 80];
  };
  networking.firewall.interfaces."wg9" = {
    allowedTCPPorts = [443 80];
  };
}
