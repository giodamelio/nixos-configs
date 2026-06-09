{
  config,
  options,
  flake,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption mkIf types literalExpression;

  cfg = config.gio.deployedApps;
  deployCfg = config.gio.deploy;

  profileDir = name: "/nix/var/nix/profiles/per-user/deploy/${name}";
  profilePath = name: "${profileDir name}/profile";
  socketPath = name: "/run/${name}/${name}.sock";

  listenAddr = name: appCfg:
    if appCfg.listener.type == "port"
    then "127.0.0.1:${toString appCfg.listener.port}"
    else socketPath name;

  isUnixListener = appCfg: appCfg.listener.type == "unix" || appCfg.listener.type == "unix-activated";
  isSocketActivated = appCfg: appCfg.listener.type == "unix-activated";

  listenerType = types.submodule {
    options = {
      type = mkOption {
        type = types.enum ["port" "unix" "unix-activated"];
        description = ''
          How the app receives connections:
            port           — bind a TCP port, always running
            unix           — bind a Unix socket, always running
            unix-activated — Unix socket managed by systemd, process started on first connection
        '';
      };
      port = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "TCP port to listen on. Required when type = \"port\".";
      };
    };
  };

  reverseProxyType = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to create a reverse proxy entry for this app.";
      };
      subdomain = mkOption {
        type = types.str;
        description = "Subdomain for the reverse proxy (e.g. \"my-app\" becomes my-app.gio.ninja).";
      };
      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = "Extra Caddy config to include in the virtual host block.";
      };
    };
  };

  appType = types.submodule ({name, ...}: {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether this deployed app slot is active.";
      };

      description = mkOption {
        type = types.str;
        default = name;
        description = "Human-readable description for the systemd service.";
      };

      listener = mkOption {
        type = listenerType;
        description = "How the app listens for connections.";
      };

      reverseProxy = mkOption {
        type = reverseProxyType;
        default = {};
        description = "Optional reverse proxy configuration.";
      };

      credentials = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of credential names to load via LoadCredentialEncrypted.";
      };

      gradient = mkOption {
        default = {};
        description = "Gradient binding for pull-based deploys via the gradient-deployer agent.";
        type = types.submodule {
          options.project = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "default/yesman";
            description = ''
              Gradient "<org>/<project>" slug. The gradient-deployer agent
              manages this slot: on a webhook poke it pulls the latest succeeded
              build for this project and deploys it.
            '';
          };
        };
      };
    };
  });

  enabledApps = lib.filterAttrs (_: appCfg: appCfg.enable) cfg;
  unixReverseProxyApps = lib.filterAttrs (_: a: a.reverseProxy.enable && isUnixListener a) enabledApps;

  # Slots the gradient-deployer agent manages (those that set gradient.project).
  agentApps = lib.filterAttrs (_: a: a.gradient.project != null) enabledApps;
  hostname = config.networking.hostName;
  gradientDeployer = flake.packages.${pkgs.stdenv.hostPlatform.system}.gradient-deployer;

  # The Restate Virtual Object name. Encodes the host so each machine is a
  # distinct Restate deployment (Restate routes one deployment per service name).
  deployerService = "gradient-deployer-${hostname}";
  deployerBind = "127.0.0.1:9080";

  # TOML config consumed by the gradient-deployer Restate service. Secrets are
  # referenced by path (systemd credentials), never inlined.
  deployerConfig = (pkgs.formats.toml {}).generate "gradient-deployer.toml" {
    gradient = {
      server = deployCfg.gradientServer;
      api_key_file = "/run/credentials/gradient-deployer.service/gradient_deployer_api_key";
    };
    restate.service_name = deployerService;
    slots =
      lib.mapAttrs (name: appCfg: {
        project = appCfg.gradient.project;
        profile = profilePath name;
        restart_unit = "${name}.service";
      })
      agentApps;
  };

  # Manual deploy: POST to the local Restate ingress to invoke a slot's
  # Reconcile handler now, instead of waiting for a build webhook.
  gradientDeployWrapper = pkgs.writeShellApplication {
    name = "gradient-deploy";
    runtimeInputs = [pkgs.curl];
    text = ''
      slot="''${1:-}"
      if [[ -z "$slot" ]]; then
        echo "usage: gradient-deploy <slot>" >&2
        exit 1
      fi
      curl -sf -X POST "${config.gio.restate.ingressEndpoint}/${deployerService}/$slot/Reconcile" \
        -H 'content-type: application/json' -d '{}'
      echo
    '';
  };
