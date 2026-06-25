# windmill — workflow engine (windmill.gio.ninja), postgres created locally with
# peer auth. The built-in workers are disabled in favour of two podman worker
# containers (default + native) that reach postgres over the mounted socket.
# Converted from nix/hosts/carbon/windmill.nix.
_: {
  den.aspects.carbon.nixos = {
    perSystem,
    lib,
    ...
  }: {
    services.windmill = {
      enable = true;
      package = perSystem.self.windmill;
      baseUrl = "https://windmill.gio.ninja";
      database.createLocally = true;
    };

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

    systemd.services.windmill-worker.enable = false;
    systemd.services.windmill-worker-native.enable = false;

    services.postgresql = {
      identMap = lib.mkAfter ''
        windmill root windmill
        windmill windmill windmill
      '';
      authentication = lib.mkAfter ''
        local all windmill peer map=windmill
      '';
    };
  };

  den.hosts.x86_64-linux.carbon.services.windmill = {
    endpoint = {
      domain = "windmill";
      backend.host = "localhost";
      backend.port = 8000;
    };
    healthcheck.target = "https://windmill.gio.ninja/";
  };
}
