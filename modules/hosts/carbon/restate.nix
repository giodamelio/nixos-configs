# restate — durable execution platform (admin.restate / ingress.restate). Defines
# the gio.restate options consumed by hooks (ingressEndpoint) and the deployed-apps
# agent + yesman (deployments). No secrets. The two endpoints + the restate-admin
# consul registration become fleet.services. Converted from nix/hosts/carbon/restate.nix.
_: {
  den.aspects.carbon.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkOption types;

    listenHost = "127.0.0.1";
    ingressPort = 8080;
    adminPort = 9070;

    ingressEndpoint = "http://${listenHost}:${toString ingressPort}";
    adminEndpoint = "http://${listenHost}:${toString adminPort}";

    restateConfig = {
      cluster-name = "restate";
      node-name = "carbon";
      bind-address = "${listenHost}:5122";
      auto-provision = true;

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
              RESTATE_CLI_CONFIG_HOME = "/run/restate-register-${name}";
            };
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              DynamicUser = true;
              RuntimeDirectory = "restate-register-${name}";
            };
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
      description = "Restate service-deployment registrations turned into register oneshots.";
      type = types.attrsOf (types.submodule {
        options = {
          endpoint = mkOption {
            type = types.str;
            description = "HTTP endpoint of the Restate SDK service to register.";
          };
          dependencies = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Extra systemd units to order after / want.";
          };
          restartTriggers = mkOption {
            type = types.listOf (types.either types.str types.package);
            default = [];
            description = "Extra restart triggers (e.g. the service package).";
          };
        };
      });
    };

    config = {
      environment.systemPackages = [pkgs.restate];

      systemd.services =
        {
          restate = {
            description = "Restate distributed application platform";
            wantedBy = ["multi-user.target"];
            after = ["network-online.target"];
            wants = ["network-online.target"];

            serviceConfig = {
              ExecStart = "${pkgs.restate}/bin/restate-server --config-file ${configFile}";

              DynamicUser = true;
              StateDirectory = "restate";
              WorkingDirectory = "/var/lib/restate";

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

              Restart = "on-failure";
              RestartSec = "10s";
            };
          };
        }
        // registerServices;
    };
  };

  # Two endpoints (admin + ingress); only admin is registered in consul
  # (restate-admin), matching Blueprint.
  den.hosts.x86_64-linux.carbon.services.restate = {
    endpoints = {
      admin = {
        domain = "admin.restate";
        backend.host = "localhost";
        backend.port = 9070;
      };
      ingress = {
        domain = "ingress.restate";
        backend.host = "localhost";
        backend.port = 8080;
      };
    };
    consul = {
      name = "restate-admin";
      address = "admin.restate.gio.ninja";
      port = 443;
    };
    healthcheck.target = "https://admin.restate.gio.ninja/health";
    "prometheus-endpoint".target = "localhost:5122";
  };
}
