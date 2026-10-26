# nats — JetStream-enabled NATS in a two-node homelab cluster (carbon + gallium).
# Shared server aspect; the websocket GUI vhost is declared per-host as a
# fleet.services endpoint (only gallium owns nats-ws.gio.ninja). Converted from
# nix/modules/nixos/nats.nix.
_: {
  den.aspects.nats.nixos = {
    pkgs,
    lib,
    config,
    ...
  }: let
    inherit (lib) mkOption types;
    cfg = config.gio.nats;

    seconds = {
      s = 1;
      m = 60;
      h = 3600;
      d = 86400;
    };
    toNanoseconds = d: let
      m = builtins.match "([0-9]+)([smhd])" d;
    in
      lib.toInt (lib.elemAt m 0) * seconds.${lib.elemAt m 1} * 1000000000;

    # Every field the server would otherwise default is spelled out, so an
    # unchanged stream makes `nats stream edit` report no difference.
    streamConfig = name: s:
      lib.recursiveUpdate {
        inherit name;
        inherit (s) subjects storage retention;
        num_replicas = s.replicas;
        max_age =
          if s.maxAge == null
          then 0
          else toNanoseconds s.maxAge;
        max_bytes =
          if s.maxBytes == null
          then -1
          else s.maxBytes;
        max_msgs = -1;
        max_msg_size = -1;
        max_msgs_per_subject = -1;
        max_consumers = -1;
        discard = "old";
        duplicate_window = 120 * 1000000000;
        metadata = {};
      }
      s.extraConfig;

    streamFiles = lib.mapAttrs (name: s: pkgs.writeText "nats-stream-${name}.json" (builtins.toJSON (streamConfig name s))) cfg.streams;

    applyStreams = pkgs.writeShellApplication {
      name = "nats-create-streams";
      runtimeInputs = [pkgs.natscli];
      text = lib.concatStrings (lib.mapAttrsToList (name: file: ''
          if nats stream info ${lib.escapeShellArg name} >/dev/null 2>&1; then
            nats stream edit ${lib.escapeShellArg name} --config ${file} --force
          else
            nats stream add ${lib.escapeShellArg name} --config ${file}
          fi
        '')
        streamFiles);
    };
  in {
    options.gio.nats.streams = mkOption {
      default = {};
      description = ''
        JetStream streams to create or update after NATS starts. Streams are
        cluster-wide, so declare each on one host only. A stream that is no
        longer declared is left alone, never deleted.
      '';
      type = types.attrsOf (types.submodule {
        options = {
          subjects = mkOption {
            type = types.nonEmptyListOf types.str;
            example = ["webhooks.>"];
          };
          storage = mkOption {
            type = types.enum ["file" "memory"];
            default = "file";
            description = "Can't be changed on an existing stream; the oneshot fails instead.";
          };
          retention = mkOption {
            type = types.enum ["limits" "interest" "workqueue"];
            default = "limits";
          };
          replicas = mkOption {
            type = types.ints.between 1 5;
            default = 2;
            description = "Copies across the cluster.";
          };
          maxAge = mkOption {
            type = types.nullOr (types.strMatching "[0-9]+[smhd]");
            default = null;
            example = "7d";
            description = "Oldest message kept. null keeps messages forever.";
          };
          maxBytes = mkOption {
            type = types.nullOr types.ints.positive;
            default = null;
            description = "Largest the stream may grow. null is unlimited.";
          };
          extraConfig = mkOption {
            type = types.attrsOf types.anything;
            default = {};
            example = {max_msgs_per_subject = 100;};
            description = "Merged into the stream's JSON config, in NATS's own field names.";
          };
        };
      });
    };

    config = {
      environment.systemPackages = with pkgs; [
        natscli
        nats-top
      ];

      services.nats = {
        enable = true;
        jetstream = true;
        serverName = config.networking.hostName;
        settings = {
          http = "127.0.0.1:8222";

          websocket = {
            port = 9222;
            no_tls = true;
          };

          cluster = {
            name = "homelab";
            listen = "0.0.0.0:4248";
            routes = [
              "nats://carbon.gio.ninja:4248"
              "nats://gallium.gio.ninja:4248"
            ];
          };
        };
      };

      networking.firewall.allowedTCPPorts = [
        4248 # NATS clustering
        4222 # client connections
      ];

      systemd.services.nats-create-streams = lib.mkIf (cfg.streams != {}) {
        description = "Create or update the JetStream streams in gio.nats.streams";
        wantedBy = ["multi-user.target"];
        after = ["nats.service"];
        requires = ["nats.service"];
        # JetStream needs a cluster majority, which with two nodes is both, so
        # keep retrying until the other one is up.
        startLimitIntervalSec = 0;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = lib.getExe applyStreams;
          Restart = "on-failure";
          RestartSec = "10s";
          DynamicUser = true;
        };
      };
    };
  };
}
