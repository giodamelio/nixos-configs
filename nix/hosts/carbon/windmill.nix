{
  flake,
  pkgs,
  config,
  ...
}: let
  inherit (flake.packages.${pkgs.stdenv.hostPlatform.system}) windmill;
in {
  services.windmill = {
    enable = true;
    package = windmill;
    baseUrl = "https://windmill.gio.ninja";
    database = {
      createLocally = true;
    };
  };

  # Run a worker in a Podman container for runtime compatability
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers = let
    baseContainerAttrs = {
      image = "ghcr.io/windmill-labs/windmill-full:1.576";
      autoStart = true;
      volumes = [
        "/var/run/postgresql:/var/run/postgresql"
      ];
    };
  in {
    windmill_worker =
      baseContainerAttrs
      // {
        environment = {
          DATABASE_URL = "postgres://windmill?host=/var/run/postgresql&user=windmill";
          MODE = "worker";
          WORKER_GROUP = "default";
        };
      };
    windmill_worker_native =
      baseContainerAttrs
      // {
        environment = {
          DATABASE_URL = "postgres://windmill?host=/var/run/postgresql&user=windmill";
          MODE = "worker";
          WORKER_GROUP = "native";
          NUM_WORKERS = "8";
          SLEEP_QUEUE = "200";
        };
      };
  };

  # Disable the built in worker services
  systemd.services.windmill-worker.enable = false;
  systemd.services.windmill-worker-native.enable = false;

  # Allow containers to connect to the windmill database
  services.postgresql = {
    identMap = ''
      windmill root windmill
      windmill windmill windmill
    '';
    authentication = ''
      local all windmill peer map=windmill
    '';
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "windmill" = {
        host = "localhost";
        port = config.services.windmill.serverPort;
      };
    };
  };
}
