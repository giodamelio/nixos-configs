{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types;

  # Single source of truth for where the local Restate server listens. Everything
  # else (the server config, the reverse-proxy vhosts, the loopback endpoints
  # other modules call) derives from these, so changing a port can't drift.
  listenHost = "127.0.0.1";
  ingressPort = 8080;
  adminPort = 9070;

  ingressEndpoint = "http://${listenHost}:${toString ingressPort}";
  adminEndpoint = "http://${listenHost}:${toString adminPort}";

  restateConfig = {
    cluster-name = "restate";
    node-name = "carbon";
    bind-address = "${listenHost}:5122";
    auto-provision = true; # Disable if we ever go multi node

    log-filter = "info";
    log-format = "json";

    disable-telemetry = true;

    ingress = {
      bind-address = "${listenHost}:${toString ingressPort}";
      advertised-ingress-endpoint = "https://ingress.restate.gio.ninja";
    };

    admin = {
      bind-address = "${listenHost}:${toString adminPort}";
      advertised-admin-endpoint = "https://admin.restate.gio.ninja";
    };
  };

  configFile = (pkgs.formats.toml {}).generate "restate.toml" restateConfig;

  # One oneshot per declared deployment: register its endpoint with Restate so
  # the server discovers the service's handlers, without a manual CLI step.
  registerServices =
    lib.mapAttrs' (
      name: dep:
        lib.nameValuePair "restate-register-${name}" {
          description = "Register ${name} (${dep.endpoint}) with Restate";
          after = ["restate.service" "network-online.target"] ++ dep.dependencies;
          wants = ["restate.service" "network-online.target"] ++ dep.dependencies;
          wantedBy = ["multi-user.target"];
          restartTriggers = dep.restartTriggers ++ [dep.endpoint];
          path = [pkgs.restate pkgs.curl];
          environment = {
            RESTATE_ADMIN_URL = adminEndpoint;
            # DynamicUser has no real HOME; give the CLI a writable config dir.
            RESTATE_CLI_CONFIG_HOME = "/run/restate-register-${name}";
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            DynamicUser = true;
            RuntimeDirectory = "restate-register-${name}";
          };
          # `after = restate.service` only guarantees the unit has *started*, not
          # that the admin API is accepting connections — on boot Restate replays
          # its partitions first ("attempt finding the tail again"), which can take
          # a couple of minutes. So we gate on the admin /health endpoint before
          # registering, then retry the register itself (the service's own endpoint,
          # which Restate calls to discover handlers, may still be coming up).
          # --force makes re-registration after a handler change create a new
          # version instead of erroring on the existing deployment. Total budget
          # ~3min for readiness + ~1min for registration.
          script = ''
            set -euo pipefail

            echo "waiting for Restate admin API at ${adminEndpoint} to become ready"
            for attempt in $(seq 1 90); do
              if curl -fsS -o /dev/null "${adminEndpoint}/health"; then
                echo "Restate admin API is ready"
                break
              fi
              if [ "$attempt" -eq 90 ]; then
                echo "Restate admin API not ready after 3 minutes" >&2
                exit 1
              fi
              sleep 2
            done

            for attempt in $(seq 1 30); do
              if restate -y deployments register --force "${dep.endpoint}"; then
                echo "registered ${dep.endpoint} with Restate"
                exit 0
              fi
              echo "registration attempt $attempt for ${dep.endpoint} failed; retrying in 2s" >&2
              sleep 2
            done
            echo "failed to register ${dep.endpoint} after 30 attempts" >&2
            exit 1
          '';
        }
    )
    config.gio.restate.deployments;
in {
  # Canonical loopback endpoints of the local Restate server, derived from the
  # listen ports above. Other modules on this host (webhookcatcher's forward,
  # the gradient-deploy wrapper) read these instead of re-hardcoding the port.
  options.gio.restate.ingressEndpoint = mkOption {
    type = types.str;
    readOnly = true;
    default = ingressEndpoint;
    description = "Loopback HTTP endpoint of the local Restate ingress.";
  };

  options.gio.restate.adminEndpoint = mkOption {
    type = types.str;
    readOnly = true;
    default = adminEndpoint;
    description = "Loopback HTTP endpoint of the local Restate admin API.";
  };

  options.gio.restate.deployments = mkOption {
    default = {};
    description = ''
      Restate service-deployment registrations. Each entry names an HTTP
      endpoint that the local Restate server should discover; it is turned into
      a `restate deployments register` oneshot against the local admin API.
    '';
    example = lib.literalExpression ''
      {
        my-service = {
          endpoint = "http://127.0.0.1:9080";
          dependencies = ["my-service.service"];
        };
      }
    '';
    type = types.attrsOf (types.submodule {
      options = {
        endpoint = mkOption {
          type = types.str;
          example = "http://127.0.0.1:9080";
          description = "HTTP endpoint of the Restate SDK service to register.";
        };

        dependencies = mkOption {
          type = types.listOf types.str;
          default = [];
          example = ["my-service.service"];
          description = ''
            Extra systemd units to order after / want. Set this to the service's
            own unit so registration only fires once its endpoint is listening
            (Restate calls the endpoint to discover handlers at registration time).
          '';
        };

        restartTriggers = mkOption {
          type = types.listOf (types.either types.str types.package);
          default = [];
          description = ''
            Extra restart triggers. Re-runs registration when any of these change
            — set this to the service's package so a new build re-registers and
            Restate re-discovers its handlers.
          '';
        };
      };
    });
  };

  config = {
    environment.systemPackages = with pkgs; [
      restate
    ];

    systemd.services =
      {
        restate = {
          description = "Restate distributed application platform";
          wantedBy = ["multi-user.target"];
          after = ["network-online.target"];
          wants = ["network-online.target"];

          serviceConfig = {
            ExecStart = "${pkgs.restate}/bin/restate-server --config-file ${configFile}";

            # Dynamic user and state management
            DynamicUser = true;
            StateDirectory = "restate";
            WorkingDirectory = "/var/lib/restate";

            # Security hardening
            CapabilityBoundingSet = "";
            LockPersonality = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateTmp = true;
            PrivateUsers = true;
            ProcSubset = "pid";
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            ProtectSystem = "strict";
            RemoveIPC = true;
            RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = ["@system-service" "~@privileged"];
            UMask = "0077";

            # Support for encrypted credentials
            LoadCredentialEncrypted = [];

            # Restart policy
            Restart = "on-failure";
            RestartSec = "10s";
          };
        };
      }
      // registerServices;

    services.gio.reverse-proxy = {
      enable = true;
      virtualHosts = {
        "admin.restate" = {
          host = "localhost";
          port = adminPort;
        };
        "ingress.restate" = {
          host = "localhost";
          port = ingressPort;
        };
      };
    };

    gio.services.restate-admin.consul = {
      name = "restate-admin";
      address = "admin.restate.gio.ninja";
      port = 443;
      checks = [
        {
          http = "https://admin.restate.gio.ninja/health";
          interval = "60s";
        }
      ];
    };
  };
}
