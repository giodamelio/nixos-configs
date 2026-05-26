{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption mkIf types literalExpression;

  cfg = config.gio.deployedApps;
  deployCfg = config.gio.deploy;

  profileDir = name: "/nix/var/nix/profiles/per-user/deploy/${name}";
  profilePath = name: "${profileDir name}/profile";
  credstorePath = cred: "/etc/gio-credentials/${cred}";
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
    };
  });

  enabledApps = lib.filterAttrs (_: appCfg: appCfg.enable) cfg;
  unixReverseProxyApps = lib.filterAttrs (_: a: a.reverseProxy.enable && isUnixListener a) enabledApps;

  hostname = config.networking.hostName;

  # Nushell script that subscribes to NATS JetStream for deploy messages.
  # Ensures stream/consumer exist on startup, then loops pulling messages.
  mkSubscriberScript = name:
    pkgs.writeTextFile {
      name = "${name}-deploy-subscriber.nu";
      text = ''
        let app = "${name}"
        let consumer = "${name}-${hostname}"
        let profile = "${profilePath name}"
        let nats = "${lib.getExe pkgs.natscli}"
        let nix_env = "${pkgs.nix}/bin/nix-env"
        let systemctl = "/run/current-system/sw/bin/systemctl"

        # Ensure the DEPLOY stream exists (idempotent)
        let stream = (do { ^$nats stream add DEPLOY --subjects "deploy.>" --retention limits --max-msgs-per-subject 5 --storage file --replicas 1 --discard old --defaults } | complete)
        if $stream.exit_code != 0 and not ($stream.stderr | str contains "already") {
          print $"Stream setup warning: ($stream.stderr)"
        }

        # Ensure durable pull consumer exists (idempotent)
        let cons = (do { ^$nats consumer add DEPLOY $consumer --pull --filter $"deploy.($app)" --deliver all --ack explicit --max-deliver 3 --defaults } | complete)
        if $cons.exit_code != 0 and not ($cons.stderr | str contains "already") {
          print $"Consumer setup warning: ($cons.stderr)"
        }

        print $"Subscriber ready: ($consumer) listening for deploy.($app)"

        loop {
          let result = (do { ^$nats consumer next DEPLOY $consumer --raw --timeout 30s } | complete)

          if $result.exit_code != 0 {
            continue
          }

          let store_path = ($result.stdout | str trim)
          if ($store_path | is-empty) {
            continue
          }

          # Validate the message looks like a nix store path
          if not ($store_path | str starts-with "/nix/store/") {
            print $"Ignoring invalid store path: ($store_path)"
            continue
          }

          print $"Deploying ($store_path) to ($app)"

          # Atomically switch the profile to the new store path
          let install = (do { ^$nix_env --profile $profile --set $store_path } | complete)
          if $install.exit_code != 0 {
            print $"Deploy failed: ($install.stderr)"
            continue
          }

          # sudo must be bare — it resolves via /run/wrappers for the setuid wrapper
          let restart = (do { ^sudo $systemctl restart $"($app).service" } | complete)
          if $restart.exit_code != 0 {
            print $"Restart failed: ($restart.stderr)"
            continue
          }

          print $"Deploy complete for ($app)"
        }
      '';
    };
in {
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
    signingPublicKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Public key for verifying CI-signed nix store paths.
        Generate a keypair with:
          nix key generate-secret --key-name ci-deploy > ci-deploy-secret-key
          nix key convert-secret-to-public < ci-deploy-secret-key
        Store the secret key as a Forgejo CI secret. Put the public key here.
        CI signs paths with: nix store sign --key-file secret-key --recursive ./result
      '';
      example = "ci-deploy:base64publickey==";
    };
  };

  config = {
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
      ];

    # Trust the CI signing key so app users can nix copy without being trusted-users
    nix.settings.trusted-public-keys = lib.mkIf (deployCfg.signingPublicKey != null) [
      deployCfg.signingPublicKey
    ];

    users.users =
      (lib.mapAttrs (name: _: {
          isSystemUser = true;
          group = name;
          home = "/var/lib/${name}";
          createHome = false;
        })
        enabledApps)
      // lib.optionalAttrs (unixReverseProxyApps != {}) {
        # Add caddy to app groups so it can access unix sockets for reverse proxying
        caddy.extraGroups = lib.mapAttrsToList (name: _: name) unixReverseProxyApps;
      };

    users.groups = lib.mapAttrs (_: _: {}) enabledApps;

    systemd.tmpfiles.rules =
      [
        "d /nix/var/nix/profiles/per-user/deploy 0755 root root -"
      ]
      ++ lib.concatLists (lib.mapAttrsToList (name: _: [
          "d /var/lib/${name} 0750 ${name} ${name} -"
          "d ${profileDir name} 0755 ${name} ${name} -"
        ])
        enabledApps);

    # Scoped sudo: each app user can only restart their own service
    security.sudo.extraRules =
      lib.mapAttrsToList (name: _: {
        users = [name];
        commands = [
          {
            command = "/run/current-system/sw/bin/systemctl restart ${name}.service";
            options = ["NOPASSWD"];
          }
        ];
      })
      enabledApps;

    systemd.services =
      lib.concatMapAttrs (name: appCfg: {
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
                    echo "${name} has not been deployed yet — run CI to deploy"
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
                  map (c: "${c}:${credstorePath c}") appCfg.credentials;
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

        # Deploy subscriber: pulls from NATS JetStream, installs via nix profile
        "${name}-deploy-subscriber" = {
          description = "Deploy subscriber for ${name}";
          wantedBy = ["multi-user.target"];
          after = ["network-online.target"];
          wants = ["network-online.target"];

          serviceConfig = {
            ExecStart = "${pkgs.nushell}/bin/nu ${mkSubscriberScript name}";
            User = name;
            Group = name;
            Restart = "always";
            RestartSec = "10";
            KillMode = "mixed";
            TimeoutStopSec = "60";

            # Hardening (NoNewPrivileges omitted — sudo needs privilege escalation)
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
            RemoveIPC = true;

            # Profile dir needs write access; nix store writes go through the daemon
            ReadWritePaths = [
              "${profileDir name}"
            ];
          };

          path = ["/run/wrappers"];
        };
      })
      enabledApps;

    # Socket units — only for unix-activated apps
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

    # Reverse proxy entries
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
  };
}