in {
  imports = [
    flake.nixosModules.reverse-proxy
  ];

  options.gio.deployedApps = mkOption {
    type = types.attrsOf appType;
    default = {};
    description = "Declarative deployment slots for self-contained app binaries.";
    example = literalExpression ''
      {
        my-app = {
          description = "My little Go service";
          listener = { type = "unix"; };
          reverseProxy = {
            enable = true;
            subdomain = "my-app";
          };
          credentials = [ "db-password" ];
        };
      }
    '';
  };

  options.gio.deploy = {
    gradientServer = mkOption {
      type = types.str;
      default = "https://gradient.gio.ninja";
      description = "Base URL of the Gradient instance the deploy agent pulls builds from.";
    };
  };

  config = lib.mkMerge [
    {
      assertions =
        (lib.mapAttrsToList (name: appCfg: {
            assertion = appCfg.listener.type != "port" || appCfg.listener.port != null;
            message = "gio.deployedApps.${name}: listener.port is required when type = \"port\"";
          })
          enabledApps)
        ++ [
          {
            assertion = !(enabledApps ? "caddy");
            message = "gio.deployedApps: app name \"caddy\" conflicts with the reverse proxy user";
          }
        ]
        ++ (lib.mapAttrsToList (name: appCfg: {
            assertion = appCfg.gradient.project != null;
            message = "gio.deployedApps.${name}: gradient.project is required — deploys are managed by the gradient-deployer agent";
          })
          enabledApps);

      environment.systemPackages = lib.optional (agentApps != {}) gradientDeployWrapper;

      users.users =
        (lib.mapAttrs (name: _: {
            isSystemUser = true;
            group = name;
            home = "/var/lib/${name}";
            createHome = false;
          })
          enabledApps)
        // lib.optionalAttrs (unixReverseProxyApps != {}) {
          caddy.extraGroups = lib.mapAttrsToList (name: _: name) unixReverseProxyApps;
        }
        // lib.optionalAttrs (agentApps != {}) {
          gradient-deployer = {
            isSystemUser = true;
            group = "gradient-deployer";
            home = "/var/lib/gradient-deployer";
            description = "Gradient pull-deploy agent";
          };
        };

      users.groups =
        (lib.mapAttrs (_: _: {}) enabledApps)
        // lib.optionalAttrs (agentApps != {}) {
          gradient-deployer = {};
        };

      systemd.tmpfiles.rules =
        [
          "d /nix/var/nix/profiles/per-user/deploy 0755 root root -"
        ]
        ++ lib.concatLists (lib.mapAttrsToList (name: _: [
            "d /var/lib/${name} 0750 ${name} ${name} -"
            "d ${profileDir name} 0755 gradient-deployer gradient-deployer -"
          ])
          enabledApps);

      systemd.services = lib.mkMerge [
        (lib.concatMapAttrs (name: appCfg: {
            ${name} = lib.mkMerge [
              {
                inherit (appCfg) description;

                serviceConfig = lib.mkMerge [
                  {
                    User = name;
                    Group = name;
                    StateDirectory = name;
                    StateDirectoryMode = "0750";

                    ExecCondition = pkgs.writeShellScript "${name}-check" ''
                      if [ ! -x ${profilePath name}/bin/${name} ]; then
                        echo "${name} has not been deployed yet — run 'gradient-deploy ${name}' or push to trigger a build"
                        exit 1
                      fi
                    '';
                    ExecStart = "${profilePath name}/bin/${name}";

                    # Hardening
                    NoNewPrivileges = true;
                    ProtectSystem = "strict";
                    ProtectHome = true;
                    PrivateTmp = true;
                    PrivateDevices = true;
                    ProtectKernelTunables = true;
                    ProtectKernelModules = true;
                    ProtectControlGroups = true;
                    RestrictNamespaces = true;
                    LockPersonality = true;
                    RestrictRealtime = true;
                    RestrictSUIDSGID = true;
                    RemoveIPC = true;
                  }
                  (mkIf (isUnixListener appCfg && !(isSocketActivated appCfg)) {
                    RuntimeDirectory = name;
                    RuntimeDirectoryMode = "0750";
                  })
                  (mkIf (appCfg.credentials != []) {
                    LoadCredentialEncrypted =
                      appCfg.credentials;
                  })
                ];

                environment = lib.optionalAttrs (!(isSocketActivated appCfg)) {
                  LISTEN_ADDR = listenAddr name appCfg;
                };
              }
              (mkIf (isSocketActivated appCfg) {
                requires = ["${name}.socket"];
                after = ["${name}.socket"];
              })
              (mkIf (!(isSocketActivated appCfg)) {
                wantedBy = ["multi-user.target"];
                after = ["network.target"];
              })
            ];
          })
          enabledApps)

        # The gradient-deployer agent — a Restate Virtual Object service. Long
        # running (the Restate server calls it on :9080); real user, no DynamicUser
        # since it writes profiles + restarts units. Registered with Restate via
        # gio.restate.deployments below.
        (lib.mkIf (agentApps != {}) {
          gradient-deployer = {
            description = "Gradient pull-deploy agent (Restate service)";
            wantedBy = ["multi-user.target"];
            after = ["network.target" "restate.service"];
            wants = ["restate.service"];
            # The reconcile steps shell out to nix-store/nix-env (realize the
            # closure, point the profile) and systemctl (restart the unit), so
            # those must be on the unit's PATH — systemd units don't inherit the
            # system profile's bin dir.
            path = [config.nix.package config.systemd.package];
            environment =
              {
                HOME = "/var/lib/gradient-deployer";
              }
              // config.nix.envVars;
            serviceConfig = {
              Type = "simple";
              User = "gradient-deployer";
              Group = "gradient-deployer";
              ExecStart = "${lib.getExe gradientDeployer} ${deployerConfig}";
              Restart = "on-failure";
              RestartSec = "5s";
              StateDirectory = "gradient-deployer";
              LoadCredentialEncrypted = ["gradient_deployer_api_key"];

              # Hardening. ProtectSystem = "full" (not "strict") deliberately leaves
              # /nix/var/nix and /run writable, so nix-env profile updates and the
              # systemctl/D-Bus restart path keep working.
              NoNewPrivileges = true;
              ProtectSystem = "full";
              ProtectHome = true;
              PrivateTmp = true;
              ProtectKernelTunables = true;
              ProtectKernelModules = true;
              ProtectControlGroups = true;
              RestrictRealtime = true;
              RestrictSUIDSGID = true;
              LockPersonality = true;
            };
          };
        })
      ];

      # Socket units — only for unix-activated apps.
      systemd.sockets = lib.concatMapAttrs (name: appCfg:
        lib.optionalAttrs (isSocketActivated appCfg) {
          ${name} = {
            description = "Socket for ${appCfg.description}";
            wantedBy = ["sockets.target"];
            socketConfig = {
              ListenStream = socketPath name;
              SocketUser = name;
              SocketGroup = name;
              SocketMode = "0660";
              RuntimeDirectory = name;
              RuntimeDirectoryMode = "0750";
            };
          };
        })
      enabledApps;

      # Allow the agent to restart only its managed app units, without sudo.
      security.polkit = lib.mkIf (agentApps != {}) {
        enable = true;
        extraConfig = let
          unitMatch =
            lib.concatStringsSep " || "
            (lib.mapAttrsToList (name: _: ''unit === "${name}.service"'') agentApps);
        in ''
          polkit.addRule(function(action, subject) {
            if (subject.user !== "gradient-deployer") return polkit.Result.NO_MATCH;
            if (action.id !== "org.freedesktop.systemd1.manage-units") return polkit.Result.NO_MATCH;
            var unit = action.lookup("unit");
            if (${unitMatch}) return polkit.Result.YES;
            return polkit.Result.NO_MATCH;
          });
        '';
      };

      # Reverse proxy entries for the per-app vhosts.
      services.gio.reverse-proxy.virtualHosts = lib.concatMapAttrs (name: appCfg:
        lib.optionalAttrs appCfg.reverseProxy.enable {
          ${appCfg.reverseProxy.subdomain} =
            {
              extraConfig = appCfg.reverseProxy.extraConfig;
            }
            // (
              if appCfg.listener.type == "port"
              then {
                host = "127.0.0.1";
                port = appCfg.listener.port;
              }
              else {
                socket_path = socketPath name;
              }
            );
        })
      enabledApps;
    }

    # Register the agent's Restate endpoint so the Restate server discovers it.
    # Only define this on hosts that actually import the restate module — the
    # `gio.restate` option only exists there. Guarding with `options ? gio.restate`
    # drops the whole attribute elsewhere (e.g. gallium), so non-restate hosts
    # don't fail with "option gio.restate does not exist".
    (lib.optionalAttrs (options ? gio.restate) {
      gio.restate.deployments = lib.mkIf (agentApps != {}) {
        gradient-deployer = {
          endpoint = "http://${deployerBind}";
          dependencies = ["gradient-deployer.service"];
          restartTriggers = [gradientDeployer deployerConfig];
        };
      };
    })
  ];
}
