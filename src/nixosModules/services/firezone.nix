{...}: {
  pkgs,
  config,
  ...
}: let
  lib = pkgs.lib;
in {
  # Load our secrets
  age.secrets.cert_firezone_gio_ninja.file = ../../../secrets/cert_cloudflare_gio_ninja.age;
  age.secrets.service_firezone_postgres_password.file = ../../../secrets/service_firezone_postgres_password.age;
  age.secrets.service_firezone_envfile.file = ../../../secrets/service_firezone_envfile.age;

  # Get HTTPS certificates from LetsEncrypt for Firezone
  security.acme = {
    acceptTerms = true;
    defaults.email = "gio@damelio.net";

    certs."firezone.gio.ninja" = {
      dnsProvider = "cloudflare";
      credentialsFile = config.age.secrets.cert_firezone_gio_ninja.path;
    };
  };

  # Configure containers
  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings = {
        dns_enabled = true;
      };
    };
    oci-containers.backend = "podman";
  };

  # Run Firezone Container
  # TODO: run on a pinned version
  # TODO: setup some kind of version alerting system to tell me to update
  virtualisation.oci-containers.containers.firezone = {
    image = "docker.io/firezone/firezone:latest";
    autoStart = true;
    extraOptions = [
      # Needed for WireGuard/Fireall
      "--cap-add=NET_ADMIN"
      "--cap-add=SYS_MODULE"
      # Needed for NAT
      "--sysctl=net.ipv4.ip_forward=1"
    ];
    ports = [
      "13000:13000" # WebUI
      "51820:51820/udp" # Wireguard
    ];
    volumes = [
      "/var/lib/firezone:/var/firezone"
    ];
    environmentFiles = [
      config.age.secrets.service_firezone_envfile.path
    ];
    environment = {
      # Reset admin password every boot to the one from the envfile
      RESET_ADMIN_ON_BOOT = "true";

      DATABASE_HOST = "host.containers.internal";
      DATABASE_USER = "firezone";
      # DATABASE_PASSWORD = ""; # Written by an the envfile

      # Disable IPv6 since our DigitalOcean host doesn't support it with custom OS images
      WIREGUARD_IPV6_ENABLED = "false";
    };
  };

  # Make sure the state directory is created for the container volume mount
  systemd.services.podman-firezone = {
    serviceConfig = {
      StateDirectory = "firezone";
    };
  };

  # Use Caddy to reverse proxy
  services.caddy = {
    enable = true;
    group = "acme";

    virtualHosts."https://firezone.gio.ninja" = {
      useACMEHost = "firezone.gio.ninja";
      extraConfig = ''
        reverse_proxy localhost:13000
      '';
    };
  };

  # Open up firewall ports
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [80 443];
    allowedUDPPorts = [51820];
  };

  # Ensure PostgreSQL is running and has a database and user for us
  services.my-postgres = {
    enable = true;
    databases = {
      firezone = config.age.secrets.service_firezone_postgres_password.path;
    };
  };
}
